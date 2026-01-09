ogin desktop

💾 Encrypted data only


Just tell me.
#!/bin/bash
set -e

DISK=/dev/nvme0n1
HOST=arch
USER=tuhin
PASS=1234

echo "==> Wiping disk"
sgdisk --zap-all $DISK
wipefs -a $DISK

echo "==> Creating partitions"
sgdisk -n1:0:+2G -t1:ef00 $DISK
sgdisk -n2:0:+200G -t2:8300 $DISK
sgdisk -n3:0:0 -t3:8300 $DISK

mkfs.fat -F32 ${DISK}p1
mkfs.btrfs -f ${DISK}p2
mkfs.btrfs -f ${DISK}p3

mount ${DISK}p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@snapshots
umount /mnt

mount -o noatime,compress=zstd,subvol=@ ${DISK}p2 /mnt
mkdir -p /mnt/{boot,data,.snapshots}
mount ${DISK}p1 /mnt/boot
mount -o noatime,compress=zstd ${DISK}p3 /mnt/data

echo "==> Installing base system"
pacstrap /mnt base linux linux-firmware \
  networkmanager sudo btrfs-progs snapper \
  iproute2 iptables tcpdump git vim

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt <<EOF
set -e

ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo $HOST > /etc/hostname

echo "root:$PASS" | chpasswd
useradd -m -G wheel $USER
echo "$USER:$PASS" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

systemctl enable NetworkManager

echo "==> systemd-boot setup"
bootctl install

cat > /boot/loader/loader.conf <<LOADER
default arch
timeout 0
editor no
console-mode max
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=UUID=$(blkid -s UUID -o value ${DISK}p2) \
rootflags=subvol=@ rw quiet loglevel=0 rd.systemd.show_status=0 \
vt.global_cursor_default=0 systemd.log_level=emergency \
systemd.log_target=null
ENTRY

echo "==> Snapper config"
snapper -c root create-config /
rm -rf /.snapshots
mkdir /.snapshots
mount -a

snapper -c root set-config \
  TIMELINE_CREATE=yes \
  TIMELINE_CLEANUP=yes \
  NUMBER_LIMIT=5 \
  TIMELINE_LIMIT_HOURLY=2 \
  TIMELINE_LIMIT_DAILY=2 \
  TIMELINE_LIMIT_WEEKLY=1 \
  TIMELINE_LIMIT_MONTHLY=0 \
  TIMELINE_LIMIT_YEARLY=0

cat > /etc/systemd/system/rollback.service <<ROLL
[Unit]
Description=Auto rollback on boot failure
DefaultDependencies=no
Before=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/snapper -c root rollback

[Install]
WantedBy=multi-user.target
ROLL

systemctl enable rollback.service

echo "==> Networking & kernel permissions"
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-forward.conf
setcap cap_net_raw,cap_net_admin=eip /usr/bin/tcpdump

EOF

umount -R /mnt
swapoff -a

echo "✅ INSTALL COMPLETE — REBOOT NOW"

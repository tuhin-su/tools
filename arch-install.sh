#!/bin/bash
set -e

### ================= CONFIG =================
DISK="/dev/nvme0n1"      # CHANGE IF NEEDED
HOSTNAME="arch"
USERNAME="tuhin"
USERPASS="1234"
EFI_SIZE="2G"
SYS_SIZE="200G"
TIMEZONE="Asia/Kolkata"
LOCALE="en_US.UTF-8"

### ================= PREP =================
timedatectl set-ntp true
pacman -Sy --noconfirm archlinux-keyring

### ================= WIPE DISK =================
wipefs -af $DISK
sgdisk -Z $DISK

### ================= PARTITION =================
sgdisk -n 1:0:+$EFI_SIZE -t 1:ef00 $DISK
sgdisk -n 2:0:+$SYS_SIZE -t 2:8300 $DISK
sgdisk -n 3:0:0         -t 3:8300 $DISK

EFI="${DISK}p1"
SYS="${DISK}p2"
DATA="${DISK}p3"

### ================= FILESYSTEM =================
mkfs.fat -F32 $EFI
mkfs.btrfs -f $SYS
mkfs.btrfs -f $DATA

mount $SYS /mnt
btrfs sub create /mnt/@root
btrfs sub create /mnt/@pkg
btrfs sub create /mnt/@snapshots
umount /mnt

mount -o subvol=@root,noatime,compress=zstd $SYS /mnt
mkdir -p /mnt/{boot,home,var/cache/pacman/pkg,.snapshots}

mount -o subvol=@pkg,noatime,compress=zstd $SYS /mnt/var/cache/pacman/pkg
mount -o subvol=@snapshots,noatime,compress=zstd $SYS /mnt/.snapshots
mount $DATA /mnt/home
mount $EFI /mnt/boot

### ================= BASE INSTALL =================
pacstrap /mnt base linux linux-firmware btrfs-progs \
  sudo networkmanager snapper plymouth \
  iproute2 bridge-utils openvswitch tcpdump

genfstab -U /mnt >> /mnt/etc/fstab

### ================= CHROOT =================
arch-chroot /mnt /bin/bash <<EOF

### TIME & LOCALE
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

### USER (ROOT LOCKED)
passwd -l root
useradd -m -G wheel $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USERNAME

### BOOTLOADER (APPLE-STYLE SILENT)
bootctl install
ROOT_UUID=\$(blkid -s UUID -o value $SYS)

cat > /boot/loader/loader.conf <<BOOT
default arch
timeout 0
editor no
console-mode keep
BOOT

cat > /boot/loader/entries/arch.conf <<BOOT
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=UUID=\$ROOT_UUID rw quiet loglevel=0 rd.systemd.show_status=false rd.udev.log_level=0 systemd.log_target=null vt.global_cursor_default=0 splash
BOOT

### INITRAMFS (NO OUTPUT)
sed -i 's/^HOOKS=.*/HOOKS=(base systemd plymouth autodetect modconf block filesystems keyboard fsck)/' /etc/mkinitcpio.conf
plymouth-set-default-theme -R text

### SNAPSHOT + AUTO RECOVERY
snapper -c root create-config /
systemctl enable snapper-timeline.timer

cat > /usr/local/bin/boot-fail-rollback.sh <<'ROLL'
#!/bin/bash
[ -f /run/boot-success ] && exit 0
snapper rollback && reboot -f
ROLL
chmod +x /usr/local/bin/boot-fail-rollback.sh

cat > /etc/systemd/system/boot-fail-rollback.service <<ROLL
[Unit]
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/boot-fail-rollback.sh
[Install]
WantedBy=multi-user.target
ROLL

cat > /etc/systemd/system/boot-success.service <<OK
[Unit]
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/bin/touch /run/boot-success
[Install]
WantedBy=multi-user.target
OK

systemctl enable boot-fail-rollback boot-success

### NETWORK
systemctl enable NetworkManager

### VIRTUAL NETWORK SUPPORT
echo -e "bridge\nbr_netfilter\ntun\nveth" > /etc/modules-load.d/net.conf
systemctl enable openvswitch-switch

### TCPDUMP
setcap cap_net_raw,cap_net_admin=eip /usr/bin/tcpdump

### SWAPFILE (16GB)
truncate -s 0 /swapfile
chattr +C /swapfile
dd if=/dev/zero of=/swapfile bs=1M count=16384
chmod 600 /swapfile
mkswap /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

EOF

echo "======================================"
echo " INSTALL COMPLETE"
echo " User: tuhin"
echo " Password: 1234"
echo " Root login: DISABLED"
echo " Silent Apple-style boot enabled"
echo "======================================"

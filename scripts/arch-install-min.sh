#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/vda"

echo "==> Partitioning disk..."
sgdisk --zap-all $DISK
parted -s $DISK mklabel msdos
parted -s $DISK mkpart primary ext4 1MiB 100%

echo "==> Formatting..."
mkfs.ext4 -F ${DISK}1

echo "==> Mounting..."
mount ${DISK}1 /mnt

echo "==> Installing base system..."
pacstrap /mnt base linux linux-firmware vim dhcpcd qemu-guest-agent

echo "==> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "==> Chroot steps..."
arch-chroot /mnt /bin/bash << 'EOF'
set -e

echo "==> Setting timezone and basic config..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "arch-qemu" > /etc/hostname

echo "127.0.0.1 localhost" >> /etc/hosts

echo "==> Set root password to: root"
echo "root:root" | chpasswd

echo "==> Install bootloader..."
pacman --noconfirm -Sy grub
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Enable DHCP + QEMU agent..."
systemctl enable dhcpcd
systemctl enable qemu-guest-agent

echo "==> Setup root autologin (experimental)..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << AEND
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin root --noclear %I 38400 linux
AEND

EOF

echo "==> Install complete!"
echo "Type 'reboot' when ready."

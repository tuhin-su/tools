#!/bin/bash
set -e

# --- VARIABLES ---
DISK="/dev/nvme0n1"       # NVMe disk
EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
HOSTNAME=""                
USERNAME="tuhin"
PASSWORD="arch123"         
USER_HOME="/home"

# --- UPDATE CLOCK ---
timedatectl set-ntp true

# --- WIPE DISK AND CREATE PARTITIONS ---
sgdisk -Z $DISK
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" $DISK
sgdisk -n 2:0:0 -t 2:8300 -c 2:"LinuxRoot" $DISK

# --- FORMAT PARTITIONS ---
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 "$ROOT_PART"

# --- MOUNT ---
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# --- INSTALL BASE SYSTEM ---
pacstrap /mnt base linux linux-firmware vim zsh sudo dhcpcd iwd git base-devel systemd-boot

# --- GENERATE FSTAB ---
genfstab -U /mnt >> /mnt/etc/fstab

# --- CHROOT CONFIGURATION ---
arch-chroot /mnt /bin/bash <<EOF
# --- TIMEZONE ---
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

# --- LOCALE ---
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# --- HOSTNAME ---
echo "$HOSTNAME" > /etc/hostname

# --- USERS ---
useradd -M -d "$USER_HOME" -G wheel -s /bin/zsh $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd

# --- SUDOERS ---
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- ENABLE SERVICES ---
systemctl enable dhcpcd
systemctl enable iwd

# --- INSTALL SYSTEMD-BOOT ---
bootctl --path=/boot install

# --- CREATE BOOT ENTRY ---
mkdir -p /boot/loader/entries
cat <<EOL > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=$(blkid -s UUID -o value $ROOT_PART) rw
EOL

# --- BLACKARCH REPO ---
pacman -Sy --noconfirm curl
curl -O https://blackarch.org/strap.sh
chmod +x strap.sh
./strap.sh
pacman -Syyu --noconfirm

EOF

echo "Arch Linux installation complete! Reboot now."

#!/bin/bash

set -eio pipefail

set -x

# Step 1: Prepare the Build Environment
sudo apt update
sudo apt install -y debootstrap squashfs-tools live-boot live-boot-initramfs-tools

mkdir -p ~/live-debian
cd ~/live-debian

# Step 2: Bootstrap a Minimal Debian System
sudo debootstrap --variant=minbase --arch=amd64 trixie chroot http://deb.debian.org/debian/

# Step 3: Configure the Chroot Environment
sudo mount --bind /dev chroot/dev
sudo mount --bind /proc chroot/proc
sudo mount --bind /sys chroot/sys
sudo mount --bind /run chroot/run

# Run commands inside chroot
sudo chroot chroot /bin/bash -c '
  echo "debian-live" > /etc/hostname

  cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian trixie main
deb http://security.debian.org/debian-security trixie-security main
EOF

  apt update
  apt install -y --no-install-recommends linux-image-amd64 live-boot systemd-sysv ifupdown net-tools iputils-ping

  # Set root password non-interactively (change "rootpassword" to your desired password)
  echo "root:rootpassword" | chpasswd

  apt clean
  rm -rf /var/lib/apt/lists/*
'

# Unmount after chroot commands
sudo umount chroot/dev chroot/proc chroot/sys chroot/run


# Step 4: Create the Squashfs Image and Extract Boot File

sudo mksquashfs chroot filesystem.squashfs -e boot

sudo cp chroot/boot/vmlinuz-* vmlinuz
sudo cp chroot/boot/initrd.img-* initrd

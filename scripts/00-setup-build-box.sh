#!/bin/bash

set -eo pipefail

# Set artifacts directory with fallback
ARTIFACTS="${ARTIFACTS:-$(pwd -P)/artifacts}"
[ -d "$ARTIFACTS" ] || mkdir -p "$ARTIFACTS"
CHROOT_DIR="${ARTIFACTS}/rootfs"

# Step 1: Prepare the Build Environment
sudo apt-get update
sudo apt-get install -y debootstrap squashfs-tools live-boot live-boot-initramfs-tools

mkdir -p "${ARTIFACTS}"
cd "${ARTIFACTS}"

# Step 2: Bootstrap a Minimal Debian System
sudo debootstrap --variant=minbase --arch=amd64 trixie "${CHROOT_DIR}" http://deb.debian.org/debian/

# Step 3: Configure the Chroot Environment
sudo mount --bind /dev "${CHROOT_DIR}/dev"
sudo mount --bind /proc "${CHROOT_DIR}/proc"
sudo mount --bind /sys "${CHROOT_DIR}/sys"
sudo mount --bind /run "${CHROOT_DIR}/run"

# Run commands inside chroot
sudo chroot "${CHROOT_DIR}" /bin/bash -c '
  export DEBIAN_FRONTEND=noninteractive
  export LANG=C
  export LC_ALL=C
  
  echo "debian-live" > /etc/hostname

  cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian trixie main
deb http://security.debian.org/debian-security trixie-security main
EOF

  apt-get update
  apt-get install -y --no-install-recommends linux-image-amd64 live-boot systemd-sysv ifupdown net-tools iputils-ping

  # Set root password non-interactively (change "rootpassword" to your desired password)
  echo "root:rootpassword" | chpasswd

  apt-get clean
  rm -rf /var/lib/apt/lists/*
'

# Unmount after chroot commands
sudo umount "${CHROOT_DIR}/dev" "${CHROOT_DIR}/proc" "${CHROOT_DIR}/sys" "${CHROOT_DIR}/run"

# Step 4: Create the Squashfs Image and Extract Boot File

sudo mksquashfs "${CHROOT_DIR}" filesystem.squashfs -e boot

sudo cp "${CHROOT_DIR}"/boot/vmlinuz-* vmlinuz
sudo cp "${CHROOT_DIR}"/boot/initrd.img-* initrd
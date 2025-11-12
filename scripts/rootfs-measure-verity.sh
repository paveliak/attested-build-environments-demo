#!/bin/bash

set -e

# TODO: pass it into this script as parameter
LUN_ID="0"

ROOTFS_DEVICE=$(sudo blkid /dev/disk/azure/scsi1/lun0* --match-token LABEL=cloudimg-rootfs -o device)
UEFI_DEVICE=$(sudo blkid /dev/disk/azure/scsi1/lun0* --match-token LABEL=UEFI -o device)
BOOT_DEVICE=$(sudo blkid /dev/disk/azure/scsi1/lun0* --match-token LABEL=BOOT -o device)
VERITY_DEVICE=$(sudo blkid /dev/disk/azure/scsi1/lun0* --match-token PARTLABEL=verity-tree -o device)

ROOTFS_PARTUUID=$(sudo blkid -s PARTUUID -o value $ROOTFS_DEVICE)
VERITY_PARTUUID=$(sudo blkid -s PARTUUID -o value $VERITY_DEVICE)

echo "Setting up Verity for $ROOTFS_DEVICE on $VERITY_DEVICE"
#sudo veritysetup --verbose --debug format $ROOTFS_DEVICE $VERITY_DEVICE --root-hash-file rootfs.hash
echo "foobar" > rootfs.hash 

echo "Building UKI"
sudo mkdir -p /mnt/root
sudo mkdir -p /mnt/boot
sudo mkdir -p /mnt/uefi

sudo mount -o ro $ROOTFS_DEVICE /mnt/root
sudo mount -o ro $BOOT_DEVICE /mnt/boot
sudo mount $UEFI_DEVICE /mnt/uefi

PROC_CMDLINE="root=PARTUUID=$ROOTFS_PARTUUID ro veritydata=PARTUUID=$ROOTFS_PARTUUID veritytree=PARTUUID=$VERITY_PARTUUID verityhash=$(cat rootfs.hash) verityname=/dev/meow"
UNAME=$(ls /mnt/root/usr/lib/modules)
# TODO: sign UKI for the SecureBoot
echo "Kernel cmdline: $PROC_CMDLINE"
sudo ukify build --linux="/mnt/boot/vmlinuz-$UNAME" --initrd="/mnt/boot/initrd.img-$UNAME" --uname=$UNAME --cmdline="$PROC_CMDLINE" --output=/mnt/uefi/EFI/BOOT/BOOTX64.EFI --all

sudo umount /mnt/uefi
sudo umount /mnt/boot
sudo umount /mnt/root

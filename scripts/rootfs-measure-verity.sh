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
sudo veritysetup --verbose --debug format $ROOTFS_DEVICE $VERITY_DEVICE --root-hash-file rootfs.hash

echo "Building UKI"
sudo mkdir -p /mnt/root
sudo mkdir -p /mnt/boot
sudo mkdir -p /mnt/uefi

sudo mount -o ro $ROOTFS_DEVICE /mnt/root
sudo mount -o ro $BOOT_DEVICE /mnt/boot
sudo mount $UEFI_DEVICE /mnt/uefi

PROC_CMDLINE="root=/dev/mapper/verityroot ro fastboot rootfstype=ext4 console=tty1 console=ttyS0 earlyprintk=ttyS0 veritydata=PARTUUID=$ROOTFS_PARTUUID veritytree=PARTUUID=$VERITY_PARTUUID verityhash=$(cat rootfs.hash) verityname=verityroot"
UNAME=$(ls /mnt/root/usr/lib/modules)
echo "Kernel cmdline: $PROC_CMDLINE"
# We could also build UKI within the Image VM and create UKI addon here for the kernel command line
openssl req -new -x509 -newkey rsa:2048 -keyout MOK.key -out MOK.pem -days 365 -nodes -subj "/CN=SLSA BuildEnv Demo/"
sudo ukify build --linux="/mnt/boot/vmlinuz-$UNAME" --initrd="/mnt/boot/initrd.img-$UNAME" --uname=$UNAME --cmdline="$PROC_CMDLINE" --output=uki.efi --signtool=sbsign --secureboot-private-key=MOK.key --secureboot-certificate=MOK.pem
sudo cp uki.efi /mnt/uefi/EFI/BOOT/BOOTX64.EFI

sudo umount /mnt/uefi
sudo umount /mnt/boot
sudo umount /mnt/root

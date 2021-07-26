#!/bin/bash -eu

function log_progress () {
  if declare -F setup_progress > /dev/null
  then
    setup_progress "create-backingfiles-partition: $1"
    return
  fi
  echo "create-backingfiles-partition: $1"
}

# Will check for USB Drive before running sd card
if [ -n "$USB_DRIVE" ]
then
  log_progress "USB_DRIVE is set to $USB_DRIVE"
  # Check if backingfiles and mutable partitions exist
  if [ /dev/disk/by-label/backingfiles -ef /dev/sda2 ] && [ /dev/disk/by-label/mutable -ef /dev/sda1 ]
  then
    log_progress "Looks like backingfiles and mutable partitions already exist. Skipping partition creation."
  else
    log_progress "WARNING !!! This will delete EVERYTHING in $USB_DRIVE."
    wipefs -afq "$USB_DRIVE"
    parted "$USB_DRIVE" --script mktable gpt
    log_progress "$USB_DRIVE fully erased. Creating partitions..."
    parted -a optimal -m /dev/sda mkpart primary ext4 '0%' 2GB
    parted -a optimal -m /dev/sda mkpart primary ext4 2GB '100%'
    log_progress "Backing files and mutable partitions created."

    log_progress "Formatting new partitions..."
    # Force creation of filesystems even if previous filesystem appears to exist
    mkfs.ext4 -F -L mutable /dev/sda1
    mkfs.ext4 -F -L backingfiles /dev/sda2
  fi

  BACKINGFILES_MOUNTPOINT="$1"
  MUTABLE_MOUNTPOINT="$2"
  if grep -q backingfiles /etc/fstab
  then
    log_progress "backingfiles already defined in /etc/fstab. Not modifying /etc/fstab."
  else
    echo "LABEL=backingfiles $BACKINGFILES_MOUNTPOINT ext4 auto,rw,noatime 0 2" >> /etc/fstab
  fi
  if grep -q 'mutable' /etc/fstab
  then
    log_progress "mutable already defined in /etc/fstab. Not modifying /etc/fstab."
  else
    echo "LABEL=mutable $MUTABLE_MOUNTPOINT ext4 auto,rw 0 2" >> /etc/fstab
  fi
  log_progress "Done."
  exit 0
else
  echo "USB_DRIVE not set. Proceeding to SD card setup"
fi

# partition 3 and 4 either don't exist, or are the wrong type
if [ -e "${BOOT_DEVICE_PART}3" ] || [ -e "${BOOT_DEVICE_PART}4" ]
then
  log_progress "STOP: partitions already exist, but are not as expected"
  log_progress "please delete them and re-run setup"
  exit 1
fi

BACKINGFILES_MOUNTPOINT="$1"
MUTABLE_MOUNTPOINT="$2"

log_progress "Checking existing partitions..."

DISK_SECTORS=$(blockdev --getsz "${BOOT_DEVICE}")
LAST_DISK_SECTOR=$((DISK_SECTORS - 1))
# mutable partition is 100MB at the end of the disk, calculate its start sector
FIRST_MUTABLE_SECTOR=$((LAST_DISK_SECTOR-204800+1))
# backingfiles partition sits between the root and mutable partition, calculate its start sector and size
LAST_ROOT_SECTOR=$(sfdisk -l "${BOOT_DEVICE}" | grep "${BOOT_DEVICE_PART}2" | awk '{print $3}')
FIRST_BACKINGFILES_SECTOR=$((LAST_ROOT_SECTOR + 1))
BACKINGFILES_NUM_SECTORS=$((FIRST_MUTABLE_SECTOR - FIRST_BACKINGFILES_SECTOR))

# As a rule of thumb, one gigabyte of /backingfiles space can hold about 36
# recording files. We need enough inodes in /mutable to create symlinks to
# the recordings. Leaving enough headroom to account for short recordings,
# directories, duplication of sentry files in recentclips, etc, this works
# out to about 1 inode for every 20000 sectors in /backingfiles.
NUM_MUTABLE_INODES=$((BACKINGFILES_NUM_SECTORS / 20000))

ORIGINAL_DISK_IDENTIFIER=$( fdisk -l "${BOOT_DEVICE}" | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

log_progress "Modifying partition table for backing files partition..."
echo "$FIRST_BACKINGFILES_SECTOR,$BACKINGFILES_NUM_SECTORS" | sfdisk --force "${BOOT_DEVICE}" -N 3

log_progress "Modifying partition table for mutable (writable) partition for script usage..."
echo "$FIRST_MUTABLE_SECTOR," | sfdisk --force "${BOOT_DEVICE}" -N 4

# manually adding the partitions to the kernel's view of things is sometimes needed
if [ ! -e "${BOOT_DEVICE_PART}3" ] || [ ! -e "${BOOT_DEVICE_PART}4" ]
then
  partx --add --nr 3:4 "${BOOT_DEVICE}"
fi
if [ ! -e "${BOOT_DEVICE_PART}3" ] || [ ! -e "${BOOT_DEVICE_PART}4" ]
then
  log_progress "failed to add partitions"
  exit 1
fi

NEW_DISK_IDENTIFIER=$( fdisk -l "${BOOT_DEVICE}" | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

log_progress "Writing updated partitions to fstab and /boot/cmdline.txt"
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/g" /etc/fstab
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/" /boot/cmdline.txt

log_progress "Formatting new partitions..."
# Force creation of filesystems even if previous filesystem appears to exist
mkfs.ext4 -F -L backingfiles "${BOOT_DEVICE_PART}3"
mkfs.ext4 -F -N "$NUM_MUTABLE_INODES" -L mutable "${BOOT_DEVICE_PART}4"

echo "LABEL=backingfiles $BACKINGFILES_MOUNTPOINT ext4 auto,rw,noatime 0 2" >> /etc/fstab
echo "LABEL=mutable $MUTABLE_MOUNTPOINT ext4 auto,rw 0 2" >> /etc/fstab

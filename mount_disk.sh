sudo mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/[DEVICE_ID]
sudo mkdir -p /mnt/disks/[MNT_DIR]
sudo cp /etc/fstab /etc/fstab.backup
sudo blkid /dev/[DEVICE_ID]
/etc/fstab >> UUID=xxxxx-yyyy-xxxx-yyyy-zxcvbnm /mnt/disks/[MNT_DIR] ext4 discard,defaults,[NOFAIL] 0 2
mount /dev/sda1  /mnt/
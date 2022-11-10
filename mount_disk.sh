#!/bin/bash
##############################################################################################################################################################
# @author: Sameer Deshmukh
# Mount disk to linux machine, enable automount
##############################################################################################################################################################

set -e

mount_disk () {
  CURRENT_USER=$1

  read -p "Please enter mount directory full path: " MOUNT_DIR
  if [ -z "$MOUNT_DIR" ]; then
    echo "Invalid mount directory input"
    exit 1
  fi 

  read -p "Please enter device name (run lsblk): " DEVICE_NAME
  if [ -z "$DEVICE_NAME" ]; then
    echo "Invalid device name input"
    exit 1
  fi
  device_path="/dev/$DEVICE_NAME"

  #Disk Format
  read -p "Do you want  format the disk (it will wipe out the disk), (Y|y|N|n): " FORMAT_RESPONSE
  if [[ $FORMAT_RESPONSE == "Y" || $FORMAT_RESPONSE == "y" ]]; then
    mkfs.ext4 -I 128 $device_path 
    echo "Completed disk format"
  else
    echo "Skipped disk format, Warning: script might fail if disk is not in correct filesystem format..."
  fi
  
  #Disk Mount
  uuid_for_fstab=`blkid $device_path | awk '{print $2}'`

  if [ -z "$uuid_for_fstab" ]; then 
    echo "Disk incorrect Or not initialized/formatted properly, exiting.."
    exit 1
  else
    ##Create mount point
    mkdir -p $MOUNT_DIR
    echo "Created directory at mount point"
 
    ##mount disk
    mount $device_path $MOUNT_DIR

    ##add fstab entry
    line_for_fstab="$uuid_for_fstab $MOUNT_DIR ext4 defaults 0 2"
    echo -e "$line_for_fstab\n" >> /etc/fstab
    echo "Added entry in fstab"
  fi
  
  #Cleanup
  chown -R $CURRENT_USER:$CURRENT_USER $MOUNT_DIR
  echo "Disk Mount success!"

  #Test mount
  mount -a
}

main () {
  CURR_USER="$USER"
  DECL=`declare -f mount_disk`
  sudo bash -c "$DECL; mount_disk $CURR_USER" 
}

main
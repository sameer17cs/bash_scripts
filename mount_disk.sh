#!/bin/bash
##############################################################################################################################################################
# @author: Sameer Deshmukh
# Purpose: Linux operations
##############################################################################################################################################################

set -e

USER=$(whoami)
LIB_SCRIPT="_lib.sh"

mount_disk() {

  prompt_for_input MOUNT_DIR "Please enter mount directory full path" true

  prompt_for_input DEVICE_NAME "Please enter device name (run lsblk)" true

  device_path="/dev/$DEVICE_NAME"

  #Disk Format
  prompt_for_input FORMAT_RESPONSE "Do you want format the disk (it will wipe out the disk), (Y|y|N|n)" true

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
    echo -e "$line_for_fstab\n" | tee -a /etc/fstab
    echo "Added entry in fstab"
  fi
  
  #Cleanup
  chown -R $USER:$USER $MOUNT_DIR
  echo "Disk Mount success!"

  #Test mount
  mount -a
}

resize_disk() {
  prompt_for_input DEVICE_NAME "Please enter device name (run lsblk)" true
  device_path="/dev/$DEVICE_NAME"
  
  echo "Resizing filesystem on $device_path..."
  resize2fs $device_path
  echo "Filesystem resize completed on $device_path."
}

add_ssh_key() {
  prompt_for_input SSH_KEY_PATH "Please enter the full path of your SSH private key" true
  
  if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "The file $SSH_KEY_PATH does not exist."
    exit 1
  fi

  chmod 400 "$SSH_KEY_PATH"
  eval "$(ssh-agent -s)"
  ssh-add "$SSH_KEY_PATH"
  echo "SSH key added and permissions set."
}

main () {
  local option_selected=$1

  source $LIB_SCRIPT

  declare -a FUNCTIONS=(
    mount_disk
    resize_disk
    add_ssh_key
  )
  
  local ts_start=$(date +%F_%T)

  # Check if function exists & run it, otherwise list options
  if [[ " ${FUNCTIONS[@]} " =~ " $option_selected " ]]; then
    echo "---------------------------------------------------"
    echo -e "\033[0;32m Option selected: $option_selected \033[0m"
    echo "---------------------------------------------------"
    
    #call the function
    sudo bash -c "source $LIB_SCRIPT; $option_selected"

    local ts_end=$(date +%F_%T)
    echo -e "${C_GREEN} Script for $option_selected finished successfully. \n Begin at: $ts_start \n End at: $ts_end${C_DEFAULT}"

  else
    echo -e "${C_RED}Unknown option $option_selected, please choose from below options${C_DEFAULT}"
    _print_array_ "${FUNCTIONS[@]}"
  fi
}

main $1
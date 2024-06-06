#!/bin/bash
##############################################################################################################################################################
# @author: Sameer Deshmukh
# Purpose: Linux operations
##############################################################################################################################################################

set -e

USER=$(whoami)
LIB_SCRIPT="_lib.sh"

mount_disk() {

  _prompt_for_input_ MOUNT_DIR "Please enter mount directory full path" true

  _prompt_for_input_ DEVICE_NAME "Please enter device name (run lsblk)" true

  device_path="/dev/$DEVICE_NAME"

  #Disk Format
  _prompt_for_input_ FORMAT_RESPONSE "Do you want format the disk (it will wipe out the disk), (Y|y|N|n)" true

  if [[ $FORMAT_RESPONSE == "Y" || $FORMAT_RESPONSE == "y" ]]; then
    sudo mkfs.ext4 -I 128 $device_path 
    echo "Completed disk format"
  else
    echo "Skipped disk format, Warning: script might fail if disk is not in correct filesystem format..."
  fi
  
  #Disk Mount
  uuid_for_fstab=$(sudo blkid -s UUID -o value $device_path)
  echo "Device UUID: $uuid_for_fstab"

  if [ -z "$uuid_for_fstab" ]; then 
    echo "Disk incorrect Or not initialized/formatted properly, exiting.."
    exit 1
  fi
  
  ##Create mount point
  sudo mkdir -p $MOUNT_DIR
  echo "Created directory at mount point"
 
  ##mount disk
  sudo mount $device_path $MOUNT_DIR

  ##add fstab entry
  line_for_fstab="UUID=$uuid_for_fstab $MOUNT_DIR ext4 defaults 0 2"
  echo -e "$line_for_fstab\n" | sudo tee -a /etc/fstab
  echo "Added entry in fstab"
  
  #Cleanup
  echo "Changing directory owner to $USER"
  sudo chown -R $USER:$USER $MOUNT_DIR
  echo "Disk Mount success!"

  #Test mount
  sudo mount -a
}

resize_disk() {
  _prompt_for_input_ DEVICE_NAME "Please enter device name (run lsblk)" true
  device_path="/dev/$DEVICE_NAME"
  
  echo "Resizing filesystem on $device_path..."
  sudo resize2fs $device_path
  echo "Filesystem resize completed on $device_path."
}

add_ssh_key() {
  _prompt_for_input_ SSH_KEY_PATH "Please enter the full path of your SSH private key" true
  
  if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "The file $SSH_KEY_PATH does not exist."
    exit 1
  fi

  chmod 400 "$SSH_KEY_PATH"
  eval "$(ssh-agent -s)"
  ssh-add "$SSH_KEY_PATH"
  echo "SSH key added and permissions set."
}

distribute_files() {
  _prompt_for_input_ PARENT_DIR "Enter base directory full path"
  if [ ! -d "$PARENT_DIR" ]; then
    echo "Directory does not exist. Exiting."
    exit 1
  fi

  _prompt_for_input_ NUM_SUB_DIRS "Enter number of sub directories to create"
  if ! [[ "$NUM_SUB_DIRS" =~ ^[0-9]+$ ]]; then
    echo "Invalid number of sub directories. Exiting."
    exit 1
  fi

  _prompt_for_input_ SUB_DIRECTORY_PREFIX_ "Enter sub directory prefix"

  local temp_dir="$PARENT_DIR/temp"
  
  # Create specified number of sub directories in parent directory if they do not exist
  for i in $(seq 1 $NUM_SUB_DIRS); do
    if [ ! -d "$PARENT_DIR/$SUB_DIRECTORY_PREFIX_$i" ]; then
      mkdir "$PARENT_DIR/$SUB_DIRECTORY_PREFIX_$i"
    fi
  done

  # Create temporary directory
  mkdir "$temp_dir" || true

  # Move all files from parent directory and its sub directories to temporary directory
  find "$PARENT_DIR/" -type f -exec bash -c '
  src_file="$0"
  dest_file="'$temp_dir'/$(basename "$0")"
  if [ "$src_file" != "$dest_file" ]; then
    mv "$src_file" "$dest_file"
  fi' {} \;

  # Function to get the smallest directory
  get_smallest_directory() {
    local smallest_size=0
    local smallest_dir=""
    for i in $(seq 1 $NUM_SUB_DIRS); do
      local curr_dir="$PARENT_DIR/$SUB_DIRECTORY_PREFIX_$i"
      local curr_size=$(du -s "$curr_dir" | awk '{print $1}')
      if [ $i -eq 1 ] || [ $curr_size -lt $smallest_size ]; then
        smallest_size=$curr_size
        smallest_dir=$curr_dir
      fi
    done
    echo "$smallest_dir"
  }

  # Move all files from temporary directory to sub directories
  while [ $(ls -A "$temp_dir" | wc -l) -gt 0 ]; do
    smallest_dir=$(get_smallest_directory)
    file=$(ls -A "$temp_dir" | head -n 1)

    echo "moving $file ---> $smallest_dir"
    mv "$temp_dir/$file" "$smallest_dir"
  done

  # Remove temp directory
  rm -rf "$temp_dir"

  # Remove empty sub directories
  find "$PARENT_DIR" -type d -empty -delete
}

main () {
  local option_selected=$1
  source $LIB_SCRIPT

  declare -a FUNCTIONS=(
    mount_disk
    resize_disk
    add_ssh_key
    distribute_files
  )
  
  local ts_start=$(date +%F_%T)

  # Check if function exists & run it, otherwise list options
  if [[ " ${FUNCTIONS[@]} " =~ " $option_selected " ]]; then
    echo "---------------------------------------------------"
    echo -e "\033[0;32m Option selected: $option_selected \033[0m"
    echo "---------------------------------------------------"
    
    #call the function
    #sudo bash -c "$(declare -f $option_selected); source $LIB_SCRIPT; $option_selected"

    "$option_selected"

    local ts_end=$(date +%F_%T)
    echo -e "${C_GREEN} Script for $option_selected finished successfully. \n Begin at: $ts_start \n End at: $ts_end${C_DEFAULT}"

  else
    echo -e "${C_RED}Unknown option $option_selected, please choose from below options${C_DEFAULT}"
    _print_array_ "${FUNCTIONS[@]}"
  fi
}

main $1
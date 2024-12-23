#!/bin/bash
##############################################################################################################################################################
# @author: Sameer Deshmukh
# Purpose: Linux operations
##############################################################################################################################################################

set -e

USER=$(whoami)
LIB_SCRIPT="_lib.sh"

# Function: mount_disk
# Purpose: This function mounts a disk to a specified directory. 
#          It prompts the user to format the disk if needed, creates a mount point, mounts the device, 
#          and updates the fstab file for persistent mounting.
# 
mount_disk() {
  # Prompt for mount directory and device name
  _prompt_for_input_ MOUNT_DIR "Please enter mount directory full path" true
  _prompt_for_input_ DEVICE_NAME "Please enter device name (run lsblk)" true

  device_path="/dev/$DEVICE_NAME"

  # Disk Format Option
  _prompt_for_input_ FORMAT_RESPONSE "Do you want to format the disk (it will wipe out the disk), (Y|y|N|n)" true

  if [[ $FORMAT_RESPONSE == "Y" || $FORMAT_RESPONSE == "y" ]]; then
    # Define valid filesystems
    valid_filesystems=("ext4" "xfs" "btrfs")
    
    while true; do
      echo -e "Available filesystems: ${valid_filesystems[@]}"
      _prompt_for_input_ FILESYSTEM_TYPE "Please enter the filesystem type you want to use" true

      # Check if the entered filesystem type is valid
      if [[ " ${valid_filesystems[@]} " =~ " ${FILESYSTEM_TYPE} " ]]; then
        break
      else
        echo -e "${C_RED}Invalid filesystem type entered. Please choose from: ${valid_filesystems[@]}${C_DEFAULT}"
      fi
    done

    # Format the disk with the selected filesystem
    case $FILESYSTEM_TYPE in
      ext4)
        sudo mkfs.ext4 -F -I 128 $device_path
        ;;
      xfs)
        sudo mkfs.xfs -f $device_path
        ;;
      btrfs)
        sudo mkfs.btrfs -f $device_path
        ;;
    esac

    echo -e "${C_YELLOW}Completed disk format${C_DEFAULT}"
  else
    echo -e "${C_PURPLE}Skipped disk format${C_DEFAULT}"
  fi

  # Detect filesystem type (whether formatted or not)
  filesystem_type=$(sudo blkid -s TYPE -o value $device_path)
  if [ -z "$filesystem_type" ]; then
    echo -e "${C_RED}Could not detect filesystem type. Disk might not be formatted. Exiting...${C_DEFAULT}"
    exit 1
  fi
  echo -e "${C_BLUE}Detected filesystem type: $filesystem_type${C_DEFAULT}"

  # Disk Mount
  uuid_for_fstab=$(sudo blkid -s UUID -o value $device_path)
  echo -e "${C_BLUE}Device UUID: $uuid_for_fstab${C_DEFAULT}"

  if [ -z "$uuid_for_fstab" ]; then 
    echo -e "${C_RED}Disk incorrect or not initialized/formatted properly, exiting...${C_DEFAULT}"
    exit 1
  fi

  # Create mount point
  sudo mkdir -p $MOUNT_DIR
  echo -e "${C_BLUE}Created directory at mount point${C_DEFAULT}"

  # Mount disk
  sudo mount $device_path $MOUNT_DIR
  if [ $? -ne 0 ]; then
    echo -e "${C_RED}Failed to mount the disk. Exiting...${C_DEFAULT}"
    exit 1
  fi

  # Add fstab entry with defaults
  line_for_fstab="UUID=$uuid_for_fstab $MOUNT_DIR $filesystem_type defaults 0 2"
  echo -e "$line_for_fstab\n" | sudo tee -a /etc/fstab
  echo -e "${C_BLUE}Added entry in fstab${C_DEFAULT}"

  # Cleanup
  echo -e "${C_BLUE}Changing directory owner to $USER${C_DEFAULT}"
  sudo chown -R $USER:$USER $MOUNT_DIR
  echo -e "${C_GREEN}Disk mount success!${C_DEFAULT}"

  # Test mount
  sudo mount -a
}

# Function: resize_disk
# Purpose: This function resizes the filesystem on a specified disk device.
#          It prompts the user for the device name, then uses `resize2fs` to resize the filesystem to utilize all available space on the disk.
resize_disk() {
  _prompt_for_input_ DEVICE_NAME "Please enter device name (run lsblk)" true
  device_path="/dev/$DEVICE_NAME"
  
  echo -e "${C_BLUE} Resizing filesystem on $device_path...${C_DEFAULT}"
  sudo resize2fs $device_path
  echo -e "${C_GREEN} Filesystem resize completed on $device_path.${C_DEFAULT}"
}

# Function: rsync
# Purpose: This function performs parallel file synchronization from a source directory to a destination directory.
#          It prompts the user for the source and destination directories, validates them, 
#          and then uses `rsync` with parallel threads to optimize the file transfer.
rsync() {
  # Prompt for input values
  _prompt_for_input_ source_dir "Enter the source directory" true
  
  # Validate source directory
  while [[ ! -d "$source_dir" ]]; do
    echo -e "${C_RED}Source directory does not exist. Please provide a valid directory.${C_DEFAULT}"
    _prompt_for_input_ source_dir "Enter the source directory" true
  done

  _prompt_for_input_ dest_dir "Enter the destination directory" true
  
  # Validate destination directory
  while [[ ! -d "$dest_dir" ]]; do
    echo -e "${C_RED}Destination directory does not exist. Please provide a valid directory.${C_DEFAULT}"
    _prompt_for_input_ dest_dir "Enter the destination directory" true
  done

  _prompt_for_input_ parallel_count "Enter the number of parallel threads" true
  
  # Validate parallel thread count
  while ! [[ "$parallel_count" =~ ^[0-9]+$ ]]; do
    echo -e "${C_RED}Invalid parallel thread count. Please provide a positive integer.${C_DEFAULT}"
    _prompt_for_input_ parallel_count "Enter the number of parallel threads" true
  done

  # Perform parallel rsync copying
  cd "$source_dir" && find . -type f -print0 | xargs -0 -P "$parallel_count" -I{} rsync -av --relative {} "$dest_dir/"; cd -

}

# Function: add_ssh_key
# Purpose: This function adds an SSH private key to the SSH agent and sets appropriate file permissions.
#          It prompts the user for the key's file path, validates its existence, and then adds it to the SSH agent.
add_ssh_key() {
  _prompt_for_input_ SSH_KEY_PATH "Please enter the full path of your SSH private key" true
  
  if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${C_RED} The file $SSH_KEY_PATH does not exist.${C_DEFAULT}"
    exit 1
  fi

  chmod 400 "$SSH_KEY_PATH"
  eval "$(ssh-agent -s)"
  ssh-add "$SSH_KEY_PATH"
  echo -e "${C_GREEN} SSH key added and permissions set.${C_DEFAULT}"
}

# Function: extract
# Purpose: This function extracts various archive file types (.zip, .rar, .7z, .tar, .tar.gz, .tar.bz2) from an input directory to an output directory.
#          It checks for the presence of the 'unar' tool, installs it if needed, and handles extraction for each supported archive file.
extract() {
  # Check if 'unar' is installed; if not, install it based on Linux package manager
  if ! command -v unar &> /dev/null; then
    echo -e "${C_BLUE}unar is not installed. Installing...${C_DEFAULT}"
    
    # Detect package manager and install unar accordingly
    if command -v apt &> /dev/null; then
      sudo apt update && sudo apt install -y unar
    elif command -v yum &> /dev/null; then
      sudo yum install -y unar
    else
      echo -e "${C_RED}Unsupported package manager. Please install 'unar' manually.${C_DEFAULT}"
      exit 1
    fi

    # Re-check if 'unar' is available after installation
    if ! command -v unar &> /dev/null; then
      echo -e "${C_RED}Failed to install unar. Please install it manually and try again.${C_DEFAULT}"
      exit 1
    fi
  fi

  # Input and output directories: read from args or prompt
  INPUT_DIR="${1}"
  OUTPUT_DIR="${2}"
  if [[ -z "$INPUT_DIR" ]]; then
    read -rp "Please enter the input directory: " INPUT_DIR
  fi
  if [[ -z "$OUTPUT_DIR" ]]; then
    read -rp "Please enter the output directory: " OUTPUT_DIR
  fi

  # Ensure output directory exists
  mkdir -p "${OUTPUT_DIR}"

  # Find and process all archive files in the input directory
  find "${INPUT_DIR}" -type f \( -iname "*.zip" -o -iname "*.rar" -o -iname "*.7z" -o -iname "*.tar" -o -iname "*.tar.gz" -o -iname "*.tar.bz2" \) | while IFS= read -r archive; do
      # Generate output folder based on the archive path
      relative_path="${archive#${INPUT_DIR}/}"
      base_name="${relative_path%.*}"
      output_folder="${OUTPUT_DIR}/${base_name}"

      # Create target output directory
      mkdir -p "${output_folder}"

      # Extract archive contents into the designated output folder using unar
      echo -e "${C_BLUE}Extracting ${archive} to ${output_folder}...${C_DEFAULT}"
      unar -o "${output_folder}" "${archive}" || echo -e "${C_YELLOW}Warning: Some files in ${archive} could not be extracted.${C_DEFAULT}"
  done

  echo -e "${C_GREEN}Extraction completed.${C_DEFAULT}"
}

# Function: dir_balance
# Purpose: Split the contents of a directory into a specified number of smaller subdirectories of similar sizes.
#          This function supports distributing files that are in the base directory (level 0) or its immediate subdirectories (level 1).
dir_balance() {
  # Read base directory
  read -p "Enter base directory full path: " PARENT_DIR
  if [ -z "$PARENT_DIR" ]; then
    echo -e "${C_RED}Invalid directory${C_DEFAULT}"
    exit 1
  fi

  # Read number of subdirectories to create
  read -p "Enter number of subdirectories to create (default: 1): " NUM_SUB_DIRS
  NUM_SUB_DIRS=${NUM_SUB_DIRS:-1}

  # Constants
  SUB_DIRECTORY_PREFIX_="subdir_"

  # Helper function to find the subdirectory with the smallest size
  get_smallest_directory() {
    local smallest_size=0
    local smallest_dir=""
    for i in $(seq 1 $NUM_SUB_DIRS); do
      local curr_dir="$PARENT_DIR/$SUB_DIRECTORY_PREFIX_$i"
      local curr_size=$(du -s "$curr_dir" | awk '{print $1}')
      if [ $i -eq 1 ] || [ "$curr_size" -lt "$smallest_size" ]; then
        smallest_size=$curr_size
        smallest_dir=$curr_dir
      fi
    done
    echo "$smallest_dir"
    return
  }

  # Create specified number of subdirectories if they don't exist
  for i in $(seq 1 "$NUM_SUB_DIRS"); do
    local sub_dir="$PARENT_DIR/$SUB_DIRECTORY_PREFIX_$i"
    if [ ! -d "$sub_dir" ]; then
      mkdir "$sub_dir"
    fi
  done

  # Temporary directory to hold files for distribution
  local temp_dir="$PARENT_DIR/temp"
  mkdir -p "$temp_dir"

  # Move all files from the parent directory and its subdirectories to the temporary directory
  find "$PARENT_DIR" -type f -exec bash -c '
    src_file="$0"
    dest_file="'$temp_dir'/$(basename "$0")"
    if [ "$src_file" != "$dest_file" ]; then
      mv "$src_file" "$dest_file"
    fi' {} \;

  # Distribute files from the temporary directory to the subdirectories
  while [ "$(ls -A "$temp_dir" | wc -l)" -gt 0 ]; do
    smallest_dir=$(get_smallest_directory)
    file=$(ls -A "$temp_dir" | head -n 1)
    echo "Moving $file ---> $smallest_dir"
    mv "$temp_dir/$file" "$smallest_dir"
  done

  # Remove the temporary directory
  rm -rf "$temp_dir"

  # Remove any empty subdirectories left in the parent directory
  find "$PARENT_DIR" -type d -empty -delete

  echo -e "${C_GREEN}Distribution completed successfully.${C_DEFAULT}"
}

main () {
  local option_selected=$1
  source $LIB_SCRIPT

  declare -a FUNCTIONS=(
    mount_disk
    resize_disk
    rsync
    add_ssh_key
    extract
    dir_balance
  )
  
  # Check if function exists & run it, otherwise list options
  if [[ " ${FUNCTIONS[@]} " =~ " $option_selected " ]]; then
    echo "---------------------------------------------------"
    echo -e "\033[0;32m Option selected: $option_selected \033[0m"
    echo "---------------------------------------------------"
    
    #call the function
    shift
    "$option_selected" "$@"

  else
    echo -e "${C_RED}Unknown option $option_selected, please choose from below options${C_DEFAULT}"
    _print_array_ "${FUNCTIONS[@]}"
  fi
}

main "$@"
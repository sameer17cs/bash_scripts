#!/bin/bash
##############################################################################################################################################################
# @author: Sameer Deshmukh
# Purpose: Linux operations
##############################################################################################################################################################

set -e

USER=$(whoami)
LIB_SCRIPT="_lib.sh"

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

resize_disk() {
  _prompt_for_input_ DEVICE_NAME "Please enter device name (run lsblk)" true
  device_path="/dev/$DEVICE_NAME"
  
  echo -e "${C_BLUE} Resizing filesystem on $device_path...${C_DEFAULT}"
  sudo resize2fs $device_path
  echo -e "${C_GREEN} Filesystem resize completed on $device_path.${C_DEFAULT}"
}

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

extract() {
  # Check for 7z, install if not found
  if ! command -v 7z &> /dev/null; then
    echo -e "${C_BLUE} z (7-Zip) is not installed. Installing with apt ${C_DEFAULT}"
    sudo apt update && sudo apt install -y p7zip-full
    if ! command -v 7z &> /dev/null; then
      echo -e "${C_RED} Failed to install 7z. Please install it manually and try again.${C_DEFAULT}"
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
    # Generate output folder based on the archive path, stripping extension
    relative_path="${archive#${INPUT_DIR}/}"
    base_name="${relative_path%.*}"
    output_folder="${OUTPUT_DIR}/${base_name}"

    # Handle special cases for double extensions like .tar.gz or .tar.bz2
    if [[ "${archive}" == *.tar.gz || "${archive}" == *.tar.bz2 ]]; then
      base_name="${relative_path%.*.*}"
      output_folder="${OUTPUT_DIR}/${base_name}"
    fi

    # Create target output directory
    mkdir -p "${output_folder}"

    # Extract archive contents into the designated output folder
    echo -e "${C_BLUE} Extracting ${archive} to ${output_folder}...${C_DEFAULT}"
    7z x -o"${output_folder}" "${archive}" -y

    # Clean up unnecessary extensions in output folder names
    if [[ "${output_folder}" == *".zip"* || "${output_folder}" == *".rar"* || "${output_folder}" == *".7z"* || "${output_folder}" == *".tar"* ]]; then
      clean_name="${output_folder%.*}"
      mv "${output_folder}" "${clean_name}"
    fi
  done

  echo -e "${C_GREEN}Extraction completed.${C_DEFAULT}"
}

main () {
  local option_selected=$1
  source $LIB_SCRIPT

  declare -a FUNCTIONS=(
    mount_disk
    resize_disk
    rsync
    add_ssh_key
    distribute_files
    extract
  )
  
  # Check if function exists & run it, otherwise list options
  if [[ " ${FUNCTIONS[@]} " =~ " $option_selected " ]]; then
    echo "---------------------------------------------------"
    echo -e "\033[0;32m Option selected: $option_selected \033[0m"
    echo "---------------------------------------------------"
    
    #call the function
    #sudo bash -c "$(declare -f $option_selected); source $LIB_SCRIPT; $option_selected"
    shift
    "$option_selected" "$@"

  else
    echo -e "${C_RED}Unknown option $option_selected, please choose from below options${C_DEFAULT}"
    _print_array_ "${FUNCTIONS[@]}"
  fi
}



main "$@"
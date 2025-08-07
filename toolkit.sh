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
# Purpose: Recursively and in parallel, extract all supported archive files (.zip, .rar, .7z, .tar, .tar.gz, .tar.bz2) from an input directory to an output directory.
#          It preserves folder hierarchy, logs successes and failures to a 'meta' directory, handles nested archives, avoids double-nesting, and cleans up temporary files.
#          The temporary directory is created inside the output directory, and parallelization is handled with background jobs.
# Arguments:
#   $1: Input directory path.
#   $2: Output directory path.
#   $3: (Optional) Number of parallel threads to use (default: 4).
extract() {
  # --- Argument and Variable Setup ---
  local INPUT_DIR="${1}"
  local OUTPUT_DIR="${2}"
  local THREAD_COUNT="${3}"

  # Prompt for arguments if they are not provided
  if [[ -z "$INPUT_DIR" ]]; then
    read -rp "Please enter the input directory: " INPUT_DIR
  fi
  if [[ -z "$OUTPUT_DIR" ]]; then
    read -rp "Please enter the output directory: " OUTPUT_DIR
  fi
  if [[ -z "$THREAD_COUNT" ]]; then
    read -rp "Enter number of parallel threads (default: 4): " THREAD_COUNT
    THREAD_COUNT=${THREAD_COUNT:-4}
  fi

  # Create output and meta directories
  mkdir -p "${OUTPUT_DIR}/meta"
  local META_DIR="${OUTPUT_DIR}/meta"

  # Define log file paths
  local SUCCESS_LOG_FILE="${META_DIR}/success.log"
  local ERROR_LOG_FILE="${META_DIR}/error.log"
  # Touch log files to ensure they exist
  touch "$SUCCESS_LOG_FILE" "$ERROR_LOG_FILE"

  # Define archive patterns variable for reuse as an array
  local ARCHIVE_PATTERNS=(-iname "*.zip" -o -iname "*.rar" -o -iname "*.7z" -o -iname "*.tar" -o -iname "*.tar.gz" -o -iname "*.tar.bz2")

  # --- Helper Functions ---

  # Helper function to extract an archive and avoid double-nesting
  # Arguments:
  #   $1: Path to the archive file
  #   $2: Destination directory for extraction
  smart_extract_archive() {
    local archive_path="$1"
    local dest_dir="$2"
    local base_name
    base_name="$(basename "${archive_path%.*}")"
    mkdir -p "$dest_dir"  # Ensure destination directory exists
    local tmp_extract_dir
    # Create a unique temporary directory inside the meta folder
    tmp_extract_dir=$(mktemp -d "${META_DIR}/extract.XXXXXX")
    echo -e "${C_BLUE}Extracting $archive_path to temporary directory $tmp_extract_dir...${C_DEFAULT}"
    # Attempt to extract and log success or failure
    if unar -o "$tmp_extract_dir" "$archive_path"; then
        echo "$archive_path" >> "$SUCCESS_LOG_FILE"
    else
        echo -e "${C_YELLOW}Warning: Failed to extract ${archive_path}.${C_DEFAULT}"
        echo "$archive_path" >> "$ERROR_LOG_FILE"
    fi
    # Check for single top-level directory with same name as archive
    local top_level_items=("$tmp_extract_dir"/*)
    if [ ${#top_level_items[@]} -eq 1 ] && [ -d "${top_level_items[0]}" ]; then
      local single_dir_name
      single_dir_name="$(basename "${top_level_items[0]}")"
      if [ "$single_dir_name" = "$base_name" ]; then
        # Move contents of the single directory up one level to avoid double-nesting
        mv "${top_level_items[0]}"/* "$dest_dir" 2>/dev/null || true
        shopt -s dotglob
        mv "${top_level_items[0]}"/* "$dest_dir" 2>/dev/null || true
        shopt -u dotglob
        rmdir "${top_level_items[0]}"
      else
        # Move all extracted files/folders to destination
        mv "$tmp_extract_dir"/* "$dest_dir" 2>/dev/null || true
      fi
    else
      # Move all extracted files/folders to destination
      mv "$tmp_extract_dir"/* "$dest_dir" 2>/dev/null || true
    fi
    # Remove the temporary extraction directory
    rm -rf "$tmp_extract_dir"
  }

  # Helper function for recursive extraction of all nested archives
  # Arguments:
  #   $1: Base directory to search for archives
  #   $2: Number of parallel threads
  extract_archives_recursive() {
    local base_dir="$1"
    local thread_count="$2"
    while true; do
      local archives=()
      # Find all archives, using -print0 for safety, and read into an array
      while IFS= read -r -d $'\0' archive; do
          archives+=("$archive")
      done < <(find "$base_dir" -type f \( "${ARCHIVE_PATTERNS[@]}" \) -print0)
      
      # Exit loop if no archives are found
      if [ ${#archives[@]} -eq 0 ]; then
        break
      fi

      # Process archives in parallel using background jobs
      for archive in "${archives[@]}"; do
        # Pause if the number of running jobs reaches the thread limit
        while [[ $(jobs -p | wc -l) -ge $thread_count ]]; do
          wait -n # Wait for any single background job to finish
        done

        # Launch extraction and removal in a background subshell
        (
          archive_dir="${archive%.*}"
          smart_extract_archive "$archive" "$archive_dir"
          rm -f "$archive"
        ) &
      done
      
      # Wait for all jobs in the current batch to complete before finding more archives
      wait
    done
  }

  # Helper function to install dependencies (unar)
  install_dependencies() {
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
  }

  #### main logic flow ####
  
  install_dependencies  # Ensure unar is installed

  echo "Starting extraction with $THREAD_COUNT parallel threads..."

  # 1. Extract all archives in the top level of the input directory in parallel
  local top_level_archives=()
  while IFS= read -r -d $'\0' archive; do
      top_level_archives+=("$archive")
  done < <(find "$INPUT_DIR" -maxdepth 1 -type f \( "${ARCHIVE_PATTERNS[@]}" \) -print0)

  for archive in "${top_level_archives[@]}"; do
    while [[ $(jobs -p | wc -l) -ge "$THREAD_COUNT" ]]; do
      wait -n
    done
    
    (
      base_name="$(basename "$archive" | sed "s/\.[^.]*$//")"
      output_folder="$OUTPUT_DIR/$base_name"
      smart_extract_archive "$archive" "$output_folder"
    ) &
  done

  # Wait for all initial extractions to complete
  wait

  # 2. Copy all other non-archive files and directories from input to output, preserving structure
  # Copy non-archive files at the top level
  find "$INPUT_DIR" -maxdepth 1 -type f ! \( "${ARCHIVE_PATTERNS[@]}" \) -exec cp '{}' "$OUTPUT_DIR/" \;
  # Copy non-archive directories (excluding . and ..)
  find "$INPUT_DIR" -mindepth 1 -maxdepth 1 -type d -exec bash -c '
    dir="$1"
    base="$(basename "$dir")"
    cp -r "$dir" "$2/$base"
  ' _ '{}' "$OUTPUT_DIR" \;

  # 3. Recursively extract any remaining archives found in the output directory, in parallel
  extract_archives_recursive "$OUTPUT_DIR" "$THREAD_COUNT"

  # --- Final Counts and Cleanup ---
  
  # Count the total number of unzipped archives
  local unzipped_files_count
  unzipped_files_count=$(wc -l < "$SUCCESS_LOG_FILE" | tr -d ' ')

  # Count the number of failed extractions
  local error_files_count
  error_files_count=$(wc -l < "$ERROR_LOG_FILE" | tr -d ' ')
  
  # Count the total number of files in the output directory
  local total_output_files
  total_output_files=$(find "$OUTPUT_DIR" -path "${META_DIR}" -prune -o -type f | wc -l)

  # Final cleanup of temporary marker files
  find "$OUTPUT_DIR" -name '*.extracted_marker' -delete # Remove any marker files left by unar

  echo -e "\n${C_GREEN}---- Extraction Summary ----${C_DEFAULT}"
  echo -e "Successfully unzipped: ${C_GREEN}${unzipped_files_count}${C_DEFAULT} archives."
  echo -e "Failed to extract:    ${C_RED}${error_files_count}${C_DEFAULT} archives."
  echo -e "Total files in output: ${C_BLUE}${total_output_files}${C_DEFAULT} files."
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

# Function: gzip_dir
# Purpose: Compress all files in a specified directory using gzip compression.
#          Uses xargs to compress files in parallel with gzip verbose output.
# Arguments:
#   $1: Directory path containing files to compress (optional, will prompt if not provided)
#   $2: Number of parallel processes (optional, will prompt if not provided, default: 4, max: 10)
gzip_dir() {
  local TARGET_DIR="${1}"
  local PARALLEL_COUNT="${2}"

  # Prompt for arguments if they are not provided
  if [[ -z "$TARGET_DIR" ]]; then
    _prompt_for_input_ TARGET_DIR "Please enter the directory path containing files to compress" true
  fi

  if [[ -z "$PARALLEL_COUNT" ]]; then
    _prompt_for_input_ PARALLEL_COUNT "Please enter the number of parallel processes (default: 4)" false
    PARALLEL_COUNT=${PARALLEL_COUNT:-4}
  fi

  # Validate directory exists
  if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "${C_RED}Error: Directory '$TARGET_DIR' does not exist.${C_DEFAULT}"
    exit 1
  fi

  # Validate parallel count is a positive integer
  if ! [[ "$PARALLEL_COUNT" =~ ^[0-9]+$ ]] || [[ "$PARALLEL_COUNT" -lt 1 ]]; then
    echo -e "${C_RED}Error: Parallel count must be a positive integer.${C_DEFAULT}"
    exit 1
  fi

  # Read all compressible files into array (only once!)
  local files_to_compress=()
  while IFS= read -r file; do
    [[ -n "$file" ]] && files_to_compress+=("$file")
  done < <(find "$TARGET_DIR" -maxdepth 1 -type f ! -name "*.gz" ! -name ".*" ! -name "*.zip" ! -name "*.bz2" ! -name "*.xz" ! -name "*.7z" ! -name "*.rar" ! -name "*.tar")
  
  # Check array size
  local total_files=${#files_to_compress[@]}
  
  # Exit if no files to compress
  if [[ $total_files -eq 0 ]]; then
    echo -e "${C_YELLOW}No files to compress found.${C_DEFAULT}"
    return 0
  fi
  
  # Compress files in parallel using xargs
  echo -e "${C_PURPLE}Found $total_files files to compress, starting parallel compression with $PARALLEL_COUNT processes...${C_DEFAULT}"
  
  local start_time=$(date +%s)
  
  # Use xargs to compress files in parallel with gzip verbose output
  printf '%s\n' "${files_to_compress[@]}" | xargs -P "$PARALLEL_COUNT" -I {} gzip -9 -f -v {}
  
  local end_time=$(date +%s)
  local total_duration=$((end_time - start_time))
  echo -e "${C_GREEN}[$(date '+%H:%M:%S')] All compression jobs completed in ${total_duration}s${C_DEFAULT}"
  
  # Show compression statistics
  echo -e "${C_PURPLE}Compression Statistics:${C_DEFAULT}"
  local total_orig=0 total_comp=0
  for file in "${files_to_compress[@]}"; do
    local gz_file="${file}.gz"
    if [[ -f "$gz_file" ]]; then
      local gzip_info=$(gzip -l "$gz_file" | tail -1)
      local comp_size=$(echo "$gzip_info" | awk '{print $1}')
      local orig_size=$(echo "$gzip_info" | awk '{print $2}')
      local percent=$(echo "scale=2; (($orig_size - $comp_size) * 100) / $orig_size" | bc -l 2>/dev/null || echo "0")
      local orig_mb=$(bytes_to_mb $orig_size)
      local comp_mb=$(bytes_to_mb $comp_size)
      echo -e "${C_BLUE}  $(basename "$file"): ${orig_mb}MB → ${comp_mb}MB (${percent}% saved)${C_DEFAULT}"
      total_orig=$((total_orig + orig_size))
      total_comp=$((total_comp + comp_size))
    fi
  done
  local total_percent=$(echo "scale=2; (($total_orig - $total_comp) * 100) / $total_orig" | bc -l 2>/dev/null || echo "0")
  local total_orig_mb=$(bytes_to_mb $total_orig)
  local total_comp_mb=$(bytes_to_mb $total_comp)
  echo -e "${C_PURPLE}Total: ${total_orig_mb}MB → ${total_comp_mb}MB (${total_percent}% saved)${C_DEFAULT}"
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
    gzip_dir
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
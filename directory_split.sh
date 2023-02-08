#!/bin/bash

############################################################################################################################################
# @author: Sameer Deshmukh
# Purpose: Split the contents of a directory into smaller subdirectories, of similar sizes
#          Currently it only supports distributing files which are in parent directory or files in subdirectories (level 0 and 1)
############################################################################################################################################

set -e

PARENT_DIR=''
NUM_SUB_DIRS=1
SUB_DIRECTORY_PREFIX_="subdir_"

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
  return
}

distribute_files() {
  local temp_dir="$PARENT_DIR/temp"
  # Create specified number of sub directories in parent directory if they do not exist
  for i in $(seq 1 $NUM_SUB_DIRS); do
    if [ ! -d "$PARENT_DIR/$SUB_DIRECTORY_PREFIX_$i" ]; then
      mkdir $PARENT_DIR/$SUB_DIRECTORY_PREFIX_$i
    fi
  done

  # Create temporary directory
  mkdir $temp_dir || true

  # Move all files from parent directory and its sub directories to temporary directory
  find $PARENT_DIR/ -type f -exec bash -c '
  src_file="$0"
  dest_file="'$temp_dir'/$(basename "$0")"
  if [ "$src_file" != "$dest_file" ]; then
    mv "$src_file" "$dest_file"
  fi' {} \;

  # Move all files from temporary directory to sub directories
  while [ $(ls -A $temp_dir | wc -l) -gt 0 ]; do
    smallest_dir=$(get_smallest_directory)
    file=$(ls -A $temp_dir | head -n 1)

    echo "moving $file ---> $smallest_dir"
    mv $temp_dir/$file $smallest_dir
  done

  # remove temp directory
  rm -rf $temp_dir

  #Remove empty sub directories
  find "$PARENT_DIR" -type d -empty -delete
}

main() {
  read -p "Enter base directory full path: " base_dir
  if [ -z "$base_dir" ]; then
    echo "Invalid directory"
    exit 1
  else 
    PARENT_DIR=$base_dir
  fi

  read -p "Enter number of sub directories to create (default: $NUM_SUB_DIRS ): " subdir_count
  if [[ ! -z "$subdir_count" && "$subdir_count" -ne 0 ]]; then
    NUM_SUB_DIRS=$subdir_count
  fi
  distribute_files
}

main
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

find_smallest_dir() {
  if [ $NUM_SUB_DIRS -eq 1 ]; then
    echo 1
    return
  fi
  local size_subdirs=()
  for i in $(seq 1 $NUM_SUB_DIRS); do
    size_subdirs[$i]=$(du -s "$PARENT_DIR/$SUB_DIRECTORY_PREFIX_$i" | awk '{print $1}')
  done
  local min_size=${size_subdirs[1]}
  local min_index=1
  for i in $(seq 2 $NUM_SUB_DIRS); do
    if [ ${size_subdirs[$i]} -lt $min_size ]; then
      min_size=${size_subdirs[$i]}
      min_index=$i
      break
    fi
  done
  echo $min_index
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
  mkdir $temp_dir

  # Move all files from parent directory and its sub directories to temporary directory
  find $PARENT_DIR/ -type f -exec mv {} $temp_dir \;

  # Move all files from temporary directory to sub directories
  while [ $(ls -A $temp_dir | wc -l) -gt 0 ]; do
    min_index=$(find_smallest_dir)
    file=$(ls -A $temp_dir | head -n 1)
    mv $temp_dir/$file $PARENT_DIR/$SUB_DIRECTORY_PREFIX_$min_index
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
#!/bin/bash

# Set the desired file descriptor limit
FILE_MAX=9999999
SOFT_LIMIT=9999999
HARD_LIMIT=9999999

LIB_SCRIPT="_lib.sh"

# Function to update /etc/sysctl.conf
update_sysctl_conf() {
  local sysctl_conf="/etc/sysctl.conf"
  if grep -q "fs.file-max" "$sysctl_conf"; then
    sudo sed -i "s/^fs.file-max.*/fs.file-max = $FILE_MAX/" "$sysctl_conf"
  else
    echo "fs.file-max = $FILE_MAX" | sudo tee -a "$sysctl_conf"
  fi
  echo -e "${C_BLUE}Modified $sysctl_conf${C_DEFAULT}"
}

# Function to update /etc/security/limits.conf
update_limits_conf() {
  local limits_conf="/etc/security/limits.conf"
  if ! grep -q "\* soft nofile" "$limits_conf"; then
    echo "* soft nofile $SOFT_LIMIT" | sudo tee -a "$limits_conf"
  else
    sudo sed -i "s/^\* soft nofile.*/\* soft nofile $SOFT_LIMIT/" "$limits_conf"
  fi

  if ! grep -q "\* hard nofile" "$limits_conf"; then
    echo "* hard nofile $HARD_LIMIT" | sudo tee -a "$limits_conf"
  else
    sudo sed -i "s/^\* hard nofile.*/\* hard nofile $HARD_LIMIT/" "$limits_conf"
  fi

  echo -e "${C_BLUE}Modified $limits_conf${C_DEFAULT}"
}

# Function to update PAM configuration
update_pam_limits() {
  local pam_files=("/etc/pam.d/common-session" "/etc/pam.d/common-session-noninteractive")
  for file in "${pam_files[@]}"; do
    if ! grep -q "session required pam_limits.so" "$file"; then
      echo "session required pam_limits.so" | sudo tee -a "$file"
      echo -e "${C_BLUE}Modified $file${C_DEFAULT}"
    fi
  done
}

# Apply changes and reboot
apply_changes() {
  sudo sysctl -p
  echo "Changes applied. A reboot is recommended to fully apply all changes."
}

# Main function
main() {
  source $LIB_SCRIPT
  echo -e "${C_GREEN}Updating system file descriptor limits...${C_DEFAULT}"
  update_sysctl_conf
  update_limits_conf
  update_pam_limits
  apply_changes
}

# Run the main function
main

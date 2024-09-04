#!/bin/bash

# Define the new file descriptor limit
NEW_LIMIT=500000
NEW_FILE_MAX=1000000
USER=$(whoami)

# Function to update the system-wide file descriptor limit
update_sysctl() {
    echo "Updating /etc/sysctl.conf with fs.file-max=$NEW_FILE_MAX"
    if grep -q "fs.file-max" /etc/sysctl.conf; then
        sudo sed -i 's/fs.file-max.*/fs.file-max = '"$NEW_FILE_MAX"'/g' /etc/sysctl.conf
    else
        echo "fs.file-max = $NEW_FILE_MAX" | sudo tee -a /etc/sysctl.conf
    fi
    sudo sysctl -p
}

# Function to update the per-user limits in limits.conf
update_limits_conf() {
    echo "Updating /etc/security/limits.conf with soft and hard nofile limits"
    if ! grep -q "$USER soft nofile" /etc/security/limits.conf; then
        echo "$USER soft nofile $NEW_LIMIT" | sudo tee -a /etc/security/limits.conf
    else
        sudo sed -i 's/'"$USER"' soft nofile.*/'"$USER"' soft nofile '"$NEW_LIMIT"'/g' /etc/security/limits.conf
    fi

    if ! grep -q "$USER hard nofile" /etc/security/limits.conf; then
        echo "$USER hard nofile $NEW_LIMIT" | sudo tee -a /etc/security/limits.conf
    else
        sudo sed -i 's/'"$USER"' hard nofile.*/'"$USER"' hard nofile '"$NEW_LIMIT"'/g' /etc/security/limits.conf
    fi
}

# Function to update the PAM configuration
update_pam_config() {
    echo "Updating PAM configuration"
    if ! grep -q "session required pam_limits.so" /etc/pam.d/common-session; then
        echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session
    fi
    
    if ! grep -q "session required pam_limits.so" /etc/pam.d/common-session-noninteractive; then
        echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session-noninteractive
    fi
}

# Function to update systemd system.conf and user.conf
update_systemd_conf() {
    echo "Updating systemd limits in /etc/systemd/system.conf and /etc/systemd/user.conf"
    sudo sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE='"$NEW_LIMIT"'/' /etc/systemd/system.conf
    sudo sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE='"$NEW_LIMIT"'/' /etc/systemd/user.conf

    if ! grep -q "^DefaultLimitNOFILE" /etc/systemd/system.conf; then
        echo "DefaultLimitNOFILE=$NEW_LIMIT" | sudo tee -a /etc/systemd/system.conf
    fi

    if ! grep -q "^DefaultLimitNOFILE" /etc/systemd/user.conf; then
        echo "DefaultLimitNOFILE=$NEW_LIMIT" | sudo tee -a /etc/systemd/user.conf
    fi
}

# Apply changes
update_sysctl
update_limits_conf
update_pam_config
update_systemd_conf

# Reload systemd configuration
echo "Reloading systemd daemon"
sudo systemctl daemon-reload

# Display instructions
echo "Reboot your system or log out and log back in to apply the changes."
echo "To check the new limit, run: ulimit -n"

#!/bin/bash

##############################################################################################################################################################
# @author: Sameer Deshmukh
# Purpose: Linux operations
# Description: 
# This script is intended for configuring a watchdog on a Linux system that will reboot the machine if it becomes unresponsive for 2 minutes.
# It automates the installation, configuration, and enabling of the watchdog service, utilizing the software watchdog (softdog).
# The script uses a modular function-based approach to maintain clear separation of responsibilities.
##############################################################################################################################################################

# Ensure the script is being run with root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run this script as root (using sudo)."
        exit 1
    fi
}

# Step 1: Install the watchdog package
install_watchdog() {
    echo "Installing the watchdog package..."
    apt-get update && apt-get install -y watchdog
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install watchdog. Please check your network connection or package manager settings."
        exit 1
    fi
    echo "Watchdog package installed successfully."
}

# Step 2: Load the softdog kernel module
load_softdog() {
    echo "Loading the softdog kernel module..."
    modprobe softdog
    if [ $? -ne 0 ]; then
        echo "Error: Failed to load softdog module. Ensure your kernel supports softdog."
        exit 1
    fi

    # Ensure softdog loads at boot
    echo "Ensuring softdog loads at boot..."
    if ! grep -q "^softdog" /etc/modules; then
        echo "softdog" >> /etc/modules
    fi
    echo "Softdog module will now load at boot."
}

# Step 3: Configure the watchdog daemon to restart after 2 minutes of unresponsiveness
configure_watchdog() {
    echo "Configuring watchdog daemon to restart the system if unresponsive for 2 minutes..."

    # Backup existing configuration if not already backed up
    if [ ! -f /etc/watchdog.conf.bak ]; then
        cp /etc/watchdog.conf /etc/watchdog.conf.bak
        echo "Backup of watchdog.conf created at /etc/watchdog.conf.bak"
    fi

    # Update watchdog.conf with minimal required settings
    cat <<EOL > /etc/watchdog.conf
watchdog-device = /dev/watchdog
watchdog-timeout = 120
interval = 60
reboot = yes
EOL

    echo "Watchdog configuration updated to reboot the machine if unresponsive for 2 minutes."
}

# Step 4: Enable and start the watchdog service
enable_watchdog_service() {
    echo "Enabling and starting the watchdog service..."
    systemctl enable watchdog
    if [ $? -ne 0 ]; then
        echo "Error: Failed to enable watchdog service. Exiting."
        exit 1
    fi

    systemctl start watchdog
    if [ $? -ne 0 ]; then
        echo "Error: Failed to start watchdog service. Exiting."
        exit 1
    fi
    echo "Watchdog service is now enabled and running."
}

# Step 5: Display the status of the watchdog service
display_watchdog_status() {
    echo "Displaying the status of the watchdog service..."
    systemctl status watchdog
    if [ $? -ne 0 ]; then
        echo "Error: Failed to retrieve the watchdog service status."
        exit 1
    fi
}

# Main function to call all steps
main() {
    check_root
    install_watchdog
    load_softdog
    configure_watchdog
    enable_watchdog_service
    display_watchdog_status
}

# Execute main function
main

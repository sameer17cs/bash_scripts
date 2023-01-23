## Mount Disk
 - script: mount_disk.sh
 - Description: Automate external disk mounting in a linux
 - Keywords: "disk mount", "fstab", "automount", "disk format", "ext4"

 ## Nix Tuning
 - script: nix_tuning.sh
 - Description: Parameter tuning for linux system for scaling
 - Keywords: "performance", "scale", "tuning" 

 ## Install Docker
 - script: install_docker.sh
 - Description: Properly install/uninstall docker
 - Keywords: "docker", "docker-compose"

## Install Tools
 - script: install_tools.sh
 - Description: Script to install some useful tools via Docker or apt-get
 - Keywords: "mongodb", "elasticsearch", "redis", "neo4j", "redash", "nginx", "nginx_certbot"
## GCP Firewall: 
 - script: ./gcloud_firewall.sh `your firewall rule name`
 - Description: Add your dynamic ip to firewall rules in gcp

## AWS Firewall: 
 - script: ./aws_firewall.sh `security group id` `security group rule id` `port number`
 - Description: Add your dynamic ip to security group in aws

## Directory Distribution
 - script: ./directory_split.sh
 - Description: Allows you move split a large directory into smaller directories
#!/bin/bash

##############################################################################################################################################################
# @author: Sameer Deshmukh
# Purpose: Configure system kernel parameters and limits for performance tuning on Ubuntu
##############################################################################################################################################################

set -e

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

# Kernel parameters
echo 327680000 > /proc/sys/net/core/wmem_max
echo 327680000 > /proc/sys/net/core/wmem_default
echo 1310720000 > /proc/sys/net/core/rmem_max
echo 1310720000 > /proc/sys/net/core/rmem_default
echo 3285814 > /proc/sys/fs/file-max
echo 1 > /proc/sys/net/ipv4/tcp_tw_recycle
echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse
echo 360000 > /proc/sys/net/ipv4/tcp_max_tw_buckets
echo 15 > /proc/sys/net/ipv4/tcp_fin_timeout
echo 65536 > /proc/sys/net/ipv4/tcp_max_syn_backlog
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
echo "1024 65535" > /proc/sys/net/ipv4/ip_local_port_range
echo 100000 > /proc/sys/net/core/netdev_max_backlog
echo 1 > /proc/sys/net/ipv4/route/flush
echo 1 > /proc/sys/net/ipv4/tcp_fin_timeout

# Setting interface queue length
ifconfig eth0 txqueuelen 10000

# Update /etc/sysctl.conf
sysctl_conf="/etc/sysctl.conf"

declare -A sysctl_params=(
  ["net.ipv4.tcp_rmem"]="4096 87380 16777216"
  ["net.ipv4.tcp_wmem"]="4096 16384 16777216"
  ["net.ipv4.ip_local_port_range"]="1024 65535"
  ["net.core.somaxconn"]="30000"
  ["net.ipv4.tcp_mem"]="4200000 4200000 4200000"
  ["net.ipv4.tcp_max_orphans"]="131072"
)

for param in "${!sysctl_params[@]}"; do
  sed -i "/\b\($param\)\b/d" "$sysctl_conf"
  echo "$param = ${sysctl_params[$param]}" >> "$sysctl_conf"
done

# Update /etc/pam.d/common-session
pam_conf="/etc/pam.d/common-session"
sed -i "/\b\(session required pam_limits.so\)\b/d" "$pam_conf"
echo "session required pam_limits.so" >> "$pam_conf"

# Update /etc/security/limits.conf
limits_conf="/etc/security/limits.conf"
declare -A limits_params=(
  ["root -nofile"]="999999"
  ["root soft nofile"]="999999"
  ["root hard nofile"]="999999"
)

for param in "${!limits_params[@]}"; do
  sed -i "/\b\(${param%% *}\)\b/d" "$limits_conf"
  echo "$param ${limits_params[$param]}" >> "$limits_conf"
done

# Apply the new limits
ulimit -n 999999

# Reload configurations
ldconfig
sysctl -p

echo "System limits modified successfully."

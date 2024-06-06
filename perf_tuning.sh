#!/bin/bash
##############################################################################################################################################################
# @author: Sameer Deshmukh
# Kernel parameter tuning for linux system to handle heavy load
##############################################################################################################################################################

set -e
echo 327680000 > /proc/sys/net/core/wmem_max
echo 327680000 > /proc/sys/net/core/wmem_default
echo 1310720000 > /proc/sys/net/core/rmem_max
echo 1310720000 > /proc/sys/net/core/rmem_default
echo 3285814 > /proc/sys/fs/file-max
echo 1 >/proc/sys/net/ipv4/tcp_tw_reuse
echo 360000 > /proc/sys/net/ipv4/tcp_max_tw_buckets
echo 15 > /proc/sys/net/ipv4/tcp_fin_timeout
echo 65536 > /proc/sys/net/ipv4/tcp_max_syn_backlog
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
echo "1024 65535" > /proc/sys/net/ipv4/ip_local_port_range
echo 100000 > /proc/sys/net/core/netdev_max_backlog
echo 1 > /proc/sys/net/ipv4/route/flush
echo 1 > /proc/sys/net/ipv4/tcp_fin_timeout
ifconfig eth0 txqueuelen 10000

#Append values in file (delete the line first, then re-insert with new values 
sed -i "/\b\(net.ipv4.tcp_rmem\)\b/d" /etc/sysctl.conf
echo "net.ipv4.tcp_rmem = 4096  87380   16777216" >> /etc/sysctl.conf

sed -i "/\b\(net.ipv4.tcp_wmem\)\b/d" /etc/sysctl.conf
echo "net.ipv4.tcp_wmem = 4096  16384   16777216" >> /etc/sysctl.conf

sed -i "/\b\(net.ipv4.ip_local_port_range\)\b/d" /etc/sysctl.conf
echo "net.ipv4.ip_local_port_range = 1024 65535" >> /etc/sysctl.conf

sed -i "/\b\(net.core.somaxconn\)\b/d" /etc/sysctl.conf
echo "net.core.somaxconn = 30000" >> /etc/sysctl.conf

sed -i "/\b\(net.ipv4.tcp_mem\)\b/d" /etc/sysctl.conf
echo "net.ipv4.tcp_mem = 4200000 4200000 4200000" >> /etc/sysctl.conf

sed -i "/\b\(net.ipv4.tcp_max_orphans\)\b/d" /etc/sysctl.conf
echo "net.ipv4.tcp_max_orphans = 131072" >> /etc/sysctl.conf

sed -i "/\b\(session required pam_limits.so\)\b/d" /etc/pam.d/common-session
echo "session   required        pam_limits.so"  >> /etc/pam.d/common-session

sed -i "/\b\(root -nofile\)\b/d" /etc/security/limits.conf
echo "root -nofile 999999" >> /etc/security/limits.conf

sed -i "/\b\(root soft nofile\)\b/d" /etc/security/limits.conf
echo "root soft nofile 999999" >> /etc/security/limits.conf

sed -i "/\b\(root hard nofile\)\b/d" /etc/security/limits.conf
echo "root hard nofile 999999" >> /etc/security/limits.conf

ulimit -n 999999

ldconfig
sysctl  -p
echo "system limits modified"
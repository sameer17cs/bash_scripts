#!/bin/bash
set -e
# update a security group rule allowing 
# your current IPv4 I.P. to connect on port 22 (SSH)

# Values to identify sec group and sec group rule
SECURITY_GROUP_ID=$1
SECURITY_GROUP_RULE_ID=$2
PORT_TO_OPEN=$3

CURRENT_DATE=$(date +'%Y-%m-%d')

# description updated
SECURITY_GROUP_RULE_DESCRIPTION="My dynamic ip updated on ${CURRENT_DATE}"

# gets I.P. and adds /32 for ipv4 cidr
CURRENT_IP=$(curl --silent https://checkip.amazonaws.com)
NEW_IPV4_CIDR="${CURRENT_IP}"/32

# updates the public IP in the rule
aws ec2 modify-security-group-rules --group-id ${SECURITY_GROUP_ID} --security-group-rules SecurityGroupRuleId=${SECURITY_GROUP_RULE_ID},SecurityGroupRule="{CidrIpv4=${NEW_IPV4_CIDR}, IpProtocol=tcp,FromPort=$PORT_TO_OPEN,ToPort=$PORT_TO_OPEN,Description=${SECURITY_GROUP_RULE_DESCRIPTION}}"

# shows the rule updated
aws ec2 describe-security-group-rules --filter Name="security-group-rule-id",Values="${SECURITY_GROUP_RULE_ID}"
echo "AWS Security group modified with new IP ${NEW_IPV4_CIDR}"
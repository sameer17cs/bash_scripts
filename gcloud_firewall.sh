#!/bin/bash
set -e
#initialize vars
describe=null
existing_ipv4=null
my_ipv4=null
my_ipv6=null

#Get my public ip (v4) from internet
get_my_public_ipv4() {
    my_ipv4=`dig @resolver1.opendns.com A myip.opendns.com +short -4`
    my_ipv6=`dig @resolver1.opendns.com AAAA myip.opendns.com +short -6`
    echo "my ip v4: $my_ipv4"
    echo "my ip v6: $my_ipv6"
}

add_exisiting_ips() {
    N=3;
    existing_ipv4=`echo $describe`
    rm1='SRC_RANGES:' rm2='DEST_RANGES:'
    existing_ipv4=`echo ${existing_ipv4/$rm1/}`
    existing_ipv4=`echo ${existing_ipv4/$rm2/}`
    existing_ipv4=`echo ${existing_ipv4}| xargs`
    echo "Existing Ips: $existing_ipv4"
}

#get details about my firewall rule
FIREWALL_RULE=$1

if [ -z "$FIREWALL_RULE" ]
then
      echo "Enter firewall rule name (only 1 allowed)"
else
      describe=`gcloud compute firewall-rules describe $FIREWALL_RULE --format="table(sourceRanges.list():label=SRC_RANGES,destinationRanges.list():label=DEST_RANGES)"`

      #extract and map requisties
      get_my_public_ipv4
      add_exisiting_ips
      finalList="$my_ipv4,$existing_ipv4"
      finalList=`echo ${finalList}| xargs`
      #final list can contain duplicates,it is handled by gcp
      echo "FinalList Ips: $finalList"

      #update firewall rule
      #gcloud compute firewall-rules update $FIREWALL_RULE --source-ranges=$existing_ipv4,$my_ipv4
      gcloud compute firewall-rules update $FIREWALL_RULE --source-ranges=$my_ipv4
      echo "Firewall updated for tag: $FIREWALL_RULE"
fi

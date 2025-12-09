#!/bin/bash
##
## Drive detector


echo ">> Checking block devices (SSD = ROTA 0):"
lsblk_data=$(lsblk -o NAME,ROTA,TYPE,MOUNTPOINT,MODEL | grep -v loop | awk 'NR==1 || $2==0')

if command -v nvme &> /dev/null; then
    echo ">> NVMe drives detected:"
    nvme_data=$(nvme list | grep '/dev/' | awk '{print $1}')
else
    echo ">> nvme-cli not installed. Skipping NVMe-specific listing."
    echo "   To install: sudo apt install nvme-cli"
fi

merge=$(echo -e "$lsblk_data\n$nvme_data")

echo "--"
echo "$merge"
echo "------"

#! /bin/bash
#=======================================================================#
#                    FreeHPC Basic Setup for Rocky Linux 8.10           #
#=======================================================================#


# Load environment variables
. $HOME/env.conf

# check environment variable
if [ -z "$SOFT_SERV" ]; then
    echo "Error: The environmenal variable SOFT_SERV is empty."
    exit -1
fi

# obtain system information: ip addr show ib0|grep -i link|awk '{print $2}'
mst_guid=$(ip addr show ib0|grep infiniband|awk '{print $2}'|awk -F: '{for(i=NF-7; i<=NF; i++) printf "%s", $i; print ""}')
MST_IP=$(ip addr show $IB_DEV|grep "inet "|awk -F "/" '{print $1}'|awk '{print $2}')
IP_PRE=$(echo $MST_IP|awk -F "." '{print $1"."$2"."$3}')


# Download ibpxe program from abhpc server
rm -rf /usr/bin/ibpxe
wget $SOFT_SERV/uefi/ibpxe-${mst_guid}.el8 --no-check-certificate -O /usr/bin/ibpxe
chmod +x /usr/bin/ibpxe

# Check if ibpxe is ready
if [ ! -f /usr/bin/ibpxe ]; then
    echo "Error: /usr/bin/ibpxe does not exist."
    exit 0
fi

# Check if guid.txt is ready
if [ ! -f /root/Admin/mac/guid.txt ]; then
    echo "Error: /root/Admin/mac/guid.txt does not exist. Please collect the GUIDs information into this file!"
    exit 0
fi

# Create guid-ip.txt and dhcpd.conf files
rm -rf /root/Admin/ibpxe/freehpc
mkdir -p /root/Admin/ibpxe/freehpc

# Generate guid-ip.txt
printf "00:00:00:00:00:00:00:00\t\t%s\t\tmaster\n" "$MST_IP" > /root/Admin/ibpxe/freehpc/guid-ip.txt
awk -v pre=$IP_PRE '{printf "%s\t\t%s.%d\t\tn%03d\n", $0, pre, NR, NR;}' /root/Admin/mac/guid.txt >> /root/Admin/ibpxe/freehpc/guid-ip.txt

# Revise kernerl
cd /root/Admin/ibpxe
wget $SOFT_SERV/uefi/rootfs-efi.tgz

# Check if guid.txt is ready
if [ ! -f rootfs-efi.tgz ]; then
    echo "Error: rootfs-efi.tgz does not exist."
    exit 0
fi

tar -vxf rootfs-efi.tgz
rm -rf rootfs-efi.tgz
ibpxe -c freehpc/

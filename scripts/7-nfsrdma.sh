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

# Generate nfsd configure
cat << EOF > /etc/nfs.conf
[general]
[nfsrahead]
[exportfs]
[gssd]
use-gss-proxy=1
[lockd]
[mountd]
[nfsdcld]
[nfsdcltrack]
[nfsd]
threads=$NFSD_NUM
rdma=y
rdma-port=20049
[statd]
[sm-notify]
EOF

# obtain system information: ip addr show ib0|grep -i link|awk '{print $2}'
mst_guid=$(ip addr show ib0|grep infiniband|awk '{print $2}'|awk -F: '{for(i=NF-7; i<=NF; i++) printf "%s", $i; print ""}')
MST_IP=$(ip addr show $IB_DEV|grep "inet "|awk -F "/" '{print $1}'|awk '{print $2}')
IP_PRE=$(echo $MST_IP|awk -F "." '{print $1"."$2"."$3}')

# For server
service nfs-server restart

# For computing nodes
cat << EOF > /opt/etc/fstab.add
$MST_IP:/usr/lib64             /lib64      nfs    ro,soft,nfsvers=3,tcp,,defaults        0 0
$MST_IP:/usr/lib               /lib        nfs    ro,soft,nfsvers=3,tcp,,defaults        0 0
$MST_IP:/usr/bin               /bin        nfs    ro,soft,nfsvers=3,tcp,,defaults        0 0
$MST_IP:/usr/sbin              /sbin       nfs    ro,soft,nfsvers=3,tcp,,defaults        0 0
EOF

cat << EOF > /root/Admin/IB/usr-nfs.sh
#! /bin/bash

nodeip=\$(ls /tftpboot/nodes/)

for i in \$nodeip
do
        opn="/tftpboot/nodes/\$i"
        cat /opt/etc/fstab.add >> \$opn/etc/fstab     
        awk '!seen[\$0]++' \$opn/etc/fstab > \$opn/etc/fstab.uniq
        mv -f \$opn/etc/fstab.uniq \$opn/etc/fstab
done
EOF

sh /root/Admin/IB/usr-nfs.sh

cat << EOF > /root/Admin/IB/nfsrdma.sh
#! /bin/bash

nodeip=\$(ls /tftpboot/nodes/)

for i in \$nodeip
do
        opn="/tftpboot/nodes/\$i"
        sed -i "s@nfsvers=3,tcp@nfsvers=3,rdma,port=20049@g" \$opn/etc/fstab
        awk '!seen[\$0]++' \$opn/etc/fstab > \$opn/etc/fstab.uniq
        mv -f \$opn/etc/fstab.uniq \$opn/etc/fstab
done
EOF

sh /root/Admin/IB/nfsrdma.sh
service nfs-server restart
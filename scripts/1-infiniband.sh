#! /bin/bash
#=======================================================================#
#                  FreeHPC Basic Setup for Rocky Linux 8.10             #
#=======================================================================#

# Load environment variables
. $HOME/env.conf

# check environment variable
if [ -z "$SOFT_SERV" ]; then
    echo "Error: The environmenal variable SOFT_SERV is empty."
    exit 1
fi
if [ -z "$MST_IP" ]; then
    echo "Error: The environmenal variable MST_IP is empty."
    exit 1
fi

# Install redhat-lsb-core
yum install redhat-lsb-core python3 -y

# Install Development tools
yum install -y glibc-static libstdc++-static blas-devel lapack-devel

# Delete virbr0
yum install libvirt -y
virsh net-destroy default; virsh net-undefine default; systemctl restart libvirtd.service

# Download Mellanox OFED drivers
cd /tmp
wget $SOFT_SERV/MLNX_OFED_LINUX-5.8-5.1.1.2-rhel8.9-x86_64.tgz
tar -xf MLNX_OFED_LINUX-5.8-5.1.1.2-rhel8.9-x86_64.tgz
cd MLNX_OFED_LINUX-5.8-5.1.1.2-rhel8.9-x86_64/
yum install -y kernel-rpm-macros python36-devel createrepo chkconfig tcsh kernel-modules-extra tcl gcc-gfortran tk lsof
#./mlnxofedinstall --distro rhel8.9 --add-kernel-support --with-nfsrdma --without-fw-update --with-nvmf
./mlnxofedinstall --distro rhel8.9 --add-kernel-support --with-nfsrdma --with-nvmf
dracut -f

# Configure Infiniband card
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-bond0
DEVICE=bond0
TYPE=Bond
BONDING_MASTER=yes
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
NAME=bond0
ONBOOT=yes
BONDING_OPTS="mode=active-backup miimon=100 primary=ib0 updelay=100 downdelay=100 max_bonds=2 fail_over_mac=1"
IPADDR=$MST_IP
PREFIX=24
MTU=65520
CONNECTED_MODE=yes
EOF

cat << EOF > /etc/sysconfig/network-scripts/ifcfg-ib0
TYPE=Infiniband
NAME=ib0
DEVICE=ib0
ONBOOT=yes
MASTER=bond0
SLAVE=yes
MTU=65520
CONNECTED_MODE=yes
EOF

cat << EOF > /etc/sysconfig/network-scripts/ifcfg-ib1
TYPE=Infiniband
NAME=ib1
DEVICE=ib1
ONBOOT=yes
MASTER=bond0
SLAVE=yes
MTU=65520
CONNECTED_MODE=yes
EOF

cat << EOF >> /etc/rc.local
/etc/init.d/openibd start
/etc/init.d/opensmd start
echo connected > /sys/class/net/ib0/mode
service nfs-server restart
EOF

# Enable openibd and opensmd when startup
chkconfig openibd on
chkconfig opensmd on

# Enable connected mode for IB cards
cat << EOF > /etc/modprobe.d/ib_ipoib.conf
alias netdev-ib* ib_ipoib
options ib_ipoib ipoib_enhanced=0
EOF
sed -i 's/^SET_IPOIB_CM=.*/SET_IPOIB_CM=yes/' /etc/infiniband/openib.conf


# change limits.conf
cat << EOF >/etc/security/limits.conf
* soft memlock unlimited
* hard memlock unlimited
* soft stack   unlimited
* hard stack   unlimited
* soft memlock unlimited
* hard memlock unlimited
* soft core    0
* hard core    0
EOF

# disable cockpit alert
ln -sfn /dev/null /etc/motd.d/cockpit

# Clean files
cd /tmp
rm -rf MLNX_OFED_LINUX*

# Reboot the server
reboot

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

# Download lustre source codes
cd /tmp
wget $SOFT_SERV/lustre-2.15.5.tar.gz
tar -vxf lustre-2.15.5.tar.gz
cd lustre-release-2.15.5/

# Build lustre clients
yum install -y libmount-devel libnl3-devel libyaml-devel kernel-abi-whitelists
chmod +x autogen.sh
./autogen.sh
./configure --with-o2ib=/usr/src/ofa_kernel/default/ --with-linux=/usr/src/kernels/$(uname -r)

# Comment system find-requires
# [ -x /usr/lib/rpm/redhat/find-requires.ksyms ] && [ "$is_kmod" ] &&
#    printf "%s\n" "${filelist[@]}" | /usr/lib/rpm/redhat/find-requires.ksyms
sed -i '/find-requires\.ksyms/s/^/#/' /usr/lib/rpm/redhat/find-requires

# Then compile rpms
make rpms
yum localinstall -y lustre-client-2.15.5-1.el8.x86_64.rpm kmod-lustre-client-2.15.5-1.el8.x86_64.rpm lustre-client-devel-2.15.5-1.el8.x86_64.rpm
echo 'options lnet networks=o2ib(bond0)' > /etc/modprobe.d/lustre.conf
depmod -a
modprobe lustre
mkdir -p /opt/etc/
echo 'options lnet networks=o2ib(ib0)' > /opt/etc/lustre.conf

if [[ -n "$LUSTRE_FS" && -n "$LUSTRE_MNT" ]]; then
    mkdir -p $LUSTRE_MNT
    echo "mount.lustre $LUSTRE_FS $LUSTRE_MNT -o localflock,_netdev" >> /etc/rc.local
    mount.lustre $LUSTRE_FS $LUSTRE_MNT -o localflock,_netdev
fi

# Clean files
cd /tmp
rm -rf lustre-2.15.5.tar.gz lustre-release-2.15.5/
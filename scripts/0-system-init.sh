#! /bin/bash
#=======================================================================#
#                    FreeHPC Basic Setup for Rocky Linux 8.10           #
#=======================================================================#

# Revise yum source
sed -e 's|^mirrorlist=|#mirrorlist=|g' \
    -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.ustc.edu.cn/rocky|g' \
    -i.bak \
    /etc/yum.repos.d/Rocky-AppStream.repo \
    /etc/yum.repos.d/Rocky-BaseOS.repo \
    /etc/yum.repos.d/Rocky-Extras.repo \
    /etc/yum.repos.d/Rocky-PowerTools.repo

# Update kernel and related source
yum update -y
yum install epel-release -y

# Disable NetManager and enable network
yum install -y network-scripts dhclient
systemctl disable NetworkManager
chkconfig network on

# Install net-tools and openssl
yum install -y pciutils vim net-tools chkconfig epel-release wget ipmitool
yum install -y bash-comp*
yum config-manager --set-enabled powertools
yum install -y libstdc++-static glibc-static pdsh pdsh-rcmd-ssh rsyslog
yum install -y openssl-devel  kernel-devel python36-devel createrepo chrony pdsh msr-tools

# Disable selinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

# disable firewalld and enable iptables
systemctl stop firewalld
systemctl mask firewalld
yum install iptables-services -y
systemctl enable --now iptables
iptables -F
mkdir /opt/etc
iptables-save >/opt/etc/iptables.none
chmod +x /etc/rc.d/rc.local
echo "/usr/sbin/iptables-restore /opt/etc/iptables.none" >> /etc/rc.local

# Enable chronyd
cat << EOF > /etc/chrony.conf
server ntp.ntsc.ac.cn iburst
driftfile /var/lib/chrony/chrony.drift
makestep 0.1 3
rtcsync
allow all
local stratum 10
EOF
systemctl enable --now chronyd.service

# Generate auto-gen-sshkey script
cat << EOF > /etc/profile.d/auto-gen-sshkey.sh
#!/bin/bash

user=\`whoami\`
home=\$HOME

if [ "\$user" == "nobody" ] ; then
    echo Not creating SSH keys for user \$user
elif [ \`echo \$home | wc -w\` -ne 1 ] ; then
    echo cannot determine home directory of user \$user
else
    if ! [ -d \$home ] ; then
        echo cannot find home directory \$home
    elif ! [ -w \$home ]; then
        echo the home directory \$home is not writtable
    else
        file=\$home/.ssh/id_rsa
        type=rsa
        if [ ! -e \$file ] ; then
            echo generating ssh file \$file ...
            ssh-keygen -t \$type -N '' -f \$file
        fi

        file=\$home/.bashrc
        if [ ! -e \$file ] ; then
            cp /etc/skel/.bashrc \$home/.bashrc
            cp /etc/skel/.bash_logout  \$HOME/.bash_logout
            cp /etc/skel/.bash_profile \$HOME/.bash_profile
        fi

        id="\`cat \$home/.ssh/id_rsa.pub\`"
        file=\$home/.ssh/authorized_keys
        if ! grep "^\$id\\\$" \$file >/dev/null 2>&1 ; then
            echo adding id to ssh file \$file
            echo \$id >> \$file
        fi

        file=\$home/.ssh/config
        if ! grep 'StrictHostKeyChecking.*no' \$file >/dev/null 2>&1 ; then
            echo adding StrictHostKeyChecking=no to ssh config file \$file
            echo 'StrictHostKeyChecking no' >> \$file
        fi

        chmod 600 \$home/.ssh/authorized_keys
        chmod 600 \$home/.ssh/config
    fi
fi
EOF
chmod +x /etc/profile.d/auto-gen-sshkey.sh

# Install xfonts
yum install langpacks-zh_CN glibc-all-langpacks -y
yum install -y xorg-x11-server-Xorg
yum groupinstall -y Fonts

# ANSYS and abaqus requirements
yum install -y xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi libpng12 libpng libpng-devel libXp-devel xterm motif-devel libXxf86vm-devel xcb-util-renderutil
yum install -y glibc.i686 alsa-lib at-spi2-atk at-spi2-core \
    atk avahi-libs cairo cairo-gobject cups-libs dbus-libs \
    expat fribidi gdk-pixbuf2 glib2 glibc glibc-devel gnutls \
    graphite2 gtk3 gzip harfbuzz keyutils-libs krb5-libs \
    libXcomposite libXcursor libXdamage libXfixes libXi libXinerama \
    libXrandr libXrender libblkid libcap libcom_err libdatrie libdrm \
    libepoxy libgcrypt libgpg-error libidn2 libjpeg-turbo libmount \
    libnsl libselinux libtasn1 libthai libunistring libuuid \
    libwayland-client libwayland-cursor libwayland-egl \
    libwayland-server libxcb libxcrypt libxkbcommon mesa-libgbm \
    nettle nspr nss nss-util p11-kit pango pcre2 redhat-lsb-core \
    systemd-libs tar which xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi mesa-libGLU

# system fonts
yum install xorg-x11-fonts* -y
#yum install -y $SOFT_SERV/msttcore-fonts-installer-2.6-1.noarch.rpm


reboot
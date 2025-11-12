#! /bin/bash
#=======================================================================#
#                    FreeHPC Basic Setup for Rocky Linux 8.10           #
#=======================================================================#

# Load environment variables
. $HOME/env.conf

# Install MATE Desktop
yum install -y NetworkManager-adsl NetworkManager-bluetooth NetworkManager-libreswan-gnome \
               NetworkManager-openvpn-gnome NetworkManager-ovs NetworkManager-ppp \
               NetworkManager-team NetworkManager-wifi NetworkManager-wwan abrt-desktop \
               abrt-java-connector adwaita-gtk2-theme alsa-plugins-pulseaudio atril atril-caja \
               atril-thumbnailer caja caja-actions caja-image-converter caja-open-terminal \
               caja-sendto caja-wallpaper caja-xattr-tags dconf-editor engrampa eom \
               firewall-config gnome-disk-utility gnome-epub-thumbnailer \
               gstreamer1-plugins-ugly-free gtk2-engines gucharmap gvfs-afc gvfs-afp \
               gvfs-archive gvfs-fuse gvfs-gphoto2 gvfs-mtp gvfs-smb initial-setup-gui \
               libmatekbd libmatemixer libmateweather libsecret lm_sensors marco mate-applets \
               mate-backgrounds mate-calc mate-control-center mate-desktop mate-dictionary \
               mate-disk-usage-analyzer mate-icon-theme mate-media mate-menus \
               mate-menus-preferences-category-menu mate-notification-daemon \
               mate-panel mate-polkit mate-power-manager mate-screensaver mate-screenshot \
               mate-search-tool mate-session-manager mate-settings-daemon mate-system-log \
               mate-system-monitor mate-terminal mate-themes mate-user-admin mate-user-guide \
               mozo network-manager-applet nm-connection-editor p7zip p7zip-plugins pluma \
               seahorse seahorse-caja xdg-user-dirs-gtk
yum install mate-* -y

# Install KDE Desktop
yum groupinstall "KDE Plasma Workspaces" -y

# check environment variable
if [ -z "$SOFT_SERV" ]; then
    echo "Error: The environmenal variable SOFT_SERV is empty."
    exit -1
fi

# check environment variable
if [ -z "$ETH_DEV" ]; then
    echo "Error: The environmenal variable ETH_DEV is empty."
    exit -1
fi

# Obtain system information
MST_IP=$(ip addr show $IB_DEV|grep "inet "|awk -F "/" '{print $1}'|awk '{print $2}')

# Download and install drbl packages
cd /tmp
wget $SOFT_SERV/drbl.tgz  --no-check-certificate
tar -zxf drbl.tgz
cd drbl
yum localinstall *.rpm -y
cd ..
rm -rf drbl drbl.tgz

# Generate kernel images for diskless cluster
yum install -y elrepo-release
yum install -y dhcp-* tftp-server nfs-utils ypserv ypbind yp-tools dialog tcpdump lftp nc expect memtest86+ yum-utils ecryptfs-utils udev grub2-*
drblsrv-offline -s `uname -r` -c <<< $'\n'

# Generate client-ip-hostname file for cluster
NET_PRE=$(echo $MST_IP | awk -F. '{print $1"."$2"."$3}')
cat /dev/null > /etc/drbl/client-ip-hostname
for i in `seq 1 $CLI_NUM`
do
  printf "$NET_PRE.$i\t\t${CLI_PRE}%03d\n" "$i" >> /etc/drbl/client-ip-hostname
done

# Generate clients filesystem
mkdir -p /root/Admin/mac
cd /root/Admin/mac
cat /dev/null >  macadr-${IB_DEV}.txt
for i in `seq 1 $CLI_NUM`
do
  echo $(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/.$//' | awk '{print $0}') >> macadr-${IB_DEV}.txt
done
cd /root/Admin/mac
cat << EOF > push.conf
#Setup for general
[general]
domain=freehpc
nisdomain=freehpc
localswapfile=no
client_init=text
login_gdm_opt=
timed_login_time=
maxswapsize=
ocs_img_repo_dir=/home/partimag
total_client_no=$CLI_NUM
create_account=
account_passwd_length=8
hostname=$CLI_PRE
purge_client=yes
client_autologin_passwd=
client_root_passwd=
client_pxelinux_passwd=
set_client_system_select=no
use_graphic_pxelinux_menu=no
set_DBN_client_audio_plugdev=
open_thin_client_option=no
client_system_boot_timeout=
language=en_US.UTF-8
set_client_public_ip_opt=no
config_file=drblpush.conf
collect_mac=no
run_drbl_ocs_live_prep=yes
drbl_ocs_live_server=
clonezilla_mode=full_clonezilla_mode
live_client_branch=alternative
live_client_cpu_mode=i386
drbl_mode=full_drbl_mode
drbl_server_as_NAT_server=no
add_start_drbl_services_after_cfg=yes
continue_with_one_port=

#Setup for $IB_DEV
[$IB_DEV]
interface=$IB_DEV
mac=macadr-$IB_DEV.txt
ip_start=1
EOF

drblpush -c push.conf <<< $'\n\n'

# Generate static IP for the last eth
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-$ETH_DEV
DEVICE=$ETH_DEV
TYPE="Ethernet"
BOOTPROTO=static
IPADDR=$PXE_IP
NETMASK=255.255.255.0
ONBOOT=yes
EOF
service network restart

# Generate DHCP service
echo "DHCPDARGS=\"$ETH_DEV\"" > /etc/sysconfig/dhcpd
PXE_PRE=$(echo $PXE_IP | awk -F. '{print $1"."$2"."$3}')
NET_PRE=$(echo $MST_IP | awk -F. '{print $1"."$2"."$3}')
cat << EOF > /etc/dhcp/dhcpd.conf
default-lease-time                      300;
max-lease-time                          300;
option subnet-mask                      255.255.255.0;
option domain-name-servers              $PXE_IP;
option domain-name                      "freehpc";
ddns-update-style                       none;
server-name                             freehpc;
allow booting;
allow bootp;
option arch code 93 = unsigned integer 16;
option space pxelinux;
option pxelinux.magic      code 208 = string;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;
site-option-space "pxelinux";
if exists dhcp-parameter-request-list {
    option dhcp-parameter-request-list = concat(option dhcp-parameter-request-list,d0,d1,d2,d3);
}
if option arch = 00:06 {
    filename "bootia32.efi";
} else if option arch = 00:07 {
    filename "bootx64.efi";
} else if option arch = 00:09 {
    filename "bootx64.efi";
} else {
    filename "pxelinux.0";
}
class "FreeHPC-Client" {
  match if
  (substring(option vendor-class-identifier, 0, 9) = "PXEClient") or
  (substring(option vendor-class-identifier, 0, 9) = "Etherboot") or
  (substring(option vendor-class-identifier, 0, 10) = "FreeHPCClient") ;
}
subnet $PXE_PRE.0 netmask 255.255.255.0 {
    option subnet-mask  255.255.255.0;
    option routers $PXE_IP;
    next-server $PXE_IP;
    range dynamic-bootp $PXE_PRE.1 $PXE_PRE.200;
}
EOF
service dhcpd restart

# Generate Infiniband card information
mkdir -p /root/Admin/IB
cd /root/Admin/IB

cat << EOF > ifcfg-ib.sh
#! /bin/bash

NODEIP=\$(ls /tftpboot/nodes/)

for i in \$NODEIP
do
        opn="/tftpboot/nodes/\$i"
        rm -rf \$opn/etc/sysconfig/network-scripts/ifcfg-en*
        rm -rf \$opn/etc/sysconfig/network-scripts/ifcfg-eth*
        rm -rf \$opn/etc/sysconfig/network-scripts/ifcfg-bond0
        rm -rf \$opn/etc/sysconfig/network-scripts/ifcfg-ib*
        \cp -Rf /opt/etc/ifcfg-ib0 \$opn/etc/sysconfig/network-scripts/ifcfg-ib0
        sed -i "s@abcdefg@\$i@g" \$opn/etc/sysconfig/network-scripts/ifcfg-ib0
done
EOF

mkdir -p /opt/etc/
cat << EOF > /opt/etc/ifcfg-ib0
DEVICE=ib0
TYPE='InfiniBand'
BOOTPROTO=static
IPADDR=abcdefg
NETMASK=255.255.255.0
ONBOOT=yes
CONNECTED_MODE=yes
MTU=65520
EOF

sh ifcfg-ib.sh

wget $SOFT_SERV/freehpc.png -O /tftpboot/nbi_img/freehpc.png
rm -rf /tftpboot/nbi_img/drblwp.png

cat << EOF > /opt/etc/grub-efi.cfg
set default=freehpc-client
set timeout_style=menu
set timeout=7
set hidden_timeout_quiet=false
set graphic_bg=yes

function load_gfxterm {
  set gfxmode=auto
  insmod efi_gop
  insmod efi_uga
  insmod gfxterm
  terminal_output gfxterm
}

if [ x"\${graphic_bg}" = xyes ]; then
  if loadfont unicode; then
    load_gfxterm
  elif loadfont unicode.pf2; then
    load_gfxterm
  fi
fi
if background_image drblwp.png; then
  set color_normal=black/black
  set color_highlight=magenta/black
else
  set color_normal=cyan/blue
  set color_highlight=white/blue
fi

menuentry "Diskless FreeHPC on Rocky 8.10" --id freehpc-client {
  echo "Enter FreeHPC..."
  echo "Loading Linux kernel vmlinuz-pxe..."
  linux vmlinuz-pxe devfs=nomount drblthincli=off selinux=0 drbl_bootp=\$net_default_next_server nomodeset rd.driver.blacklist=nouveau nouveau.modeset=0 systemd.unified_cgroup_hierarchy=1
  echo "Loading initial ramdisk initrd-pxe.img..."
  initrd initrd-pxe.img
}

menuentry "Reboot" --id reboot {
  echo "System rebooting..."
  reboot
}

menuentry "Shutdown" --id shutdown {
  echo "System shutting down..."
  halt
}
EOF

cat << EOF > /opt/etc/pxelinux.cfg 
default menu.c32
timeout 5
prompt 0
noescape 1
MENU MARGIN 5
MENU BACKGROUND freehpc.png


say **********************************************
say Welcome to FreeHPC.
say http://www.freehpc.com
say **********************************************

ALLOWOPTIONS 1

MENU TITLE FreeHPC (http://www.freehpc.com)

label freehpc
  MENU DEFAULT
  MENU LABEL Diskless FreeHPC on Rocky Linux 8.10
  IPAPPEND 1
  kernel vmlinuz-pxe
  append initrd=initrd-pxe.img devfs=nomount drblthincli=off selinux=0 nomodeset blacklist=ast xdriver=vesa brokenmodules=ast rd.driver.blacklist=nouveau nouveau.modeset=0 systemd.unified_cgroup_hierarchy=1
  TEXT HELP
  * FreeHPC version: 2025R1 (C) 2025-2035, www.freehpc.com
  * Disclaimer: FreeHPC is a free HPC solution based on openHPC
  ENDTEXT
EOF

\cp -Rf /opt/etc/pxelinux.cfg /tftpboot/nbi_img/pxelinux.cfg/default
\cp -Rf /opt/etc/grub-efi.cfg /tftpboot/nbi_img/grub-efi.cfg/grub.cfg

sed -i "s@DRBL@FreeHPC@g" /etc/exports

# Generate ibpxe informarion
image=$(ls /tftpboot/nbi_img/initrd-pxe.*.img |awk -F "/" '{print $NF}')
ibmac=$(ip addr show ib0|grep infiniband|awk '{print $2}')
cat << EOF > /opt/etc/ibpxe.info
$image      $ibmac
EOF

drbl-cp-host ~/.ssh ~

if [[ -n "$LUSTRE_FS" && -n "$LUSTRE_MNT" ]]; then
    mkdir -p /tftpboot/node_root/$LUSTRE_MNT
fi
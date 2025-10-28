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
SLM_NUM=$(printf "%03d" "$CLI_NUM")

cd $HOME
rpm -e VirtualGL
yum install -y $SOFT_SERV/VirtualGL-2.6.5.x86_64.rpm

# Master node VGL setting
rm -rf /etc/X11/xorg.conf
nvidia-xconfig -a --allow-empty-initial-configuration
vglserver_config -config +s +f +t
systemctl set-default graphical.target

mkdir -p $APP_DIR/bin
cat << EOF > $APP_DIR/bin/vgl.sh
init 3
nvidia-xconfig -a --allow-empty-initial-configuration
vglserver_config -config +s +f +t
systemctl set-default graphical.target
reboot
EOF
chmod +x $APP_DIR/bin/vgl.sh

pdsh -t 1 -w ${CLI_PRE}[001-${SLM_NUM}] "$APP_DIR/bin/vgl.sh"

# Clean Files
cd $HOME
rm -rf VirtualGL-2.6.5.x86_64.rpm
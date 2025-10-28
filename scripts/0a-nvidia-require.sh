#! /bin/bash
#=======================================================================#
#                    ABHPC Basic Setup for Rocky Linux 8.10             #
#=======================================================================#


# Install required packages
yum -y update
yum -y groupinstall "Development Tools" "Xfce" "Server with GUI"
yum -y install kernel-devel
yum -y install epel-release
yum -y install dkms

# Revise /etc/default/grub, generate new grub.cfg
sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/ rd.driver.blacklist=nouveau nouveau.modeset=0"/' /etc/default/grub
sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/ systemd.unified_cgroup_hierarchy=1"/' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

# Disable nouveau
echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf

# Update initramfs and reboot
mv -f /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r)-nouveau.img
dracut /boot/initramfs-$(uname -r).img $(uname -r)
reboot

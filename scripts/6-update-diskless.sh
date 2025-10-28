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


# Generate update script
cat << EOF > /root/Admin/update.sh
#! /bin/bash

nodeip=\$(ls /tftpboot/nodes/)

for i in \$nodeip
do
        opn="/tftpboot/nodes/\$i"
        unlink \$opn/etc/localtime
        \cp -Rf /usr/share/zoneinfo/Asia/Shanghai \$opn/etc/localtime
        \cp -Rf /opt/etc/chrony.conf \$opn/etc/chrony.conf
        rm -rf \$opn/etc/modprobe.d/mlx5_core.conf
        \cp -Rf /opt/etc/lustre.conf \$opn/etc/modprobe.d/lustre.conf
        #\cp -Rf /etc/xdg/user-dirs.defaults \$opn/etc/xdg/user-dirs.defaults
        \cp -Rf /opt/etc/nsswitch.conf \$opn/etc/nsswitch.conf
        rm -rf \$opn/etc/systemd/system/weight.*
        \cp -Rf /etc/init.d/slurm \$opn/etc/init.d/slurm
        \cp -Rf /opt/etc/slurmd.service \$opn/etc/systemd/system/slurmd.service
        \cp -Rf /etc/security/limits.conf \$opn/etc/security/limits.conf
        \cp -Rf /etc/sysctl.conf \$opn/etc/sysctl.conf
        \cp -Rf /etc/ssh/sshd_config \$opn/etc/ssh/sshd_config
        \cp -Rf /etc/munge/munge.key \$opn/etc/munge/munge.key
        \cp -Rf /etc/bashrc \$opn/etc/bashrc
        \cp -Rf /etc/profile \$opn/etc/profile
        \cp -Rf /opt/etc/hosts \$opn/etc/hosts
        \cp -Rf /opt/etc/rc.local \$opn/etc/rc.local
        \cp -Rf /opt/etc/rc.local \$opn/etc/rc.d/rc.local
        \cp -Rf /opt/etc/slurm_pam/password-auth-ac \$opn/etc/authselect/password-auth
        \cp -Rf /opt/etc/slurm_pam/sshd \$opn/etc/pam.d/sshd
        \cp -Rf /opt/etc/slurm_pam/access.conf \$opn/etc/security/access.conf
        sed -i 's/^SET_IPOIB_CM=.*/SET_IPOIB_CM=yes/' \$opn/etc/infiniband/openib.conf
        
done
\cp -Rf /opt/etc/hosts /etc/hosts
rm -rf /tftpboot/node_root/bin/mlnx_interface_mgr.sh
\cp -Rf /opt/etc/pxelinux.cfg /tftpboot/nbi_img/pxelinux.cfg/default
EOF

# Generate chrony.conf file
cat << EOF > /opt/etc/chrony.conf
server $MST_IP iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF

# nsswitch.conf
\cp -Rf /etc/nsswitch.conf /opt/etc/nsswitch.conf
sed -i 's/^passwd:.*/passwd:\tfiles nis sss ldap/' /opt/etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow:\tfiles nis sss ldap/' /opt/etc/nsswitch.conf
sed -i 's/^group:.*/group:\tfiles nis sss ldap/' /opt/etc/nsswitch.conf
sed -i 's/^hosts:.*/hosts:\tfiles nis dns myhostname/' /opt/etc/nsswitch.conf

# rc.local file
cat << EOF > /opt/etc/rc.local
#!/bin/bash
touch /var/lock/subsys/local
/usr/sbin/iptables-restore /opt/etc/iptables.none
/etc/init.d/openibd start
echo connected > /sys/class/net/ib0/mode
sleep 10
systemctl restart chronyd.service
chronyc -a makestep
systemctl restart nslcd.service
nvidia-smi
EOF

if [[ -n "$LUSTRE_FS" && -n "$LUSTRE_MNT" ]]; then
    echo "mount.lustre $LUSTRE_FS $LUSTRE_MNT -o localflock,_netdev" >> /opt/etc/rc.local
fi

cat << EOF >> /opt/etc/rc.local
FILE="$APP_DIR/slurm/sbin/slurmd"
while true; do
    if [ -e "\$FILE" ]; then
        service munge restart
        systemctl start slurmd.service
        break
    else
        sleep 1
    fi
done
EOF
chmod +x /opt/etc/rc.local

# slurm_pam
rm -rf /opt/etc/slurm_pam/ && mkdir -p /opt/etc/slurm_pam/
cat << EOF > /opt/etc/slurm_pam/access.conf 
+:root:ALL
-:ALL:ALL
EOF

cat << EOF > /opt/etc/slurm_pam/password-auth-ac
auth        required      pam_env.so
auth        required      pam_faildelay.so delay=2000000
auth        sufficient    pam_unix.so nullok try_first_pass
auth        requisite     pam_succeed_if.so uid >= 1000 quiet_success
auth        sufficient    pam_ldap.so use_first_pass
auth        required      pam_deny.so

account     required      pam_unix.so broken_shadow
account     sufficient    pam_succeed_if.so uid < 1000 quiet
account     [default=bad success=ok user_unknown=ignore] pam_ldap.so
account     required      pam_permit.so

password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
password    sufficient    pam_unix.so sha512 shadow nis nullok try_first_pass use_authtok
password    sufficient    pam_ldap.so use_authtok
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
session     optional      pam_oddjob_mkhomedir.so umask=0077
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
session     optional      pam_ldap.so
EOF

\cp -Rf /opt/etc/slurm_pam/password-auth-ac /etc/pam.d/password-auth-ac

cat << EOF > /opt/etc/slurm_pam/sshd
auth       required     pam_sepermit.so
auth       substack     password-auth
auth       include      postlogin
-auth      optional     pam_reauthorize.so prepare
account    required     pam_nologin.so
account    include      password-auth
password   include      password-auth
account    sufficient   pam_access.so
account    required     pam_slurm.so
session    required     pam_selinux.so close
session    required     pam_loginuid.so
session    required     pam_selinux.so open env_params
session    required     pam_namespace.so
session    optional     pam_keyinit.so force revoke
session    include      password-auth
session    include      postlogin
-session   optional     pam_reauthorize.so prepare
EOF


# Run update scripts
sh /root/Admin/update.sh
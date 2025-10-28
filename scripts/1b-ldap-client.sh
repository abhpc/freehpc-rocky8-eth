#! /bin/bash
#=======================================================================#
#                    ABHPC Basic Setup for Rocky Linux 8.10             #
#=======================================================================#

# Load environment variables
. $HOME/env.conf

# check environment variable
if [ -z "$LDAP_SERV" ]; then
    echo "Error: The environmenal variable LDAP_SERV is empty."
    exit 1
fi
if [ -z "$LDAP_BASE" ]; then
    echo "Error: The environmenal variable LDAP_BASE is empty."
    exit 1
fi
if [ -z "$LDAP_PASS" ]; then
    echo "Error: The environmenal variable LDAP_PASS is empty."
    exit 1
fi

# Install necessary packages
yum -y install openldap-clients nss-pam-ldapd oddjob-mkhomedir
mkdir -p /etc/openldap/cacerts

# Create /etc/nslcd.conf
cat << EOF > /etc/nslcd.conf
uid nslcd
gid ldap
uri ldap://$LDAP_SERV/
base $LDAP_BASE
ssl no
tls_cacertdir /etc/openldap/cacerts
binddn cn=admin,$LDAP_BASE
bindpw $LDAP_PASS
validnames /^[a-z0-9._@\$-][a-z0-9._@$ \\\~-]*[a-z0-9._@$~-]$/i
EOF

# Create nslcd module
cp -Rp /usr/share/authselect/default/sssd /etc/authselect/custom/nslcd
cd /etc/authselect/custom/nslcd
sed -i 's/sss/ldap/g' fingerprint-auth
sed -i 's/sss/ldap/g' password-auth
sed -i 's/sss/ldap/g' smartcard-auth
sed -i 's/sss/ldap/g' system-auth
sed -i 's/sss/ldap/g' nsswitch.conf
sed -i 's/SSSD/NSLCD/g' REQUIREMENTS
sed -i 's/SSSD/NSLCD/g' README

# Write list users script
mkdir $APP_DIR/bin/ -p
cat << EOF > $APP_DIR/bin/list-users
#! /bin/bash
(echo -e "ID\tUSER\tNAME\tHOMEDIR\n------ ---------- ---------- --------------" && getent passwd | awk -F ":" '\$3>1000 && \$3<65500 {print \$3"\t"\$1,\$5"\t\t"\$6}'|sort -n)| column -t
EOF
chmod +x $APP_DIR/bin/list-users

# Set nslcd auth
authselect select custom/nslcd with-mkhomedir --force
systemctl enable --now oddjobd.service
systemctl enable --now nslcd.service
systemctl restart oddjobd.service
systemctl restart nslcd.service
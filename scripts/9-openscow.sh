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

# Install KDE Desktop
#yum groupinstall -y "KDE Plasma Workspaces"

yum install -y $SOFT_SERV/turbovnc-3.1.2-20240808.x86_64.rpm

# Download scow slurm adapter
mkdir -p /opt/scow-slurm-adapter/config
cd /opt/scow-slurm-adapter
wget $SOFT_SERV/scow-slurm-adapter
chmod +x scow-slurm-adapter

# Write scow slurm adapter config
cat << EOF > /opt/scow-slurm-adapter/config/config.yaml
# slurm database
mysql:
  host: 127.0.0.1
  port: 3306
  user: slurm
  dbname: slurm
  password: '$DBPASSWD'
  clustername: $CLUSNAME
  databaseencode: utf8

# service port
service:
  port: 8972

# slurm default Qos
slurm:
  defaultqos: normal
  slurmpath: $APP_DIR/slurm

# module profile path
modulepath:
  path: $APP_DIR/modules/init/profile.sh
EOF

# scow slurm adapter systemd service
cat << EOF > /etc/systemd/system/scow-adapter.service 
[Unit]
Description=SCOW SLURM Adapter Service
After=network.target

[Service]
StandardOutput=null
WorkingDirectory=/opt/scow-slurm-adapter/
ExecStart=/opt/scow-slurm-adapter/scow-slurm-adapter
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now scow-adapter.service

# Download and load docker images
cd /tmp
wget $SOFT_SERV/scow-images.tar.gz
tar -vxf scow-images.tar.gz
scowimg="fluentd.tar  mysql.tar  novnc.tar  redis.tar  scow.tar"
for i in $scowimg
do
    docker load -i $i
done
rm -rf *.tar *.tar.gz

# Revise auth.yml
cd $HOME
wget $SOFT_SERV/ascow.tgz
tar -vxf ascow.tgz
rm -rf ascow.tgz
cd ascow/config
sed -i "s/^\([[:space:]]*url:[[:space:]]*\).*/\1 ldap:\/\/$LDAP_SERV/" auth.yml
sed -i "s/^\([[:space:]]*bindDN:[[:space:]]*\).*/\1 cn=admin,$LDAP_BASE/" auth.yml
sed -i "s/^\([[:space:]]*bindPassword:[[:space:]]*\).*/\1 \"$LDAP_PASS\"/" auth.yml
sed -i "s/^\([[:space:]]*searchBase:[[:space:]]*\).*/\1 \"$LDAP_BASE\"/" auth.yml
sed -i "s/^\([[:space:]]*userBase:[[:space:]]*\).*/\1 \"$LDAP_BASE\"/" auth.yml
if [[ -n "$LUSTRE_FS" && -n "$LUSTRE_MNT" ]]; then
    sed -i "s|^\([[:space:]]*homeDir:[[:space:]]*\).*|\1 $LUSTRE_MNT/users/{{ userId }}|" auth.yml
else
    sed -i "s/^\([[:space:]]*homeDir:[[:space:]]*\).*/\1 \/home\/{{ userId }}/" auth.yml
fi

# Cluster configure
mstname=`hostname`
cat << EOF > clusters/$CLUSNAME.yml
displayName: FreeHPC

loginNodes:
  - name: $mstname
    address: $MST_IP

adapterUrl: "$MST_IP:8972"

loginDesktop:
  enabled: true
  wms: 
    - name: Mate
      wm: mate
  maxDesktops: 30
  desktopsDir: scow/desktops

turboVNCPath: /opt/TurboVNC
EOF

# Start SCOW
cd ..
service docker restart
 ./scow-cli generate
 sed -i "s@unless-stopped@always@g" docker-compose.yml
docker compose up -d

# Add Group freehpc
cat << EOF > group.ldif
dn: cn=freehpc,dc=freehpc,dc=com
objectClass: top
objectClass: posixGroup
cn: freehpc
gidNumber: 5000
EOF
ldapadd -x -D "cn=admin,$LDAP_BASE" -w "$LDAP_PASS" -f group.ldif
rm -rf group.ldif

# Generate delete scripts
cat << EOF > $APP_DIR/bin/userdelss
#! /bin/bash

# Function to display help
show_help() {
    echo "Usage: \$0 <user_name>"
    echo
    echo "This script deletes user in SLURM, SCOW and LDAP."
    echo
    ptuser=\$(sacctmgr list assoc format="User" -n|uniq|tr '\n' ' ')
    echo "Users in SlURM can be deleted: \$ptuser"
}

# Check if the correct number of arguments is provided
if [ "\$#" -ne 1 ]; then
    echo "Error: Incorrect number of arguments."
    echo 
    show_help
    exit -1
fi

# remove user in slurm system
tuser=\$1
sacctmgr -i delete user \$tuser

# remove user in SCOW db
docker exec -it ascow-db-1 bash -c "/usr/bin/mysql -u root -p@Freehpc%1234 -e \"use scow; delete from user where user_id='\$tuser'\" "

# remove user in LDAP system
ldapdelete -x -H ldap://$LDAP_SERV -D "cn=admin,dc=freehpc,dc=com" -w "$LDAP_PASS" "uid=\$tuser,dc=freehpc,dc=com"
EOF
chmod +x $APP_DIR/bin/userdelss

cat << EOF > $APP_DIR/bin/acctdelss
#!/bin/bash

# Function to display help
show_help() {
    echo "Usage: \$0 <account_name>"
    echo
    echo "This script deletes all users associated with a given SLURM accoun and then deletes the account itself."
    ptacct=\$(sacctmgr list assoc format="Account" -n|uniq|tr '\n' ' ')
    echo "Account in SLURM can be deleted: \$ptacct"
}

# Check if the correct number of arguments is provided
if [ "\$#" -ne 1 ]; then
    echo "Error: Incorrect number of arguments."
    show_help
    exit -1
fi

tacct=\$1

# Get the list of users associated with the account
tuser=\$(sacctmgr list assoc format="User" account=\$tacct -n | awk '{print \$1}')

# Delete each user associated with the account
for i in \$tuser; do
    sacctmgr -i delete user \$i account=\$tacct
done

# Delete the account
sacctmgr -i delete account \$tacct


# delete from user_account where account_id = (select id from account where account_name='myacct2');
docker exec -it ascow-db-1 bash -c "/usr/bin/mysql -u root -p@Freehpc%1234 -e \"use scow; delete from user_account where account_id = (select id from account where account_name='\$tacct')\" "
docker exec -it ascow-db-1 bash -c "/usr/bin/mysql -u root -p@Freehpc%1234 -e \"use scow; delete from account where account_name='\$tacct'\" "
EOF
chmod +x $APP_DIR/bin/acctdelss

cat << EOF > $APP_DIR/bin/tendelss
#! /bin/bash

# Function to display help
show_help() {
    echo "Usage: \$0 <tenant_name>"
    echo
    echo "This script deletes tenant in SCOW."
    echo
    echo "Tenant in SCOW can be deleted:"
    docker exec -it ascow-db-1 bash -c "/usr/bin/mysql -u root -p@Freehpc%1234 -e \"use scow; select * from tenant\" "
}

# Check if the correct number of arguments is provided
if [ "\$#" -ne 1 ]; then
    echo "Error: Incorrect number of arguments."
    echo 
    show_help
    exit -1
fi

tten=\$1

# remove account assosited with tenant in SCOW db
docker exec -it ascow-db-1 bash -c "/usr/bin/mysql -u root -p@Freehpc%1234 -e \"use scow; delete from account where tenant_id = (select id from tenant where name='\$tten')\" "

# remove tenant in SCOW db
docker exec -it ascow-db-1 bash -c "/usr/bin/mysql -u root -p@Freehpc%1234 -e \"use scow; delete from tenant where name='\$tten' \" "
EOF
chmod +x $APP_DIR/bin/tendelss
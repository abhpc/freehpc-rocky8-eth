#! /bin/bash
#=======================================================================#
#                    ABHPC Basic Setup for Rocky Linux 8.10             #
#=======================================================================#

# Load environment variables
. $HOME/env.conf

# check environment variable
if [ -z "$SOFT_SERV" ]; then
    echo "Error: The environmenal variable SOFT_SERV is empty."
    exit -1
fi

# check if MST_IP == LDAP_SERV
if [ "$MST_IP" != "$LDAP_SERV" ]; then
    echo "Will not install LDAP server on master server, skip ..."
    exit 0
fi

# Install podman
yum remove -y podman* runc

# configure yum source
yum install -y yum-utils
yum-config-manager  --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sed -i 's+https://download.docker.com+https://mirrors.tuna.tsinghua.edu.cn/docker-ce+' /etc/yum.repos.d/docker-ce.repo

# install docker
yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# start docker when bootup
echo {\"registry-mirrors\":[\"https://registry.docker-cn.com/\"]} > /etc/docker/daemon.json
systemctl enable docker.service
systemctl start docker.service

# Network
docker network create --driver bridge --subnet=172.20.1.0/24 --gateway=172.20.1.1 ldap-net

# Load openldap images
cd /tmp
wget $SOFT_SERV/openldap.tar
wget $SOFT_SERV/phpldapadmin.tar
docker load -i openldap.tar
docker load -i phpldapadmin.tar

# LDAP server for SCOW
LDAP_DOMAIN=$(echo $LDAP_BASE|awk -F 'dc=' '{for(i=2; i<=NF; i++) {gsub(",", ".", $i); printf "%s", $i}}')
docker run -itd --name abhpcldap \
            --restart=always \
            -p 389:389 -p 636:636 \
            -e LDAP_ORGANISATION="abhpc" \
            -e LDAP_DOMAIN="$LDAP_DOMAIN" \
            -e LDAP_ADMIN_PASSWORD="$LDAP_PASS" \
            --network ldap-net --ip 172.20.1.2 \
            osixia/openldap:1.5.0

docker run -itd --name ldapadmin \
      --restart=always \
      -p 6443:443 \
      --network ldap-net --ip 172.20.1.3 \
      --env PHPLDAPADMIN_LDAP_HOSTS=172.20.1.2 \
      --detach osixia/phpldapadmin:0.9.0

cat << EOF > /usr/bin/listcontainers
#! /bin/bash

docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' \$@
EOF
chmod +x /usr/bin/listcontainers

# Clean files
cd /tmp
rm -rf openldap.tar phpldapadmin.tar
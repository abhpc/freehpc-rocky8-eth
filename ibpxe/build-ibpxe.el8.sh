#! /bin/bash

# Obtain basic information
image=$(cat ibpxe.info|awk '{print $1}')
ibmac=$(cat ibpxe.info|awk '{print $2}')
des_guid=$(echo $ibmac|awk -F: '{for(i=NF-7; i<=NF; i++) printf "%s", $i; print ""}')

# Revise src codes
\cp -Rf ibpxe.el8.src.cpp ibpxe.cpp
sed -i "s@abcdefg-image@$image@g" ibpxe.cpp
sed -i "s@abcdefg-ibmac@$ibmac@g" ibpxe.cpp

# Compile ibpxe code
module purge
module load gcc/7.5.0
g++ ibpxe.cpp -o ibpxe -static
strip ibpxe

# Move ibpxe executation to web server
mkdir -p /var/www/html/abhpc/uefi
mv -f ibpxe /var/www/html/abhpc/uefi/ibpxe-${des_guid}.el8
chmod 755 /var/www/html/abhpc/uefi/ibpxe-${des_guid}.el8
rm -rf ibpxe.cpp

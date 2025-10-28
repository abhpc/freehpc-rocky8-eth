#! /bin/bash

# Define scripts to run
script_order="0 0a 0b 0c 1 1a 1b 2 3 4 5 6 7 8 9"
#script_order="9"

# Check args
if [ "$#" -ne 1 ]; then
    echo -e "Error! autogen.sh usage: ./autogen.sh <HPC config dir>\n"
    exit -1
fi

# Check directory
if [ ! -d "$1" ]; then
    echo "Error：directory $1 does not exist."
    exit -1
fi

# Obtain environment
. $1/env.conf

# Check files
if [ ! -f $1/env.conf ]; then
    echo "Error: $1/env.conf does not exist."
    exit -1
fi
if [ ! -f $1/guid.txt ]; then
    echo "Error: $1/guid.txt does not exist."
    exit -1
fi

# check environment variable
if [ -z "$rdhost" ]; then
    echo "Error: The environmenal variable rdhost is empty."
    exit -1
fi
if [ -z "$ssh_port" ]; then
    echo "Error: The environmenal variable rdhost is empty."
    exit -1
fi

scp -P $ssh_port $1/env.conf root@$rdhost:/root/
\cp -Rf $1/env.conf ./

for i in $script_order
do
        if [ "$i" == "5" ]; then
                cd ibpxe 
                ssh -p $ssh_port root@$rdhost "cat /opt/etc/ibpxe.info" > ibpxe.info
                sh build-ibpxe.el8.sh
                cd ..
                scp -P $ssh_port $1/guid.txt root@$rdhost:/root/Admin/mac
        fi
        ./rcmd.sh scripts/$i-*.sh
        sleep 10
done

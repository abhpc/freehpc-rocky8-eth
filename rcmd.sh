#! /bin/bash

# Obtain environment
. env.conf

while true; do
    if ssh -p $ssh_port root@$rdhost "echo OK" | grep -q "OK"; then
        echo "Connection successful. Running script $1 ..."
        ssh -p $ssh_port root@$rdhost "bash -s" < $1
        break
    else
        echo "Connection failed. Retrying in 5 seconds..."
        sleep 5
    fi
done
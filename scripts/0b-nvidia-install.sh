#! /bin/bash
#=======================================================================#
#                    ABHPC Basic Setup for Rocky Linux 8.10             #
#=======================================================================#

# Load environment variables
. $HOME/env.conf

# check environment variable
if [ -z "$SOFT_SERV" ]; then
    echo "Error: The environmenal variable SOFT_SERV is empty."
    exit 1
fi

# Download nvidia drivers
cd /tmp
wget -O NVIDIA.run $SOFT_SERV/NVIDIA-Linux-x86_64-550.107.02.run

# Check if nvidia driver is ready
if [ ! -f NVIDIA.run ]; then
    echo "Error: NVIDIA.run does not exist."
    exit 0
fi
chmod +x NVIDIA.run

# Close graphic and start install
init 3
./NVIDIA.run --kernel-source-path=/usr/src/kernels/$(uname -r) --silent --accept-license --dkms --no-questions --rebuild-initramfs

# Clean files
cd /tmp
rm -rf NVIDIA.run
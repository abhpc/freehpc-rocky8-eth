# ABHPC on Rocky Linux 8 <!-- omit in toc -->

# 目录 <!-- omit in toc -->
- [1 系统设置](#1-系统设置)
  - [1.0 基础配置](#10-基础配置)
    - [建立SSH/RSA密钥访问](#建立sshrsa密钥访问)
    - [更改yum源](#更改yum源)
    - [升级系统并安装必要组件](#升级系统并安装必要组件)
    - [禁用SELinux](#禁用selinux)
    - [禁用NetManager改用network](#禁用netmanager改用network)
    - [禁用firewalld改用iptables](#禁用firewalld改用iptables)
    - [静默登录提示](#静默登录提示)
  - [1.1 安装NVIDIA驱动](#11-安装nvidia驱动)
  - [1.2 安装MLNXOFED驱动](#12-安装mlnxofed驱动)
  - [1.3 配置LDAP客户端](#13-配置ldap客户端)
- [2 分布式存储](#2-分布式存储)
  - [2.1 Lustre o2ib客户端](#21-lustre-o2ib客户端)
  - [2.2 BeeGFS客户端](#22-beegfs客户端)
- [3 并行计算环境](#3-并行计算环境)
  - [3.1 Environment Module安装](#31-environment-module安装)
  - [3.2 Intel OneAPI 2023安装](#32-intel-oneapi-2023安装)
- [4 无盘环境搭建](#4-无盘环境搭建)
  - [4.1 下载](#41-下载)
  - [4.2 安装](#42-安装)
  - [生成网卡信息文件](#生成网卡信息文件)
    - [GUID转MAC](#guid转mac)
    - [生成client-ip-hostname文件](#生成client-ip-hostname文件)
    - [生成guid-ip.txt文件](#生成guid-iptxt文件)
    - [生成dhcpd.conf文件](#生成dhcpdconf文件)


## 1 系统设置

### 1.0 基础配置
#### 建立SSH/RSA密钥访问
```bash
#!/bin/bash

user=`whoami`
home=$HOME

if [ "$user" == "nobody" ] ; then
    echo Not creating SSH keys for user $user
elif [ `echo $home | wc -w` -ne 1 ] ; then
    echo cannot determine home directory of user $user
else
    if ! [ -d $home ] ; then
        echo cannot find home directory $home
    elif ! [ -w $home ]; then
        echo the home directory $home is not writtable
    else
        file=$home/.ssh/id_rsa
        type=rsa
        if [ ! -e $file ] ; then
            echo generating ssh file $file ...
            ssh-keygen -t $type -N '' -f $file
        fi

        id="`cat $home/.ssh/id_rsa.pub`"
        file=$home/.ssh/authorized_keys
        if ! grep "^$id\$" $file >/dev/null 2>&1 ; then
            echo adding id to ssh file $file
            echo $id >> $file
        fi

        file=$home/.ssh/config
        if ! grep 'StrictHostKeyChecking.*no' $file >/dev/null 2>&1 ; then
            echo adding StrictHostKeyChecking=no to ssh config file $file
            echo 'StrictHostKeyChecking no' >> $file
        fi

        chmod 600 $home/.ssh/authorized_keys
        chmod 600 $home/.ssh/config
    fi
fi
```
#### 更改yum源
```bash
sed -e 's|^mirrorlist=|#mirrorlist=|g' \
    -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.ustc.edu.cn/rocky|g' \
    -i.bak \
    /etc/yum.repos.d/Rocky-AppStream.repo \
    /etc/yum.repos.d/Rocky-BaseOS.repo \
    /etc/yum.repos.d/Rocky-Extras.repo \
    /etc/yum.repos.d/Rocky-PowerTools.repo
```
#### 升级系统并安装必要组件
```bash
yum update -y
yum install -y pciutils vim net-tools chkconfig epel-release wget ipmitool
yum install -y bash-comp*
yum config-manager --set-enabled powertools
yum install -y libstdc++-static glibc-static pdsh pdsh-rcmd-ssh rsyslog
```
#### 禁用SELinux
```bash
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
```
#### 禁用NetManager改用network
```bash
yum install -y network-scripts dhclient
```
在目录
```bash
/etc/sysconfig/network-scripts
```
中写入相关网络设置。**注意：这里一定要写好，否则重启后网络无法连接。**
然后切换服务，重启服务器
```bash
systemctl disable NetworkManager
chkconfig network on
reboot
```
#### 禁用firewalld改用iptables
```bash
#! /bin/sh
systemctl stop firewalld
systemctl mask firewalld
yum install iptables-services -y
systemctl enable --now iptables
iptables -F
mkdir /opt/etc
iptables-save >/opt/etc/iptables.none
chmod +x /etc/rc.d/rc.local
echo "/usr/sbin/iptables-restore /opt/etc/iptables.none" >> /etc/rc.local
```
#### 静默登录提示
登录时总有提示：
```bash
Activate the web console with: systemctl enable --now cockpit.socket
```
关闭该提示：
```bash
ln -sfn /dev/null /etc/motd.d/cockpit
```

### 1.1 安装NVIDIA驱动
首先安装必要软件包：
```bash
yum -y update
yum -y groupinstall "Development Tools" "Xfce"
yum -y install kernel-devel
yum -y install epel-release
yum -y install dkms
```
修改文件```/etc/default/grub```:
```bash
vi /etc/default/grub
```
将以下文字添加到```GRUB_CMDLINE_LINUX```的行末：
```bash
rd.driver.blacklist=nouveau nouveau.modeset=0
```
更新```grub.cfg```：
```bash
grub2-mkconfig -o /boot/grub2/grub.cfg
```
禁用```nouveau```:
```bash
echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
```
更新```initramfs```后，重启服务器（**这一步持续时间可能会比较长，需要耐心等待，千万不能中途Ctrl+C，否则可能造成系统紊乱**）:
```bash
mv /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r)-nouveau.img
dracut /boot/initramfs-$(uname -r).img $(uname -r)
reboot
```
在官网上下载NVIDIA驱动(这里另存为NVIDIA.run文件)，例如：
```bash
wget -O NVIDIA.run https://us.download.nvidia.com/XFree86/Linux-x86_64/550.107.02/NVIDIA-Linux-x86_64-550.107.02.run
chmod +x NVIDIA.run
```
然后关闭图形界面，启动NVIDIA驱动安装
```bash
init 3
./NVIDIA.run --kernel-source-path=/usr/src/kernels/$(uname -r)
```
检查是否能正常运行：
```bash
nvidia-smi
```
解决API不匹配的问题：
```bash
dracut --regenerate-all --force
```

### 1.2 安装MLNXOFED驱动

下载LTS驱动(**注意：从23.07开始不支持connected模式，因此选用OFED-5.8x-LTS**)：
```bash
wget https://content.mellanox.com/ofed/MLNX_OFED-5.8-5.1.1.2/MLNX_OFED_LINUX-5.8-5.1.1.2-rhel8.9-x86_64.tgz
tar -vxf MLNX_OFED_LINUX-5.8-5.1.1.2-rhel8.9-x86_64.tgz
cd MLNX_OFED_LINUX-5.8-5.1.1.2-rhel8.9-x86_64/
```
安装必要依赖包：
```bash
yum install -y kernel-rpm-macros python36-devel createrepo chkconfig tcsh kernel-modules-extra tcl gcc-gfortran tk lsof
```
解压并安装Mellanox驱动（**注意该步骤持续时间较长**）：
```bash
./mlnxofedinstall --distro rhel8.9 --add-kernel-support --with-nfsrdma
dracut -f
```
然后添加[IB网卡配置文件](ifcfg-ib)到目录：
```bash
/etc/sysconfig/network-scripts/
```
并修改IP地址：
```bash
IPADDR=10.10.10.1
```
然后删除/etc/Net
设置```openibd```和```opensmd```开机启动：
```bash
chkconfig openibd on
chkconfig opensmd on
```
修改文件```/etc/infiniband/openib.conf```，将```SET_IPOIB_CM=auto```改为```SET_IPOIB_CM=yes```，也即：
```bash
echo 'options ib_ipoib ipoib_enhanced=0' >> /etc/modprobe.d/ib_ipoib.conf
sed -i 's/^SET_IPOIB_CM=.*/SET_IPOIB_CM=yes/' /etc/infiniband/openib.conf
```
第一次安装好以后，需要重启系统，使Infiniband网卡驱动生效。

### 1.3 配置LDAP客户端
安装必要组件：
```bash
yum -y install openldap-clients nss-pam-ldapd oddjob-mkhomedir
mkdir -p /etc/openldap/cacerts
```
修改```/etc/nslcd.conf```文件，例如：
```bash
uid nslcd
gid ldap

uri ldap://10.10.30.230/
base dc=pims,dc=ac,dc=cn

ssl no
tls_cacertdir /etc/openldap/cacerts

binddn cn=admin,dc=pims,dc=ac,dc=cn
bindpw @Pims%1234
validnames /^[a-z0-9._@$-][a-z0-9._@$ \\~-]*[a-z0-9._@$~-]$/i
```
然后创建nslcd模块：
```bash
cp -Rp /usr/share/authselect/default/sssd /etc/authselect/custom/nslcd
cd /etc/authselect/custom/nslcd
sed -i 's/sss/ldap/g' fingerprint-auth
sed -i 's/sss/ldap/g' password-auth
sed -i 's/sss/ldap/g' smartcard-auth
sed -i 's/sss/ldap/g' system-auth
sed -i 's/sss/ldap/g' nsswitch.conf
sed -i 's/SSSD/NSLCD/g' REQUIREMENTS
sed -i 's/SSSD/NSLCD/g' README
```
最后，选择nslcd认证，并设置nslcd服务开机启动；
```bash
authselect select custom/nslcd with-mkhomedir --force
systemctl enable --now oddjobd.service
systemctl enable --now nslcd.service
```

## 2 分布式存储
### 2.1 Lustre o2ib客户端
下载源代码：
```bash
 wget https://github.com/lustre/lustre-release/archive/refs/tags/2.15.5.tar.gz
 tar -vxf 2.15.5.tar.gz
 cd lustre-release-2.15.5/
```
编译安装：
```bash
yum install -y libmount-devel libnl3-devel libyaml-devel kernel-abi-whitelists
chmod +x autogen.sh
./autogen.sh
./configure --with-o2ib=/usr/src/ofa_kernel/default/ --with-linux=/usr/src/kernels/4.18.0-553.8.1.el8_10.x86_64
```
编译之前，修改文件
```bash
vi /usr/lib/rpm/redhat/find-requires
```
将以下两行注释掉：
```bash
[ -x /usr/lib/rpm/redhat/find-requires.ksyms ] && [ "$is_kmod" ] &&
    printf "%s\n" "${filelist[@]}" | /usr/lib/rpm/redhat/find-requires.ksyms
```
然后再编译：
```bash
make rpms
mkdir lustre-2.15.5-MOFED5.8.el8.10
mv *.rpm lustre-2.15.5-MOFED5.8.el8.10/
mv lustre-2.15.5-MOFED5.8.el8.10/ ~/software/
```
安装：
```bash
yum localinstall -y lustre-client-2.15.5-1.el8.x86_64.rpm kmod-lustre-client-2.15.5-1.el8.x86_64.rpm
echo 'options lnet networks=o2ib(bond0)' > /etc/modprobe.d/lustre.conf
depmod -a
modprobe lustre
```


### 2.2 BeeGFS客户端

## 3 并行计算环境

### 3.1 Environment Module安装
```bash
#! /bin/bash
export SOFT_SERV="http://118.123.172.217:40899"

# Install environment module
yum install tcsh tcl tcl-devel -y
wget $SOFT_SERV/modules-5.3.1.tar.bz2 --no-check-certificate
tar -vxf modules-5.3.1.tar.bz2
cd modules-5.3.1/
./configure --prefix=/opt/apps/modules
make && make install
cd ..
rm -rf modules-5.3.1*
cat << EOF >> /opt/apps/modules/etc/initrc
module use --append {/opt/apps/modules/modulefiles/intel}
module use --append {/opt/apps/modules/modulefiles/development}
module use --append {/opt/apps/modules/modulefiles/mechanics}
module use --append {/opt/apps/modules/modulefiles/chemistry}
module use --append {/opt/apps/modules/modulefiles/mathtools}
module use --append {/opt/apps/modules/modulefiles/physics}
EOF
```


### 3.2 Intel OneAPI 2023安装
下载安装包，然后静默安装：
```bash
./l_BaseKit_p_2023.1.0.46401_offline.sh -a -s --eula accept --install-dir /opt/apps/devt/oneAPI2023
./l_HPCKit_p_2023.1.0.46346_offline.sh -a -s --eula accept --install-dir /opt/apps/devt/oneAPI2023
```
再编译好FFTW：
```bash
#! /bin/sh
module purge
module load compiler/2023.1.0 mkl/2023.1.0 mpi/2021.9.0

cd $MKLROOT/interfaces/fftw2xc
make libintel64 PRECISION=MKL_DOUBLE
make libintel64 PRECISION=MKL_SINGLE

cd $MKLROOT/interfaces/fftw2xf
make libintel64 PRECISION=MKL_DOUBLE
make libintel64 PRECISION=MKL_SINGLE

cd $MKLROOT/interfaces/fftw2x_cdft
make libintel64 PRECISION=MKL_DOUBLE
make libintel64 PRECISION=MKL_SINGLE

cd $MKLROOT/interfaces/fftw3xc
make libintel64

cd $MKLROOT/interfaces/fftw3xf
make libintel64

cd $MKLROOT/interfaces/fftw3x_cdft
make libintel64 interface=lp64
make libintel64 interface=ilp64
```

## 4 无盘环境搭建

### 4.1 下载

### 4.2 安装
```bash
yum install -y elrepo-release
yum install -y dhcp-* tftp-server nfs-utils ypserv ypbind yp-tools dialog tcpdump lftp nc expect memtest86+ yum-utils ecryptfs-utils udev grub2-*
yum localinstall *.rpm -y
```

### 生成网卡信息文件
全部网卡的信息采集为guid.txt文件，例如：
```bash
08:c0:eb:03:00:ac:ad:ec
94:40:c9:ff:ff:8c:f0:60
08:c0:eb:03:00:ac:ae:b0
08:c0:eb:03:00:ac:af:b8
08:c0:eb:03:00:ac:ac:10
......
```
#### GUID转MAC
```bash
 cat guid.txt | awk -F ":" '{print $1":"$2":"$3":"$6":"$7":"$8}' > macadr-bond0.txt
```

#### 生成client-ip-hostname文件
```bash
for i in `seq 1 10`; do printf "10.10.30.%d\t\th%03d\n" "$i" "$i"; done > /etc/drbl/client-ip-hostname
```

#### 生成guid-ip.txt文件
```bash
mst_ip=$(ip addr show bond0 | grep -i 'inet ' | awk '{print $2}'| awk -F "/" '{print $1}')
echo -e "00:00:00:00:00:00:00:00 $mst_ip\t\tmaster" > guid-ip.txt
paste ../../mac/guid.txt /etc/drbl/client-ip-hostname >> guid-ip.txt
```

#### 生成dhcpd.conf文件
```bash
cp /etc/dhcp/dhcpd.conf ./dhcpd.conf.save
cp dhcpd.conf.save dhcpd.conf
```
必须和guid-ip.txt在同一目录下，然后执行python3脚本，生成文件```dhcpd.conf2```：
```python
with open("dhcpd.conf") as f_conf, open("guid-ip.txt") as f_guid:
    conf_lines = f_conf.readlines()
    guid_lines = f_guid.readlines()
    for guid_ip_line in guid_lines:
        guid_ip = guid_ip_line.split()
        if len(guid_ip) > 2:
            host_name = guid_ip[2]
            for i in range(len(conf_lines)):
                if f"host {host_name} " in conf_lines[i]:
                    j = i + 1
                    while "}" not in conf_lines[j]:
                        if "fixed-address" in conf_lines[j]:
                            ip_address = conf_lines[j].split()[-1].strip(";\n")
                            mac_address = guid_ip[0].upper()
                            guid = f"ff:00:00:00:00:00:02:00:00:02:c9:00:{mac_address.lower()}"
                            conf_lines[j]=f'        option dhcp-client-identifier = {guid};\n'+conf_lines[j]
                        j += 1
with open("dhcpd.conf2", "w") as f_conf:
    f_conf.writelines(conf_lines)
```
然后删去空白行和注释行：
```bash
cat dhcpd.conf2 |grep -v "#" > dhcpd.conf
sed -i '/^\s*$/d' dhcpd.conf
rm -rf dhcpd.conf2
```
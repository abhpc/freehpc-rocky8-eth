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

# Obtain environment variables
export SLM_INST="$APP_DIR/slurm"
MST_IP=$(ip addr show $IB_DEV|grep "inet "|awk -F "/" '{print $1}'|awk '{print $2}')
SLM_NUM=$(printf "%03d" "$CLI_NUM")
IP_PRE=$(echo $MST_IP|awk -F "." '{print $1"."$2"."$3}')

# Stop potential slurm processes
service slurm    stop
service slurmdbd stop
rm -rf $SLM_INST

# Install munge package
#yum install -y epel-release
yum install -y munge munge-devel munge-libs gtk2-devel
rm -rf /etc/munge/munge.key

# use old munge.key
#scp mxgraph:/etc/munge/munge.key /etc/munge/munge.key
#chown munge:munge /etc/munge/munge.key
create-munge-key
chkconfig munge on
service munge start

# Install MySQL
yum remove -y mariadb mariadb-server mariadb-devel
rm -rf /var/lib/mysql/*
yum install -y mariadb mariadb-server mariadb-devel
yum install pam pam-devel gtk2-devel -y
systemctl enable --now mariadb
mysql -u root -e "use mysql; update user set password=password('$DBPASSWD') where user='root'; flush privileges;"
mysql -u root -p$DBPASSWD -e "create database slurm; grant all privileges on slurm.* to 'slurm'@'localhost' identified by '$DBPASSWD'; flush privileges;"

rm -rf slurm-18.08.7 slurm-18.08.7.tar.bz2

# Download Slurm 18.08.7
cd /tmp
wget --no-check-certificate $SOFT_SERV/slurm-18.08.7.tar.bz2
tar -xf slurm-18.08.7.tar.bz2
cd slurm-18.08.7/

# Install slurm
ln -s /usr/bin/python3.11 /usr/bin/python
./configure --prefix=$SLM_INST --sysconfdir=$SLM_INST/etc --enable-pam
make -j20 && make install
cd contribs/pam && make && make install
cd ../pmi2 && make && make install
cd ../pam_slurm_adopt/ && make && make install
#cd ../nss_slurm/ && make && make install
cd ../../etc
\cp -Rf init.d.slurm /etc/init.d/slurm && chmod +x /etc/init.d/slurm
sed -i '/^SBINDIR=/a ulimit -s unlimited' /etc/init.d/slurm
sed -i '/^SBINDIR=/a ulimit -l unlimited' /etc/init.d/slurm
\cp -Rf init.d.slurmdbd /etc/init.d/slurmdbd && chmod +x /etc/init.d/slurmdbd
\cp -Rf slurmd.service /opt/etc/slurmd.service
cd ../..
rm -rf slurm-18.08.7 slurm-18.08.7.tar.bz2

# Configure Slurm
cd $SLM_INST && mkdir etc log state
useradd $ADMINUSER
chown -Rf $ADMINUSER:$ADMINUSER state/ && chmod -Rf 777 log

mkdir -p $SLM_INST/usrbin
cat << EOF > $SLM_INST/usrbin/epilog.sh
#!/bin/sh
#
# This script will kill any user processes on a node when the last
# SLURM job there ends. For example, if a user directly logs into
# an allocated node SLURM will not kill that process without this
# script being executed as an epilog.
#
# SLURM_BIN can be used for testing with private version of SLURM
SLURM_BIN="$SLM_INST/bin/"
#
if [ x\$SLURM_UID == "x" ] ; then
        exit 0
fi
if [ x\$SLURM_JOB_ID == "x" ] ; then
        exit 0
fi

#
# Don't try to kill user root or system daemon jobs
#
if [ \$SLURM_UID -lt 100 ] ; then
        exit 0
fi

job_list=\`\${SLURM_BIN}squeue --noheader --format=%i --user=\$SLURM_UID --node=localhost\`
for job_id in \$job_list
do
        if [ \$job_id -ne \$SLURM_JOB_ID ] ; then
                exit 0
        fi
done

#
# No other SLURM jobs, purge all remaining processes of this user
#
pkill -KILL -U \$SLURM_UID
rm -rf /tmp/*
exit 0
EOF
chmod +x $SLM_INST/usrbin/epilog.sh

# Add slurm configurations
echo "CgroupAutomount=yes" > $SLM_INST/etc/cgroup.conf

cat << EOF > $SLM_INST/etc/gres.conf
# A Nodes
# NodeName=${CLI_PRE}[001-${SLM_NUM}] Type=rtx4060ti Name=gpu File=/dev/nvidia[0-1]
EOF

cat << EOF > $SLM_INST/etc/nodes.conf
# A nodes
NodeName=${CLI_PRE}[001-${SLM_NUM}] sockets=2 CoresPerSocket=24 ThreadsPerCore=1 State=UNKNOWN
EOF

cat << EOF > $SLM_INST/etc/partitions.conf
# Partition
PartitionName=FH Nodes=${CLI_PRE}[001-${SLM_NUM}] MaxTime=INFINITE State=UP PriorityTier=100 Default=YES OverSubscribe=NO
EOF

cat << EOF > $SLM_INST/etc/slurm.conf
# Example slurm.conf file. Please run configurator.html
# (in doc/html) to build a configuration file customized
# for your environment.

# Include odes information
include $SLM_INST/etc/nodes.conf

# Define first job id
# FirstJobId=4969

# Include partitions information
include $SLM_INST/etc/partitions.conf

# Cluster information
ClusterName=$CLUSNAME
ControlMachine=$HOSTNAME
ControlAddr=$MST_IP
AccountingStorageHost=$MST_IP

# Administrator
SlurmUser=$ADMINUSER
SlurmdUser=root
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge

# Define system files directories
StateSaveLocation=$SLM_INST/state
SlurmdSpoolDir=/var/log/slurmd
SwitchType=switch/none
MpiDefault=pmi2
SlurmctldPidFile=/var/run/slurmctld.pid
SlurmdPidFile=/var/run/slurmd.pid

# Slurm service configurations
ReturnToService=2
PropagateResourceLimits=ALL
SlurmdTimeout=300
TCPTimeout=10

# Run script at job allocation
#Prolog=$SLM_INST/usrbin/prolog.sh
#PrologFlags=Alloc

# Run script at job termination
Epilog=$SLM_INST/usrbin/epilog.sh

# SCHEDULING
SchedulerType=sched/backfill
#SelectType=select/linear
SelectType=select/cons_res
SelectTypeParameters=CR_Core
#GresTypes=gpu
#FastSchedule=1

# QOS factor
PriorityType=priority/multifactor
PriorityWeightQOS=100000

# CGROUP
TaskPlugin=task/cgroup
ProctrackType=proctrack/cgroup

# LOGGING
#DebugFlags=gres
SlurmctldDebug=3
SlurmctldLogFile=$SLM_INST/log/slurmctld.log
SlurmdDebug=quiet
#SlurmdDebug=3
SlurmdLogFile=/var/log/slurmd.log

# JOBS
JobCompType=jobcomp/mysql
JobCompHost=localhost
JobCompLoc=slurm
JobCompUser=slurm
JobCompPass=$DBPASSWD
JobCompPort=3306
JobContainerType=job_container/none
JobAcctGatherFrequency=30
JobAcctGatherType=jobacct_gather/linux
JobRequeue=0

# ACCOUNTING
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageEnforce=associations,qos,limits

# PrivateData
PrivateData=jobs,accounts,events,users,usage,reservations

DebugFlags=NO_CONF_HASH
EOF

cat << EOF > $SLM_INST/etc/slurmdbd.conf
# Authentication info
AuthType=auth/munge

# slurmdbd info
DbdAddr=0.0.0.0
DbdHost=localhost
DbdPort=6819
SlurmUser=$ADMINUSER
DebugLevel=4
LogFile=$SLM_INST/log/slurmdbd.log
PidFile=/var/run/slurmdbd.pid
#PluginDir=/usr/lib/slurm
PrivateData=jobs,accounts,events,users,usage,reservations
#TrackWCKey=yes

# Database info
StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePort=3306
StoragePass=$DBPASSWD
StorageUser=slurm
StorageLoc=slurm
EOF

chmod 600 $SLM_INST/etc/slurmdbd.conf
chown $ADMINUSER:$ADMINUSER -Rf $SLM_INST/etc/

# Add user define commands
cat << EOF > $SLM_INST/usrbin/slassoc
#! /bin/bash

if [ \$USER != "root"  ]; then
        sacctmgr list assoc format="Clusters,Account,User,qos,partition,MaxSubmitJobs,GrpTRES%30" user=\$USER
else
        sacctmgr list assoc format="Clusters,Account,User,qos,partition,MaxSubmitJobs,GrpTRES%30"
fi
EOF
chmod +x $SLM_INST/usrbin/slassoc

cat << EOF > $SLM_INST/usrbin/slhist
#! /bin/bash
ARGS=\$*
sacct -X -o "jobid%6,jobname%20,AllocCPUS,user,Submit%14,Elapsed%12,state%10,workdir%70" \$ARGS
EOF
chmod +x $SLM_INST/usrbin/slhist

cat << EOF > $SLM_INST/usrbin/slhosts
#! /bin/bash
printf "%-8s %-10s %-6s %-14s %5s %8s %8s %s\n" "HOSTNAME" "STATE" "CPUS" "CPUS(A/I/O/T)" "LOAD" "MEM/GB" "WEIGHT" "REASON"
sinfo -o "%8n %10t %6c %14C %10O %8e %8w %E" -S "n" -h|awk '{printf("%-8s %-10s %-6i %-14s %4i%s %8i %8i %s %s\n", \$1,\$2,\$3,\$4,100*\$5/\$3,"%",\$6/1024,\$7,\$8,\$9)}'
EOF
chmod +x $SLM_INST/usrbin/slhosts

cat << EOF > $SLM_INST/usrbin/slload
#! /bin/bash
printf "%-6s %-8s %-6s %5s %8s\n" "Host" "Status" "CPUs" "Load" "Mem/GB"
sinfo -o "%8n %10t %6c %10O %10e %8d" -S "t,O" -h|awk '{printf("%-6s %-8s %-6i %4i%s %8i\n", \$1,\$2,\$3,100*\$4/\$3,"%",\$5/1024)}'
EOF
chmod +x $SLM_INST/usrbin/slload

cat << EOF > $SLM_INST/usrbin/slqos
#! /bin/bash
sacctmgr list qos format="Name,priority,gracetime,preemptmode,usagefactor"
EOF
chmod +x $SLM_INST/usrbin/slqos

cat << EOF > $SLM_INST/usrbin/sresume
#! /bin/bash
NODE_LIST=\$1
scontrol update nodename="\$NODE_LIST" state=resume
EOF
chmod +x $SLM_INST/usrbin/sresume

cat << EOF > $SLM_INST/usrbin/slcores
#! /bin/bash

sinfo -o "%20P %10D %20C" -h | awk 'BEGIN {printf "%-20s %-10s %-10s %-10s %-10s %-10s\\n", "PARTITION", "NODES", "Total", "Alloc", "Idle", "Other"} {split(\$3, cpus, "/"); printf "%-20s %-10s %-10s %-10s %-10s %-10s\n", \$1, \$2, cpus[4], cpus[1], cpus[2], cpus[3]}'
EOF
chmod +x $SLM_INST/usrbin/slcores


cat << EOF > /opt/etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

$MST_IP$(printf "\t\t")$HOSTNAME
EOF

for i in `seq 1 $CLI_NUM`
do
        printf "$IP_PRE.$i\t\t${CLI_PRE}%03d\n" "$i" >> /opt/etc/hosts
done
\cp -Rf /opt/etc/hosts /etc/hosts

source /etc/bashrc

systemctl daemon-reload
service munge restart
service slurmdbd start
chkconfig slurmdbd on
echo "Sleep for 10 seconds ..."
sleep 10
sacctmgr -i add cluster Name=$CLUSNAME
chkconfig slurm on
service slurm restart

cat << EOF >> /etc/rc.d/rc.local
FILE="$SLM_INST/sbin/slurmd"
while true; do
    if [ -e "\$FILE" ]; then
        service munge restart
        service slurmdbd restart
        service slurm restart
        break
    else
        sleep 1
    fi
done
EOF

awk '!seen[$0]++' /etc/rc.d/rc.local > /etc/rc.d/rc.local.uniq
mv /etc/rc.d/rc.local.uniq /etc/rc.d/rc.local
chmod +x /etc/rc.d/rc.local
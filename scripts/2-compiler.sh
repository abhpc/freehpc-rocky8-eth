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

# Obtain system variables
export SLM_INST="$APP_DIR/slurm"
GCC_DIR="$APP_DIR/devt"
JN="20"
mkdir $APP_DIR -p
cd /tmp

# Install environment module
if [ ! -d "$APP_DIR/modules" ] || [ -z "$(ls -A $APP_DIR/modules)" ]; then
    yum install tcsh tcl tcl-devel isl isl-devel -y
    wget $SOFT_SERV/modules-5.3.1.tar.bz2 --no-check-certificate
    tar -vxf modules-5.3.1.tar.bz2
    cd modules-5.3.1/
    ./configure --prefix=$APP_DIR/modules
    make && make install
    cd ..
    rm -rf modules-5.3.1*

    # Create directories for modulefiles
    mkdir -p $APP_DIR/modules/modulefiles/development
    mkdir -p $APP_DIR/modules/modulefiles/mechanics
    mkdir -p $APP_DIR/modules/modulefiles/chemistry
    mkdir -p $APP_DIR/modules/modulefiles/mathtools
    mkdir -p $APP_DIR/modules/modulefiles/physics
else
    echo "The Environment Module has been installed. Skip ..."
    sleep 5
fi
cat << EOF > $APP_DIR/modules/etc/initrc
#%Module
module use --append {$APP_DIR/modules/modulefiles/intel}
module use --append {$APP_DIR/modules/modulefiles/development}
module use --append {$APP_DIR/modules/modulefiles/mechanics}
module use --append {$APP_DIR/modules/modulefiles/chemistry}
module use --append {$APP_DIR/modules/modulefiles/mathtools}
module use --append {$APP_DIR/modules/modulefiles/physics}
EOF

# Revise /etc/bashrc and default.sh
if ! grep -q "$APP_DIR/config/\*.sh" "/etc/bashrc"; then
    cat << EOF >> /etc/bashrc
for i in $APP_DIR/config/*.sh; do
        if [ -r "\$i" ]; then
            if [ "\$PS1" ]; then
                . "\$i"
            else
                . "\$i" >/dev/null 2>&1
            fi
        fi
done
EOF
    uniq /etc/bashrc > /etc/bashrc.tmp
    mv -f /etc/bashrc.tmp /etc/bashrc
fi

mkdir -p $APP_DIR/config
cat << EOF > $APP_DIR/config/default.sh
#! /bin/bash

# System bin
export PATH="$APP_DIR/bin:/opt/MegaRAID/MegaCli/:\$PATH"

# Enviroment Module
source $APP_DIR/modules/init/profile.sh

# Slurm
export PATH="$SLM_INST/bin:$SLM_INST/sbin:$SLM_INST/usrbin:\$PATH"
export LD_LIBRARY_PATH="$SLM_INST/lib/slurm:$SLM_INST/lib:\$LD_LIBRARY_PATH"
export SINFO_FORMAT="%10P %.6a %.6D  %.4c  %8t %16G %N"
#export SQUEUE_FORMAT="%10A %10P %8u %8a %30j %4t %8D %8C %16M %8q %R"
export SQUEUE_FORMAT="%10A %8u %8a %30j %4t %8D %8C %16V %16M %R"
export SQUEUE_SORT="-t,+i"
export SLURM_TIME_FORMAT=relative

# srun default using intel mpirun
export SLURM_MPI_TYPE="pmi2"
export I_MPI_HYDRA_RMK="slurm"
EOF

# Install oneAPI 2023.1.0
if [ ! -d "$APP_DIR/devt/oneAPI2023" ] || [ -z "$(ls -A $APP_DIR/devt/oneAPI2023)" ]; then
    wget $SOFT_SERV/l_BaseKit_p_2023.1.0.46401_offline.sh --no-check-certificate
    wget $SOFT_SERV/l_HPCKit_p_2023.1.0.46346_offline.sh --no-check-certificate
    chmod +x l_BaseKit_p_2023.1.0.46401_offline.sh
    chmod +x l_HPCKit_p_2023.1.0.46346_offline.sh
    mkdir -p $APP_DIR/devt/oneAPI2023
    ./l_BaseKit_p_2023.1.0.46401_offline.sh -a -s --eula accept --install-dir $APP_DIR/devt/oneAPI2023
    ./l_HPCKit_p_2023.1.0.46346_offline.sh -a -s --eula accept --install-dir $APP_DIR/devt/oneAPI2023
else
    echo "OneAPI 2023 has been installed. Skip ..."
    sleep 5
fi
rm -rf $APP_DIR/modules/modulefiles/intel
$APP_DIR/devt/oneAPI2023/modulefiles-setup.sh --ignore-latest --output-dir="$APP_DIR/modules/modulefiles/intel"

# Install Anaconda 3
if [ ! -d "$APP_DIR/devt/anaconda3" ] || [ -z "$(ls -A $APP_DIR/devt/anaconda3)" ]; then
    wget $SOFT_SERV/Anaconda3-2023.07-0-Linux-x86_64.sh --no-check-certificate
    chmod +x Anaconda3-2023.07-0-Linux-x86_64.sh
    ./Anaconda3-2023.07-0-Linux-x86_64.sh -b -p $APP_DIR/devt/anaconda3
else
    echo "Anaconda3 has been installed. Skip ..."
    sleep 5
fi
mkdir -p $APP_DIR/modules/modulefiles/development/anaconda3/
cat << EOF > $APP_DIR/modules/modulefiles/development/anaconda3/2023.07
#%Module1.0
module-whatis "Anaconda3 environment 2023.07"

conflict anaconda3
set ANACONDA3_PATH $APP_DIR/devt/anaconda3

prepend-path PATH \$ANACONDA3_PATH/bin
prepend-path LD_LIBRARY_PATH \$ANACONDA3_PATH/lib
prepend-path MANPATH \$ANACONDA3_PATH/share/man
EOF

# Install gcc 13.1.0
export GCC_VERS="13.1.0"
if [ ! -d "$GCC_DIR/gcc-$GCC_VERS" ] || [ -z "$(ls -A $GCC_DIR/gcc-$GCC_VERS)" ]; then
    # Down gcc 13.1.0 and related packages
    wget $SOFT_SERV/gcc-$GCC_VERS.tar.xz --no-check-certificate
    wget $SOFT_SERV/gmp-6.1.2.tar.xz --no-check-certificate
    wget $SOFT_SERV/mpfr-3.1.6.tar.gz --no-check-certificate
    wget $SOFT_SERV/mpc-1.0.3.tar.gz --no-check-certificate
    mkdir -p $APP_DIR/modules/modulefiles/development/gcc

    # Install gmp 6.1.2
    tar xvf gmp-6.1.2.tar.xz
    cd gmp-6.1.2
    ./configure --prefix=$GCC_DIR/gmp-6.1.2
    make -j $JN && make install
    cd ..

    # Install mpfr 3.1.6
    tar xvf mpfr-3.1.6.tar.gz
    cd mpfr-3.1.6
    ./configure --prefix=$GCC_DIR/mpfr-3.1.6 --with-gmp=$GCC_DIR/gmp-6.1.2
    make -j $JN && make install
    cd ..

    # Install mpc 1.0.3
    tar xvf mpc-1.0.3.tar.gz
    cd mpc-1.0.3
    ./configure --prefix=$GCC_DIR/mpc-1.0.3 --with-gmp=$GCC_DIR/gmp-6.1.2 --with-mpfr=$GCC_DIR/mpfr-3.1.6
    make -j $JN && make install
    cd ..

    # Clean gmp, mpc and mpfr files
    rm -rf gmp-6.1.2 mpc-1.0.3 mpfr-3.1.6

    # ld configure
    echo "$GCC_DIR/gmp-6.1.2/lib"  >> /etc/ld.so.conf
    echo "$GCC_DIR/mpfr-3.1.6/lib" >> /etc/ld.so.conf
    echo "$GCC_DIR/mpc-1.0.3/lib"  >> /etc/ld.so.conf
    awk '!seen[$0]++' /etc/ld.so.conf > /etc/ld.so.conf.uniq
    mv -f /etc/ld.so.conf.uniq /etc/ld.so.conf
    ldconfig -v

    # Install GCC 13.1.0
    tar xvf gcc-$GCC_VERS.tar.xz
    cd gcc-$GCC_VERS
    ./configure --enable-checking=release --enable-languages=c,c++,fortran --disable-multilib \
                                                --prefix=$GCC_DIR/gcc-$GCC_VERS --with-gmp=$GCC_DIR/gmp-6.1.2 \
                                                --with-mpfr=$GCC_DIR/mpfr-3.1.6 --with-mpc=$GCC_DIR/mpc-1.0.3
    make -j $JN
    make install
    cd ..
    rm -rf gcc-$GCC_VERS
else
    echo "GCC $GCC_VERS has been installed. Skip ..."
    sleep 5
fi
cat << EOF > $APP_DIR/modules/modulefiles/development/gcc/$GCC_VERS
#%Module 1.0
conflict        gcc
set             DES             $GCC_DIR/gcc-$GCC_VERS

prepend-path    PATH            \$DES/bin
prepend-path    LD_LIBRARY_PATH \$DES/lib64
prepend-path    LIBRARY_PATH    \$DES/lib64
prepend-path    MANPATH         \$DES/share/man
EOF


# Install cmake 3.28.1
if [ ! -d "$APP_DIR/devt/cmake-3.28.1" ] || [ -z "$(ls -A $APP_DIR/devt/cmake-3.28.1)" ]; then
    wget $SOFT_SERV/cmake-3.28.1.tar.gz --no-check-certificate
    tar -zxf cmake-3.28.1.tar.gz
    cd cmake-3.28.1/
    ./configure --prefix=$APP_DIR/devt/cmake-3.28.1
    make -j $JN
    make install
    cd .. && rm -rf cmake-3.28.1/
else
    echo "Cmake 3.28.1 has been installed. Skip ..."
    sleep 5
fi
mkdir -p $APP_DIR/modules/modulefiles/development/cmake
cat << EOF > $APP_DIR/modules/modulefiles/development/cmake/3.28.1
#%Module 1.0
conflict cmake

prepend-path    PATH             $APP_DIR/devt/cmake-3.28.1/bin
EOF

# Compile FFTW for oneAPI
source /etc/bashrc
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

# Install make 4.3
cd /tmp
wget $SOFT_SERV/make-4.3.tar.gz 
tar -vxf make-4.3.tar.gz
cd make-4.3/
./configure --prefix="$APP_DIR/devt/make-4.3"
make -j10
make install
mkdir -p $APP_DIR/modules/modulefiles/development/make/
cat << EOF > $APP_DIR/modules/modulefiles/development/make/4.3
#%Module 1.0
conflict        make
set             DES             $APP_DIR/devt/make-4.3

prepend-path    PATH            \$DES/bin
EOF
ln -s $APP_DIR/devt/make-4.3/bin/make $APP_DIR/devt/make-4.3/bin/gmake

# Clean files
cd /tmp
rm -rf  Anaconda3-2023.07-0-Linux-x86_64.sh cmake-3.28.1.tar.gz \
        gcc-$GCC_VERS.tar.xz gmp-6.1.2.tar.xz intel/ l_BaseKit_p_2023.1.0.46401_offline.sh \
        l_HPCKit_p_2023.1.0.46346_offline.sh mpc-1.0.3.tar.gz mpfr-3.1.6.tar.gz make-4.3*
# Copyright 2013 Enea Software AB
# Authored-by:  David Nyström <david.nystrom@enea.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# An Openembedded rootfs-sandbox intended for use with the 
# meta-toolchain SDK tarball provided with a OE based distro.
# Uses a remote or local package repository for rootfs configuration. 

# TODO :
# 1: Fix missing shlibsign in nativesdk (nss).
# 2: Reset RPM DB rootfs path to / before creating the rootfs tarball. Not working.
# 3: Remove host-native path to ensure no host-contamination when
#    All needed items are added to nativesdk.
# 4: Fix extesion of nativesdk and target sysroots with RPM. Not working.
# 20: do_vmdk, do_ext3 or do_it_yourself ?
# 999: Allow sandbox usage of deb PMS
 
### Set ENV ###
export INTERCEPT_DIR="${OECORE_NATIVE_SYSROOT}/usr/share/postinst-intercepts"

# Setup pseduo environment
export PSEUDO_BINDIR=${OECORE_NATIVE_SYSROOT}/bin
export PSEUDO_LIBDIR=${OECORE_NATIVE_SYSROOT}/usr/lib/pseudo/lib
export PSEUDO_PREFIX=${OECORE_NATIVE_SYSROOT}
export LD_LIBRARY_PATH=${OECORE_NATIVE_SYSROOT}/usr/lib/pseudo/lib:${LD_LIBRARY_PATH}
export LD_LIBRARY_PATH=${OECORE_NATIVE_SYSROOT}/usr/lib/pseudo/lib64:${LD_LIBRARY_PATH}
export PSEUDO_NOSYMLINKEXP=1
export PSEUDO_DISABLED=0
export PSEUDO_UNLOAD=0
export PSEUDO_DEBUG=0
FAKEROOT="pseudo"

# Needed by qemuwrapper and postinstall intercepts
export datadir="/usr/share"
export includedir="/usr/include"
export libdir="/usr/lib"
export base_libdir="/lib"
export bindir="/usr/bin"
export base_bindir="/bin"
export sysconfdir="/etc"

export PYTHONIOENCODING="UTF-8"

DEVTABLE="${OECORE_NATIVE_SYSROOT}/usr/share/device_table-minimal.txt"
ORIGDIR=$(pwd)
rpmlibdir="/var/lib/rpm"
export REPO_URL="http://downloads.yoctoproject.org/releases/yocto/yocto-1.5"


### Define helper functions ###
create_scripts()
{
	cat << EOF > ${SCRIPTS}/scriptlet_wrapper
#!/bin/sh

export PATH="${PATH}"
export D="${IMAGE_ROOTFS}"
export OFFLINE_ROOT="\$D"
export IPKG_OFFLINE_ROOT="\$D"
export OPKG_OFFLINE_ROOT="\$D"
export INTERCEPT_DIR="${INTERCEPT_DIR}"
export NATIVE_ROOT=${OECORE_NATIVE_SYSROOT}
export PYTHONIOENCODING="UTF-8"

\$2 \$1/\$3 \$4
if [ \$? -ne 0 ]; then
  if [ \$4 -eq 1 ]; then
    mkdir -p \$1/etc/rpm-postinsts
    num=100
    while [ -e \$1/etc/rpm-postinsts/\${num}-* ]; do num=\$((num + 1)); done
    name=\`head -1 \$1/\$3 | cut -d' ' -f 2\`
    echo "#!\$2" > \$1/etc/rpm-postinsts/\${num}-\${name}
    echo "# Arg: \$4" >> \$1/etc/rpm-postinsts/\${num}-\${name}
    cat \$1/\$3 >> \$1/etc/rpm-postinsts/\${num}-\${name}
    chmod +x \$1/etc/rpm-postinsts/\${num}-\${name}
  else
    echo "Error: pre/post remove scriptlet failed"
  fi
fi
EOF
	chmod 755 ${SCRIPTS}/scriptlet_wrapper

	cat << EOF > ${SCRIPTS}/opkg-cl
#!/bin/sh
${OECORE_NATIVE_SYSROOT}/usr/bin/opkg-cl ${OFLAGS} "\$@"
if [ \$? -ne 0 ]; then
    ${OECORE_NATIVE_SYSROOT}/usr/bin/opkg-cl ${OFLAGS} install run-postinsts >/dev/null 2>&1
fi
EOF
	chmod 755 ${SCRIPTS}/opkg-cl

	cat << EOF > ${SCRIPTS}/smart
#!/bin/sh
${OECORE_NATIVE_SYSROOT}/usr/bin/smart ${OFLAGS} "\$@"
if [ \$? -ne 0 ]; then
    ${OECORE_NATIVE_SYSROOT}/usr/bin/opkg-cl ${OFLAGS} install -y run-postinsts >/dev/null 2>&1
fi
EOF
	chmod 755 ${SCRIPTS}/smart


# Create devmodwrapper dummy script
    if [ ! -f ${SCRIPTS}/depmodwrapper ] ; then
	cat > ${SCRIPTS}/depmodwrapper << EOF
#!/bin/sh
# Expected to be called as: depmodwrapper -a KERNEL_VERSION
if [ "\$1" != "-a" -o "\$2" != "-b" ]; then
    echo "Usage: depmodwrapper -a -b rootfs KERNEL_VERSION" >&2
    exit 1
fi

# Sanity checks off, since we are installing from a package repository,
# dependency checks should be alredy in place in package RDEPENDS.
exec env depmod "\$1" "\$2" "\$3" "\$4"
EOF
	chmod 755 ${SCRIPTS}/depmodwrapper
    fi

    if [ ! -f ${SCRIPTS}/do_ext2.sh ] ; then
	cat > ${SCRIPTS}/do_ext2.sh << EOF
#!/bin/sh

if [ \$# = 0 ]; then
    echo "Usage: \$0 /tmp/rootfs_filename"
    exit 1
fi 

rootfs_size="\$(du -ks ${IMAGE_ROOTFS} | awk '{print \$1 * 2}')"
genext2fs -b \$rootfs_size -d ${IMAGE_ROOTFS} \$1.ext2
echo "Output: \$1.ext2"
exit 0

EOF
	chmod 755 ${SCRIPTS}/do_ext2.sh
    fi

    if [ ! -f ${SCRIPTS}/do_tar.sh ] ; then
	cat > ${SCRIPTS}/do_tar.sh << EOF
#!/bin/sh

if [ \$# = 0 ]; then
    echo "Usage: \$0 /tmp/rootfs_filename"
    exit 1
fi

( cd \${IMAGE_ROOTFS};
  tar cfz \$1.tar.gz .
)
echo "Output: \$1.tar.gz"
exit 0

EOF
	chmod 755 ${SCRIPTS}/do_tar.sh
    fi
}

show_help() {
    cat << EOF
Usage: $0 -r <rootfs_path> -p <ipk|rpm|deb>

The -s sysroot options help you expand your toolchain
sysroot, if you have any missing libs.

If you get postinstall failures, please make sure you 
have "run-postinsts" installed, which will run your failed 
postinstall hooks at first boot.

Example: 
# Create a runnable target rootfs
$0 -r /tmp/rootfs -p ipk -a x86_64 -b qemux86_64
$0 -r /tmp/rootfs -p ipk -a ppce500v2 -b p1025twr -u file:///media/sdb5/poky/build/tmp/deploy/

# Expand your nativesdk sysroot
$0 -r /opt/poky/1.5/sysroots/x86_64-pokysdk-linux/ -p ipk -a x86_64_nativesdk  -s

# Expand your target sysroot
$0 -r /opt/poky/1.5/sysroots/x86_64-poky-linux/ -p ipk -a x86_64 -b qemux86_64  -s
$0 -r /opt/poky/1.5/sysroots/ppce500v2-oel-linux-gnuspe/ -p ipk -a ppce500v2 -b p1025twr -s -u file:///media/sdb5/poky/build/tmp/deploy/

OPTIONS:
   -r      Rootfs path
   -a      Architecture (x86-64, ppce500v2 et.c.)
   -b      BSP (qemux86_64, p1022ds et.c.)
   -f      Select custom opkg configuration file
   -d      Use this makedevs devicetable instead of default
   -u      Set Repository URL
   -s      This is a sysroot, i.e. dont run postinstall hooks.
   -p      ipk|deb|rpm
   -v      Verbose mode
EOF
}

### BEGIN ###
if [ "${OECORE_NATIVE_SYSROOT}x" = "x" ]; then
    echo "source the SDK environment before running me"
    exit 1
fi

if [ $# = 0 ]; then
    show_help
    exit 1
fi 

rflag=false
pflag=false

# Set sane default
export T_ARCH="x86_64"
export T_BSP="qemux86_64"

while getopts "h?r:f:d:p:u:a:b:s" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    r)  export IMAGE_ROOTFS=${OPTARG%/}
        rflag=true
        ;;
    a)  export T_ARCH=$OPTARG
        ;;
    s)  export IS_SYSROOT="1"
        ;;
    b)  export T_BSP=$OPTARG
        ;;
    f)  OPKG_CONFFILE=$OPTARG
        ;;
    d)  DEVTABLE=$OPTARG
        ;;
    u)  REPO_URL=${OPTARG%/}
        ;;
    p)  
        pflag=true
        if [ "$OPTARG" = "deb" ]; then
	    echo "Only ipk & rpm supported sofar"
	    exit 1
	elif [ "$OPTARG" = "rpm" ]; then
	    export PMS="rpm"
	    export PMC="smart"
	elif [ "$OPTARG" = "ipk" ]; then
	    export PMS="ipk"
	    export PMC="opkg-cl"
	else
	    pflag=false
	fi
        ;;    
    esac
done
if [ $rflag = false ] || [ $pflag = false ]; then
    echo "Error: Options -r and -p are mandatory"
    exit 0
fi

### BEGIN ENV ###

# Stores PSEUDO fakeroot DB and opkg temp files
export OPKG_TMP_DIR="${IMAGE_ROOTFS}-tmp"
export SCRIPTS="${IMAGE_ROOTFS}-tmp/scripts"

# Use targets "special" update-rc.d + shadow utils + makedevs
export PATH="${OECORE_NATIVE_SYSROOT}/usr/sbin:${OECORE_TARGET_SYSROOT}/usr/sbin:${PATH}"
export PATH="${OECORE_NATIVE_SYSROOT}/sbin:${OECORE_NATIVE_SYSROOT}/usr/bin/crossscripts:${PATH}"
#python path
export PATH="${SCRIPTS}:${OECORE_NATIVE_SYSROOT}/usr/bin:${PATH}"

export PSEUDO_LOCALSTATEDIR="${IMAGE_ROOTFS}-tmp/var/lib/pseudo"

# Needed for SDKs update-alternatives
export OPKG_OFFLINE_ROOT="${IMAGE_ROOTFS}"
export OPKG_CONFDIR_TARGET="${IMAGE_ROOTFS}/etc/opkg"

# Needed for update-rc.d and many others
export D="${IMAGE_ROOTFS}"

# Old Legacy, to be removed ?
export OFFLINE_ROOT="${IMAGE_ROOTFS}"
export IPKG_OFFLINE_ROOT="${IMAGE_ROOTFS}"
SDIR="$( cd "$( dirname "$0" )" && pwd )"
### END ENV ###

mkdir -p ${SCRIPTS}

if [ "$PMS" = "rpm" ]; then
    export OFLAGS="--data-dir=${IMAGE_ROOTFS}/var/lib/smart"
elif [ "$PMS" = "ipk" ]; then
    if [ -z $OPKG_CONFFILE ]; then
	export OPKG_CONFFILE="${IMAGE_ROOTFS}/etc/opkg.conf"
    fi
    if [ ! -f $OPKG_CONFFILE ]; then
	echo "dest root /" > $OPKG_CONFFILE
	echo "lists_dir ext /var/lib/opkg" >> $OPKG_CONFFILE 
    fi
    
    if [ -z ${IS_SYSROOT} ]; then
	export OFLAGS="--force-postinstall --no-install-recommends --prefer-arch-to-version -t ${OPKG_TMP_DIR} -f ${OPKG_CONFFILE} -o ${IMAGE_ROOTFS}"
    else
	export OFLAGS="--prefer-arch-to-version -t ${OPKG_TMP_DIR} -f ${OPKG_CONFFILE} -o ${IMAGE_ROOTFS}"
    fi
fi

create_scripts

$FAKEROOT -d

echo "Installing initial /dev directory"

$FAKEROOT mkdir -p ${IMAGE_ROOTFS}/dev
$FAKEROOT mkdir -p ${IMAGE_ROOTFS}/etc/opkg/arch
$FAKEROOT mkdir -p ${IMAGE_ROOTFS}/etc/rpm
$FAKEROOT mkdir -p ${IMAGE_ROOTFS}/etc/rpm-postinsts
$FAKEROOT mkdir -p ${IMAGE_ROOTFS}/install/tmp

$FAKEROOT mkdir -p ${IMAGE_ROOTFS}/var/lib/opkg
$FAKEROOT mkdir -p ${OPKG_TMP_DIR}/var/lib/pseudo

if [ "$PMS" = "rpm" ]; then    
    $FAKEROOT mkdir -p ${IMAGE_ROOTFS}/etc/rpm/sysinfo
    $FAKEROOT echo "/" > ${IMAGE_ROOTFS}/etc/rpm/sysinfo/Dirnames
    $FAKEROOT mkdir -p ${IMAGE_ROOTFS}/$rpmlibdir
    if [ ! -z ${IS_SYSROOT} ]; then
	$FAKEROOT rm -fr ${IMAGE_ROOTFS}/$rpmlibdir/*
    fi
    $FAKEROOT mkdir -p ${IMAGE_ROOTFS}/$rpmlibdir/log

    # After change the __db.* cache size, log file will not be generated automatically,
    # that will raise some warnings, so touch a bare log for rpm write into it.
    $FAKEROOT touch ${IMAGE_ROOTFS}/$rpmlibdir/log/log.0000000001
    if [ ! -e ${IMAGE_ROOTFS}/$rpmlibdir/DB_CONFIG ]; then
        $FAKEROOT cat > ${IMAGE_ROOTFS}/$rpmlibdir/DB_CONFIG << EOF
# ================ Environment
set_data_dir .
set_create_dir .
set_lg_dir ./log
set_tmp_dir ./tmp
set_flags db_log_autoremove on

# -- thread_count must be >= 8
set_thread_count 64

# ================ Logging

# ================ Memory Pool
set_cachesize 0 1048576 0
set_mp_mmapsize 268435456

# ================ Locking
set_lk_max_locks 16384
set_lk_max_lockers 16384
set_lk_max_objects 16384
mutex_set_max 163840

# ================ Replication
EOF

    # Create database so that smart doesn't complain (lazy init)
    $FAKEROOT rpm --root ${IMAGE_ROOTFS} --dbpath $rpmlibdir -qa > /dev/null
    $FAKEROOT $PMC ${OFLAGS} config --set rpm-root=${IMAGE_ROOTFS}
    $FAKEROOT $PMC ${OFLAGS} config --set rpm-dbpath=$rpmlibdir
    $FAKEROOT $PMC ${OFLAGS} config --set rpm-extra-macros._var=/var
    $FAKEROOT $PMC ${OFLAGS} config --set rpm-extra-macros._tmppath=/install/tmp

    # Write common configuration for host and target usage
    $FAKEROOT $PMC ${OFLAGS} config --set rpm-nolinktos=1
    $FAKEROOT $PMC ${OFLAGS} config --set ignore-all-recommends=1
    $FAKEROOT $PMC ${OFLAGS} config --set rpm-extra-macros._cross_scriptlet_wrapper=${SCRIPTS}/scriptlet_wrapper
    $FAKEROOT rpm --eval "%{_arch}-%{_vendor}-%{_os}%{?_gnu}" > ${IMAGE_ROOTFS}/etc/rpm/platform
    $FAKEROOT echo ".*" >> ${IMAGE_ROOTFS}/etc/rpm/platform
    if [ ! -z ${IS_SYSROOT} ]; then
	$FAKEROOT $PMC ${OFLAGS} config --set rpm-noscripts=1
    fi

  fi	
  export RPM_ETCRPM=${IMAGE_ROOTFS}/etc/rpm
fi

command -v makedevs >/dev/null 2>&1 || { echo "Cant find 'makedevs' in PATH. Aborting." >&2; exit 1; }

# Ignore exitcode
set +e
$FAKEROOT makedevs -r ${IMAGE_ROOTFS} -D $DEVTABLE
set -e

# Base time
$FAKEROOT date "+%m%d%H%M%Y" > ${IMAGE_ROOTFS}/etc/timestamp

# Add OpenDNS
$FAKEROOT echo "nameserver 208.67.220.220" >> ${IMAGE_ROOTFS}/etc/resolv.conf
$FAKEROOT echo "nameserver 208.67.222.222" >> ${IMAGE_ROOTFS}/etc/resolv.conf

cd ${IMAGE_ROOTFS};

cat << EOF
Welcome to interactive image creation sandbox
You are now "root".
How to Setup repositories (Only needed first time):

EOF
if [ "$PMS" = "rpm" ]; then
    cat << EOF
RPM: smartpm
smart channel -y --add rpmsys type=rpm-sys name="Local RPM Database"
smart channel -y --add all type=rpm-md baseurl=${REPO_URL}/rpm/all
smart channel -y --add ${T_ARCH} type=rpm-md baseurl=${REPO_URL}/rpm/${T_ARCH}
smart channel -y --add ${T_BSP} type=rpm-md baseurl=${REPO_URL}/rpm/${T_BSP}
smart channel -y --set all priority=1
smart channel -y --set ${T_ARCH} priority=16
smart channel -y --set ${T_BSP} priority=21
smart update
EOF
elif [ "$PMS" = "ipk" ]; then
    cat << EOF
IPK: opkg-cl
echo "src/gz all ${REPO_URL}/ipk/all" > \
${OPKG_CONFFILE}
echo "src/gz ${T_ARCH} ${REPO_URL}/ipk/${T_ARCH}" >> \
${OPKG_CONFFILE}
echo "src/gz ${T_BSP} ${REPO_URL}/ipk/${T_BSP}" >> \
${OPKG_CONFFILE}
echo "arch all 1" >> ${OPKG_CONFFILE}
echo "arch any 6" >> ${OPKG_CONFFILE}
echo "arch noarch 11" >> ${OPKG_CONFFILE}
echo "arch ${T_ARCH} 16" >> ${OPKG_CONFFILE}
echo "arch ${T_BSP} 21" >> ${OPKG_CONFFILE}
opkg-cl update
EOF
elif [ "$PMS" = "deb" ]; then
cat << EOF
DEB: TBD
EOF
fi

cat << EOF
Example usecases:

1. List options
# $PMC --help

2. Install new packages: 
# $PMC install packagegroup-core-boot gcc

3. Install kernel dtb&image and u-boot:
# $PMC install u-boot-images kernel-devicetree kernel-3.4.10...

4. Install your own stuff:
# cd <source>; make install DESTDIR=\${IMAGE_ROOTFS}

5. When done, create a tarball or ext2 FS
# do_tar.sh ~/my_rootfs
# do_ext2.sh ~/my_rootfs

6. Run with a custom kernel
# cd <kernel_dir>
# INSTALL_MOD_PATH=${IMAGE_ROOTFS} make modules_install
# INSTALL_MOD_PATH=${IMAGE_ROOTFS} make firmware_install
# do_ext2.sh ~/nameX
# exit
# kvm  -hda /home/dany/nameX.ext2 -kernel <kernel_dir>/arch/x86/boot/bzImage \
-nographic -smp 1 -append " console=ttyS0 earlyprintk=serial  root=/dev/sda rw"
EOF

# Spawn the fakeroot
$FAKEROOT

# Kill the pseudo daemon
$FAKEROOT -S

exit 0

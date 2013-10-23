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

# TODO : 
# 1: Allow sandbox usage of deb PMS
# 2: do_vmdk, do_ext3 ?
# 3: Automate the alias opkg-cl ${OFLAGS}
# 4: Fix INTERCEPT_DIR functionality.
# 5. Fix missing shlibsign in nativesdk (nss).
# 6. Remove host-native path to ensure no host-contamination when
#    All needed items are added to nativesdk.
 
### Set ENV ###
export INTERCEPT_DIR="${OECORE_NATIVE_SYSROOT}/usr/share/opkg/intercept"

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
export FAKEROOT="pseudo"

export PYTHONIOENCODING="UTF-8"

DEVTABLE="${OECORE_NATIVE_SYSROOT}/usr/share/device_table-minimal.txt"
ORIGDIR=$(pwd)
rpmlibdir="/var/lib/rpm"

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

Please customize ${OPKG_CONFFILE} to
your liking before running the sandbox.

Example: 
$0 -r /tmp/rootfs ipk

OPTIONS:
   -r      Rootfs path
   -f      Select custom opkg configuration file
   -d      Use this makedevs devicetable instead of default
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

while getopts "h?r:f:d:p:a:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    r)  export IMAGE_ROOTFS=${OPTARG%/}
        ;;
    f)  export OPKG_CONFFILE=$OPTARG
        ;;
    d)  DEVTABLE=$OPTARG
        ;;
    a)  REPO_URL=${OPTARG%/}
        ;;
    p)  
        if [ "$OPTARG" = "deb" ]; then
	    echo "Only ipk & rpm supported sofar"
	    exit
	elif [ "$OPTARG" = "rpm" ]; then
	    export PMS="rpm"
	    export PMC="smart"
	elif [ "$OPTARG" = "ipk" ]; then
	    export PMS="ipk"
	    export PMC="opkg-cl"
	fi
        ;;    
    esac
done

### BEGIN ENV ###

# Stores PSEUDO fakeroot DB and opkg temp files
export OPKG_TMP_DIR="${IMAGE_ROOTFS}-tmp"
export SCRIPTS="${IMAGE_ROOTFS}-tmp/scripts"

# Use targets "special" update-rc.d + shadow utils + makedevs
export PATH="${SCRIPTS}:${OECORE_NATIVE_SYSROOT}/usr/sbin:${OECORE_TARGET_SYSROOT}/usr/sbin:${PATH}"
export PATH="${OECORE_NATIVE_SYSROOT}/sbin:${PATH}"
#python path
export PATH="${OECORE_NATIVE_SYSROOT}/usr/bin:${PATH}"

export PSEUDO_LOCALSTATEDIR="${IMAGE_ROOTFS}-tmp/var/lib/pseudo"

# Needed for SDKs update-alternatives
export OPKG_OFFLINE_ROOT="${IMAGE_ROOTFS}"
export OPKG_CONFDIR_TARGET="${IMAGE_ROOTFS}/etc/opkg"

# Needed for update-rc.d and many others
export D="${IMAGE_ROOTFS}"

# Old Legacy, to be removed ?
export OFFLINE_ROOT="${IMAGE_ROOTFS}"
export IPKG_OFFLINE_ROOT="${IMAGE_ROOTFS}"

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
    export OFLAGS="--force-postinstall --prefer-arch-to-version -t ${OPKG_TMP_DIR} -f ${OPKG_CONFFILE} -o ${IMAGE_ROOTFS}"    
fi

create_scripts

${FAKEROOT} -d

echo "Installing initial /dev directory"

${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/dev
${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/etc/opkg/arch
${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/etc/rpm
${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/etc/rpm-postinsts
${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/install/tmp

${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/var/lib/opkg
${FAKEROOT} mkdir -p ${OPKG_TMP_DIR}/var/lib/pseudo

if [ "$PMS" = "rpm" ]; then
    
    ${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/etc/rpm/sysinfo
    ${FAKEROOT} echo "/" > ${IMAGE_ROOTFS}/etc/rpm/sysinfo/Dirnames
    ${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/$rpmlibdir
    ${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/$rpmlibdir/log

    # After change the __db.* cache size, log file will not be generated automatically,
    # that will raise some warnings, so touch a bare log for rpm write into it.
    ${FAKEROOT} touch ${IMAGE_ROOTFS}/$rpmlibdir/log/log.0000000001
    if [ ! -e ${IMAGE_ROOTFS}/$rpmlibdir/DB_CONFIG ]; then
        ${FAKEROOT} cat > ${IMAGE_ROOTFS}/$rpmlibdir/DB_CONFIG << EOF
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
    fi	
  # Create database so that smart doesn't complain (lazy init)
  ${FAKEROOT} rpm --root ${IMAGE_ROOTFS} --dbpath $rpmlibdir -qa > /dev/null
  ${FAKEROOT} $PMC ${OFLAGS} config --set rpm-root=${IMAGE_ROOTFS}
  ${FAKEROOT} $PMC ${OFLAGS} config --set rpm-dbpath=$rpmlibdir
  ${FAKEROOT} $PMC ${OFLAGS} config --set rpm-extra-macros._var=/var
  ${FAKEROOT} $PMC ${OFLAGS} config --set rpm-extra-macros._tmppath=/install/tmp
  # Write common configuration for host and target usage
  ${FAKEROOT} $PMC ${OFLAGS} config --set rpm-nolinktos=1
  ${FAKEROOT} $PMC ${OFLAGS} config --set rpm-noparentdirs=1
  ${FAKEROOT} $PMC ${OFLAGS} config --set ignore-all-recommends=1
  ${FAKEROOT} $PMC ${OFLAGS} channel -y --add rpmsys type=rpm-sys name="Local RPM Database"
  ${FAKEROOT} $PMC ${OFLAGS} config --set rpm-extra-macros._cross_scriptlet_wrapper=${SCRIPTS}/scriptlet_wrapper
  ${FAKEROOT} rpm --eval "%{_arch}-%{_vendor}-%{_os}%{?_gnu}" > ${IMAGE_ROOTFS}/etc/rpm/platform
  ${FAKEROOT} echo ".*" >> ${IMAGE_ROOTFS}/etc/rpm/platform
  export RPM_ETCRPM=${IMAGE_ROOTFS}/etc/rpm
fi

command -v makedevs >/dev/null 2>&1 || { echo "Cant find 'makedevs' in PATH. Aborting." >&2; exit 1; }

# Ignore exitcode
set +e
${FAKEROOT} makedevs -r ${IMAGE_ROOTFS} -D $DEVTABLE

cd ${IMAGE_ROOTFS};

set -e
cat << EOF

Welcome to interactive image creation sandbox
You are now "root".
How to Setup repositories (Only needed first time):
--- 
NOTE: Setup your environment first!
alias $PMC='$PMC \${OFLAGS}'
---
EOF
if [ "$PMS" = "rpm" ]; then
    cat << EOF
RPM: smartpm
smart channel -y --add all type=rpm-md baseurl=http://downloads.yoctoproject.org/releases/yocto/yocto-1.4.2/rpm/all
smart channel -y --add x86_64 type=rpm-md baseurl=http://downloads.yoctoproject.org/releases/yocto/yocto-1.4.2/rpm/x86_64
smart channel -y --add qemux86_64 type=rpm-md baseurl=http://downloads.yoctoproject.org/releases/yocto/yocto-1.4.2/rpm/qemux86_64
smart channel -y --set all priority=1
smart channel -y --set x86_64 priority=16
smart channel -y --set qemux86_64 priority=21
smart update
EOF
elif [ "$PMS" = "ipk" ]; then
    cat << EOF
IPK: opkg-cl
echo "src/gz all http://downloads.yoctoproject.org/releases/yocto/yocto-1.4.2/ipk/all" > \
${OPKG_CONFFILE}
echo "src/gz x86_64 http://downloads.yoctoproject.org/releases/yocto/yocto-1.4.2/ipk/x86_64" >> \
${OPKG_CONFFILE}
echo "src/gz qemux86_64 http://downloads.yoctoproject.org/releases/yocto/yocto-1.4.2/ipk/qemux86_64" >> \
${OPKG_CONFFILE}
echo "arch all 1" >> ${OPKG_CONFFILE}
echo "arch any 6" >> ${OPKG_CONFFILE}
echo "arch noarch 11" >> ${OPKG_CONFFILE}
echo "arch x86_64 16" >> ${OPKG_CONFFILE}
echo "arch qemux86_64 21" >> ${OPKG_CONFFILE}
opkg-cl update
EOF
elif [ "$PMS" = "deb" ]; then
cat << EOF
DEB: TBD
EOF
fi

cat << EOF
Example usecases:

1. Install new packages: 
# $PMC install packagegroup-core-boot gcc

2. Install your own stuff:
# cd <source>; make install DESTDIR=\${IMAGE_ROOTFS}

3. When done, create a tarball or ext2 FS
# do_tar.sh ~/my_rootfs
# do_ext2.sh ~/my_rootfs

4. Run with a different kernel
# cd <kernel_dir>
# INSTALL_MOD_PATH=${IMAGE_ROOTFS} make modules_install
# INSTALL_MOD_PATH=${IMAGE_ROOTFS} make firmware_install
# do_ext2.sh ~/nameX
# exit
# kvm  -hda /home/dany/nameX.ext2 -kernel <kernel_dir>/arch/x86/boot/bzImage \
-nographic -smp 1 -append " console=ttyS0 earlyprintk=serial  root=/dev/sda rw"
EOF

# Spawn the fakeroot
${FAKEROOT} /bin/sh

# Install run-postinsts for failing pre/post hooks
${FAKEROOT} $PMC ${OFLAGS} install run-postinsts

# Base time
${FAKEROOT} date "+%m%d%H%M%Y" > ${IMAGE_ROOTFS}/etc/timestamp

# Add OpenDNS
${FAKEROOT} echo "nameserver 208.67.220.220" >> ${IMAGE_ROOTFS}/etc/resolv.conf
${FAKEROOT} echo "nameserver 208.67.222.222" >> ${IMAGE_ROOTFS}/etc/resolv.conf

sync

${FAKEROOT} -S
exit 0

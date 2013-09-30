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
# 1: Allow sandbox usage of rpm and deb PMS
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

DEVTABLE="${OECORE_NATIVE_SYSROOT}/usr/share/device_table-minimal.txt"
ORIGDIR=$(pwd)

export OPKG_CONFFILE="${OECORE_TARGET_SYSROOT}/etc/opkg.conf"

### Define helper functions ###
create_scripts()
{
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

while getopts "h?r:f:d:p:" opt; do
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
    p)  
        if [ "$OPTARG" != "ipk" ]; then
	    echo "Only ipk supported sofar"
	    exit
	else
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

export PSEUDO_LOCALSTATEDIR="${IMAGE_ROOTFS}-tmp/var/lib/pseudo"

# Needed for SDKs update-alternatives
export OPKG_OFFLINE_ROOT="${IMAGE_ROOTFS}"
export OPKG_CONFDIR_TARGET="${IMAGE_ROOTFS}/etc/opkg"
export OFLAGS="--force-postinstall --prefer-arch-to-version -t ${OPKG_TMP_DIR} -f ${OPKG_CONFFILE} -o ${IMAGE_ROOTFS}"

# Needed for update-rc.d and many others
export D="${IMAGE_ROOTFS}"

# Old Legacy, to be removed ?
export OFFLINE_ROOT="${IMAGE_ROOTFS}"
export IPKG_OFFLINE_ROOT="${IMAGE_ROOTFS}"

### END ENV ###
mkdir -p ${SCRIPTS}
create_scripts

${FAKEROOT} -d

echo "Installing initial /dev directory"

${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/dev
${FAKEROOT} mkdir -p ${IMAGE_ROOTFS}/var/lib/opkg
${FAKEROOT} mkdir -p ${OPKG_TMP_DIR}/var/lib/pseudo

command -v makedevs >/dev/null 2>&1 || { echo "Cant find 'makedevs' in PATH. Aborting." >&2; exit 1; }

# Ignore exitcode
set +e
${FAKEROOT} makedevs -r ${IMAGE_ROOTFS} -D $DEVTABLE

cd ${IMAGE_ROOTFS};
${FAKEROOT} $PMC ${OFLAGS} update
${FAKEROOT} $PMC ${OFLAGS} install packagegroup-core-boot
${FAKEROOT} $PMC ${OFLAGS} install opkg opkg-collateral

# Install run-postinsts for failing pre/post hooks
${FAKEROOT} $PMC ${OFLAGS} install run-postinsts
set -e
cat << EOF

 Welcome to interactive image creation sandbox
 You are now "root".

 Already done for your conveniece:
 # $PMC \${OFLAGS} update
 # $PMC \${OFLAGS} install packagegroup-core-boot

 Example usecases:

 0. Setup environment:
 # alias $PMC='$PMC \${OFLAGS}'

 1. Install a new package: 
 # $PMC install gcc

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
${FAKEROOT} /bin/bash

# Base time
${FAKEROOT} date "+%m%d%H%M%Y" > ${IMAGE_ROOTFS}/etc/timestamp

# Add OpenDNS
${FAKEROOT} echo "nameserver 208.67.220.220" >> ${IMAGE_ROOTFS}/etc/resolv.conf
${FAKEROOT} echo "nameserver 208.67.222.222" >> ${IMAGE_ROOTFS}/etc/resolv.conf

sync

${FAKEROOT} -S
exit 0

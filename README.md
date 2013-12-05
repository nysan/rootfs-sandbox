rootfs-sandbox
==============

An Openembedded rootfs-sandbox intended for use with the 
meta-toolchain SDK tarball provided with a OE based distro.

Use PMS to install/remove individual packages, and create an 
image of your choice when done.

Make sure to install package "run-postinsts", this will ensure
that all postinstalls which fail during offline rootfs assembly
will be run at first boot.

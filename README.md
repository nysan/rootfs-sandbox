rootfs-sandbox
==============

An Openembedded rootfs-sandbox intended for use with the 
meta-toolchain SDK tarball provided with a OE based distro.

Use PMS to install/remove individual packages, and create an 
image of your choice when done.

Make sure to install package "run-postinsts", this will ensure
that all postinstalls which fail during offline rootfs assembly
will be run at first boot.

Also, to get the same rate of postinstall successrate as when deploying
the rootfs with bitbake, you need to have the qemuwrapper in your 
target sysroot. i.e. package "qemuwrapper-cross".

Send patches to david.c.nystrom@gmail.com, or get a github account
and ping me to get contributor access.

#!/bin/sh
# Copyright (C) 2024 csdvrx, MIT licensed

# FreeBSD problem with bangpath:
#init 14 - - can't exec /bin/sh for /etc/rc: Exec format error
# If can't use imgact_shell, check if FreeBSD may be like when NetBSD has EXEC_SCRIPT missing
# FreeBSD seems also very precious about osabi: it refuses SYSV binaries?
#ELF binary type "0" not known.

# NetBSD "tolerates" differences, except when it matters:
# init uses a hardcoded list: init,oinit,init.bak
#[   1.0401788] exec /sbin/init: error 8
#[   1.0401788] init: trying /sbin/oinit
#[   1.0401788] exec /sbin/oinit: error 2
#[   1.0401788] init: trying /sbin/init.bak
# but then problems with NetBSD init: sometimes ignores the /etc/rc bangpath and uses /rescue/sh
# Using a different bangpath that the one that's written (!!) can cause problems
# Like when mixing in FreBSD binaries for tests and /rescue/sh won't work while /bin/sh would
# init: can't exec `/rescue/sh' for `/etc/rc': Exec format error
# BTW it was fun learning about bangpath history
#cf https://www.in-ulm.de/~mascheck/various/shebang/

# TODO: just rewrite init in C and call it a day, too many subtle differences, not worth wasting more time!
# use sys/kern/imgact_binmisc.c with MZqFpD= for APEs, or just assimilate init

# For vi
export TERM=xterm
# NetBSD has usr before and bin before sbin, FreeBSD does the opposite, here:
#  - The crunched binaries from /rescue are symlinked to /bin
#  - /usr/bin contains amd64 cosmo binaries
#  - /sbin will have bslinit
export PATH=/usr/bin:/bin:/sbin

# Warn about that
echo "Single user mode: PATH=${PATH}, TERM=${TERM}"

#echo "Probabilistic fsck using the kern.root_device"
# Because I have no idea what I'm doing or which slice should be used!
#for b in /dev/`sysctl -r kern.root_device`* ; do [ -b $b ] && /rescue/fsck_ffs -f -y $b ; done

echo "Doing fsck_ffs on kern.root_device"
/rescue/fsck_ffs -f -y /dev/`sysctl -r kern.root_device`

echo "Mounting all filesystems from /etc/fstab"
mount -a \
 && mount |grep -q /tmp \
 && echo "Deploying dotfiles from / to /tmp" \
 && cp -r /.[a-zA-Z0-9]* /tmp \
 && export HOME=/tmp \
 && echo "Exported HOME=${HOME}" \
# Root may not be rw, so use /tmp

echo "Collecting tslog data by temporarily the rootfs in rw"
# tslog_collect needs /tmp, can specify another file to use
mount -u -o rw / \
 && /tslog_collect.sh

echo "Putting back the rootfs in ro"
mount -u -o ro /

echo "Starting a shell"
[ -e /rescue/ksh ] \
 && echo "Running ksh" \
 && /rescue/ksh \
 || /bin/sh

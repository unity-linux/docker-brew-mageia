#!/usr/bin/env bash
#
# Script to create Mageia official base images for integration with stackbrew 
# library.
#
# Needs to be run from Mageia 6 or greater, as it requires DNF.
#
# Tested working versions are for Mageia 6 onwards (inc. cauldron).
#
# Based on mkimage-urpmi.sh
#

set -e

mkimg="$(basename "$0")"

usage() {
	echo >&2 "usage: $mkimg --rootfs=rootfs_path --version=mageia_version [--mirror=url] [--package-manager=(dnf|microdnf|urpmi)] [--with-systemd]"
	echo >&2 "   ie: $mkimg --rootfs=. --version=6 --with-systemd"
	echo >&2 "       $mkimg --rootfs=. --version=cauldron --package-manager=dnf --with-systemd"
	echo >&2 "       $mkimg --rootfs=/tmp/rootfs --version=6 --mirror=http://mirrors.kernel.org/mageia/distrib/6/x86_64/ --with-systemd"
	echo >&2 "       $mkimg --rootfs=. --version=6 --package-manager=microdnf"
	exit 1
}

optTemp=$(getopt --options '+d,v:,s,p,h' --longoptions 'rootfs:,version:,mirror:,package-manager:,with-systemd, help' --name mkimage-dnf -- "$@")
eval set -- "$optTemp"
unset optTemp

installversion=
mirror=
while true; do
        case "$1" in
                -d|--rootfs) dir=$2 ; shift 2 ;;
                -v|--version) installversion="$2" ; shift 2 ;;
                -m|--mirror) mirror="$2" ; shift 2 ;;
                -p|--package-manager) pkgmgr="$2" ; shift 2 ;;
                -s|--with-systemd) systemd=true ; shift ;;
                -h|--help) usage ;;
                 --) shift ; break ;;
        esac
done

#dir="$1"
rootfsDir="$dir/rootfs"
#shift


#[ "$dir" ] || usage

if [ -z $installversion ]; then
        # Attempt to match host version
        if [ -r /etc/mageia-release ]; then
                installversion="$(sed 's/^[^0-9\]*\([0-9.]\+\).*$/\1/' /etc/mageia-release)"
        else
                echo "Error: no version supplied and unable to detect host mageia version"
                exit 1
        fi
fi

if [ ! -z $mirror ]; then
        # If mirror provided, use it exclusively
        reposetup="--nogpgcheck --disablerepo=* --repofrompath=mgarel,$mirror/media/core/release/ --repofrompath=mgaup,$mirror/media/core/updates/ --enablerepo=mgarel --enablerepo=mgaup"
fi

if [ -z $mirror ]; then
        # If mirror is *not* provided, use mirrorlist
        reposetup="--disablerepo=* --enablerepo=mageia-x86_64 --enablerepo=updates-x86_64"
fi

if [ ! -z $pkgmgr ]; then
        valid_pkg_mgrs="dnf microdnf urpmi"

        [[ $valid_pkg_mgrs =~ (^|[[:space:]])$pkgmgr($|[[:space:]]) ]] && true || echo "Invalid package manager selected." && exit 1

        echo -e "--------------------------------------"
        echo -e "Creating image to use $pkgmgr."
        echo -e "--------------------------------------\n"

fi

# Must be after the non-empty check or otherwise this will fail
if [ -z $pkgmgr ]; then
        pkgmgr="dnf urpmi" 
fi

if [ ! -z $systemd ]; then
        echo -e "--------------------------------------"
        echo -e "Creating image with systemd support."
        echo -e "--------------------------------------\n"
        systemd="systemd" 
fi

(
        dnf \
            $reposetup \
            --installroot="$rootfsDir" \
            --releasever="$installversion" \
            --setopt=install_weak_deps=False \
            --nodocs --assumeyes \
            install basesystem-minimal $pkgmgr locales locales-en $systemd
)

"$(dirname "$BASH_SOURCE")/.febootstrap-minimize" "$rootfsDir"

if [ -d "$rootfsDir/etc/sysconfig" ]; then
        # allow networking init scripts inside the container to work without extra steps
        echo 'NETWORKING=yes' > "$rootfsDir/etc/sysconfig/network"
fi

if [ ! -z $systemd ]; then
	#Prevent systemd from starting unneeded services
	(cd $rootfsDir/lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
        rm -f $rootfsDir/lib/systemd/system/multi-user.target.wants/*;\
        rm -f $rootfsDir/etc/systemd/system/*.wants/*;\
        rm -f $rootfsDir/lib/systemd/system/local-fs.target.wants/*; \
        rm -f $rootfsDir/lib/systemd/system/sockets.target.wants/*udev*; \
        rm -f $rootfsDir/lib/systemd/system/sockets.target.wants/*initctl*; \
        rm -f $rootfsDir/lib/systemd/system/basic.target.wants/*;\
        rm -f $rootfsDir/lib/systemd/system/anaconda.target.wants/*;
fi


# Docker mounts tmpfs at /dev and procfs at /proc so we can remove them
rm -rf "$rootfsDir/dev" "$rootfsDir/proc"
mkdir -p "$rootfsDir/dev" "$rootfsDir/proc"

# make sure /etc/resolv.conf has something useful in it
mkdir -p "$rootfsDir/etc"
cat > "$rootfsDir/etc/resolv.conf" <<'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

rootfsSuffix=

if [ ! -z $pkgmgr ]; then
    rootfsSuffix="-$pkgmgr"
fi

if [ ! -z $systemd ]; then
    rootfsSuffix="$rootfsSuffix-systemd"
fi

tarFile="$dir/rootfs$rootfsSuffix.tar.xz"
    
touch "$tarFile"

(
        set -x
        tar --numeric-owner -caf "$tarFile" -C "$rootfsDir" --transform='s,^./,,' .
)

( set -x; rm -rf "$rootfsDir" )

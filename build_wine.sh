#!/bin/bash

## Script for building Wine (vanilla, staging, esync, pba, proton).
## It use two chroots for compiling (x32 chroot and x64 chroot).
##
## You can change env variables to desired values.
##
## Examples of how to use it:
##
## ./build_wine.sh 4.0-rc3						(build Wine 4.0-rc3)
## ./build_wine.sh 4.0-rc3 exit					(download Wine sources and exit)
## ./build_wine.sh 4.0-rc3 staging				(build Wine 4.0-rc3 with Staging patches)
## ./build_wine.sh 4.0-rc3 esync				(build Wine 4.0-rc3 with ESYNC patches)
## ./build_wine.sh 3.16-6 proton				(build latest Proton and name it 3.16-6)
## ./build_wine.sh 4.0-rc3 esync pba fshack		(build WIne 4.0-rc3 with ESYNC, PBA and FSHACK patches)

export MAINDIR="$HOME"
export SOURCES_DIR="$MAINDIR/sources_dir"
export CHROOT_X64="$MAINDIR/xenial64_chroot"
export CHROOT_X32="$MAINDIR/xenial_chroot"

export C_COMPILER="gcc-8"
export CXX_COMPILER="g++-8"

export CFLAGS_X32="-march=pentium4 -O2"
export CFLAGS_X64="-march=nocona -O2"
export FLAGS_LD="-O2"
export WINE_BUILD_OPTIONS="--without-coreaudio --without-curses --without-gstreamer --without-oss --disable-winemenubuilder --disable-tests --disable-win16"

export ESYNC_VERSION="ce79346"

build_in_chroot () {
	if [ "$1" = "32" ]; then
		CHROOT_PATH="$CHROOT_X32"
	else
		CHROOT_PATH="$CHROOT_X64"
	fi

	echo "Unmount chroot directories. Just in case."
	sudo umount -Rl "$CHROOT_PATH"

	echo "Mount directories for chroot"
	sudo mount --bind "$CHROOT_PATH" "$CHROOT_PATH"
	sudo mount --bind /dev "$CHROOT_PATH/dev"
	sudo mount --bind /dev/shm "$CHROOT_PATH/dev/shm"
	sudo mount --bind /dev/pts "$CHROOT_PATH/dev/pts"
	sudo mount --bind /proc "$CHROOT_PATH/proc"
	sudo mount --bind /sys "$CHROOT_PATH/sys"

	echo "Chrooting into $CHROOT_PATH"
	sudo chroot "$CHROOT_PATH" /usr/bin/env LANG=en_US.UTF-8 TERM=xterm PATH="/bin:/sbin:/usr/bin:/usr/sbin" /opt/build.sh

	echo "Unmount chroot directories"
	sudo umount -Rl "$CHROOT_PATH"
}

create_build_scripts () {
	echo '#!/bin/sh' > $MAINDIR/build32.sh
	echo 'cd /opt' >> $MAINDIR/build32.sh
	echo 'export CC="'${C_COMPILER}'"' >> $MAINDIR/build32.sh
	echo 'export CXX="'${CXX_COMPILER}'"' >> $MAINDIR/build32.sh
	echo 'export CFLAGS="'${CFLAGS_X32}'"' >> $MAINDIR/build32.sh
	echo 'export CXXFLAGS="'${CFLAGS_X32}'"' >> $MAINDIR/build32.sh
	echo 'export LDFLAGS="'${FLAGS_LD}'"' >> $MAINDIR/build32.sh
	echo 'mkdir build-tools && cd build-tools' >> $MAINDIR/build32.sh
	echo '../wine/configure '${WINE_BUILD_OPTIONS}' --prefix /opt/wine32-build' >> $MAINDIR/build32.sh
	echo 'make -j2' >> $MAINDIR/build32.sh
	echo 'make install' >> $MAINDIR/build32.sh
	echo 'export CFLAGS="'${CFLAGS_X64}'"' >> $MAINDIR/build32.sh
	echo 'export CXXFLAGS="'${CFLAGS_X64}'"' >> $MAINDIR/build32.sh
	echo 'cd ..' >> $MAINDIR/build32.sh
	echo 'mkdir build-combo && cd build-combo' >> $MAINDIR/build32.sh
	echo '../wine/configure '${WINE_BUILD_OPTIONS}' --with-wine64=../build64 --with-wine-tools=../build-tools --prefix /opt/wine-build' >> $MAINDIR/build32.sh
	echo 'make -j2' >> $MAINDIR/build32.sh
	echo 'make install' >> $MAINDIR/build32.sh

	echo '#!/bin/sh' > $MAINDIR/build64.sh
	echo 'cd /opt' >> $MAINDIR/build64.sh
	echo 'export CC="'${C_COMPILER}'"' >> $MAINDIR/build64.sh
	echo 'export CXX="'${CXX_COMPILER}'"' >> $MAINDIR/build64.sh
	echo 'export CFLAGS="'${CFLAGS_X64}'"' >> $MAINDIR/build64.sh
	echo 'export CXXFLAGS="'${CFLAGS_X64}'"' >> $MAINDIR/build64.sh
	echo 'export LDFLAGS="'${FLAGS_LD}'"' >> $MAINDIR/build64.sh
	echo 'mkdir build64 && cd build64' >> $MAINDIR/build64.sh
	echo '../wine/configure '${WINE_BUILD_OPTIONS}' --enable-win64 --prefix /opt/wine-build' >> $MAINDIR/build64.sh
	echo 'make -j2' >> $MAINDIR/build64.sh
	echo 'make install' >> $MAINDIR/build64.sh

	chmod +x "$MAINDIR/build64.sh"
	chmod +x "$MAINDIR/build32.sh"

	sudo mv "$MAINDIR/build64.sh" "$CHROOT_X64/opt/build.sh"
	sudo mv "$MAINDIR/build32.sh" "$CHROOT_X32/opt/build.sh"
}

patching_error () {
	clear
	echo "Some patches were not applied correctly. Exiting."
	exit
}

if [ ! "$1" ]; then
	echo "No version specified"
	exit
fi

if [ "$(echo "$1" | cut -c3)" = "0" ]; then
	WINE_SOURCES_VERSION=$(echo "$1" | cut -c1).0
else
	WINE_SOURCES_VERSION=$(echo "$1" | cut -c1).x
fi

rm -rf "$SOURCES_DIR"
mkdir "$SOURCES_DIR"
cd "$SOURCES_DIR" || exit

clear
echo "Downloading sources and patches."
echo "Preparing Wine for compiling."
echo

if [ "$2" = "esync" ]; then
	WINE_VERSION="$1-esync-staging"
	PATCHES_DIR="$SOURCES_DIR/PKGBUILDS/wine-tkg-git/wine-tkg-patches"

	wget https://dl.winehq.org/wine/source/$WINE_SOURCES_VERSION/wine-$1.tar.xz
	wget https://github.com/wine-staging/wine-staging/archive/v$1.tar.gz
	wget https://github.com/zfigura/wine/releases/download/esync$ESYNC_VERSION/esync.tgz
	git clone https://github.com/Tk-Glitch/PKGBUILDS.git
	git clone https://github.com/Firerat/wine-pba.git

	tar xf wine-$1.tar.xz
	tar xf v$1.tar.gz
	tar xf esync.tgz

	mv wine-$1 wine

	cd wine
	patch -Np1 < "$PATCHES_DIR"/use_clock_monotonic.patch || patching_error
	patch -Np1 < "$PATCHES_DIR"/poe-fix.patch || patching_error
	patch -Np1 < "$PATCHES_DIR"/steam.patch || patching_error

	cd ../wine-staging-$1
	patch -Np1 < "$PATCHES_DIR"/CSMT-toggle.patch || patching_error
	cd patches
	./patchinstall.sh DESTDIR=../../wine --all || patching_error


	# Apply fixes for esync patches
	cd ../../esync
	patch -Np1 < "$PATCHES_DIR"/esync-staging-fixes-r3.patch || patching_error
	patch -Np1 < "$PATCHES_DIR"/esync-compat-fixes-r3.patch || patching_error

	# Apply esync patches
	cd ../wine
	for f in ../esync/*.patch; do
		git apply -C1 --verbose < "${f}" || patching_error
	done
	patch -Np1 < "$PATCHES_DIR"/esync-no_alloc_handle.patch || patching_error

	if [ "$3" = "pba" ] || [ "$4" = "pba" ] || [ "$5" = "pba" ]; then
		WINE_VERSION="$WINE_VERSION-pba"

		# Apply pba patches
		for f in $(ls ../wine-pba/patches); do
			patch -Np1 < ../wine-pba/patches/"${f}" || patching_error
		done
	fi

	if [ "$3" = "fshack" ] || [ "$4" = "fshack" ] || [ "$5" = "fshack" ]; then
		WINE_VERSION="$WINE_VERSION-fshack"

		patch -Np1 < "$PATCHES_DIR"/FS_bypass_compositor.patch || patching_error
		patch -Np1 < "$PATCHES_DIR"/valve_proton_fullscreen_hack-staging.patch || patching_error
	fi
elif [ "$2" = "proton" ]; then
	WINE_VERSION="$1-proton"

	git clone https://github.com/ValveSoftware/wine.git
else
	WINE_VERSION="$1"

	wget https://dl.winehq.org/wine/source/$WINE_SOURCES_VERSION/wine-$1.tar.xz

	tar xf wine-$1.tar.xz

	mv wine-$1 wine

	if [ "$2" = "staging" ]; then
		WINE_VERSION="$1-staging"

		wget https://github.com/wine-staging/wine-staging/archive/v$1.tar.gz

		tar xf v$1.tar.gz

		cd wine-staging-$1/patches
		./patchinstall.sh DESTDIR=../../wine --all || patching_error
	fi
fi

if [ "$2" = "exit" ] || [ "$3" = "exit" ] || [ "$4" = "exit" ] || [ "$5" = "exit" ] || [ "$6" = "exit" ]; then
	echo "Force exiting"
	exit
fi

clear; echo "Creating build scripts"
create_build_scripts

clear; echo "Compiling 64-bit Wine"
sudo cp -r "$SOURCES_DIR/wine" "$CHROOT_X64/opt"
build_in_chroot 64

sudo mv "$CHROOT_X64/opt/wine-build" "$CHROOT_X32/opt"
sudo cp -r "$CHROOT_X32/opt/wine-build" "$MAINDIR/wine-$WINE_VERSION-amd64-nomultilib"
sudo mv "$CHROOT_X64/opt/build64" "$CHROOT_X32/opt"

clear; echo "Compiling 32-bit Wine"
sudo mv "$CHROOT_X64/opt/wine" "$CHROOT_X32/opt"
build_in_chroot 32

clear; echo "Compiling is done. Packing Wine."

sudo mv "$CHROOT_X32/opt/wine-build" "$MAINDIR/wine-$WINE_VERSION-amd64"
sudo mv "$CHROOT_X32/opt/wine32-build" "$MAINDIR/wine-$WINE_VERSION-x86"

sudo chown -R $USER:$USER "$MAINDIR/wine-$WINE_VERSION-amd64"
sudo chown -R $USER:$USER "$MAINDIR/wine-$WINE_VERSION-amd64-nomultilib"
sudo chown -R $USER:$USER "$MAINDIR/wine-$WINE_VERSION-x86"

sudo rm -r "$CHROOT_X64/opt"
sudo mkdir "$CHROOT_X64/opt"
sudo rm -r "$CHROOT_X32/opt"
sudo mkdir "$CHROOT_X32/opt"

cd "$MAINDIR/wine-$WINE_VERSION-x86" && rm -r include && rm -r share/applications && rm -r share/man
cd "$MAINDIR/wine-$WINE_VERSION-amd64" && rm -r include && rm -r share/applications && rm -r share/man
cd "$MAINDIR/wine-$WINE_VERSION-amd64-nomultilib" && rm -r include && rm -r share/applications && rm -r share/man && cd bin && ln -sr wine64 wine

cd "$MAINDIR"
tar -cf wine-$WINE_VERSION-amd64.tar wine-$WINE_VERSION-amd64
tar -cf wine-$WINE_VERSION-amd64-nomultilib.tar wine-$WINE_VERSION-amd64-nomultilib
tar -cf wine-$WINE_VERSION-x86.tar wine-$WINE_VERSION-x86
xz -9 wine-$WINE_VERSION-amd64.tar
xz -9 wine-$WINE_VERSION-amd64-nomultilib.tar
xz -9 wine-$WINE_VERSION-x86.tar

rm -r wine-$WINE_VERSION-*

clear; echo "Done."
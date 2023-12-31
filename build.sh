#!/usr/bin/env bash

set -euo pipefail

if [[ ! -v PREFIX ]]; then
	echo "Please set the PREFIX environment variable to where to want to put the built libraries and programs."
	exit 1
fi
if [ ! -d "$PREFIX" ]; then
	echo "Please make sure $PREFIX is a directory."
	exit 1
fi
if [[ ! -v BUILD_DIR ]]; then
	echo "Please set the BUILD_DIR environment variable to where you want to put downloaded archives and source code directories."
	exit 1
fi
if [ ! -d "$BUILD_DIR" ]; then
	echo "Please make sure $BUILD_DIR is a directory."
	exit 1
fi

# XXX: Ugly cross-compile stuff begins here
export CPPFLAGS="-static -I$PREFIX/include"
# set $ARCH for Linux makefile, hack your ISA in. XXX: better way to map this
if [[ -v TARGET ]]; then
	echo "Cross-compiling..."
	CROSS_COMPILE_CONFIGURE="--host=$TARGET"
	case "$TARGET" in
		aarch64*)
			ARCH=arm64
			# XXX: OpenSSL, why can't you do this better (blocking Windows builds)
			CROSS_COMPILE_OPENSSL="linux-aarch64"
			;;
		amd64*|x86_64*)
			CROSS_COMPILE_OPENSSL="linux-x86_64"
			ARCH=x86_64
			;;
		i*86*)
			CROSS_COMPILE_OPENSSL="linux-x86"
			ARCH=x86
			;;
		*)
			echo "Please add your architecture to build.sh"
			exit 1
			;;
	esac
else
	echo "Natively compiling..."
	CROSS_COMPILE_CONFIGURE=""
	CROSS_COMPILE_OPENSSL=""
	case $(uname -m) in
		aarch64)
			ARCH=arm64
			;;
		amd64|x86_64)
			ARCH=x86_64
			;;
		i*86)
			ARCH=x86
			;;
		*)
			echo "Please add your architecture to build.sh"
			exit 1
			;;
	esac
fi
# -mno-outline-atomics is to workaround getauxval issue with musl-gcc on aarch64 (found in curl)
if [ "$ARCH" = "arm64" ]; then
	export CPPFLAGS="$CPPFLAGS -mno-outline-atomics"
fi
export LDFLAGS="--static -L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

download_extract() {
	url="$1"
	dir="$2"
	file="$3"

	cd "$BUILD_DIR"
	if [ ! -f "$file" ]; then
		wget -O "$file" "$url"
	fi
	if [ ! -d "$dir" ]; then
		tar xvf "$file"
	fi
	cd "$dir"
}

clone() {
	url="$1"
	name="$2"
	tag="$3"

	cd "$BUILD_DIR"
	if [ ! -d "$name-$tag" ]; then 
		git clone "$url" "$name-$tag"
	fi
	cd "$name-$tag"
}

configure() {
	./configure --enable-static --disable-shared --prefix="$PREFIX" $CROSS_COMPILE_CONFIGURE "$@"
}

autogen() {
	./autogen.sh --enable-static --disable-shared --prefix="$PREFIX" $CROSS_COMPILE_CONFIGURE "$@"
}

mkdir -p "$PREFIX"
mkdir -p "$BUILD_DIR"

###
### PACKAGES
###

setup_dirs() {
	# only allow one libdir (thanks OpenSSL linux-x86_64 target)
	ln -s lib "$PREFIX/lib64"
}

build_kernel_headers() {
	if [ -f "$PREFIX/kernel_installed" ]; then
		return
	fi
	echo " *** Copying kernel headers ***"
	download_extract "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.5.10.tar.xz" "linux-6.5.10" "linux-6.5.10.tar.xz"
	make clean
	ARCH_VAR=""
	if [[ -v ARCH ]]; then
		ARCH_VAR="ARCH=$ARCH"
	fi
	make headers_install INSTALL_HDR_PATH="$PREFIX" $ARCH_VAR
	touch "$PREFIX/kernel_installed"
}

build_zlib() {
	if [ -f "$PREFIX/zlib_installed" ]; then
		return
	fi
	echo " *** Building zlib ***"
	download_extract "http://zlib.net/zlib-1.3.tar.gz" "zlib-1.3" "zlib-1.3.tar.gz"
	./configure --static --prefix="$PREFIX"
	make clean
	make -j
	make install
	touch "$PREFIX/zlib_installed"
}

build_libzip() {
	if [ -f "$PREFIX/libzip_installed" ]; then
		return
	fi
	echo " *** Building libzip ***"
	download_extract "https://libzip.org/download/libzip-1.10.1.tar.xz" "libzip-1.10.1" "libzip-1.10.1.tar.xz"
	# cmake doesn't like leftovers, purge build dir every time
	rm -rf build || true
	mkdir build
	cd build
	# IPSWs are store iirc, so we can be conservative with enabeld options
	# allocate buffer is due to small default musl stack sizes
	cmake \
		-DBUILD_SHARED_LIBS=OFF \
		-DENABLE_BZIP2=OFF \
		-DENABLE_ZSTD=OFF \
		-DENABLE_LZMA=OFF \
		-DENABLE_OPENSSL=OFF \
		-DENABLE_MBEDTLS=OFF \
		-DBUILD_TOOLS=OFF \
		-DBUILD_EXAMPLES=OFF \
		-DBUILD_DOC=OFF \
		-DBUILD_REGRESS=OFF \
		-DBUILD_OSSFUZZ=OFF \
		-DZIP_ALLOCATE_BUFFER=ON \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_C_FLAGS="$CPPFLAGS" \
		-DCMAKE_BUILD_TYPE:STRING=Release \
		..
	make -j
	make install
	touch "$PREFIX/libzip_installed"
}

build_libusb() {
	if [ -f "$PREFIX/libusb_installed" ]; then
		return
	fi
	echo " *** Building libusb ***"
	download_extract "https://github.com/libusb/libusb/releases/download/v1.0.26/libusb-1.0.26.tar.bz2" "libusb-1.0.26" "libusb-1.0.26.tar.bz2"
	# XXX: revisit udev later
	configure --disable-udev
	make clean
	make -j
	make install
	touch "$PREFIX/libusb_installed"
}

build_openssl() {
	if [ -f "$PREFIX/openssl_installed" ]; then
		return
	fi
	echo " *** Building openssl ***"
	download_extract "https://www.openssl.org/source/openssl-3.0.12.tar.gz" "openssl-3.0.12" "openssl-3.0.12.tar.gz"
	# gross it hardcodes these paths
	./Configure --prefix="$PREFIX" --openssldir=/usr/local/ssl $CROSS_COMPILE_OPENSSL no-zlib no-autoload-config no-shared no-engine no-module no-dso no-tests
	make clean
	make -j build_sw
	make install_sw
	touch "$PREFIX/openssl_installed"
}

build_curl() {
	if [ -f "$PREFIX/curl_installed" ]; then
		return
	fi
	echo " *** Building curl ***"
	download_extract "https://curl.se/download/curl-8.4.0.tar.gz" "curl-8.4.0" "curl-8.4.0.tar.gz"
	configure --with-openssl="$PREFIX" --with-zlib="$PREFIX" \
		--disable-manual --disable-dict --disable-smtp --disable-imap --disable-tftp --disable-ftp --disable-telnet --disable-smb --disable-gopher --disable-ntlm --disable-mqtt --disable-rtsp --disable-pop3
	# make sure bin/curl is static
	make clean
	make -j LDFLAGS="$LDFLAGS -all-static"
	make install
	touch "$PREFIX/curl_installed"
}

build_plist() {
	if [ -f "$PREFIX/plist_installed" ]; then
		return
	fi
	echo " *** Building libplist ***"
	clone "https://github.com/libimobiledevice/libplist/" "libplist" "master"
	autogen --without-tests --without-cython
	make clean
	make -j LDFLAGS="$LDFLAGS -all-static"
	make install
	touch "$PREFIX/plist_installed"
}

build_glue() {
	if [ -f "$PREFIX/glue_installed" ]; then
		return
	fi
	echo " *** Building libimobiledevice-glue ***"
	clone "https://github.com/libimobiledevice/libimobiledevice-glue" "libimobiledevice-glue" "master"
	autogen
	make clean
	make -j LDFLAGS="$LDFLAGS -all-static"
	make install
	touch "$PREFIX/glue_installed"
}

build_libusbmuxd() {
	if [ -f "$PREFIX/libusbmuxd_installed" ]; then
		return
	fi
	echo " *** Building libusbmuxd ***"
	clone "https://github.com/libimobiledevice/libusbmuxd" "libusbmuxd" "master"
	autogen
	make clean
	make -j LDFLAGS="$LDFLAGS -all-static"
	make install
	touch "$PREFIX/libusbmuxd_installed"
}

build_imd() {
	if [ -f "$PREFIX/imd_installed" ]; then
		return
	fi
	echo " *** Building libimobiledevice ***"
	clone "https://github.com/libimobiledevice/libimobiledevice" "libimobiledevice" "master"
	autogen --without-cython --with-openssl
	make clean
	make -j LDFLAGS="$LDFLAGS -all-static"
	make install
	touch "$PREFIX/imd_installed"
}

build_editline() {
	if [ -f "$PREFIX/rl_installed" ]; then
		return
	fi
	echo " *** Building editline ***"
	download_extract "ftp://ftp.troglobit.com/editline/editline-1.17.1.tar.gz" "editline-1.17.1" "editline-1.17.1.tar.gz"
	configure --disable-termcap
	make clean
	make -j LDFLAGS="$LDFLAGS -all-static"
	make install
	# Shim readline
	mkdir -p "$PREFIX/include/readline"
	ln -s "$PREFIX/include/editline.h" "$PREFIX/include/readline/readline.h"
	touch "$PREFIX/include/readline/history.h" # included in readline.h
	ln -s "$PREFIX/lib/libeditline.a" "$PREFIX/lib/libreadline.a"
	touch "$PREFIX/rl_installed"
}

build_libirecovery() {
	if [ -f "$PREFIX/libirecovery_installed" ]; then
		return
	fi
	echo " *** Building libirecovery ***"
	clone "https://github.com/libimobiledevice/libirecovery" "libirecovery" "master"
	# XXX: udev?
	autogen --without-udev
	make clean
	make -j LDFLAGS="$LDFLAGS -all-static"
	make install
	touch "$PREFIX/libirecovery_installed"
}

build_idr() {
	if [ -f "$PREFIX/idr_installed" ]; then
		return
	fi
	echo " *** Building idevicerecovery ***"
	clone "https://github.com/libimobiledevice/idevicerestore" "idevicerestore" "master"
	# no OpenSSL is harmless, it only uses it for SHA impl, falls back to bundled
	autogen --with-openssl
	make clean
	make -j LDFLAGS="$LDFLAGS -all-static"
	make install
	touch "$PREFIX/idr_installed"
}

build_usbmuxd() {
	if [ -f "$PREFIX/usbmuxd_installed" ]; then
		return
	fi
	echo " *** Building usbmuxd ***"
	clone "https://github.com/libimobiledevice/usbmuxd" "usbmuxd" "master"
	# XXX: no systemd support for now
	# XXX: udev is going to be janky...
	autogen --without-systemd --with-udevrulesdir="$PREFIX/udev/rules.d"
	make clean
	make -j LDFLAGS="$LDFLAGS -all-static"
	make install
	touch "$PREFIX/usbmuxd_installed"
}

setup_dirs
build_kernel_headers
build_zlib
build_libzip
build_libusb
build_openssl
build_curl
build_plist
build_glue
build_libusbmuxd
build_imd
build_editline
build_libirecovery
build_idr
build_usbmuxd

echo
echo "Done. Slurp up $PREFIX/bin/idevicerestore and $PREFIX/sbin/usbmuxd for distribution."

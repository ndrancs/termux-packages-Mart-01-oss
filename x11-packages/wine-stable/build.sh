TERMUX_PKG_HOMEPAGE=https://www.winehq.org/
TERMUX_PKG_DESCRIPTION="A compatibility layer for running Windows programs"
TERMUX_PKG_LICENSE="LGPL-2.1"
TERMUX_PKG_LICENSE_FILE="LICENSE, LICENSE.OLD, COPYING.LIB"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="10"
TERMUX_PKG_GIT_BRANCH=main
TERMUX_PKG_REVISION=4
TERMUX_PKG_SRCURL=git+https://github.com/Mart-01-oss/Wine-bionic.git
#TERMUX_PKG_SHA256=c5e0b3f5f7efafb30e9cd4d9c624b85c583171d33549d933cd3402f341ac3601
TERMUX_PKG_DEPENDS="fontconfig, freetype, krb5, libandroid-spawn, libc++, libgmp, libgnutls, libxcb, libxcomposite, libxcursor, libxfixes, libxrender, opengl, pulseaudio, sdl2 | sdl2-compat, vulkan-loader, xorg-xrandr"
TERMUX_PKG_ANTI_BUILD_DEPENDS="sdl2-compat, vulkan-loader"
TERMUX_PKG_BUILD_DEPENDS="libandroid-spawn-static, vulkan-loader-generic"
TERMUX_PKG_NO_STATICSPLIT=true
TERMUX_PKG_HOSTBUILD=true
TERMUX_PKG_EXTRA_HOSTBUILD_CONFIGURE_ARGS="
TERMUX_PKG_SHA256=SKIP_CHECKSUM
--without-x
--disable-tests
--without-freetype
"

TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
enable_wineandroid_drv=no
--prefix=$TERMUX_PREFIX/opt/wine-stable
--exec-prefix=$TERMUX_PREFIX/opt/wine-stable
--libdir=$TERMUX_PREFIX/opt/wine-stable/lib
--with-wine-tools=$TERMUX_PKG_HOSTBUILD_DIR
--enable-nls
--disable-tests
--without-alsa
--without-capi
--without-coreaudio
--without-cups
--without-dbus
--with-fontconfig
--with-freetype
--without-gettext
--with-gettextpo=no
--without-gphoto
--with-gnutls
--without-gstreamer
--without-inotify
--with-krb5
--with-mingw
--without-netapi
--without-opencl
--with-opengl
--without-osmesa
--without-oss
--without-pcap
--with-pthread
--with-pulse
--without-sane
--with-sdl
--without-udev
--without-unwind
--without-usb
--without-v4l2
--with-vulkan
--with-xcomposite
--with-xcursor
--with-xfixes
--without-xinerama
--with-xinput
--with-xinput2
--with-xrandr
--with-xrender
--without-xshape
--without-xshm
--without-xxf86vm
--without-freetype
"

# Enable win64 on 64-bit arches.
if [ "$TERMUX_ARCH_BITS" = 64 ]; then
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" --enable-win64"
fi

# Enable new WoW64 support on x86_64.
if [ "$TERMUX_ARCH" = "aarch64" ]; then
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" --enable-archs=i386,arm64ec,aarch64"
fi

TERMUX_PKG_EXCLUDED_ARCHES="arm"

_setup_llvm_mingw_toolchain() {
    DEPS=/data/data/com.winlator.cmod/files/imagefs/usr ARCH="aarch64" WINARCH="arm64ec,aarch64,i386"

#Put a Termux styled aarch64 prefix inside this folder with all the wine dependencies
export deps=$DEPS

export install_dir=$deps/../opt/wine
    export TOOLCHAIN=$HOME/android-ndk-r27b/toolchains/llvm/prebuilt/linux-x86_64/bin
export LLVM_MINGW_TOOLCHAIN=$HOME/Documenti/SourceCodes/toolchains/llvm-mingw-amd64/bin

export PATH=$LLVM_MINGW_TOOLCHAIN:$PATH

export CC="$TOOLCHAIN/clang --target=$TARGET$API"
export AS=$CC
export CXX="$TOOLCHAIN/clang++ --target=$TARGET$API"
export AR=$TOOLCHAIN/llvm-ar
export LD=$TOOLCHAIN/ld
export RANLIB=$TOOLCHAIN/llvm-ranlib
export STRIP=$TOOLCHAIN/llvm-strip
export DLLTOOL=$LLVM_MINGW_TOOLCHAIN/llvm-dlltool

export PKG_CONFIG_LIBDIR=$deps/lib/pkgconfig:$deps/share/pkgconfig
export ACLOCAL_PATH=$deps/lib/aclocal:$deps/share/aclocal
export CPPFLAGS="-I$deps/include/"
export LDFLAGS="-L$deps/lib -Wl,-rpath=$deps/lib"
export FREETYPE_CFLAGS="-I$deps/include/freetype2"
export PULSE_CFLAGS="-I$deps/include/pulse"
export PULSE_LIBS="-L$deps/lib/pulseaudio -lpulse"
export SDL2_CFLAGS="-I$deps/include/SDL2"
export SDL2_LIBS="-L$deps/lib -lSDL2"
export X_CFLAGS="-I$deps/include"
export X_LIBS="-L$deps/lib -landroid-sysvshm"
export GSTREAMER_CFLAGS="-I$deps/include/gstreamer-1.0 -I$deps/include/glib-2.0 -I$deps/lib/glib-2.0/include -I$deps/glib-2.0/include -I$deps/lib/gstreamer-1.0/include"
export GSTREAMER_LIBS="-L$deps/lib -lgstgl-1.0 -lgstapp-1.0 -lgstvideo-1.0 -lgstaudio-1.0 -lglib-2.0 -lgobject-2.0 -lgio-2.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0"
export FFMPEG_CFLAGS="-I$deps/include/libavutil -I$deps/include/libavcodec -I$deps/include/libavformat"
export FFMPEG_LIBS="-L$deps/lib -lavutil -lavcodec -lavformat"

	# LLVM-mingw's version number must not be the same as the NDK's.
	local _llvm_mingw_version=16
	local _version="20230614"
	local _url="https://github.com/mstorsjo/llvm-mingw/releases/download/$_version/llvm-mingw-$_version-ucrt-ubuntu-20.04-aarch64.tar.xz"
	local _path="$TERMUX_PKG_CACHEDIR/$(basename $_url)"
	
	termux_download $_url $_path
	local _extract_path="$TERMUX_PKG_CACHEDIR/llvm-mingw-toolchain-$_llvm_mingw_version"
	if [ ! -d "$_extract_path" ]; then
		mkdir -p "$_extract_path"-tmp
		tar -C "$_extract_path"-tmp --strip-component=1 -xf "$_path"
		mv "$_extract_path"-tmp "$_extract_path"
	fi
	export PATH="$PATH:$_extract_path/bin"
}

termux_step_host_build() {
	# Setup llvm-mingw toolchain
	_setup_llvm_mingw_toolchain

	# Make host wine-tools
	"$TERMUX_PKG_SRCDIR/configure" ${TERMUX_PKG_EXTRA_HOSTBUILD_CONFIGURE_ARGS}
	make -j "$TERMUX_PKG_MAKE_PROCESSES" __tooldeps__ nls/all
}

termux_step_pre_configure() {
	# Setup llvm-mingw toolchain
	_setup_llvm_mingw_toolchain

	# Fix overoptimization
	CPPFLAGS="${CPPFLAGS/-Oz/}"
	CFLAGS="${CFLAGS/-Oz/}"
	CXXFLAGS="${CXXFLAGS/-Oz/}"

	# Disable hardening
	CPPFLAGS="${CPPFLAGS/-fstack-protector-strong/}"
	CFLAGS="${CFLAGS/-fstack-protector-strong/}"
	CXXFLAGS="${CXXFLAGS/-fstack-protector-strong/}"
	LDFLAGS="${LDFLAGS/-Wl,-z,relro,-z,now/}"

	LDFLAGS+=" -landroid-spawn"

	if [ "$TERMUX_ARCH" = "aarch64" ]; then
		mkdir -p "$TERMUX_PKG_TMPDIR/bin"
		cat <<- EOF > "$TERMUX_PKG_TMPDIR/bin/aarch64-linux-android-clang"
			#!/bin/bash
			set -- "\${@/-mabi=ms/}"
			exec $TERMUX_STANDALONE_TOOLCHAIN/bin/aarch64-linux-android-clang "\$@"
		EOF
		chmod +x "$TERMUX_PKG_TMPDIR/bin/aarch64-linux-android-clang"
		export PATH="$TERMUX_PKG_TMPDIR/bin:$PATH"
	fi
}

termux_step_make_install() {
	make -j $TERMUX_PKG_MAKE_PROCESSES install

	# Create wine-stable script
	mkdir -p $TERMUX_PREFIX/bin
	cat << EOF > $TERMUX_PREFIX/bin/wine-stable
#!$TERMUX_PREFIX/bin/env sh

exec $TERMUX_PREFIX/opt/wine-stable/bin/wine "\$@"

EOF
	chmod +x $TERMUX_PREFIX/bin/wine-stable
}

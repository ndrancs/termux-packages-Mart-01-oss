TERMUX_PKG_HOMEPAGE=https://bladelang.com/
TERMUX_PKG_DESCRIPTION="A simple, fast, clean and dynamic language"
TERMUX_PKG_LICENSE="custom"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="0.0.87"
TERMUX_PKG_SRCURL=https://github.com/blade-lang/blade/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=7a438f126eed74077d6112b89c9d890a8cc0a3affbccde0b023ad43639fed4de
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_BUILD_DEPENDS="libgd, libcurl, openssl"
TERMUX_PKG_HOSTBUILD=true

termux_step_host_build() {
	sed -i '/add_subdirectory(imagine)/d' $TERMUX_PKG_SRCDIR/packages/CMakeLists.txt
	termux_setup_cmake
	cmake $TERMUX_PKG_SRCDIR
	make -j $TERMUX_PKG_MAKE_PROCESSES
	echo "add_subdirectory(imagine)" >> $TERMUX_PKG_SRCDIR/packages/CMakeLists.txt
}

termux_step_pre_configure() {
	# CMake's FindPkgConfig honors pkg-config output. If PKG_CONFIG_SYSROOT_DIR is
	# set in the environment (some CI setups do this for cross builds), pkg-config
	# will prefix absolute include paths with it.
	#
	# Termux .pc files already contain full $TERMUX_PREFIX include/library paths,
	# so a sysroot of $TERMUX_PREFIX would yield duplicated paths like:
	#   $TERMUX_PREFIX$TERMUX_PREFIX/include
	# which breaks CMake configuration (e.g. PkgConfig::LIBGD).
	unset PKG_CONFIG_SYSROOT_DIR

	# Ensure we *always* use a pkg-config that does not apply a sysroot, even if
	# the outer environment re-exports PKG_CONFIG_SYSROOT_DIR later.
	local wrapper_dir="$TERMUX_PKG_BUILDDIR/_wrapper/bin"
	mkdir -p "$wrapper_dir"
	local real_pkg_config
	real_pkg_config="$(command -v pkg-config)"
	# Use single-quoted heredoc delimiter so "$@" is preserved for runtime.
	cat > "$wrapper_dir/pkg-config" <<-'EOF'
		#!/bin/sh
		unset PKG_CONFIG_SYSROOT_DIR
		exec "__REAL_PKG_CONFIG__" "$@"
	EOF
	sed -i "s|__REAL_PKG_CONFIG__|$real_pkg_config|" "$wrapper_dir/pkg-config"
	chmod +x "$wrapper_dir/pkg-config"
	export PKG_CONFIG="$wrapper_dir/pkg-config"
	export PATH="$wrapper_dir:$PATH"

	PATH=$TERMUX_PKG_HOSTBUILD_DIR/blade:$PATH
	export LD_LIBRARY_PATH=$TERMUX_PKG_HOSTBUILD_DIR/blade
}

termux_step_make_install() {
	pushd blade
	install -Dm700 -t $TERMUX_PREFIX/bin blade
	install -Dm600 -t $TERMUX_PREFIX/lib libblade.so
	local sharedir=$TERMUX_PREFIX/share/blade
	mkdir -p $sharedir
	cp -r $TERMUX_PKG_SRCDIR/benchmarks $TERMUX_PKG_BUILDDIR/blade/includes $TERMUX_PKG_SRCDIR/libs $TERMUX_PKG_SRCDIR/tests $sharedir/
	popd
}

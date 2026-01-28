termux_setup_pkg_config_wrapper() {
	local _PKG_CONFIG_LIBDIR=$1
	local _WRAPPER_BIN="${TERMUX_PKG_BUILDDIR}/_wrapper/bin"
	mkdir -p "${_WRAPPER_BIN}"
	if [[ "${TERMUX_ON_DEVICE_BUILD}" == "false" ]]; then
		# Some CI setups export PKG_CONFIG_SYSROOT_DIR for cross builds.
		# Termux .pc files already contain full $TERMUX_PREFIX include/library paths,
		# so applying a sysroot would duplicate prefixes (e.g. $TERMUX_PREFIX$TERMUX_PREFIX/include)
		# and break CMake FindPkgConfig imported targets.
		sed \
			-e "s|^export PKG_CONFIG_DIR=|export PKG_CONFIG_DIR=\nunset PKG_CONFIG_SYSROOT_DIR|" \
			-e "s|^export PKG_CONFIG_LIBDIR=|export PKG_CONFIG_LIBDIR=${_PKG_CONFIG_LIBDIR}:|" \
			"${TERMUX_STANDALONE_TOOLCHAIN}/bin/pkg-config" \
			> "${_WRAPPER_BIN}/pkg-config"
		chmod +x "${_WRAPPER_BIN}/pkg-config"
		export PKG_CONFIG="${_WRAPPER_BIN}/pkg-config"
	fi
	export PATH="${_WRAPPER_BIN}:${PATH}"
}

termux_setup_glib_cross_pkg_config_wrapper() {
	termux_setup_pkg_config_wrapper "${TERMUX_PREFIX}/opt/glib/cross/lib/x86_64-linux-gnu/pkgconfig"
}

termux_setup_wayland_cross_pkg_config_wrapper() {
	termux_setup_pkg_config_wrapper "${TERMUX_PREFIX}/opt/libwayland/cross/lib/x86_64-linux-gnu/pkgconfig"
}

TERMUX_PKG_HOMEPAGE=https://luarocks.org/
TERMUX_PKG_DESCRIPTION="Deployment and management system for Lua modules"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="3.12.2"
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://luarocks.org/releases/luarocks-${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=b0e0c85205841ddd7be485f53d6125766d18a81d226588d2366931e9a1484492
TERMUX_PKG_AUTO_UPDATE=true
__LUA_VERSION=5.1 # Lua version against which it will be built.
# Do not use varible here since buildorder.py do not evaluate bash before reading.
TERMUX_PKG_DEPENDS="curl, lua51"
TERMUX_PKG_BUILD_DEPENDS="liblua51"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

termux_step_configure() {
	if [ "$TERMUX_ON_DEVICE_BUILD" != true ]; then
		# When cross-compiling, luarocks' configure/bootstrap needs a *host*
		# runnable lua interpreter. The lua51 package provides a target binary
		# which can't run on the build host, and /usr/bin/lua5.1 may not exist
		# in CI environments. Build a minimal host Lua 5.1 and temporarily
		# expose it as $PREFIX/bin/lua5.1.
		local _lua_bin="$TERMUX_PREFIX"/bin/lua"$__LUA_VERSION"
		local _lua_bin_bak="${_lua_bin}.bak"
		local _restore_lua=false

		if [ -e "${_lua_bin}" ] && [ ! -L "${_lua_bin}" ]; then
			mv "${_lua_bin}" "${_lua_bin_bak}"
			_restore_lua=true
		fi

		local _hostlua_dir="$TERMUX_PKG_HOSTBUILD_DIR/host-lua-${__LUA_VERSION}"
		local _hostlua_bin="${_hostlua_dir}/src/lua"
		if [ ! -x "${_hostlua_bin}" ]; then
			mkdir -p "$TERMUX_PKG_HOSTBUILD_DIR"
			local _lua_ver=5.1.5
			local _tar="$TERMUX_PKG_HOSTBUILD_DIR/lua-${_lua_ver}.tar.gz"
			local _src="$TERMUX_PKG_HOSTBUILD_DIR/lua-${_lua_ver}"
			if [ ! -f "${_tar}" ]; then
				curl -L --fail -o "${_tar}" "https://www.lua.org/ftp/lua-${_lua_ver}.tar.gz"
			fi
			rm -rf "${_src}" "${_hostlua_dir}"
			tar -C "$TERMUX_PKG_HOSTBUILD_DIR" -xzf "${_tar}"
			mv "${_src}" "${_hostlua_dir}"
			local _hostcc
			_hostcc="$(command -v cc || command -v gcc)"
			make -C "${_hostlua_dir}" linux CC="${_hostcc}"
		fi

		ln -sf "${_hostlua_bin}" "${_lua_bin}"
		export TERMUX_LUAROCKS__RESTORE_LUA="${_restore_lua}"
	fi

	./configure --prefix="$TERMUX_PREFIX" \
		--with-lua="$TERMUX_PREFIX" \
		--lua-version="$__LUA_VERSION" \
		--with-lua-bin="$TERMUX_PREFIX/bin"
}

termux_step_post_make_install() {
	if [ "$TERMUX_ON_DEVICE_BUILD" != "true" ]; then
		local _lua_bin="$TERMUX_PREFIX"/bin/lua"$__LUA_VERSION"
		local _lua_bin_bak="${_lua_bin}.bak"
		# Restore target lua binary if we temporarily moved it away.
		if [ -L "${_lua_bin}" ]; then
			unlink "${_lua_bin}"
		fi
		if [ "${TERMUX_LUAROCKS__RESTORE_LUA:-false}" = true ] && [ -e "${_lua_bin_bak}" ]; then
			mv "${_lua_bin_bak}" "${_lua_bin}"
		fi
	fi
}

termux_step_post_massage() {
	if [ "$TERMUX_ON_DEVICE_BUILD" != true ]; then
		# Remove lua, due to us moving it back and fourth, the build system
		# thinks it is a newly compiled package.
		rm bin/lua"$__LUA_VERSION"
	fi
}

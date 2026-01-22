TERMUX_PKG_HOMEPAGE="https://github.com/hughsie/libxmlb"
TERMUX_PKG_DESCRIPTION="Library to help create and query binary XML blobs"
TERMUX_PKG_LICENSE="LGPL-2.1"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="0.3.24"
TERMUX_PKG_SRCURL=https://github.com/hughsie/libxmlb/releases/download/${TERMUX_PKG_VERSION}/libxmlb-${TERMUX_PKG_VERSION}.tar.xz
TERMUX_PKG_SHA256=ded52667aac942bb1ff4d1e977e8274a9432d99033d86918feb82ade82b8e001
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="glib, liblzma, libstemmer, zstd"

# NOTE: GObject Introspection generally does not work for cross-compiling and
# requires gobject-introspection-1.0 (pkg-config) to be available in the build
# environment. In CI this commonly causes:
#   ERROR: Dependency "gobject-introspection-1.0" not found, tried pkgconfig
#
# We disable introspection to keep the build reproducible.
TERMUX_PKG_DISABLE_GIR=true
TERMUX_PKG_VERSIONED_GIR=false

# Meson sometimes probes for host tools like CMake during configuration.
TERMUX_PKG_BUILD_DEPENDS="glib-cross"

TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-Dgtkdoc=false
-Dintrospection=false
-Dstemmer=true
-Dtests=false
"

termux_step_pre_configure() {
	termux_setup_cmake
}

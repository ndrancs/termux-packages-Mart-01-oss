TERMUX_PKG_HOMEPAGE=https://dianne.skoll.ca/projects/rp-pppoe/
TERMUX_PKG_DESCRIPTION="A PPP-over-Ethernet redirector for pppd"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=4.0
TERMUX_PKG_REVISION=1
# dianne.skoll.ca download.php currently returns an HTML page in CI (not a tarball),
# which makes extraction fail with "gzip: stdin: not in gzip format".
# Use a stable direct mirror URL instead.
TERMUX_PKG_SRCURL=https://downloads.uls.co.za/rp-pppoe/rp-pppoe-${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=41ac34e5db4482f7a558780d3b897bdbb21fae3fef4645d2852c3c0c19d81cea
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--disable-static
"

termux_step_pre_configure() {
	TERMUX_PKG_SRCDIR=$TERMUX_PKG_SRCDIR/src
	TERMUX_PKG_BUILDDIR=$TERMUX_PKG_SRCDIR
}

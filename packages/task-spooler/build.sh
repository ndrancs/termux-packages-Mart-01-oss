TERMUX_PKG_HOMEPAGE=https://vicerveza.homeunix.net/~viric/soft/ts/
TERMUX_PKG_DESCRIPTION="Task spooler is a Unix batch system where the tasks spooled run one after the other"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1:1.0.3
TERMUX_PKG_REVISION=2
# Upstream download host currently has an expired TLS certificate (breaks CI fetch).
# Use Debian's repacked (dfsg) orig tarball which contains the same ts-${TERMUX_PKG_VERSION:2} sources.
TERMUX_PKG_SRCURL=https://deb.debian.org/debian/pool/main/t/task-spooler/task-spooler_${TERMUX_PKG_VERSION:2}+dfsg1.orig.tar.xz
TERMUX_PKG_SHA256=740c676bf5f615596773d3448c4ee7b832401e2764f07581f86aa4e196c3397a
TERMUX_PKG_AUTO_UPDATE=false

termux_step_post_make_install() {
	install -Dm600  \
		$TERMUX_PKG_SRCDIR/ts.1 \
		$TERMUX_PREFIX/share/man/man1/tsp.1
}

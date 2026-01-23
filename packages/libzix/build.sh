TERMUX_PKG_HOMEPAGE=https://drobilla.net/category/zix
TERMUX_PKG_DESCRIPTION="lightweight C99 portability and data structure library"
TERMUX_PKG_LICENSE="BSD"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="0.6.2"
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=(
	# Primary: GitLab archive (more reliable CDN in CI)
	https://gitlab.com/drobilla/zix/-/archive/v${TERMUX_PKG_VERSION}/zix-v${TERMUX_PKG_VERSION}.tar.gz
	# Fallback: upstream hosting
	https://download.drobilla.net/zix-${TERMUX_PKG_VERSION}.tar.xz
)
TERMUX_PKG_SHA256=(
	# sha256 for zix-v0.6.2.tar.gz (GitLab archive)
	caa1435c870767e12f71454e8b17e878fa9b4bb35730b8f570934fb7cb74031c
	# sha256 for zix-0.6.2.tar.xz (drobilla)
	4bc771abf4fcf399ea969a1da6b375f0117784f8fd0e2db356a859f635f616a7
)
TERMUX_PKG_AUTO_UPDATE=true

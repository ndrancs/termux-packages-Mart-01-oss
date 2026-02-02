TERMUX_PKG_HOMEPAGE="https://www.shellcheck.net/"
TERMUX_PKG_DESCRIPTION="Shell script analysis tool"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="Joshua Kahn @TomJo2000"
TERMUX_PKG_VERSION=0.11.0
TERMUX_PKG_SRCURL="https://hackage.haskell.org/package/ShellCheck-${TERMUX_PKG_VERSION}/ShellCheck-${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=81a72e9c195788301f38e4b2e250ab916cf3778993d428786bfb2fac2a847400
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_DEPENDS="libffi, libgmp, libiconv"
TERMUX_PKG_BUILD_DEPENDS="aosp-libs"
TERMUX_PKG_AUTO_UPDATE=true
# i686 is currently unsupported pending;
# https://github.com/termux/ghc-cross-tools/pull/6
TERMUX_PKG_EXCLUDED_ARCHES="i686"

termux_step_pre_configure() {
	chmod u+x ./striptests
	./striptests
}

termux_step_post_configure() {
	cabal get splitmix-0.1.3.1
	mv splitmix{-*,}

	# Patch splitmix for Android: splitmix's cbits-unix/init.c uses getentropy(),
	# which is only available on Android API >= 28.
	cat <<'PATCH' | patch --silent -p1 -d splitmix
	diff --git a/cbits-unix/init.c b/cbits-unix/init.c
	index 255b667..25a6ce7 100644
	--- a/cbits-unix/init.c
	+++ b/cbits-unix/init.c
	@@ -8,6 +8,10 @@
	 
	 uint64_t splitmix_init() {
	 	uint64_t result;
	+#if (!defined(__ANDROID__) || __ANDROID_API__ >= 28)
	 	int r = getentropy(&result, sizeof(uint64_t));
	+#else
	+	int r = -1;
	+#endif
	 	return r == 0 ? result : 0xfeed1000;
	 }
PATCH

	cabal get entropy-0.4.1.11
	mv entropy{-*,}
	sed -i -E 's|(build-type:\s*)Custom|\1Simple|' entropy/entropy.cabal

	cat <<-EOF >>cabal.project.local
		packages: splitmix entropy

		package splitmix
			benchmarks: False
			tests: False

		package entropy
			flags: +donotgetentropy
	EOF

	if [[ "$TERMUX_ON_DEVICE_BUILD" == false ]]; then # We do not need iserv for on device builds.
		termux_setup_ghc_iserv
		cat <<-EOF >>cabal.project.local
			package *
			    ghc-options: -fexternal-interpreter -pgmi=$(command -v termux-ghc-iserv)
		EOF
	fi
}

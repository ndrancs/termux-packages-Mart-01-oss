# shellcheck shell=bash
# This provides an utility function to setup iserv (external interpreter of ghc) to cross-compile haskell-template.
termux_setup_ghc_iserv() {
	local TERMUX_ISERV_BIN="$TERMUX_COMMON_CACHEDIR/iserv-bin-$TERMUX_ARCH"
	local TERMUX_ISERV_BIN_NAME="termux-ghc-iserv"

	termux_setup_proot

	export PATH="$TERMUX_ISERV_BIN:$PATH"

	# Even if the cache dir exists from a previous run, (re)generate the wrapper
	# scripts since their behavior can change over time (notably proot/qemu env).
	mkdir -p "$TERMUX_ISERV_BIN"

	local ghc_bin_dir
	ghc_bin_dir="$(ghc --print-libdir)/../bin"

	cat <<-EOF >"$TERMUX_ISERV_BIN/$TERMUX_ISERV_BIN_NAME"
		#!/bin/bash
		# ghc-iserv binaries shipped with ghc-cross don't necessarily have an rpath
		# for Termux libraries, so ensure the dynamic linker can find deps like
		# libiconv.so.
		termux-proot-run env LD_LIBRARY_PATH="$TERMUX_PREFIX/lib" $ghc_bin_dir/ghc-iserv "\$@"
	EOF

	cat <<-EOF >"$TERMUX_ISERV_BIN/${TERMUX_ISERV_BIN_NAME/iserv/iserv-dyn}"
		#!/bin/bash
		termux-proot-run env LD_LIBRARY_PATH="$TERMUX_PREFIX/lib" $ghc_bin_dir/ghc-iserv-dyn "\$@"
	EOF

	chmod +x "$TERMUX_ISERV_BIN/$TERMUX_ISERV_BIN_NAME"
	chmod +x "$TERMUX_ISERV_BIN/${TERMUX_ISERV_BIN_NAME/iserv/iserv-dyn}"
}

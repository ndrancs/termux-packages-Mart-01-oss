TERMUX_PKG_HOMEPAGE="https://github.com/charliermarsh/ruff"
TERMUX_PKG_DESCRIPTION="An extremely fast Python linter, written in Rust"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="0.13.2"
TERMUX_PKG_SRCURL="https://github.com/charliermarsh/ruff/archive/refs/tags/$TERMUX_PKG_VERSION.tar.gz"
TERMUX_PKG_SHA256=008287603094fd8ddb98bcc7dec91300a7067f1967d6e757758f3da0a83fbb5c
TERMUX_PKG_REVISION=1
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_PYTHON_COMMON_DEPS="maturin"

termux_step_pre_configure() {
	termux_setup_rust

	# maturin/pyo3 needs this to determine the target platform for Android.
	export ANDROID_API_LEVEL=$TERMUX_PKG_API_LEVEL

	rm -rf _lib
	mkdir -p _lib
	cd _lib
	$CC $CPPFLAGS $CFLAGS -fvisibility=hidden \
		-c $TERMUX_PKG_BUILDER_DIR/ctermid.c
	$AR cru libctermid.a ctermid.o

	local env_host="$(printf $CARGO_TARGET_NAME | tr a-z A-Z | sed s/-/_/g)"
	export CARGO_TARGET_${env_host}_RUSTFLAGS+=" -C link-arg=$TERMUX_PKG_BUILDDIR/_lib/libctermid.a"
}

termux_step_make() {
	# --skip-auditwheel workaround for Maturin error
	# 'Cannot repair wheel, because required library libdl.so could not be located.'
	# found here in Termux-specific upstream discussion: https://github.com/PyO3/pyo3/issues/2324
	maturin build --locked --skip-auditwheel --release --all-features --target "$CARGO_TARGET_NAME" --strip
}

termux_step_make_install() {
	install -Dm755 -t "$TERMUX_PREFIX/bin" "target/$CARGO_TARGET_NAME/release/ruff"

	# maturin's wheel tags have changed over time. Recent releases produce Android-tagged
	# wheels (e.g. android_24_arm64_v8a), but we install using host pip during packaging.
	# Keep the previous approach of renaming the wheel to a linux_* tag so pip accepts it.
	local _pip_arch="$TERMUX_ARCH"
	if [[ "${TERMUX_ARCH}" == "arm" ]]; then
		# pip in our build environment rejects linux_armv7l, but accepts linux_arm
		_pip_arch="arm"
	fi

	shopt -s nullglob
	local _wheels=("target/wheels/ruff-$TERMUX_PKG_VERSION-"*.whl)
	shopt -u nullglob
	if (( ${#_wheels[@]} == 0 )); then
		termux_error_exit "No built wheel found in target/wheels for ruff $TERMUX_PKG_VERSION"
	fi
	if (( ${#_wheels[@]} > 1 )); then
		termux_error_exit "Multiple wheels found for ruff $TERMUX_PKG_VERSION: ${_wheels[*]}"
	fi

	local _dest_whl="target/wheels/ruff-$TERMUX_PKG_VERSION-py3-none-linux_${_pip_arch}.whl"
	if [[ "${_wheels[0]}" != "$_dest_whl" ]]; then
		mv -f "${_wheels[0]}" "$_dest_whl"
	fi

	pip install --no-deps --prefix=$TERMUX_PREFIX --force-reinstall "$_dest_whl"
}

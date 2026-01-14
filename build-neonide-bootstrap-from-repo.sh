#!/usr/bin/env bash
set -euo pipefail

# Build a Termux bootstrap zip for a forked app package name WITHOUT compiling packages.
#
# This script runs fully inside the Termux package-builder docker container (scripts/run-docker.sh)
# so it works on hosts without the required tooling and matches the environment expected by
# termux-packages scripts.
#
# It does:
# 1) Run scripts/generate-bootstraps.sh to download needed .deb files from a repository
#    and assemble a bootstrap zip.
# 2) Patch the produced bootstrap zip to use the requested Android applicationId/package name.

APP_PACKAGE="com.neonide.studio"
ARCH="aarch64"
ANDROID10=1
PACKAGE_LIST_FILE_DEFAULT="scripts/neonide-bootstrap-packages.txt"
PACKAGE_LIST_FILE="$PACKAGE_LIST_FILE_DEFAULT"
REPO_URL=""  # optional: override APT repo base url
KEEP_TMP=0

# Default Termux APT repo used by scripts/generate-bootstraps.sh.
DEFAULT_REPO_URL="https://packages-cf.termux.dev/apt/termux-main"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --app-package <pkg>     Android applicationId/package name to patch into bootstrap.
                          Default: ${APP_PACKAGE}
  --arch <arch>           Architecture to build. Default: ${ARCH}
  --no-android10          Build legacy (Android <10) bootstrap.
  --packages-file <path>  Newline-separated list of packages to include (passed via --add).
                          Default: ${PACKAGE_LIST_FILE_DEFAULT}
  --repo <url>            Override repository base url used by generate-bootstraps.sh.
                          Default: ${DEFAULT_REPO_URL}
  --keep-tmp              Do not delete temporary working dir (inside docker container).
  -h, --help              Show this help.

Notes:
  - scripts/generate-bootstraps.sh always includes the minimal core set.
  - Your package list is added on top via --add, and dependencies are downloaded automatically.
  - This script runs in docker via ./scripts/run-docker.sh.

Example:
  $0 --app-package com.neonide.studio --arch aarch64
  $0 --repo https://packages-cf.termux.dev/apt/termux-main --arch aarch64
EOF
}

while (($# > 0)); do
  case "$1" in
    --app-package) APP_PACKAGE="${2:?}"; shift 2;;
    --arch) ARCH="${2:?}"; shift 2;;
    --no-android10) ANDROID10=0; shift 1;;
    --packages-file) PACKAGE_LIST_FILE="${2:?}"; shift 2;;
    --repo) REPO_URL="${2:?}"; shift 2;;
    --keep-tmp) KEEP_TMP=1; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

if [[ ! -x "$REPO_ROOT/scripts/run-docker.sh" ]]; then
  echo "ERROR: scripts/run-docker.sh not found or not executable. Are you in termux-packages repo root?" >&2
  exit 1
fi

# Resolve packages file relative to repo root for passing into container.
if [[ "$PACKAGE_LIST_FILE" != /* ]]; then
  PACKAGE_LIST_FILE="$REPO_ROOT/$PACKAGE_LIST_FILE"
fi

if [[ ! -f "$PACKAGE_LIST_FILE" ]]; then
  echo "ERROR: packages file not found: $PACKAGE_LIST_FILE" >&2
  exit 1
fi

# Prefer a repo-relative path so it maps cleanly into the container mount.
# If realpath --relative-to is unavailable, fall back to stripping REPO_ROOT prefix.
if PACKAGE_LIST_FILE_REL="$(realpath --relative-to "$REPO_ROOT" "$PACKAGE_LIST_FILE" 2>/dev/null)"; then
  :
else
  PACKAGE_LIST_FILE_REL="${PACKAGE_LIST_FILE#"$REPO_ROOT/"}"
fi

if [[ -z "$REPO_URL" ]]; then
  REPO_URL="$DEFAULT_REPO_URL"
fi

echo "[*] Running bootstrap generation inside docker container"
echo "[*] App package: $APP_PACKAGE"
echo "[*] Arch: $ARCH"
echo "[*] Android10: $ANDROID10"
echo "[*] Packages file: $PACKAGE_LIST_FILE_REL"
echo "[*] Repo: $REPO_URL"

# Everything below runs inside the docker container. The repository is mounted at:
#   /home/builder/termux-packages
# See scripts/run-docker.sh.

"$REPO_ROOT/scripts/run-docker.sh" env \
  APP_PACKAGE="$APP_PACKAGE" \
  ARCH="$ARCH" \
  ANDROID10="$ANDROID10" \
  PACKAGE_LIST_FILE="$PACKAGE_LIST_FILE_REL" \
  REPO_URL="$REPO_URL" \
  KEEP_TMP="$KEEP_TMP" \
  bash -lc '
set -euo pipefail

REPO_ROOT="$HOME/termux-packages"
cd "$REPO_ROOT"

PACKAGE_LIST_FILE_PATH="$PACKAGE_LIST_FILE"
if [[ "$PACKAGE_LIST_FILE_PATH" != /* ]]; then
  PACKAGE_LIST_FILE_PATH="$REPO_ROOT/$PACKAGE_LIST_FILE_PATH"
fi

if [[ ! -f "$PACKAGE_LIST_FILE_PATH" ]]; then
  echo "ERROR: packages file not found in container: $PACKAGE_LIST_FILE_PATH" >&2
  exit 1
fi

# Turn newline list into comma-separated list for --add.
# Also strip empty lines and comments.
PKGS_CSV="$(grep -vE "^[[:space:]]*(#|$)" "$PACKAGE_LIST_FILE_PATH" | tr "\n" "," | sed "s/,$//")"

if [[ -z "$PKGS_CSV" ]]; then
  echo "ERROR: package list is empty: $PACKAGE_LIST_FILE_PATH" >&2
  exit 1
fi

tmpdir="$(mktemp -d -t neonide-bootstrap.XXXXXX)"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "[*] KEEP_TMP=1: temp dir preserved at (inside container): $tmpdir"
    return 0
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

pushd "$tmpdir" >/dev/null

# Quick repo sanity check: ensure all requested packages exist in the Packages index.
# This avoids huge downloads before failing on a missing package.
index_url="$REPO_URL/dists/stable/main/binary-${ARCH}/Packages"
index_file="$tmpdir/Packages.${ARCH}"

echo "[*] Checking repository package list: $index_url"
if ! curl --fail --location --output "$index_file" "$index_url"; then
  echo "ERROR: failed to fetch Packages index from: $index_url" >&2
  echo "If you are using a custom repo, pass it via --repo <url>." >&2
  exit 1
fi

missing=()
while IFS= read -r pkg; do
  [[ -z "$pkg" ]] && continue
  if ! grep -q "^Package: ${pkg}$" "$index_file"; then
    missing+=("$pkg")
  fi
done < <(grep -vE "^[[:space:]]*(#|$)" "$PACKAGE_LIST_FILE_PATH")

if (( ${#missing[@]} > 0 )); then
  echo "ERROR: the following packages are NOT present in repo '$REPO_URL' for arch '$ARCH':" >&2
  printf "  - %s\n" "${missing[@]}" >&2
  echo >&2
  echo "You likely need to publish these packages to a custom APT repo and pass it via --repo." >&2
  exit 1
fi

args=(--architectures "$ARCH" --pm apt --add "$PKGS_CSV" --repository "$REPO_URL")
if [[ "$ANDROID10" == "1" ]]; then
  args+=(--android10)
fi

echo "[*] Generating bootstrap zip by downloading packages (no compilation)..."
"$REPO_ROOT/scripts/generate-bootstraps.sh" "${args[@]}"

ZIP_IN="bootstrap-${ARCH}.zip"
if [[ ! -f "$ZIP_IN" ]]; then
  echo "ERROR: expected output not found: $ZIP_IN" >&2
  ls -la
  exit 1
fi

work="$tmpdir/unzipped"
mkdir -p "$work"
unzip -q "$ZIP_IN" -d "$work"

# Patch common places that hardcode /data/data/<pkg>/...
# Keep this conservative: only replace com.termux -> requested package.
find "$work" -type f -print0 \
  | xargs -0 -r grep -Il "com.termux" \
  | while read -r f; do
      sed -i "s/com\\.termux/${APP_PACKAGE//\//\\/}/g" "$f"
    done

# Repack to repo root (mounted to host)
ZIP_OUT="$REPO_ROOT/bootstrap-${ARCH}.zip"
rm -f "$ZIP_OUT"
(
  cd "$work"
  zip -qr9 "$ZIP_OUT" .
)

popd >/dev/null

echo "[*] Done: $ZIP_OUT"
'

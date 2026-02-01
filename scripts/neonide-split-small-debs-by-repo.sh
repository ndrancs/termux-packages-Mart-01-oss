#!/usr/bin/env bash
set -euo pipefail

# Split prebuilt small .deb files between two GitHub Pages-backed APT repos:
# - Primary: Mart-01-oss/pages (https://mart-01-oss.github.io/pages/)
# - Secondary: Mart-01-oss/apt-repo (https://mart-01-oss.github.io/apt-repo/)
#
# Goal:
# - Avoid duplicate *package names* across repos.
# - If a package already exists in one repo, publish updates to the same repo.
# - If a package is new (exists in neither), publish it to the primary repo unless
#   the primary repo size is at/over the configured limit, in which case publish
#   it to the secondary repo.
#
# Inputs (env vars):
#   DEBS_DIR                (required) directory containing *.deb
#   PAGES_REPO_DIR          (required) checked-out repo directory
#   APT_REPO_DIR            (required) checked-out repo directory
#   APT_DIST                (default: stable)
#   APT_COMPONENT           (default: main)
#   APT_ARCH                (default: aarch64)
#   OUT_PAGES_DIR           (default: ./small-debs-pages)
#   OUT_APT_REPO_DIR        (default: ./small-debs-apt-repo)
#   PAGES_SIZE_LIMIT_GB     (default: 5)

: "${DEBS_DIR:?DEBS_DIR is required}"
: "${PAGES_REPO_DIR:?PAGES_REPO_DIR is required}"
: "${APT_REPO_DIR:?APT_REPO_DIR is required}"

: "${APT_DIST:=stable}"
: "${APT_COMPONENT:=main}"
: "${APT_ARCH:=aarch64}"
: "${OUT_PAGES_DIR:=small-debs-pages}"
: "${OUT_APT_REPO_DIR:=small-debs-apt-repo}"
: "${PAGES_SIZE_LIMIT_GB:=5}"

pages_pkgs_file="$PAGES_REPO_DIR/dists/${APT_DIST}/${APT_COMPONENT}/binary-${APT_ARCH}/Packages"
aptrepo_pkgs_file="$APT_REPO_DIR/dists/${APT_DIST}/${APT_COMPONENT}/binary-${APT_ARCH}/Packages"

mkdir -p "$OUT_PAGES_DIR" "$OUT_APT_REPO_DIR"

# Clear output dirs (keep dirs themselves)
find "$OUT_PAGES_DIR" -type f -delete 2>/dev/null || true
find "$OUT_APT_REPO_DIR" -type f -delete 2>/dev/null || true

# Determine whether primary repo is over limit
limit_bytes=$((PAGES_SIZE_LIMIT_GB * 1024 * 1024 * 1024))
# du -sb is GNU; fallback to du -sk
pages_bytes=$(du -sb "$PAGES_REPO_DIR" 2>/dev/null | awk '{print $1}' || true)
if [[ -z "${pages_bytes}" ]]; then
  pages_bytes=$(( $(du -sk "$PAGES_REPO_DIR" | awk '{print $1}') * 1024 ))
fi
pages_over_limit=false
if [[ "$pages_bytes" -ge "$limit_bytes" ]]; then
  pages_over_limit=true
fi

echo "[*] Primary repo size: ${pages_bytes} bytes (limit=${limit_bytes} bytes, over_limit=${pages_over_limit})"

declare -A IN_PAGES=()
declare -A IN_APTREPO=()

load_pkgs() {
  local f="$1"
  local -n dest="$2"
  [[ -f "$f" ]] || return 0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    dest["$p"]=1
  done < <(grep -E '^Package: ' "$f" | sed -E 's/^Package: //' | sort -u)
}

load_pkgs "$pages_pkgs_file" IN_PAGES
load_pkgs "$aptrepo_pkgs_file" IN_APTREPO

echo "[*] Known packages: pages=${#IN_PAGES[@]} apt-repo=${#IN_APTREPO[@]}"

count_pages=0
count_apt=0
count_total=0

shopt -s nullglob
for deb in "$DEBS_DIR"/*.deb; do
  count_total=$((count_total+1))
  pkg=""
  if command -v dpkg-deb >/dev/null 2>&1; then
    pkg="$(dpkg-deb -f "$deb" Package 2>/dev/null || true)"
  fi
  if [[ -z "$pkg" ]]; then
    pkg="$(basename "$deb" | sed -E 's/^([^_]+)_.*/\1/')"
  fi

  dest=""
  if [[ -n "${IN_PAGES[$pkg]:-}" ]]; then
    dest="pages"
  elif [[ -n "${IN_APTREPO[$pkg]:-}" ]]; then
    dest="apt"
  else
    if [[ "$pages_over_limit" == "true" ]]; then
      dest="apt"
    else
      dest="pages"
    fi
  fi

  case "$dest" in
    pages)
      cp -f "$deb" "$OUT_PAGES_DIR/"
      count_pages=$((count_pages+1))
      ;;
    apt)
      cp -f "$deb" "$OUT_APT_REPO_DIR/"
      count_apt=$((count_apt+1))
      ;;
    *)
      echo "ERROR: Unknown dest '$dest' for $deb" >&2
      exit 1
      ;;
  esac

done
shopt -u nullglob

echo "[*] Split complete: total=$count_total -> pages=$count_pages apt-repo=$count_apt"
ls -lah "$OUT_PAGES_DIR" || true
ls -lah "$OUT_APT_REPO_DIR" || true

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check-srcurls.sh [--scope all|changed] [--jobs N] [--include-disabled] [--output-dir DIR] [--fail]

Collect TERMUX_PKG_SRCURL values from package build.sh files and check whether
those URLs are reachable.

Outputs (written under --output-dir):
  - report.tsv
  - report.md
  - summary.md
  - failures.tsv
  - run.log (if the caller tees stdout)

Notes:
  - build.sh files are *sourced* in a minimal bash environment to expand variables
    like ${TERMUX_PKG_VERSION}.
  - Only http(s) URLs are actively checked. Other schemes are marked as SKIP.
  - By default the script exits 0 even if failures are found. Pass --fail to
    exit non-zero when failures are detected.
EOF
}

SCOPE="all"
JOBS=8
INCLUDE_DISABLED=false
OUTPUT_DIR="artifacts/url-check"
FAIL_ON_ISSUES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="${2:-}"; shift 2 ;;
    --jobs)
      JOBS="${2:-}"; shift 2 ;;
    --include-disabled)
      INCLUDE_DISABLED=true; shift 1 ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"; shift 2 ;;
    --fail)
      FAIL_ON_ISSUES=true; shift 1 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$SCOPE" =~ ^(all|changed)$ ]]; then
  echo "Invalid --scope: $SCOPE" >&2
  exit 2
fi

if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
  echo "Invalid --jobs: $JOBS" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"

# Termux/Android environments sometimes restrict /tmp.
TMPBASE="${TMPDIR:-$PWD/.tmp}"
mkdir -p "$TMPBASE"
TASKS_FILE="$TMPBASE/url-check-tasks.tsv"

REPORT_TSV="$OUTPUT_DIR/report.tsv"
REPORT_MD="$OUTPUT_DIR/report.md"
FAILURES_TSV="$OUTPUT_DIR/failures.tsv"
SUMMARY_MD="$OUTPUT_DIR/summary.md"

: > "$TASKS_FILE"

repo_dirs=(packages x11-packages root-packages)
if $INCLUDE_DISABLED; then
  repo_dirs+=(disabled-packages)
fi

get_changed_build_sh() {
  # Determine base/head from GitHub event JSON when available.
  local base="" head="HEAD"

  if [[ -n "${GITHUB_EVENT_PATH:-}" ]] && command -v jq >/dev/null 2>&1; then
    base=$(jq -r '.pull_request.base.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
    if [[ -z "$base" ]]; then
      base=$(jq -r '.before // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
    fi
    head=$(jq -r '.after // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
    [[ -z "$head" ]] && head="HEAD"
  fi

  if [[ -z "$base" ]] && [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    git fetch --no-tags --depth=1 origin "$GITHUB_BASE_REF" >/dev/null 2>&1 || true
    base="origin/$GITHUB_BASE_REF"
  fi

  [[ -z "$base" ]] && return 1

  git diff --name-only "$base".."${head:-HEAD}" \
    | grep -E '^(packages|x11-packages|root-packages|disabled-packages)/[^/]+/build\.sh$' || true
}

build_sh_list=()

if [[ "$SCOPE" == "changed" ]]; then
  mapfile -t changed < <(get_changed_build_sh || true)
  if [[ ${#changed[@]} -eq 0 ]]; then
    echo "No changed build.sh detected (or unable to compute base). Falling back to --scope all." >&2
    SCOPE="all"
  else
    for f in "${changed[@]}"; do
      if [[ "$f" == disabled-packages/* ]] && ! $INCLUDE_DISABLED; then
        continue
      fi
      build_sh_list+=("$f")
    done
  fi
fi

if [[ "$SCOPE" == "all" ]]; then
  for d in "${repo_dirs[@]}"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r -d '' f; do
      build_sh_list+=("${f#./}")
    done < <(find "$d" -mindepth 2 -maxdepth 2 -type f -name build.sh -print0)
  done
fi

collect_urls_for_build_sh() {
  local build_sh="$1"

  local pkg_dir repo_path pkg_name
  pkg_dir=$(dirname "$build_sh")
  repo_path=$(dirname "$pkg_dir")
  pkg_name=$(basename "$pkg_dir")

  # First try evaluating TERMUX_PKG_SRCURL by sourcing build.sh.
  # If that fails (some build.sh rely on external functions/commands),
  # fall back to a conservative static parser that extracts literal URL strings.
  local urls ec
  set +e
  urls=$(bash -c '
    set -e
    set +u
    cd "$1"
    source ./build.sh >/dev/null 2>&1 || source ./build.sh

    if ! declare -p TERMUX_PKG_SRCURL >/dev/null 2>&1; then
      exit 3
    fi

    if declare -p TERMUX_PKG_SRCURL 2>/dev/null | grep -q "declare -a"; then
      for u in "${TERMUX_PKG_SRCURL[@]}"; do
        echo "$u"
      done
    else
      read -r -a _arr <<< "${TERMUX_PKG_SRCURL}"
      for u in "${_arr[@]}"; do
        echo "$u"
      done
    fi
  ' bash "$pkg_dir" 2>/dev/null)
  ec=$?
  set -e

  if [[ $ec -ne 0 ]] || [[ -z "${urls:-}" ]]; then
    # Static parse fallback: extract http(s)://... from TERMUX_PKG_SRCURL assignments.
    # This won't expand variables, but it avoids marking a lot of packages as EVAL_FAIL.
    urls=$(grep -E '^(TERMUX_PKG_SRCURL|TERMUX_PKG_SRCURL\+)=|^TERMUX_PKG_SRCURL=\(|^TERMUX_PKG_SRCURL=\(' -n "$build_sh" \
      | cat >/dev/null; true)

    # Just extract literal URLs from the file content.
    # Use a stricter regex so we don't capture truncated fragments like "https://gi".
    # Require at least one dot in the hostname and at least 8 chars after scheme.
    urls=$(grep -Eo 'https?://[^"\x27 \t\n)]+' "$build_sh" \
      | awk 'length($0) >= 16 && $0 ~ /^https?:\/\/[^\/]+\.[^\/]+\// {print}' \
      | sort -u || true)

    if [[ -z "${urls:-}" ]]; then
      # Many packages intentionally don't have sources (repo metapackages, on-device helpers, etc.).
      # If build.sh declares it doesn't need source extraction, treat it as a skip.
      if grep -q '^TERMUX_PKG_SKIP_SRC_EXTRACT=true' "$build_sh" \
        || grep -q '^TERMUX_PKG_METAPACKAGE=true' "$build_sh" \
        || grep -q '^TERMUX_PKG_PLATFORM_INDEPENDENT=true' "$build_sh"; then
        printf '%s\t%s\t%s\n' "$repo_path" "$pkg_name" "SKIP_NO_SOURCE" >> "$TASKS_FILE"
        return 0
      fi
      printf '%s\t%s\t%s\n' "$repo_path" "$pkg_name" "PARSE_FAIL(build.sh)" >> "$TASKS_FILE"
      return 0
    fi
  fi

  while IFS= read -r u; do
    [[ -z "$u" ]] && continue
    printf '%s\t%s\t%s\n' "$repo_path" "$pkg_name" "$u" >> "$TASKS_FILE"
  done <<< "$urls"
}

for build_sh in "${build_sh_list[@]}"; do
  collect_urls_for_build_sh "$build_sh"
done

# Prepare report header
printf 'repo\tpkg\turl\tresult\thttp_code\tcurl_exit\n' > "$REPORT_TSV"

check_one_url() {
  local repo="$1" pkg="$2" url="$3"

  if [[ "$url" == EVAL_FAIL* ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$pkg" "$url" "EVAL_FAIL" "" ""
    return 0
  fi

  if [[ "$url" == PARSE_FAIL* ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$pkg" "$url" "PARSE_FAIL" "" ""
    return 0
  fi

  if [[ "$url" == SKIP_NO_SOURCE ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$pkg" "$url" "SKIP_NO_SOURCE" "" ""
    return 0
  fi

  if [[ ! "$url" =~ ^https?:// ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$pkg" "$url" "SKIP_UNSUPPORTED_SCHEME" "" ""
    return 0
  fi

  local ua="termux-packages-srcurl-checker/1.0 (+https://github.com/termux/termux-packages)"

  # We try multiple strategies because some servers:
  # - reject Range requests (400/415/etc)
  # - reject HEAD requests
  # - are flaky / slow (timeouts)
  local http_code curl_exit result

  _classify() {
    local code="$1" exit_code="$2"
    if [[ "$exit_code" -ne 0 ]]; then
      echo "CURL_ERROR"; return 0
    fi
    case "$code" in
      2*|3*) echo "OK";;
      404) echo "HTTP_404";;
      410) echo "HTTP_410";;
      5*) echo "HTTP_5XX";;
      ""|000) echo "NO_HTTP_CODE";;
      *) echo "HTTP_${code}";;
    esac
  }

  # Attempt 1: HEAD (fast, no body)
  set +e
  http_code=$(curl -I -L -o /dev/null -sS -w '%{http_code}' \
    -A "$ua" --connect-timeout 7 --max-time 25 --retry 2 --retry-all-errors --retry-delay 1 \
    "$url")
  curl_exit=$?
  set -e
  result=$(_classify "$http_code" "$curl_exit")

  # Attempt 2: Range GET (many servers return 206)
  if [[ "$result" != "OK" ]]; then
    set +e
    http_code=$(curl -L -r 0-0 -o /dev/null -sS -w '%{http_code}' \
      -A "$ua" --connect-timeout 7 --max-time 25 --retry 2 --retry-all-errors --retry-delay 1 \
      "$url")
    curl_exit=$?
    set -e
    result=$(_classify "$http_code" "$curl_exit")
  fi

  # Attempt 3: GET only the first 1MiB (covers servers that reject Range 0-0, and avoids curl exit=63 from --max-filesize)
  if [[ "$result" != "OK" ]]; then
    set +e
    http_code=$(curl -L --range 0-1048575 -o /dev/null -sS -w '%{http_code}' \
      -A "$ua" --connect-timeout 7 --max-time 35 --retry 2 --retry-all-errors --retry-delay 1 \
      "$url")
    curl_exit=$?
    set -e
    result=$(_classify "$http_code" "$curl_exit")
  fi

  # Normalize http_code for curl errors.
  if [[ "$result" == "CURL_ERROR" ]]; then
    http_code=""
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$pkg" "$url" "$result" "$http_code" "$curl_exit"
}
export -f check_one_url

# Run checks with limited parallelism.
# Use NUL delimiters to avoid any shell parsing issues (e.g. parentheses).
while IFS=$'\t' read -r repo pkg url; do
  printf '%s\0%s\0%s\0' "$repo" "$pkg" "$url"
done < "$TASKS_FILE" \
  | xargs -0 -P "$JOBS" -n 3 bash -c 'check_one_url "$1" "$2" "$3"' bash \
  >> "$REPORT_TSV"

# Produce failures list.
awk -F'\t' 'NR==1{next} $4!="OK" && $4!="SKIP_UNSUPPORTED_SCHEME" && $4!="SKIP_NO_SOURCE" {print}' "$REPORT_TSV" > "$FAILURES_TSV" || true

ok_count=$(awk -F'\t' 'NR>1 && $4=="OK"{c++} END{print c+0}' "$REPORT_TSV")
fail_count=$(awk -F'\t' 'NR>1 && $4!="OK" && $4!="SKIP_UNSUPPORTED_SCHEME" && $4!="SKIP_NO_SOURCE"{c++} END{print c+0}' "$REPORT_TSV")
skip_count=$(awk -F'\t' 'NR>1 && ($4=="SKIP_UNSUPPORTED_SCHEME" || $4=="SKIP_NO_SOURCE"){c++} END{print c+0}' "$REPORT_TSV")
eval_fail_count=$(awk -F'\t' 'NR>1 && $4=="EVAL_FAIL"{c++} END{print c+0}' "$REPORT_TSV")

# Markdown report
{
  echo "# Termux source URL check report"
  echo
  echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo
  printf 'Scope: `%s`\n' "$SCOPE"
  printf 'Repos: `%s`\n' "${repo_dirs[*]}"
  echo "Total entries: $(($(wc -l < "$REPORT_TSV") - 1))"
  echo
  echo "## Summary"
  echo
  echo "- OK: $ok_count"
  echo "- Fail: $fail_count"
  echo "- Skipped (non-http/https or no-source): $skip_count"
  echo "- Eval failures: $eval_fail_count"
  echo
  echo "## Failures (first 200)"
  echo
  echo "| repo | pkg | result | http | url |"
  echo "|---|---:|---:|---:|---|"
  awk -F'\t' 'NR>1 && $4!="OK" && $4!="SKIP_UNSUPPORTED_SCHEME" && $4!="SKIP_NO_SOURCE" {
      gsub(/\|/,"\\|",$3);
      printf("| %s | %s | %s | %s | %s |\n", $1, $2, $4, $5, $3);
    }' "$REPORT_TSV" | head -n 200
  echo
  echo "Full TSV is available in the workflow artifacts (report.tsv)."
} > "$REPORT_MD"

# A short summary file intended for $GITHUB_STEP_SUMMARY
{
  echo "## Source URL check"
  echo
  printf '%s\n' "- Scope: \`$SCOPE\`"
  echo "- Total: $(($(wc -l < "$REPORT_TSV") - 1))"
  echo "- OK: $ok_count"
  echo "- Fail: $fail_count"
  echo "- Skipped: $skip_count"
  echo "- Eval failures: $eval_fail_count"
  echo
  echo "Artifact: url-check-report (see report.tsv / report.md)"
} > "$SUMMARY_MD"

if $FAIL_ON_ISSUES && { [[ "$fail_count" -gt 0 ]] || [[ "$eval_fail_count" -gt 0 ]]; }; then
  echo "URL check detected failures (fail=$fail_count, eval_fail=$eval_fail_count)." >&2
  exit 1
fi

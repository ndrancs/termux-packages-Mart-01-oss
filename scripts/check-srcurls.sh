#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check-srcurls.sh [--scope all|changed] [--jobs N] [--include-disabled] [--output-dir DIR]

Collect TERMUX_PKG_SRCURL values from package build.sh files and check whether
those URLs are reachable.

Outputs:
  - report.tsv
  - report.md
  - summary.md
  - failures.tsv (if any)

Notes:
  - Build scripts are *sourced* in a minimal bash environment to expand variables
    like ${TERMUX_PKG_VERSION}.
  - Only http(s) URLs are actively checked. Other schemes are marked as SKIP.
EOF
}

SCOPE="all"
JOBS=8
INCLUDE_DISABLED=false
OUTPUT_DIR="artifacts/url-check"

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
    # pull_request
    base=$(jq -r '.pull_request.base.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
    # push
    if [[ -z "$base" ]]; then
      base=$(jq -r '.before // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
    fi
    head=$(jq -r '.after // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
    [[ -z "$head" ]] && head="HEAD"
  fi

  if [[ -z "$base" ]]; then
    # Fallback for PRs: base ref name
    if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
      git fetch --no-tags --depth=1 origin "$GITHUB_BASE_REF" >/dev/null 2>&1 || true
      base="origin/$GITHUB_BASE_REF"
    fi
  fi

  if [[ -z "$base" ]]; then
    # As a last resort, just check all.
    return 1
  fi

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
      # If disabled-packages were not requested, skip them.
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

# Collect URL tasks: repo_path \t pkg \t url
collect_urls_for_build_sh() {
  local build_sh="$1"
  local pkg_dir repo_path pkg_name
  pkg_dir=$(dirname "$build_sh")
  repo_path=$(dirname "$pkg_dir")
  pkg_name=$(basename "$pkg_dir")

  # Evaluate TERMUX_PKG_SRCURL by sourcing build.sh in its directory.
  # Disable nounset (set +u) to avoid failures on undefined variables.
  local urls
  set +e
  urls=$(bash -c 'set -e; set +u; cd "$1"; source ./build.sh >/dev/null 2>&1 || source ./build.sh; 
    if ! declare -p TERMUX_PKG_SRCURL >/dev/null 2>&1; then exit 3; fi
    if declare -p TERMUX_PKG_SRCURL 2>/dev/null | grep -q "declare -a"; then
      for u in "${TERMUX_PKG_SRCURL[@]}"; do echo "$u"; done
    else
      # Split on whitespace if multiple URLs were embedded in a single string.
      # (Most packages use arrays when they have multiple URLs.)
      read -r -a _arr <<< "${TERMUX_PKG_SRCURL}"
      for u in "${_arr[@]}"; do echo "$u"; done
    fi
  ' bash "$pkg_dir" 2>/dev/null)
  local ec=$?
  set -e

  if [[ $ec -ne 0 ]] || [[ -z "${urls:-}" ]]; then
    printf '%s\t%s\t%s\n' "$repo_path" "$pkg_name" "EVAL_FAIL(build.sh)" >> "$TASKS_FILE"
    return 0
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
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$pkg" "$url" "EVAL_FAIL" "" "";
    return 0
  fi

  if [[ ! "$url" =~ ^https?:// ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$pkg" "$url" "SKIP_UNSUPPORTED_SCHEME" "" "";
    return 0
  fi

  # Use a range request to avoid downloading full archives.
  # -L follow redirects
  # -r 0-0 request only first byte
  # --max-time total time limit
  # --connect-timeout handshake timeout
  local http_code curl_exit
  http_code=$(curl -L -r 0-0 -o /dev/null -sS -w '%{http_code}' \
    --connect-timeout 7 --max-time 25 --retry 0 "$url" || true)
  curl_exit=$?

  local result
  if [[ $curl_exit -ne 0 ]]; then
    result="CURL_ERROR"
  else
    case "$http_code" in
      2*|3*) result="OK";;
      404) result="HTTP_404";;
      410) result="HTTP_410";;
      5*) result="HTTP_5XX";;
      000|"") result="NO_HTTP_CODE";;
      *) result="HTTP_${http_code}";;
    esac
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$pkg" "$url" "$result" "$http_code" "$curl_exit";
}
export -f check_one_url

# Run checks (sequential by default; allow limited parallelism via xargs).
# Using xargs keeps this script POSIX-ish and avoids requiring extra deps.
# URLs do not contain spaces in practice; package names don't either.
while IFS=$'\t' read -r repo pkg url; do
  printf '%q\t%q\t%q\n' "$repo" "$pkg" "$url"
done < "$TASKS_FILE" \
  | xargs -P "$JOBS" -n 1 -I{} bash -c '
      # {} is a single line containing 3 quoted strings separated by \t.
      # shellcheck disable=SC2086
      eval "set -- {}";
      check_one_url "$1" "$2" "$3";
    ' \
  >> "$REPORT_TSV"

# Produce failures list.
awk -F'\t' 'NR==1{next} $4!="OK" && $4!="SKIP_UNSUPPORTED_SCHEME" {print}' "$REPORT_TSV" > "$FAILURES_TSV" || true

# Markdown report + summary
{
  echo "# Termux source URL check report"
  echo
  echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo
  echo "Scope: \\`$SCOPE\\`"
  echo "Repos: \\`${repo_dirs[*]}\\`"
  echo "Total entries: $(($(wc -l < "$REPORT_TSV") - 1))"
  echo
  echo "## Summary"
  echo
  ok_count=$(awk -F'\t' 'NR>1 && $4=="OK"{c++} END{print c+0}' "$REPORT_TSV")
  fail_count=$(awk -F'\t' 'NR>1 && $4!="OK" && $4!="SKIP_UNSUPPORTED_SCHEME"{c++} END{print c+0}' "$REPORT_TSV")
  skip_count=$(awk -F'\t' 'NR>1 && $4=="SKIP_UNSUPPORTED_SCHEME"{c++} END{print c+0}' "$REPORT_TSV")
  eval_fail_count=$(awk -F'\t' 'NR>1 && $4=="EVAL_FAIL"{c++} END{print c+0}' "$REPORT_TSV")
  echo "- OK: $ok_count"
  echo "- Fail: $fail_count"
  echo "- Skipped (non-http/https): $skip_count"
  echo "- Eval failures: $eval_fail_count"
  echo
  echo "## Failures (first 200)"
  echo
  echo "| repo | pkg | result | http | url |"
  echo "|---|---:|---:|---:|---|"
  awk -F'\t' 'NR>1 && $4!="OK" && $4!="SKIP_UNSUPPORTED_SCHEME" { 
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
  echo "- Scope: \\`$SCOPE\\`"
  echo "- Total: $(($(wc -l < "$REPORT_TSV") - 1))"
  echo "- OK: $ok_count"
  echo "- Fail: $fail_count"
  echo "- Skipped: $skip_count"
  echo "- Eval failures: $eval_fail_count"
  echo
  echo "Artifact: url-check-report (see report.tsv / report.md)"
} > "$SUMMARY_MD"

# Fail the job if we saw any actual failures.
if [[ "$fail_count" -gt 0 ]] || [[ "$eval_fail_count" -gt 0 ]]; then
  echo "URL check detected failures (fail=$fail_count, eval_fail=$eval_fail_count)." >&2
  exit 1
fi

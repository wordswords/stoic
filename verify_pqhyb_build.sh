#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  verify_pqhyb_build.sh --bin ./pqhyb_stream

What it checks:
- Binary exists and is executable.
- Dynamic linker can resolve dependencies via ldd.
- Binary responds to missing args with usage/non-success.
USAGE
  exit 2
}

BIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bin) BIN="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[ -n "$BIN" ] || usage
[ -x "$BIN" ] || { echo "Binary not executable: $BIN" >&2; exit 1; }

if command -v ldd >/dev/null 2>&1; then
  ldd "$BIN"
fi

set +e
"$BIN" >/dev/null 2>&1
RC=$?
set -e

if [ "$RC" -eq 0 ]; then
  echo "Expected non-zero exit when called without args" >&2
  exit 1
fi

echo 'BUILD_CHECK=PASS'


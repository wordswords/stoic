#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  pqc_checksums.sh create <file> [file...]
  pqc_checksums.sh verify <file.sha256> [file.sha256...]
  pqc_checksums.sh print <file> [file...]

Notes:
- create writes <file>.sha256 sidecars in standard sha256sum format.
- verify checks existing sidecars.
- print prints hashes without creating sidecars.
USAGE
  exit 2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

hash_one() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file"
  else
    shasum -a 256 "$file" | awk '{print $1 "  " $2}'
  fi
}

verify_one() {
  local sidecar="$1"
  [ -f "$sidecar" ] || { echo "Missing checksum file: $sidecar" >&2; exit 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$sidecar"
  else
    local expected file actual
    expected="$(awk '{print $1}' "$sidecar")"
    file="$(awk '{print $2}' "$sidecar")"
    [ -f "$file" ] || { echo "Missing file for checksum: $file" >&2; exit 1; }
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    [ "$expected" = "$actual" ] || { echo "Checksum mismatch: $file" >&2; exit 1; }
    echo "$file: OK"
  fi
}

[ $# -ge 2 ] || usage
MODE="$1"
shift

case "$MODE" in
  create)
    for f in "$@"; do
      [ -f "$f" ] || { echo "Missing file: $f" >&2; exit 1; }
      hash_one "$f" > "$f.sha256"
      echo "Wrote $f.sha256"
    done
    ;;
  verify)
    for s in "$@"; do
      verify_one "$s"
    done
    ;;
  print)
    for f in "$@"; do
      [ -f "$f" ] || { echo "Missing file: $f" >&2; exit 1; }
      hash_one "$f"
    done
    ;;
  *)
    usage
    ;;
esac


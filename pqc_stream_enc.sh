#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  pqc_stream_enc.sh --pq-pubkey pq_pub.pem --rsa-pubkey rsa_pub.pem \
    [--bin ./pqhyb_stream] [--input file] [--output file] [--progress] [--dry-run] \
    [--checksum-in MODE] [--checksum-out MODE]

Checksum modes:
  off      Do nothing.
  create   Write a new .sha256 sidecar.
  verify   Require an existing .sha256 sidecar and verify it.
  auto     Verify if sidecar exists, otherwise create it, then verify.

Notes:
- If --input/--output are omitted, stdin/stdout are used.
- --progress uses pv when input size is known.
USAGE
  exit 2
}

quote() { printf '%q' "$1"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }; }
file_size() { stat -c %s "$1"; }
write_sidecar() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" > "$file.sha256"
  else
    shasum -a 256 "$file" | awk '{print $1 "  " $2}' > "$file.sha256"
  fi
}
verify_sidecar() {
  local file="$1"
  local sidecar="$file.sha256"
  [ -f "$sidecar" ] || { echo "Missing checksum file: $sidecar" >&2; exit 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$sidecar"
  else
    local expected actual
    expected="$(awk '{print $1}' "$sidecar")"
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    [ "$expected" = "$actual" ] || { echo "Checksum mismatch: $file" >&2; exit 1; }
    echo "$file: OK"
  fi
}
handle_checksum_mode() {
  local mode="$1" file="$2"
  case "$mode" in
    off) ;;
    create) write_sidecar "$file" ;;
    verify) verify_sidecar "$file" ;;
    auto)
      if [ -f "$file.sha256" ]; then
        verify_sidecar "$file"
      else
        write_sidecar "$file"
        verify_sidecar "$file"
      fi
      ;;
    *) echo "Invalid checksum mode: $mode" >&2; exit 1 ;;
  esac
}

BIN="${PQHYB_STREAM_BIN:-./pqhyb_stream}"
PQ_PUB=""
RSA_PUB=""
INPUT=""
OUTPUT=""
PROGRESS=0
DRY_RUN=0
CHECKSUM_IN_MODE="off"
CHECKSUM_OUT_MODE="off"

while [ $# -gt 0 ]; do
  case "$1" in
    --bin) BIN="$2"; shift 2 ;;
    --pq-pubkey) PQ_PUB="$2"; shift 2 ;;
    --rsa-pubkey) RSA_PUB="$2"; shift 2 ;;
    --input) INPUT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --progress) PROGRESS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --checksum-in) CHECKSUM_IN_MODE="$2"; shift 2 ;;
    --checksum-out) CHECKSUM_OUT_MODE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[ -x "$BIN" ] || { echo "Binary not executable: $BIN" >&2; exit 1; }
[ -n "$PQ_PUB" ] || usage
[ -n "$RSA_PUB" ] || usage
CMD=("$BIN" encrypt --pq-pubkey "$PQ_PUB" --rsa-pubkey "$RSA_PUB")

if [ "$DRY_RUN" -eq 1 ]; then
  if [ -n "$INPUT" ] && [ -n "$OUTPUT" ]; then
    [ "$CHECKSUM_IN_MODE" != "off" ] && echo "# input checksum mode: $CHECKSUM_IN_MODE for $(quote "$INPUT")"
    if [ "$PROGRESS" -eq 1 ]; then
      echo "pv -ptebar -s $(quote "$(file_size "$INPUT")") $(quote "$INPUT") | $(quote "$BIN") encrypt --pq-pubkey $(quote "$PQ_PUB") --rsa-pubkey $(quote "$RSA_PUB") > $(quote "$OUTPUT")"
    else
      echo "$(quote "$BIN") encrypt --pq-pubkey $(quote "$PQ_PUB") --rsa-pubkey $(quote "$RSA_PUB") < $(quote "$INPUT") > $(quote "$OUTPUT")"
    fi
    [ "$CHECKSUM_OUT_MODE" != "off" ] && echo "# output checksum mode: $CHECKSUM_OUT_MODE for $(quote "$OUTPUT")"
  else
    echo "$(quote "$BIN") encrypt --pq-pubkey $(quote "$PQ_PUB") --rsa-pubkey $(quote "$RSA_PUB")"
  fi
  exit 0
fi

if [ -n "$INPUT" ] && [ -n "$OUTPUT" ]; then
  [ -f "$INPUT" ] || { echo "Missing input file: $INPUT" >&2; exit 1; }
  handle_checksum_mode "$CHECKSUM_IN_MODE" "$INPUT"
  if [ "$PROGRESS" -eq 1 ]; then
    need_cmd pv
    pv -ptebar -s "$(file_size "$INPUT")" "$INPUT" | "${CMD[@]}" > "$OUTPUT"
  else
    "${CMD[@]}" < "$INPUT" > "$OUTPUT"
  fi
  handle_checksum_mode "$CHECKSUM_OUT_MODE" "$OUTPUT"
else
  exec "${CMD[@]}"
fi

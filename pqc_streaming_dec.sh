#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  pqc_streaming_dec.sh --pq-privkey pq_priv.pem --rsa-privkey rsa_priv.pem \
    [--bin ./pqhyb_stream_streaming] [--input file] [--output file] [--dry-run]

Notes:
- Supports true forward-only streaming.
- If --input/--output are omitted, stdin/stdout are used.
- This wrapper is intended for producer | decrypt | consumer pipelines.
USAGE
  exit 2
}

BIN="${PQHYB_STREAMING_BIN:-./pqhyb_stream_streaming}"
PQ_PRIV=""
RSA_PRIV=""
INPUT=""
OUTPUT=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bin) BIN="$2"; shift 2 ;;
    --pq-privkey) PQ_PRIV="$2"; shift 2 ;;
    --rsa-privkey) RSA_PRIV="$2"; shift 2 ;;
    --input) INPUT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[ -x "$BIN" ] || { echo "Binary not executable: $BIN" >&2; exit 1; }
[ -n "$PQ_PRIV" ] || usage
[ -n "$RSA_PRIV" ] || usage

if [ "$DRY_RUN" -eq 1 ]; then
  if [ -n "$INPUT" ] && [ -n "$OUTPUT" ]; then
    echo "$BIN decrypt --pq-privkey $PQ_PRIV --rsa-privkey $RSA_PRIV < $INPUT > $OUTPUT"
  else
    echo "$BIN decrypt --pq-privkey $PQ_PRIV --rsa-privkey $RSA_PRIV"
  fi
  exit 0
fi

if [ -n "$INPUT" ] && [ -n "$OUTPUT" ]; then
  exec "$BIN" decrypt --pq-privkey "$PQ_PRIV" --rsa-privkey "$RSA_PRIV" < "$INPUT" > "$OUTPUT"
else
  exec "$BIN" decrypt --pq-privkey "$PQ_PRIV" --rsa-privkey "$RSA_PRIV"
fi

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  verify_pqhyb_streaming_rclone_sim.sh \
    --bin ./pqhyb_stream_streaming \
    --pq-pubkey pq_pub.pem --pq-privkey pq_priv.pem \
    --rsa-pubkey rsa_pub.pem --rsa-privkey rsa_priv.pem \
    --input sample.dat

This simulates:
  producer | encrypt | rclone rcat
  rclone cat | decrypt | consumer
by using plain shell pipes and cat.
USAGE
  exit 2
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

BIN=""
PQ_PUB=""
PQ_PRIV=""
RSA_PUB=""
RSA_PRIV=""
INPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --bin) BIN="$2"; shift 2 ;;
    --pq-pubkey) PQ_PUB="$2"; shift 2 ;;
    --pq-privkey) PQ_PRIV="$2"; shift 2 ;;
    --rsa-pubkey) RSA_PUB="$2"; shift 2 ;;
    --rsa-privkey) RSA_PRIV="$2"; shift 2 ;;
    --input) INPUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[ -n "$BIN" ] || usage
[ -n "$PQ_PUB" ] || usage
[ -n "$PQ_PRIV" ] || usage
[ -n "$RSA_PUB" ] || usage
[ -n "$RSA_PRIV" ] || usage
[ -n "$INPUT" ] || usage

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
REMOTE_OBJ="$TMPDIR/remote-object.pqhs"
RESTORED="$TMPDIR/restored.bin"

cat "$INPUT" | "$BIN" encrypt --pq-pubkey "$PQ_PUB" --rsa-pubkey "$RSA_PUB" | cat > "$REMOTE_OBJ"
cat "$REMOTE_OBJ" | "$BIN" decrypt --pq-privkey "$PQ_PRIV" --rsa-privkey "$RSA_PRIV" | cat > "$RESTORED"

ORIG_HASH="$(sha256_file "$INPUT")"
DEC_HASH="$(sha256_file "$RESTORED")"
printf 'original_sha256=%s\n' "$ORIG_HASH"
printf 'restored_sha256=%s\n' "$DEC_HASH"

[ "$ORIG_HASH" = "$DEC_HASH" ] || { echo 'RCLONE_SIM_VERIFICATION=FAIL' >&2; exit 1; }
echo 'RCLONE_SIM_VERIFICATION=PASS'

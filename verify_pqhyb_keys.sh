#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  verify_pqhyb_keys.sh \
    --pq-pubkey pq_pub.pem --pq-privkey pq_priv.pem \
    --rsa-pubkey rsa_pub.pem --rsa-privkey rsa_priv.pem

What it checks:
- Files exist.
- OpenSSL can parse the public and private keys.
USAGE
  exit 2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
PQ_PUB=""
PQ_PRIV=""
RSA_PUB=""
RSA_PRIV=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pq-pubkey) PQ_PUB="$2"; shift 2 ;;
    --pq-privkey) PQ_PRIV="$2"; shift 2 ;;
    --rsa-pubkey) RSA_PUB="$2"; shift 2 ;;
    --rsa-privkey) RSA_PRIV="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[ -n "$PQ_PUB" ] || usage
[ -n "$PQ_PRIV" ] || usage
[ -n "$RSA_PUB" ] || usage
[ -n "$RSA_PRIV" ] || usage

need_cmd "$OPENSSL_BIN"

[ -f "$PQ_PUB" ] || { echo "Missing PQ public key: $PQ_PUB" >&2; exit 1; }
[ -f "$PQ_PRIV" ] || { echo "Missing PQ private key: $PQ_PRIV" >&2; exit 1; }
[ -f "$RSA_PUB" ] || { echo "Missing RSA public key: $RSA_PUB" >&2; exit 1; }
[ -f "$RSA_PRIV" ] || { echo "Missing RSA private key: $RSA_PRIV" >&2; exit 1; }

"$OPENSSL_BIN" pkey -pubin -in "$PQ_PUB" -text -noout >/dev/null
"$OPENSSL_BIN" pkey -in "$PQ_PRIV" -text -noout >/dev/null
"$OPENSSL_BIN" pkey -pubin -in "$RSA_PUB" -text -noout >/dev/null
"$OPENSSL_BIN" pkey -in "$RSA_PRIV" -text -noout >/dev/null

echo 'KEY_CHECK=PASS'


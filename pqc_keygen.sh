#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  pqc_keygen.sh [--pq-alg MLKEM768] [--rsa-bits 3072] \
    --out-pq-priv pq_priv.pem --out-pq-pub pq_pub.pem \
    --out-rsa-priv rsa_priv.pem --out-rsa-pub rsa_pub.pem
USAGE
  exit 2
}

OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
OSSL_PROVIDER_ARGS="${OSSL_PROVIDER_ARGS:--provider default -provider oqsprovider}"
PQ_ALG="${PQ_KEM_ALG:-MLKEM768}"
RSA_BITS=3072
OUT_PQ_PRIV=""
OUT_PQ_PUB=""
OUT_RSA_PRIV=""
OUT_RSA_PUB=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pq-alg) PQ_ALG="$2"; shift 2 ;;
    --rsa-bits) RSA_BITS="$2"; shift 2 ;;
    --out-pq-priv) OUT_PQ_PRIV="$2"; shift 2 ;;
    --out-pq-pub) OUT_PQ_PUB="$2"; shift 2 ;;
    --out-rsa-priv) OUT_RSA_PRIV="$2"; shift 2 ;;
    --out-rsa-pub) OUT_RSA_PUB="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[ -n "$OUT_PQ_PRIV" ] || usage
[ -n "$OUT_PQ_PUB" ] || usage
[ -n "$OUT_RSA_PRIV" ] || usage
[ -n "$OUT_RSA_PUB" ] || usage

"$OPENSSL_BIN" genpkey -algorithm "$PQ_ALG" $OSSL_PROVIDER_ARGS -out "$OUT_PQ_PRIV"
"$OPENSSL_BIN" pkey -in "$OUT_PQ_PRIV" -pubout $OSSL_PROVIDER_ARGS -out "$OUT_PQ_PUB"
"$OPENSSL_BIN" genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:"$RSA_BITS" -provider default -out "$OUT_RSA_PRIV"
"$OPENSSL_BIN" pkey -in "$OUT_RSA_PRIV" -pubout -provider default -out "$OUT_RSA_PUB"


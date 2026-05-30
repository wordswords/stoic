#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  source ./pqc_autoenv.sh
  source ./pqc_autoenv.sh /path/to/openssl

Exports:
  OPENSSL_BIN
  OSSL_PROVIDER_ARGS
  PQ_KEM_ALG
  PQ_KEM_RSA_SUITE
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  return 0 2>/dev/null || exit 0
fi

OPENSSL_BIN_CANDIDATE="${1:-${OPENSSL_BIN:-openssl}}"
command -v "$OPENSSL_BIN_CANDIDATE" >/dev/null 2>&1 || {
  echo "Unable to find openssl binary: $OPENSSL_BIN_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
}

OPENSSL_BIN="$OPENSSL_BIN_CANDIDATE"
if "$OPENSSL_BIN" list -providers 2>/dev/null | grep -qi oqsprovider; then
  OSSL_PROVIDER_ARGS='-provider default -provider oqsprovider'
else
  OSSL_PROVIDER_ARGS='-provider default'
fi

KEMS="$($OPENSSL_BIN list -kem-algorithms $OSSL_PROVIDER_ARGS 2>/dev/null || true)"
if printf '%s\n' "$KEMS" | grep -q 'MLKEM768'; then
  PQ_KEM_ALG='MLKEM768'
elif printf '%s\n' "$KEMS" | grep -q 'mlkem768'; then
  PQ_KEM_ALG='mlkem768'
elif printf '%s\n' "$KEMS" | grep -q 'ML-KEM-768'; then
  PQ_KEM_ALG='ML-KEM-768'
else
  PQ_KEM_ALG='MLKEM768'
fi

PQ_KEM_RSA_SUITE='ml-kem-768+rsa-oaep+aes-256-gcm-stream'

export OPENSSL_BIN
export OSSL_PROVIDER_ARGS
export PQ_KEM_ALG
export PQ_KEM_RSA_SUITE

echo "OPENSSL_BIN=$OPENSSL_BIN"
echo "OSSL_PROVIDER_ARGS=$OSSL_PROVIDER_ARGS"
echo "PQ_KEM_ALG=$PQ_KEM_ALG"
echo "PQ_KEM_RSA_SUITE=$PQ_KEM_RSA_SUITE"


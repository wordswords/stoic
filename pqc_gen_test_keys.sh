#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  pqc_gen_test_keys.sh [options]

Options:
  --outdir DIR           Output directory for generated PEM files, default: ./test-keys
  --pq-alg ALG           PQ KEM algorithm, default: MLKEM768
  --rsa-bits N           RSA key size, default: 3072
  --openssl-bin PATH     OpenSSL binary, default: openssl
  --provider-args STR    Extra provider arguments, default: "-provider default -provider oqsprovider"
  --overwrite            Replace existing files in output directory
  --dry-run              Print commands without executing
  -h, --help             Show this help

Outputs:
  pq_priv.pem
  pq_pub.pem
  rsa_priv.pem
  rsa_pub.pem
USAGE
  exit 2
}

OUTDIR="./test-keys"
PQ_ALG="MLKEM768"
RSA_BITS="3072"
OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
PROVIDER_ARGS="${OSSL_PROVIDER_ARGS:--provider default -provider oqsprovider}"
OVERWRITE=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --outdir) OUTDIR="$2"; shift 2 ;;
    --pq-alg) PQ_ALG="$2"; shift 2 ;;
    --rsa-bits) RSA_BITS="$2"; shift 2 ;;
    --openssl-bin) OPENSSL_BIN="$2"; shift 2 ;;
    --provider-args) PROVIDER_ARGS="$2"; shift 2 ;;
    --overwrite) OVERWRITE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

mkdir -p "$OUTDIR"
PQ_PRIV="$OUTDIR/pq_priv.pem"
PQ_PUB="$OUTDIR/pq_pub.pem"
RSA_PRIV="$OUTDIR/rsa_priv.pem"
RSA_PUB="$OUTDIR/rsa_pub.pem"

if [ "$OVERWRITE" -ne 1 ]; then
  for f in "$PQ_PRIV" "$PQ_PUB" "$RSA_PRIV" "$RSA_PUB"; do
    if [ -e "$f" ]; then
      echo "Refusing to overwrite existing file: $f" >&2
      echo "Use --overwrite to replace existing keys." >&2
      exit 1
    fi
  done
fi

cmd_pq_priv=("$OPENSSL_BIN" genpkey -algorithm "$PQ_ALG")
# shellcheck disable=SC2206
extra_provider=( $PROVIDER_ARGS )
cmd_pq_priv+=("${extra_provider[@]}" -out "$PQ_PRIV")

cmd_pq_pub=("$OPENSSL_BIN" pkey -in "$PQ_PRIV" -pubout)
cmd_pq_pub+=("${extra_provider[@]}" -out "$PQ_PUB")

cmd_rsa_priv=("$OPENSSL_BIN" genpkey -algorithm RSA -pkeyopt "rsa_keygen_bits:$RSA_BITS" -out "$RSA_PRIV")
cmd_rsa_pub=("$OPENSSL_BIN" pkey -in "$RSA_PRIV" -pubout -out "$RSA_PUB")

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%q ' "${cmd_pq_priv[@]}"; printf '\n'
  printf '%q ' "${cmd_pq_pub[@]}"; printf '\n'
  printf '%q ' "${cmd_rsa_priv[@]}"; printf '\n'
  printf '%q ' "${cmd_rsa_pub[@]}"; printf '\n'
  exit 0
fi

"${cmd_pq_priv[@]}"
"${cmd_pq_pub[@]}"
"${cmd_rsa_priv[@]}"
"${cmd_rsa_pub[@]}"

chmod 600 "$PQ_PRIV" "$RSA_PRIV"
chmod 644 "$PQ_PUB" "$RSA_PUB"

echo "Generated test keys in: $OUTDIR"
printf '  %s\n' "$PQ_PRIV" "$PQ_PUB" "$RSA_PRIV" "$RSA_PUB"

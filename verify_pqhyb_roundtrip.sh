#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  verify_pqhyb_roundtrip.sh \
    --bin ./pqhyb_stream \
    --pq-pubkey pq_pub.pem --pq-privkey pq_priv.pem \
    --rsa-pubkey rsa_pub.pem --rsa-privkey rsa_priv.pem \
    --input sample.dat [--progress] [--dry-run] [--keep-temp] \
    [--checksum-in MODE] [--checksum-enc MODE] [--checksum-out MODE]

Checksum modes:
  off      Do nothing.
  create   Write a new .sha256 sidecar.
  verify   Require an existing .sha256 sidecar and verify it.
  auto     Verify if sidecar exists, otherwise create it, then verify.
USAGE
  exit 2
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }; }
quote() { printf '%q' "$1"; }
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
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
file_size() { stat -c %s "$1"; }

BIN=""
PQ_PUB=""
PQ_PRIV=""
RSA_PUB=""
RSA_PRIV=""
INPUT=""
KEEP_TEMP=0
PROGRESS=0
DRY_RUN=0
CHECKSUM_IN_MODE="off"
CHECKSUM_ENC_MODE="off"
CHECKSUM_OUT_MODE="off"

while [ $# -gt 0 ]; do
  case "$1" in
    --bin) BIN="$2"; shift 2 ;;
    --pq-pubkey) PQ_PUB="$2"; shift 2 ;;
    --pq-privkey) PQ_PRIV="$2"; shift 2 ;;
    --rsa-pubkey) RSA_PUB="$2"; shift 2 ;;
    --rsa-privkey) RSA_PRIV="$2"; shift 2 ;;
    --input) INPUT="$2"; shift 2 ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    --progress) PROGRESS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --checksum-in) CHECKSUM_IN_MODE="$2"; shift 2 ;;
    --checksum-enc) CHECKSUM_ENC_MODE="$2"; shift 2 ;;
    --checksum-out) CHECKSUM_OUT_MODE="$2"; shift 2 ;;
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

need_cmd awk
need_cmd mktemp
need_cmd stat
[ -x "$BIN" ] || { echo "Binary not executable: $BIN" >&2; exit 1; }
[ -f "$PQ_PUB" ] || { echo "Missing PQ public key: $PQ_PUB" >&2; exit 1; }
[ -f "$PQ_PRIV" ] || { echo "Missing PQ private key: $PQ_PRIV" >&2; exit 1; }
[ -f "$RSA_PUB" ] || { echo "Missing RSA public key: $RSA_PUB" >&2; exit 1; }
[ -f "$RSA_PRIV" ] || { echo "Missing RSA private key: $RSA_PRIV" >&2; exit 1; }
[ -f "$INPUT" ] || { echo "Missing input file: $INPUT" >&2; exit 1; }

TMPDIR="$(mktemp -d)"
ENC="$TMPDIR/test.pqhs"
DEC="$TMPDIR/restored.bin"

if [ "$DRY_RUN" -eq 1 ]; then
  [ "$CHECKSUM_IN_MODE" != "off" ] && echo "# input checksum mode: $CHECKSUM_IN_MODE for $(quote "$INPUT")"
  if [ "$PROGRESS" -eq 1 ]; then
    echo "pv -ptebar -s $(quote "$(file_size "$INPUT")") $(quote "$INPUT") | $(quote "$BIN") encrypt --pq-pubkey $(quote "$PQ_PUB") --rsa-pubkey $(quote "$RSA_PUB") > $(quote "$ENC")"
    echo "pv -ptebar $(quote "$ENC") | $(quote "$BIN") decrypt --pq-privkey $(quote "$PQ_PRIV") --rsa-privkey $(quote "$RSA_PRIV") > $(quote "$DEC")"
  else
    echo "$(quote "$BIN") encrypt --pq-pubkey $(quote "$PQ_PUB") --rsa-pubkey $(quote "$RSA_PUB") < $(quote "$INPUT") > $(quote "$ENC")"
    echo "$(quote "$BIN") decrypt --pq-privkey $(quote "$PQ_PRIV") --rsa-privkey $(quote "$RSA_PRIV") < $(quote "$ENC") > $(quote "$DEC")"
  fi
  [ "$CHECKSUM_ENC_MODE" != "off" ] && echo "# encrypted checksum mode: $CHECKSUM_ENC_MODE for $(quote "$ENC")"
  [ "$CHECKSUM_OUT_MODE" != "off" ] && echo "# restored checksum mode: $CHECKSUM_OUT_MODE for $(quote "$DEC")"
  exit 0
fi

cleanup() {
  if [ "$KEEP_TEMP" -eq 0 ]; then
    rm -rf "$TMPDIR"
  else
    echo "Kept temp files in: $TMPDIR" >&2
  fi
}
trap cleanup EXIT HUP INT TERM

handle_checksum_mode "$CHECKSUM_IN_MODE" "$INPUT"

if [ "$PROGRESS" -eq 1 ]; then
  need_cmd pv
  pv -ptebar -s "$(file_size "$INPUT")" "$INPUT" | "$BIN" encrypt --pq-pubkey "$PQ_PUB" --rsa-pubkey "$RSA_PUB" > "$ENC"
else
  "$BIN" encrypt --pq-pubkey "$PQ_PUB" --rsa-pubkey "$RSA_PUB" < "$INPUT" > "$ENC"
fi

handle_checksum_mode "$CHECKSUM_ENC_MODE" "$ENC"

if [ "$PROGRESS" -eq 1 ]; then
  pv -ptebar "$ENC" | "$BIN" decrypt --pq-privkey "$PQ_PRIV" --rsa-privkey "$RSA_PRIV" > "$DEC"
else
  "$BIN" decrypt --pq-privkey "$PQ_PRIV" --rsa-privkey "$RSA_PRIV" < "$ENC" > "$DEC"
fi

handle_checksum_mode "$CHECKSUM_OUT_MODE" "$DEC"

ORIG_HASH="$(sha256_file "$INPUT")"
ENC_HASH="$(sha256_file "$ENC")"
DEC_HASH="$(sha256_file "$DEC")"
ORIG_SIZE="$(stat -c %s "$INPUT")"
ENC_SIZE="$(stat -c %s "$ENC")"
DEC_SIZE="$(stat -c %s "$DEC")"

printf 'original_size=%s\n' "$ORIG_SIZE"
printf 'encrypted_size=%s\n' "$ENC_SIZE"
printf 'restored_size=%s\n' "$DEC_SIZE"
printf 'original_sha256=%s\n' "$ORIG_HASH"
printf 'encrypted_sha256=%s\n' "$ENC_HASH"
printf 'restored_sha256=%s\n' "$DEC_HASH"

if [ "$ORIG_HASH" != "$DEC_HASH" ]; then
  echo 'VERIFICATION=FAIL' >&2
  exit 1
fi

echo 'VERIFICATION=PASS'


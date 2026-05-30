#!/usr/bin/env bash
set -euo pipefail

: "${CC:=cc}"
: "${OPENSSL_CFLAGS:=$(pkg-config --cflags openssl 2>/dev/null || true)}"
: "${OPENSSL_LIBS:=$(pkg-config --libs openssl 2>/dev/null || echo -lssl -lcrypto)}"

SRC="${1:-pqhyb_stream.c}"
OUT="${2:-pqhyb_stream}"

$CC -O3 -march=native -Wall -Wextra -std=c11 $OPENSSL_CFLAGS -o "$OUT" "$SRC" $OPENSSL_LIBS


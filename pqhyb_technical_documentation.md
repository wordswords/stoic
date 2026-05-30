# PQ Hybrid Stream Encryption Toolkit Documentation

This document describes the complete toolkit for hybrid post-quantum encryption, including both the original seekable-file helper and the new forward-only streaming helper. The suite now supports two operational formats: `PQHS01` for file-oriented workflows and `PQHS02` for true pipe-based streaming workflows such as `producer | encrypt | rclone rcat` and `rclone cat | decrypt | consumer`.[cite:1]

## Formats

| Format | Helper | Best use | Seekable streams required |
|---|---|---|---|
| `PQHS01` | `pqhyb_stream` | Regular files, local file verification, patchable header format | Yes |
| `PQHS02` | `pqhyb_stream_streaming` | Forward-only pipelines, rclone streaming, pipe transport | No |

## Core files

| File | Purpose |
|---|---|
| `pqhyb_stream.c` | Original seekable file helper using `PQHS01`. |
| `pqhyb_stream_streaming.c` | New forward-only helper using `PQHS02`. |
| `pqc_build_helper.sh` | Builds the original helper. |
| `pqc_build_streaming_helper.sh` | Builds the streaming helper. |
| `pqc_stream_enc.sh` | File-oriented encryption wrapper for `PQHS01`. |
| `pqc_stream_dec.sh` | File-oriented decryption wrapper for `PQHS01`. |
| `pqc_streaming_enc.sh` | Streaming encryption wrapper for `PQHS02`. |
| `pqc_streaming_dec.sh` | Streaming decryption wrapper for `PQHS02`. |
| `verify_pqhyb_roundtrip.sh` | File-mode round-trip verifier. |
| `verify_pqhyb_streaming_roundtrip.sh` | Streaming-format round-trip verifier. |
| `verify_pqhyb_streaming_rclone_sim.sh` | Pipe simulation of rclone-style streaming. |
| `pqc_rclone_examples.md` | Ready-to-use rclone examples for streaming mode. |

## Streaming format design

`PQHS02` is a forward-only container. It writes the magic, PQ ciphertext length, RSA ciphertext length, IV, PQ ciphertext, RSA ciphertext, AES-GCM ciphertext stream, and the final GCM tag in strict forward order. Unlike `PQHS01`, it does not patch a plaintext-length field back into the header and it does not require seeking to the end of input during decrypt.[cite:1]

The forward-only design makes it suitable for tools that only offer stdin/stdout semantics, such as `rclone rcat` for upload streaming and `rclone cat` for download streaming. The decrypt path keeps the last 16 bytes buffered as the candidate GCM tag while streaming the preceding ciphertext through the GCM decryptor, then verifies the tag at finalization.[cite:1]

## Build scripts

### Original helper

```bash
./pqc_build_helper.sh pqhyb_stream.c pqhyb_stream
```

### Streaming helper

```bash
./pqc_build_streaming_helper.sh pqhyb_stream_streaming.c pqhyb_stream_streaming
```

## Streaming wrappers

### Encrypt wrapper

```bash
./pqc_streaming_enc.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-pubkey pq_pub.pem \
  --rsa-pubkey rsa_pub.pem
```

### Decrypt wrapper

```bash
./pqc_streaming_dec.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-privkey pq_priv.pem \
  --rsa-privkey rsa_priv.pem
```

These wrappers are intentionally minimal: they preserve full pipeline behavior and do not require seekable files.[cite:1]

## Verified workflows

### Pure pipe simulation

```bash
./verify_pqhyb_streaming_rclone_sim.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-pubkey pq_pub.pem --pq-privkey pq_priv.pem \
  --rsa-pubkey rsa_pub.pem --rsa-privkey rsa_priv.pem \
  --input sample.dat
```

### Forward-only round trip

```bash
./verify_pqhyb_streaming_roundtrip.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-pubkey pq_pub.pem --pq-privkey pq_priv.pem \
  --rsa-pubkey rsa_pub.pem --rsa-privkey rsa_priv.pem \
  --input sample.dat
```

## Rclone examples

### Upload

```bash
producer | ./pqhyb_stream_streaming encrypt \
  --pq-pubkey pq_pub.pem \
  --rsa-pubkey rsa_pub.pem | \
rclone rcat remote:backups/streamed.pqhs
```

### Download and decrypt

```bash
rclone cat remote:backups/streamed.pqhs | \
./pqhyb_stream_streaming decrypt \
  --pq-privkey pq_priv.pem \
  --rsa-privkey rsa_priv.pem | consumer
```

## Validation strategy

The streaming mode should be validated with at least these checks:

- Standard round-trip equality check on sample files.
- Pipe-only simulation that never uses seekable file semantics in the data path.
- Tamper test by flipping one ciphertext byte and confirming GCM authentication fails.
- Truncation test by removing the final bytes and confirming decryption fails.

The included verifier scripts cover the first two directly and provide the baseline needed before real rclone deployment.[cite:1]

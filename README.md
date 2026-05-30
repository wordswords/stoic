# Stoic

Stoic is a forward-only streaming PQ hybrid encryption suite. It is intended for Linux environments that need `producer | encrypt | rclone rcat` and `rclone cat | decrypt | consumer` style workflows.

## Contents

| File | Purpose |
|---|---|
| `pqhyb_stream_streaming.c` | Forward-only C helper implementing the `PQHS02` container format. |
| `pqc_build_streaming_helper.sh` | Standalone build helper for the streaming C source. |
| `pqc_streaming_enc.sh` | Wrapper for forward-only encryption from stdin or file input. |
| `pqc_streaming_dec.sh` | Wrapper for forward-only decryption from stdin or file input. |
| `verify_pqhyb_streaming_roundtrip.sh` | Round-trip verifier using local files. |
| `verify_pqhyb_streaming_rclone_sim.sh` | Pipe-only verifier that simulates `rclone rcat` and `rclone cat`. |
| `pqhyb_technical_documentation.md` | Main technical documentation. |
| `pqhyb_mermaid_diagrams.md` | Mermaid diagrams for formats, layout, and interaction flows. |
| `pqc_rclone_examples.md` | Focused examples for rclone streaming usage. |
| `Makefile` | Build, install, and packaging entry point. |

## Build

Use either the build script or `make`.

### With Make

```bash
make build
```

### With the standalone build script

```bash
./pqc_build_streaming_helper.sh pqhyb_stream_streaming.c pqhyb_stream_streaming
```

## Install

```bash
sudo make install
```

By default this installs executables into `/usr/local/bin` and documentation into `/usr/local/share/doc/pqhyb-release`.

## Verify

The release bundle ships verification scripts, but they require real key material and a test input file.

### Local round trip

```bash
./verify_pqhyb_streaming_roundtrip.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-pubkey pq_pub.pem --pq-privkey pq_priv.pem \
  --rsa-pubkey rsa_pub.pem --rsa-privkey rsa_priv.pem \
  --input sample.dat
```

### Pipe-only simulation

```bash
./verify_pqhyb_streaming_rclone_sim.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-pubkey pq_pub.pem --pq-privkey pq_priv.pem \
  --rsa-pubkey rsa_pub.pem --rsa-privkey rsa_priv.pem \
  --input sample.dat
```

## Rclone usage

### Upload stream directly to a remote object

```bash
producer | ./pqc_streaming_enc.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-pubkey pq_pub.pem \
  --rsa-pubkey rsa_pub.pem | \
rclone rcat remote:backups/streamed.pqhs
```

### Download and decrypt directly from a remote object

```bash
rclone cat remote:backups/streamed.pqhs | \
./pqc_streaming_dec.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-privkey pq_priv.pem \
  --rsa-privkey rsa_priv.pem | consumer
```

## Operational notes

- `PQHS02` is forward-only and suitable for pipe transport.
- The suite uses PQ KEM plus RSA OAEP to derive an AES-256-GCM content key.
- Authentication failure at decrypt should be treated as fatal and the output discarded.
- Verify with local round-trip tests before using remote transports in production.

## Documentation map

- Start with `pqhyb_technical_documentation.md` for the full technical reference.
- Use `pqhyb_mermaid_diagrams.md` for architecture and sequence diagrams.
- Use `pqc_rclone_examples.md` for concise streaming command lines.

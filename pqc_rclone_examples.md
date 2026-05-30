# Rclone streaming examples for PQHS02

## Direct streaming upload

```bash
producer | ./pqhyb_stream_streaming encrypt \
  --pq-pubkey pq_pub.pem \
  --rsa-pubkey rsa_pub.pem | \
rclone rcat remote:backups/streamed.pqhs
```

## Direct streaming download and decrypt

```bash
rclone cat remote:backups/streamed.pqhs | \
./pqhyb_stream_streaming decrypt \
  --pq-privkey pq_priv.pem \
  --rsa-privkey rsa_priv.pem | consumer
```

## Wrapper based upload

```bash
producer | ./pqc_streaming_enc.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-pubkey pq_pub.pem \
  --rsa-pubkey rsa_pub.pem | \
rclone rcat remote:backups/streamed.pqhs
```

## Wrapper based download

```bash
rclone cat remote:backups/streamed.pqhs | \
./pqc_streaming_dec.sh \
  --bin ./pqhyb_stream_streaming \
  --pq-privkey pq_priv.pem \
  --rsa-privkey rsa_priv.pem | consumer
```

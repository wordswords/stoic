DO NOT USE THIS FOR ANYTHING. I AM STILL ACTIVELY TESTING IT AND TRYING TO BREAK IT

The problem:
- I am using AWS S3 buckets to off-site my borg backup, and I wanted my borg backup data to be more resiliant to to 'store now decrypt later' attacks by Amazon assuming the eventual implementation of quantum codebreaking

The post quantum secure algorithms I am using
- https://csrc.nist.gov/projects/post-quantum-cryptography

The experimental method I am using them with:
- Open SSL experimental version using these algorithms in a block-wise way:
- https://github.com/open-quantum-safe/oqs-provider

The solution:
- So I vibe coded 'something' up with the help of Perplexity and now I'm going to try and break it and find vulnerabilities in the implementation that could be exploited by attackers.

## Usage:

Encrypt with strict source verification and ciphertext checksum creation:

```
./pqc_stream_enc.sh \
  --bin ./pqhyb_stream \
  --pq-pubkey pq_pub.pem \
  --rsa-pubkey rsa_pub.pem \
  --input hugefile.dat \
  --output hugefile.dat.pqhs \
  --progress \
  --checksum-in verify \
  --checksum-out create
```
Decrypt with ciphertext verification and restored-file checksum creation:

```
./pqc_stream_dec.sh \
  --bin ./pqhyb_stream \
  --pq-privkey pq_priv.pem \
  --rsa-privkey rsa_priv.pem \
  --input hugefile.dat.pqhs \
  --output hugefile.restored \
  --progress \
  --checksum-in verify \
  --checksum-out create
```

### Round-trip verify with explicit modes:

```
./verify_pqhyb_roundtrip.sh \
  --bin ./pqhyb_stream \
  --pq-pubkey pq_pub.pem --pq-privkey pq_priv.pem \
  --rsa-pubkey rsa_pub.pem --rsa-privkey rsa_priv.pem \
  --input sample.dat \
  --progress \
  --checksum-in auto \
  --checksum-enc create \
  --checksum-out create
```

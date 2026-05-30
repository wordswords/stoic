#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/err.h>
#include <openssl/rand.h>

#define MAGIC "PQHS02\0"
#define MAGIC_LEN 8
#define RSA_SEED_LEN 32
#define AES_KEY_LEN 32
#define GCM_IV_LEN 12
#define GCM_TAG_LEN 16
#define IO_CHUNK (1024 * 1024)

static void die_msg(const char *msg) {
    fprintf(stderr, "%s\n", msg);
    exit(1);
}

static void die_ssl(const char *msg) {
    fprintf(stderr, "%s\n", msg);
    ERR_print_errors_fp(stderr);
    exit(1);
}

static void secure_free(unsigned char *p, size_t n) {
    if (p) {
        OPENSSL_cleanse(p, n);
        OPENSSL_free(p);
    }
}

static void write_u32_be(FILE *f, uint32_t v) {
    unsigned char b[4];
    b[0] = (unsigned char)((v >> 24) & 0xff);
    b[1] = (unsigned char)((v >> 16) & 0xff);
    b[2] = (unsigned char)((v >> 8) & 0xff);
    b[3] = (unsigned char)(v & 0xff);
    if (fwrite(b, 1, 4, f) != 4) die_msg("write_u32_be failed");
}

static uint32_t read_u32_be(FILE *f) {
    unsigned char b[4];
    if (fread(b, 1, 4, f) != 4) die_msg("read_u32_be failed");
    return ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | (uint32_t)b[3];
}

static EVP_PKEY *load_pubkey(const char *path) {
    FILE *fp = fopen(path, "rb");
    if (!fp) die_msg("failed to open public key");
    EVP_PKEY *p = PEM_read_PUBKEY(fp, NULL, NULL, NULL);
    fclose(fp);
    if (!p) die_ssl("failed to read public key");
    return p;
}

static EVP_PKEY *load_privkey(const char *path) {
    FILE *fp = fopen(path, "rb");
    if (!fp) die_msg("failed to open private key");
    EVP_PKEY *p = PEM_read_PrivateKey(fp, NULL, NULL, NULL);
    fclose(fp);
    if (!p) die_ssl("failed to read private key");
    return p;
}

static void sha256_concat(const unsigned char *a, size_t alen,
                          const unsigned char *b, size_t blen,
                          unsigned char out[AES_KEY_LEN]) {
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    unsigned int mdlen = 0;
    if (!ctx) die_msg("EVP_MD_CTX_new failed");
    if (EVP_DigestInit_ex(ctx, EVP_sha256(), NULL) <= 0) die_ssl("DigestInit failed");
    if (EVP_DigestUpdate(ctx, a, alen) <= 0) die_ssl("DigestUpdate failed");
    if (EVP_DigestUpdate(ctx, b, blen) <= 0) die_ssl("DigestUpdate failed");
    if (EVP_DigestFinal_ex(ctx, out, &mdlen) <= 0) die_ssl("DigestFinal failed");
    EVP_MD_CTX_free(ctx);
    if (mdlen != AES_KEY_LEN) die_msg("unexpected digest size");
}

static void kem_encap(EVP_PKEY *pub, unsigned char **ct, size_t *ctlen,
                      unsigned char **ss, size_t *sslen) {
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_from_pkey(NULL, pub, NULL);
    if (!ctx) die_ssl("EVP_PKEY_CTX_new_from_pkey failed");
    if (EVP_PKEY_encapsulate_init(ctx, NULL) <= 0) die_ssl("EVP_PKEY_encapsulate_init failed");
    if (EVP_PKEY_encapsulate(ctx, NULL, ctlen, NULL, sslen) <= 0) die_ssl("EVP_PKEY_encapsulate size failed");
    *ct = OPENSSL_malloc(*ctlen);
    *ss = OPENSSL_malloc(*sslen);
    if (!*ct || !*ss) die_msg("alloc failed");
    if (EVP_PKEY_encapsulate(ctx, *ct, ctlen, *ss, sslen) <= 0) die_ssl("EVP_PKEY_encapsulate failed");
    EVP_PKEY_CTX_free(ctx);
}

static void kem_decap(EVP_PKEY *priv, const unsigned char *ct, size_t ctlen,
                      unsigned char **ss, size_t *sslen) {
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_from_pkey(NULL, priv, NULL);
    if (!ctx) die_ssl("EVP_PKEY_CTX_new_from_pkey failed");
    if (EVP_PKEY_decapsulate_init(ctx, NULL) <= 0) die_ssl("EVP_PKEY_decapsulate_init failed");
    if (EVP_PKEY_decapsulate(ctx, NULL, sslen, ct, ctlen) <= 0) die_ssl("EVP_PKEY_decapsulate size failed");
    *ss = OPENSSL_malloc(*sslen);
    if (!*ss) die_msg("alloc failed");
    if (EVP_PKEY_decapsulate(ctx, *ss, sslen, ct, ctlen) <= 0) die_ssl("EVP_PKEY_decapsulate failed");
    EVP_PKEY_CTX_free(ctx);
}

static void rsa_oaep_encrypt(EVP_PKEY *pub, const unsigned char *in, size_t inlen,
                             unsigned char **out, size_t *outlen) {
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(pub, NULL);
    if (!ctx) die_ssl("EVP_PKEY_CTX_new failed");
    if (EVP_PKEY_encrypt_init(ctx) <= 0) die_ssl("EVP_PKEY_encrypt_init failed");
    if (EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_PKCS1_OAEP_PADDING) <= 0) die_ssl("set_rsa_padding failed");
    if (EVP_PKEY_CTX_set_rsa_oaep_md(ctx, EVP_sha256()) <= 0) die_ssl("set_rsa_oaep_md failed");
    if (EVP_PKEY_CTX_set_rsa_mgf1_md(ctx, EVP_sha256()) <= 0) die_ssl("set_rsa_mgf1_md failed");
    if (EVP_PKEY_encrypt(ctx, NULL, outlen, in, inlen) <= 0) die_ssl("EVP_PKEY_encrypt size failed");
    *out = OPENSSL_malloc(*outlen);
    if (!*out) die_msg("alloc failed");
    if (EVP_PKEY_encrypt(ctx, *out, outlen, in, inlen) <= 0) die_ssl("EVP_PKEY_encrypt failed");
    EVP_PKEY_CTX_free(ctx);
}

static void rsa_oaep_decrypt(EVP_PKEY *priv, const unsigned char *in, size_t inlen,
                             unsigned char **out, size_t *outlen) {
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(priv, NULL);
    if (!ctx) die_ssl("EVP_PKEY_CTX_new failed");
    if (EVP_PKEY_decrypt_init(ctx) <= 0) die_ssl("EVP_PKEY_decrypt_init failed");
    if (EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_PKCS1_OAEP_PADDING) <= 0) die_ssl("set_rsa_padding failed");
    if (EVP_PKEY_CTX_set_rsa_oaep_md(ctx, EVP_sha256()) <= 0) die_ssl("set_rsa_oaep_md failed");
    if (EVP_PKEY_CTX_set_rsa_mgf1_md(ctx, EVP_sha256()) <= 0) die_ssl("set_rsa_mgf1_md failed");
    if (EVP_PKEY_decrypt(ctx, NULL, outlen, in, inlen) <= 0) die_ssl("EVP_PKEY_decrypt size failed");
    *out = OPENSSL_malloc(*outlen);
    if (!*out) die_msg("alloc failed");
    if (EVP_PKEY_decrypt(ctx, *out, outlen, in, inlen) <= 0) die_ssl("EVP_PKEY_decrypt failed");
    EVP_PKEY_CTX_free(ctx);
}

static void gcm_encrypt_forward(FILE *in, FILE *out,
                                const unsigned char key[AES_KEY_LEN],
                                const unsigned char iv[GCM_IV_LEN],
                                const unsigned char *aad, size_t aadlen,
                                unsigned char tag[GCM_TAG_LEN]) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    unsigned char *inbuf = OPENSSL_malloc(IO_CHUNK);
    unsigned char *outbuf = OPENSSL_malloc(IO_CHUNK + 32);
    int len = 0;

    if (!ctx || !inbuf || !outbuf) die_msg("alloc failed");
    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) <= 0) die_ssl("EncryptInit failed");
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, GCM_IV_LEN, NULL) <= 0) die_ssl("SET_IVLEN failed");
    if (EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv) <= 0) die_ssl("EncryptInit key/iv failed");
    if (aadlen > 0 && EVP_EncryptUpdate(ctx, NULL, &len, aad, (int)aadlen) <= 0) die_ssl("AAD update failed");

    for (;;) {
        size_t n = fread(inbuf, 1, IO_CHUNK, in);
        if (n > 0) {
            if (EVP_EncryptUpdate(ctx, outbuf, &len, inbuf, (int)n) <= 0) die_ssl("EncryptUpdate failed");
            if ((size_t)fwrite(outbuf, 1, (size_t)len, out) != (size_t)len) die_msg("ciphertext write failed");
        }
        if (n < IO_CHUNK) {
            if (ferror(in)) die_msg("plaintext read failed");
            break;
        }
    }

    if (EVP_EncryptFinal_ex(ctx, outbuf, &len) <= 0) die_ssl("EncryptFinal failed");
    if (len > 0 && (size_t)fwrite(outbuf, 1, (size_t)len, out) != (size_t)len) die_msg("final ciphertext write failed");
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, GCM_TAG_LEN, tag) <= 0) die_ssl("GET_TAG failed");

    EVP_CIPHER_CTX_free(ctx);
    secure_free(inbuf, IO_CHUNK);
    secure_free(outbuf, IO_CHUNK + 32);
}

static void gcm_decrypt_forward(FILE *in, FILE *out,
                                const unsigned char key[AES_KEY_LEN],
                                const unsigned char iv[GCM_IV_LEN],
                                const unsigned char *aad, size_t aadlen) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    unsigned char *hold = OPENSSL_malloc(GCM_TAG_LEN);
    unsigned char *inbuf = OPENSSL_malloc(IO_CHUNK);
    unsigned char *outbuf = OPENSSL_malloc(IO_CHUNK + 32);
    int len = 0;
    size_t hold_len = 0;

    if (!ctx || !hold || !inbuf || !outbuf) die_msg("alloc failed");
    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) <= 0) die_ssl("DecryptInit failed");
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, GCM_IV_LEN, NULL) <= 0) die_ssl("SET_IVLEN failed");
    if (EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv) <= 0) die_ssl("DecryptInit key/iv failed");
    if (aadlen > 0 && EVP_DecryptUpdate(ctx, NULL, &len, aad, (int)aadlen) <= 0) die_ssl("AAD update failed");

    for (;;) {
        size_t n = fread(inbuf, 1, IO_CHUNK, in);
        if (n == 0) {
            if (ferror(in)) die_msg("ciphertext read failed");
            break;
        }

        if (hold_len < GCM_TAG_LEN) {
            size_t take = (GCM_TAG_LEN - hold_len < n) ? (GCM_TAG_LEN - hold_len) : n;
            memcpy(hold + hold_len, inbuf, take);
            hold_len += take;
            if (take == n) continue;
            memmove(inbuf, inbuf + take, n - take);
            n -= take;
        }

        size_t total = hold_len + n;
        unsigned char *combined = OPENSSL_malloc(total);
        if (!combined) die_msg("alloc failed");
        memcpy(combined, hold, hold_len);
        memcpy(combined + hold_len, inbuf, n);

        size_t emit_len = total - GCM_TAG_LEN;
        if (emit_len > 0) {
            if (EVP_DecryptUpdate(ctx, outbuf, &len, combined, (int)emit_len) <= 0) die_ssl("DecryptUpdate failed");
            if (len > 0 && (size_t)fwrite(outbuf, 1, (size_t)len, out) != (size_t)len) die_msg("plaintext write failed");
        }
        memcpy(hold, combined + emit_len, GCM_TAG_LEN);
        hold_len = GCM_TAG_LEN;
        OPENSSL_free(combined);
    }

    if (hold_len != GCM_TAG_LEN) die_msg("truncated input: missing GCM tag");
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, GCM_TAG_LEN, hold) <= 0) die_ssl("SET_TAG failed");
    if (EVP_DecryptFinal_ex(ctx, outbuf, &len) <= 0) die_msg("GCM authentication failed");
    if (len > 0 && (size_t)fwrite(outbuf, 1, (size_t)len, out) != (size_t)len) die_msg("final plaintext write failed");

    EVP_CIPHER_CTX_free(ctx);
    secure_free(hold, GCM_TAG_LEN);
    secure_free(inbuf, IO_CHUNK);
    secure_free(outbuf, IO_CHUNK + 32);
}

static int cmd_encrypt(const char *pq_pub_path, const char *rsa_pub_path) {
    EVP_PKEY *pq_pub = load_pubkey(pq_pub_path);
    EVP_PKEY *rsa_pub = load_pubkey(rsa_pub_path);
    unsigned char *pq_ct = NULL, *pq_ss = NULL, *rsa_ct = NULL;
    size_t pq_ct_len = 0, pq_ss_len = 0, rsa_ct_len = 0;
    unsigned char rsa_seed[RSA_SEED_LEN], aes_key[AES_KEY_LEN], iv[GCM_IV_LEN], tag[GCM_TAG_LEN];
    unsigned char aad[MAGIC_LEN + 4 + 4 + GCM_IV_LEN];

    kem_encap(pq_pub, &pq_ct, &pq_ct_len, &pq_ss, &pq_ss_len);
    if (RAND_bytes(rsa_seed, sizeof(rsa_seed)) <= 0) die_ssl("RAND_bytes failed");
    rsa_oaep_encrypt(rsa_pub, rsa_seed, sizeof(rsa_seed), &rsa_ct, &rsa_ct_len);
    sha256_concat(pq_ss, pq_ss_len, rsa_seed, sizeof(rsa_seed), aes_key);
    if (RAND_bytes(iv, sizeof(iv)) <= 0) die_ssl("RAND_bytes failed");

    if (fwrite(MAGIC, 1, MAGIC_LEN, stdout) != MAGIC_LEN) die_msg("write magic failed");
    write_u32_be(stdout, (uint32_t)pq_ct_len);
    write_u32_be(stdout, (uint32_t)rsa_ct_len);
    if (fwrite(iv, 1, GCM_IV_LEN, stdout) != GCM_IV_LEN) die_msg("write iv failed");
    if (fwrite(pq_ct, 1, pq_ct_len, stdout) != pq_ct_len) die_msg("write pq ct failed");
    if (fwrite(rsa_ct, 1, rsa_ct_len, stdout) != rsa_ct_len) die_msg("write rsa ct failed");

    memcpy(aad, MAGIC, MAGIC_LEN);
    aad[8] = (unsigned char)((pq_ct_len >> 24) & 0xff);
    aad[9] = (unsigned char)((pq_ct_len >> 16) & 0xff);
    aad[10] = (unsigned char)((pq_ct_len >> 8) & 0xff);
    aad[11] = (unsigned char)(pq_ct_len & 0xff);
    aad[12] = (unsigned char)((rsa_ct_len >> 24) & 0xff);
    aad[13] = (unsigned char)((rsa_ct_len >> 16) & 0xff);
    aad[14] = (unsigned char)((rsa_ct_len >> 8) & 0xff);
    aad[15] = (unsigned char)(rsa_ct_len & 0xff);
    memcpy(aad + 16, iv, GCM_IV_LEN);

    gcm_encrypt_forward(stdin, stdout, aes_key, iv, aad, sizeof(aad), tag);
    if (fwrite(tag, 1, GCM_TAG_LEN, stdout) != GCM_TAG_LEN) die_msg("write tag failed");

    EVP_PKEY_free(pq_pub);
    EVP_PKEY_free(rsa_pub);
    secure_free(pq_ct, pq_ct_len);
    secure_free(pq_ss, pq_ss_len);
    secure_free(rsa_ct, rsa_ct_len);
    OPENSSL_cleanse(rsa_seed, sizeof(rsa_seed));
    OPENSSL_cleanse(aes_key, sizeof(aes_key));
    OPENSSL_cleanse(iv, sizeof(iv));
    OPENSSL_cleanse(tag, sizeof(tag));
    return 0;
}

static int cmd_decrypt(const char *pq_priv_path, const char *rsa_priv_path) {
    EVP_PKEY *pq_priv = load_privkey(pq_priv_path);
    EVP_PKEY *rsa_priv = load_privkey(rsa_priv_path);
    unsigned char magic[MAGIC_LEN], iv[GCM_IV_LEN];
    unsigned char *pq_ct = NULL, *rsa_ct = NULL, *pq_ss = NULL, *rsa_seed = NULL;
    size_t pq_ct_len = 0, rsa_ct_len = 0, pq_ss_len = 0, rsa_seed_len = 0;
    unsigned char aes_key[AES_KEY_LEN];
    unsigned char aad[MAGIC_LEN + 4 + 4 + GCM_IV_LEN];

    if (fread(magic, 1, MAGIC_LEN, stdin) != MAGIC_LEN) die_msg("short read on magic");
    if (memcmp(magic, MAGIC, MAGIC_LEN) != 0) die_msg("bad magic");
    pq_ct_len = read_u32_be(stdin);
    rsa_ct_len = read_u32_be(stdin);
    if (fread(iv, 1, GCM_IV_LEN, stdin) != GCM_IV_LEN) die_msg("short read on iv");

    pq_ct = OPENSSL_malloc(pq_ct_len);
    rsa_ct = OPENSSL_malloc(rsa_ct_len);
    if (!pq_ct || !rsa_ct) die_msg("alloc failed");
    if (fread(pq_ct, 1, pq_ct_len, stdin) != pq_ct_len) die_msg("short read on pq ct");
    if (fread(rsa_ct, 1, rsa_ct_len, stdin) != rsa_ct_len) die_msg("short read on rsa ct");

    kem_decap(pq_priv, pq_ct, pq_ct_len, &pq_ss, &pq_ss_len);
    rsa_oaep_decrypt(rsa_priv, rsa_ct, rsa_ct_len, &rsa_seed, &rsa_seed_len);
    if (rsa_seed_len != RSA_SEED_LEN) die_msg("unexpected rsa seed length");
    sha256_concat(pq_ss, pq_ss_len, rsa_seed, rsa_seed_len, aes_key);

    memcpy(aad, MAGIC, MAGIC_LEN);
    aad[8] = (unsigned char)((pq_ct_len >> 24) & 0xff);
    aad[9] = (unsigned char)((pq_ct_len >> 16) & 0xff);
    aad[10] = (unsigned char)((pq_ct_len >> 8) & 0xff);
    aad[11] = (unsigned char)(pq_ct_len & 0xff);
    aad[12] = (unsigned char)((rsa_ct_len >> 24) & 0xff);
    aad[13] = (unsigned char)((rsa_ct_len >> 16) & 0xff);
    aad[14] = (unsigned char)((rsa_ct_len >> 8) & 0xff);
    aad[15] = (unsigned char)(rsa_ct_len & 0xff);
    memcpy(aad + 16, iv, GCM_IV_LEN);

    gcm_decrypt_forward(stdin, stdout, aes_key, iv, aad, sizeof(aad));

    EVP_PKEY_free(pq_priv);
    EVP_PKEY_free(rsa_priv);
    secure_free(pq_ct, pq_ct_len);
    secure_free(rsa_ct, rsa_ct_len);
    secure_free(pq_ss, pq_ss_len);
    secure_free(rsa_seed, rsa_seed_len);
    OPENSSL_cleanse(aes_key, sizeof(aes_key));
    OPENSSL_cleanse(iv, sizeof(iv));
    return 0;
}

static void usage(void) {
    fprintf(stderr,
        "Usage:\n"
        "  pqhyb_stream_streaming encrypt --pq-pubkey pq_pub.pem --rsa-pubkey rsa_pub.pem < plaintext > ciphertext\n"
        "  pqhyb_stream_streaming decrypt --pq-privkey pq_priv.pem --rsa-privkey rsa_priv.pem < ciphertext > plaintext\n"
        "\n"
        "Forward-only format PQHS02 supports pipes and rclone rcat/cat style streaming.\n");
}

int main(int argc, char **argv) {
    const char *pq_pub = NULL, *pq_priv = NULL, *rsa_pub = NULL, *rsa_priv = NULL;
    int enc = 0, dec = 0;

    if (argc < 2) {
        usage();
        return 2;
    }
    if (strcmp(argv[1], "encrypt") == 0) enc = 1;
    else if (strcmp(argv[1], "decrypt") == 0) dec = 1;
    else {
        usage();
        return 2;
    }

    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--pq-pubkey") == 0 && i + 1 < argc) pq_pub = argv[++i];
        else if (strcmp(argv[i], "--pq-privkey") == 0 && i + 1 < argc) pq_priv = argv[++i];
        else if (strcmp(argv[i], "--rsa-pubkey") == 0 && i + 1 < argc) rsa_pub = argv[++i];
        else if (strcmp(argv[i], "--rsa-privkey") == 0 && i + 1 < argc) rsa_priv = argv[++i];
        else {
            usage();
            return 2;
        }
    }

    if (enc) {
        if (!pq_pub || !rsa_pub) {
            usage();
            return 2;
        }
        return cmd_encrypt(pq_pub, rsa_pub);
    }
    if (!pq_priv || !rsa_priv) {
        usage();
        return 2;
    }
    return cmd_decrypt(pq_priv, rsa_priv);
}

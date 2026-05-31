# PQ Hybrid Stream Encryption Toolkit Security Review

This document lists 10 potential weaknesses in the project from a cyber security and cryptographic perspective, ordered by importance, with suggested mitigations.

## 1. Streaming AES-GCM design and decryption buffering

The streaming helper implements AES-GCM as a single long stream with the authentication tag placed at the end. Decryption then buffers the trailing bytes that may contain the final tag while streaming the rest into the GCM state. This is a subtle and error-prone construction. Small mistakes in the buffering logic, such as off-by-one errors or accidentally authenticating the tag bytes as ciphertext, can break integrity or create exploitable decryption behavior.[cite:1][cite:2][cite:3]

### Why it matters

- Bugs in end-of-stream handling may not appear in normal round-trip tests.
- Malformed ciphertexts, truncation, or boundary cases can exercise parser and buffering flaws.
- A mistake here can undermine the authentication guarantees of AES-GCM even if the primitives themselves are sound.[cite:1][cite:2]

### Possible mitigations

- Replace the single-stream trailer-tag design with a chunked AEAD format where each chunk carries its own tag.
- If trailer-tag GCM is retained, create exhaustive tests for truncation, byte flips, split boundaries, and reordered fragments.
- Use a design review or formal model specifically focused on the decrypt state machine and boundary conditions.
- Consider an AEAD or framing design with safer streaming properties if operationally acceptable.[cite:1][cite:2][cite:4]

## 2. AES-GCM misuse risks: IV uniqueness, key reuse, and volume limits

AES-256-GCM is secure only when each key and IV pair is unique. If the same key and IV are ever reused, the mode can fail catastrophically, enabling confidentiality loss and potentially tag forgery. Even when IVs are randomly generated, large numbers of encryptions under the same key increase the probability of collisions, and AES-GCM also has practical limits on the amount of data safely processed under a given key.[cite:3][cite:5]

### Why it matters

- Random IV generation is not a complete lifecycle policy.
- Long-lived keys and high message counts increase risk over time.
- Operators may incorrectly assume GCM is tolerant of accidental nonce reuse when it is not.[cite:3][cite:5]

### Possible mitigations

- Enforce a strict per-key message limit and rotate keys before hitting that threshold.
- Use deterministic counters or a structured nonce derivation scheme when possible, rather than relying purely on random IVs.
- Record per-key usage metrics to prevent excessive volume under one keypair.
- Consider nonce-misuse-resistant alternatives such as AES-GCM-SIV or designs with stronger misuse tolerance if compatible with requirements.[cite:3][cite:5][cite:6]

## 3. Hybrid KEM plus RSA design is ad hoc and not formally analyzed

The project combines a PQ KEM shared secret and an RSA-OAEP encrypted random seed, then hashes both values together with SHA-256 to derive the content-encryption key. This is intuitively reasonable, but it is an ad hoc hybrid combiner rather than a construction aligned with a widely deployed standard or accompanied by a proof of security. There is also no explicit context string or domain separation in the derivation.[cite:7][cite:8]

### Why it matters

- It is harder to reason about the exact security level of the combined design.
- Future maintainers may reuse the same derivation logic in other contexts incorrectly.
- The RSA branch adds complexity without a clear proof that the result achieves the intended “best of both” hybrid security property.[cite:7][cite:8]

### Possible mitigations

- Replace raw SHA-256 concatenation with HKDF and explicit domain separation labels.
- Document a precise hybrid security goal and tie the design to a known combiner pattern.
- Consider removing RSA entirely unless there is a concrete migration or compliance need for it.
- If a hybrid is required, adopt a better-studied combination pattern and encode algorithm identifiers into the header and derivation context.[cite:7][cite:8]

## 4. Reliance on raw OpenSSL EVP KEM and RSA APIs with minimal hardening

The implementation uses low-level OpenSSL EVP interfaces for encapsulation, decapsulation, RSA-OAEP encryption, and AES-GCM processing. These APIs are powerful but easy to misuse. Behavior can differ depending on OpenSSL version, provider configuration, available algorithms, and parameter defaults. A subtle mismatch in key type, provider priority, or parameterization can change security properties or simply break interoperability.[cite:9][cite:10][cite:11]

### Why it matters

- Different environments may resolve ML-KEM or related key types differently.
- Provider order and runtime configuration can change the effective algorithm implementation.
- Low-level API use increases the chance of side-channel differences, error-path leaks, or inconsistent behavior across systems.[cite:9][cite:10]

### Possible mitigations

- Pin and document the exact supported OpenSSL and provider versions.
- Add explicit runtime checks for key type, algorithm identity, provider presence, and expected parameterization.
- Encode algorithm metadata in the file format so mismatches are detected early.
- Create cross-version interoperability tests and fail closed on unexpected runtime environments.[cite:9][cite:10][cite:11]

## 5. No protocol-level replay or misuse protection

The ciphertext format provides confidentiality and integrity for one blob, but it does not include protocol-level replay protection, sequence numbering, timestamps, or binding to a logical backup identity. An attacker who can modify stored objects may be able to replay older valid ciphertexts without cryptographic detection by the decryptor itself.[cite:3][cite:4]

### Why it matters

- Restoring an old but valid backup may be as damaging as direct tampering.
- Reordering or replay attacks are not prevented by AEAD alone.
- The project currently authenticates the blob contents, not the operational context in which the blob is supposed to be used.[cite:3]

### Possible mitigations

- Bind object identifiers, timestamps, backup set names, or sequence numbers into AAD.
- Maintain an authenticated manifest or signed index of expected backup versions.
- Add a freshness or monotonic counter mechanism at the application layer.
- Treat replay detection as part of the storage protocol, not only the encryption format.[cite:4][cite:8]

## 6. Single-stream GCM makes partial corruption attacks harder to detect early

In a fully streaming decrypt pipeline, plaintext may be emitted before the final GCM tag is verified. If authentication fails at the end, downstream consumers may already have received and perhaps acted upon unauthenticated plaintext. This is an inherent operational risk of trailer-tag AEAD streaming when consumers are not designed to buffer and discard output on failure.[cite:1][cite:2]

### Why it matters

- A consumer might process corrupt data before the pipeline reports failure.
- Shell pipelines often do not guarantee that partially emitted output is rolled back.
- The correctness burden shifts from the cryptographic layer to the calling environment.[cite:1][cite:2]

### Possible mitigations

- Buffer decrypted output to a temporary file or memory region and release it only after successful tag verification.
- Switch to chunked encryption so each chunk is authenticated before release.
- Document clearly that downstream consumers must treat any decrypt failure as fatal and discard partial output.
- Provide a safe wrapper that stages output before handing it to the final consumer.[cite:1][cite:4]

## 7. RSA component may be legacy baggage with unnecessary attack surface

The design uses both a PQ KEM and RSA-OAEP for each encryption. While this may be intended as a defense-in-depth or migration strategy, RSA is not post-quantum secure and it adds implementation complexity, additional key management, and more code that can fail or leak information. In many modern migration designs, the hybrid is built from two key-establishment mechanisms with clearer combiner guidance rather than from PQ KEM plus RSA encryption of a seed.[cite:7][cite:12]

### Why it matters

- More code paths mean more opportunities for implementation bugs.
- More keys mean more operational burden and more chances of private-key exposure.
- The project may end up looking more complex than its real security benefit justifies.[cite:7][cite:12]

### Possible mitigations

- Reassess whether RSA is genuinely needed for the threat model.
- Prefer a simpler, better-justified hybrid or a PQ-only mode if appropriate.
- If RSA remains, separate the rationale clearly in the documentation and state what security benefit it is intended to add.
- Add algorithm negotiation or versioning so RSA can be cleanly phased out later.[cite:7][cite:12]

## 8. Container format lacks explicit versioning and algorithm identifiers

The current forward-only format relies on a magic value and ciphertext lengths, but does not fully encode algorithm identifiers, parameter sets, or detailed protocol version metadata. This makes future upgrades, algorithm migrations, and compatibility management harder. It also increases the risk of format confusion and downgrade-style mistakes in multi-version deployments.[cite:8]

### Why it matters

- Future changes to KEM type, RSA policy, or AEAD mode may become hard to introduce safely.
- Operators may not be able to tell which algorithms were used for a given blob.
- Parsers may accept inputs that are structurally valid but semantically unexpected.[cite:8]

### Possible mitigations

- Add an explicit version field and algorithm identifiers to the header.
- Include parameter-set identifiers such as the KEM name and RSA key policy.
- Bind these identifiers into the AAD so tampering is detected.
- Define a strict compatibility policy and reject unsupported combinations.[cite:8][cite:10]

## 9. Key lifecycle, entropy, and environment assumptions

The project assumes that OpenSSL’s random number generator is properly initialized, that the execution environment is trustworthy, and that key files are securely generated and stored. It also doubles the amount of private key material by requiring both PQ and RSA keys. These are not flaws in the primitives, but they are realistic security weak points in deployment.[cite:9][cite:10]

### Why it matters

- Weak entropy at key generation time can permanently weaken the system.
- Long-lived or poorly protected private keys create a practical attack surface.
- Additional sensitive key files mean more opportunities for accidental exposure or backup leakage.[cite:9]

### Possible mitigations

- Use hardened key generation hosts and verify entropy quality in deployment environments.
- Support hardware-backed or encrypted private key storage where possible.
- Define key rotation intervals and revocation procedures.
- Minimize the number of long-lived private keys by simplifying the design if possible.[cite:9][cite:12]

## 10. Lack of formal security model, negative tests, and misuse guidance

The project is a custom cryptographic construction and currently lacks a formal security model, a written misuse analysis, and a comprehensive adversarial test suite. Standard round-trip tests are necessary but not sufficient. Without negative tests and explicit misuse guidance, subtle vulnerabilities can survive for a long time undetected.[cite:8]

### Why it matters

- Developers often overestimate what passing round-trip tests actually prove.
- Custom crypto formats are vulnerable to strange malformed-input cases that only appear under adversarial testing.
- Future refactors may weaken security without obvious functional regressions.[cite:8]

### Possible mitigations

- Write a security model that defines attacker capabilities, trust assumptions, and desired guarantees.
- Add fuzzing, truncation tests, tamper tests, replay tests, wrong-key tests, and cross-version tests.
- Document safe and unsafe usage patterns in the main README and technical documentation.
- Consider an external security review once the format and implementation stabilize.[cite:8][cite:10]

## Appendix D: Test Vectors (Forthcoming) {#appendix-d-test-vectors-forthcoming}

This appendix will provide byte-level test vectors for independent implementation verification. Test vectors will be generated from the reference algorithms in Appendix A after all wire format changes are finalized. The following areas will be covered:

1. **MIID computation** — `(source_CA, timestamp_24h, msg_counter)` inputs with expected MIID32 and MIID40 hex outputs for both addressing modes.
2. **Packet serialization** — Complete Status, Event, Request, and Response packets (8-bit and 16-bit modes, with and without optional fields) as annotated hex byte sequences with field boundary markers.
3. **Nonce construction** — Header field values mapped to the 16-byte nonce for each packet class, including the Response nonce field mapping ([Section 12.2.2](#1222-nonce-derivation), *Nonce construction*).
4. **Address derivation** — `(network_id, uid)` inputs through SHA-256, base address extraction, and conflict-step derivation for both addressing modes.
5. **TTL encoding round-trip** — Encode and decode at each piecewise boundary (0, 30, 60, 90, 120, 180, 255) to verify the non-linear encoding.
6. **CMAC authentication tag** — Tag computation including header AAD construction for each packet class ([Section 12.2.3](#1223-authentication-tag), *Tag computation*), with 4-byte, 8-byte, and 16-byte truncation outputs.
7. **Encryption round-trip** — Plaintext payload through nonce construction, AES-256-CTR encryption, and decryption, verifying ciphertext and recovered plaintext match.
8. **Fragment byte-range coverage** — Coverage tracking and redundancy decisions for overlapping fragments, re-fragmented fragments, and cross-form interactions.

Each test vector will include all intermediate values (hash digests, derived keys, nonce bytes) to enable implementers to isolate errors at each computation step.

---

*End of specification.*

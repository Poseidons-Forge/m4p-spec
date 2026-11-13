<!--
Copyright (c) 2026 Poseidon's Forge, Inc. All rights reserved.

This work is licensed under the Creative Commons Attribution 4.0
International License. To view a copy of this license, visit
https://creativecommons.org/licenses/by/4.0/

You are free to share (copy and redistribute) and adapt (remix, transform,
and build upon) this material in any medium or format for any purpose,
including commercial, under the following terms:
- Attribution: You must give appropriate credit to Poseidon's Forge, Inc.,
  provide a link to the license, and indicate if changes were made.
-->

## Appendix D: Test Vectors (Forthcoming) {#appendix-d-test-vectors-forthcoming}

This appendix will provide byte-level test vectors for independent implementation verification. Test vectors will be generated from the reference algorithms in Appendix A after all wire format changes are finalized; the payload form key vectors of [Appendix D.10](#d10-payload-form-keys) are published ahead of the rest. The following areas will be covered:

1. **MIID computation** — `(source_CA, timestamp_24h, msg_counter)` inputs with expected MIID32 and MIID40 hex outputs for both addressing modes.
2. **Packet serialization** — Complete Status, Event, Request, and Response packets (8-bit and 16-bit modes, with and without optional fields) as annotated hex byte sequences with field boundary markers.
3. **Nonce construction** — Header field values mapped to the 16-byte nonce for each packet class, including the Response nonce field mapping ([Section 12.2.2](#1222-nonce-derivation), *Nonce construction*).
4. **Address derivation** — `(network_id, uid)` inputs through SHA-256, base address extraction, and conflict-step derivation for both addressing modes.
5. **TTL encoding round-trip** — Encode and decode at each piecewise boundary (0, 30, 60, 90, 120, 180, 255) to verify the non-linear encoding.
6. **CMAC authentication tag** — Tag computation including header AAD construction for each packet class ([Section 12.2.3](#1223-authentication-tag), *Tag computation*), with 4-byte, 8-byte, and 16-byte truncation outputs.
7. **Encryption round-trip** — Plaintext payload through nonce construction, AES-256-CTR encryption, and decryption, verifying ciphertext and recovered plaintext match.
8. **Fragment byte-range coverage** — Coverage tracking and redundancy decisions for overlapping fragments, re-fragmented fragments, and interactions between fragmented and unfragmented copies.
9. **Payload forms** (placeholder) — for one message type: the plain input, its full compressed form, every degraded rung, the rungs rebuilt from a middle rung ([Section 9.11.2](#9112-degraded-rungs)), and its type identity at `compressed_encoding_version` 1 with every intermediate serialization ([Section 12.7.2](#1272-type-identity)).
10. **Payload form keys** — the plain key, the compressed key for two total lengths and two type identities, and both tag keys, with a compressed ciphertext encrypted whole and sliced into fragments ([Section 12.7](#127-payload-form-keys)). See [Appendix D.10](#d10-payload-form-keys).
<!-- PSFI-3515 (per-link compression) items 9 and 10, and the rewording of item 8, drafted by a Claude agent. -->

Each test vector will include all intermediate values (hash digests, derived keys, nonce bytes) to enable implementers to isolate errors at each computation step.

### D.10 Payload Form Keys {#d10-payload-form-keys}

These vectors start from a master PSK, derive one epoch key ([Section 12.4.1](#1241-payload-cipher-key)), derive the payload keys and tag keys of both payload forms from it ([Section 12.7](#127-payload-form-keys)), and encrypt one compressed payload whole and slice its ciphertext into fragments ([Section 12.2.5](#1225-fragmentation-interaction)). They were computed from the formulas of those sections.

All values are hexadecimal. Every HKDF is HKDF-Expand with SHA-256 and `L = 32`, with no HKDF-Extract. An `info` string printed over several lines is one octet string, read top to bottom; the right-hand column names each part. The two type identities are arbitrary 32-octet values, not derived from a DCCL definition (item 9 covers that derivation). Authentication tags are not covered here.

**Inputs.**

```text
master_psk       000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
network_id       "m4p-vector-net", UTF-8 (14 octets): 6d34702d766563746f722d6e6574
unix_seconds     1794574800  (2026-11-13T13:00:00Z)
P                43200       (12 hours)
epoch_number     41541 = floor(1794574800 / 43200)
type_identity A  a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf
type_identity B  c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf
```

**Epoch key** ([Section 12.4.1](#1241-payload-cipher-key)). PRK is `master_psk`; `info` is 31 octets.

```text
info       4d34502d65706f6368              "M4P-epoch"
           6d34702d766563746f722d6e6574    network_id
           000000000000a245                epoch_number, u64 big-endian
epoch_key  8448af2eb908a384c93d09bb93b7a4d98251183326cea9fe214f36c6de77d136
```

The epoch key is the active payload cipher key, the PRK of every key below.

**Payload keys** ([Section 12.7.1](#1271-key-derivation)). The plain `info` is 9 octets; each compressed `info` is 42 octets.

```text
plain_key
  info  4d34502d706c61696e                                                "M4P-plain"
  key   54ffeff055fa76c8cbcc093604d262c5dd4b45a0fbaada5182be18ceb694e084

compressed_key, type identity A, total length 37
  info  4d34502d636f6d70                                                  "M4P-comp"
        a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf  type_identity A
        0025                                                              total_length_be16
  key   3b2b867be0812ed3e193dbe6f7b8a52ad0f110b1b889032a2f6feffb61fa25ce

compressed_key, type identity A, total length 300
  info  4d34502d636f6d70                                                  "M4P-comp"
        a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf  type_identity A
        012c                                                              total_length_be16
  key   c10b84f2d67161ab0ce50a11ce10ed65b23dc3fb7e1a488a513318ab2c3c7235

compressed_key, type identity B, total length 37
  info  4d34502d636f6d70                                                  "M4P-comp"
        c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf  type_identity B
        0025                                                              total_length_be16
  key   e9d7da709bd529da793c4dc893145aac322574370cb29a469ef3f7006f8747f7

compressed_key, type identity B, total length 300
  info  4d34502d636f6d70                                                  "M4P-comp"
        c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf  type_identity B
        012c                                                              total_length_be16
  key   6845e9eeea1f00558e65852e747c3a9fc6977110746a0ba992baaf4f0cc0403c
```

**Tag keys** ([Section 12.7.3](#1273-tag-keys)). Each compressed tag `info` is 44 octets.

```text
plain_tag_key (the active key, equal to epoch_key)
  key   8448af2eb908a384c93d09bb93b7a4d98251183326cea9fe214f36c6de77d136

compressed_tag_key, type identity A
  info  4d34502d636f6d702d746167                                          "M4P-comp-tag"
        a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf  type_identity A
  key   3a434d195bbdca83219315f139c6ea61f32973bd69d52fad0a22f7ec5ff8b6aa

compressed_tag_key, type identity B
  info  4d34502d636f6d702d746167                                          "M4P-comp-tag"
        c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf  type_identity B
  key   284a76a7b0d1cad33f4aad9969600c7a895bc89f9de279e02cf7de32b5e171dc
```

**Nonce** ([Section 12.2.2](#1222-nonce-derivation)). A Status message of type 1234 in 8-bit addressing, with `fragment_offset = 0` for whole-payload encryption.

```text
SHA-256(network_id)  d6c835cf8883d47a8d3661bcca0b3f8ee6f27245074e65881376b1394537598e

field            value                    octets
network_id_hash  first 4 octets of hash   d6c835cf
source_ca        0xa7                     00a7
timestamp_24h    74096  (20:34:56)        012170
msg_counter      0x5b                     5b
message_type_id  1234                     04d2
fragment_offset  0                        0000
reserved                                  0000

nonce            d6c835cf00a70121705b04d200000000
```

**Compressed payload, encrypted whole and sliced** ([Section 12.2.5](#1225-fragmentation-interaction)). A 37-octet compressed payload of type identity A, encrypted with AES-256-CTR under `compressed_key` (type identity A, total length 37), with the nonce above as the initial counter block. The ciphertext is then sliced at fragment offsets 0, 13 and 26.

```text
plaintext   404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f6061626364
key         3b2b867be0812ed3e193dbe6f7b8a52ad0f110b1b889032a2f6feffb61fa25ce
nonce       d6c835cf00a70121705b04d200000000
ciphertext  0524531e1e61a7e6b16e4505e079ea4ec90fad5645e33ab6e2165ea49410c459250306225e

fragment at offset  0 (13 octets)  0524531e1e61a7e6b16e4505e0
fragment at offset 13 (13 octets)  79ea4ec90fad5645e33ab6e216
fragment at offset 26 (11 octets)  5ea49410c459250306225e
```

A receiver that reassembles the three fragments holds the 37-octet ciphertext, derives the same `compressed_key` from the total length, and decrypts with the nonce at `fragment_offset = 0`.
<!-- PSFI-3515 (per-link compression) Appendix D.10 drafted by a Claude agent, with values computed independently from Sections 12.2.2, 12.4.1 and 12.7. -->

---

*End of specification.*

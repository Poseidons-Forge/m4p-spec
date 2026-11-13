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

## 14. Normative References {#14-normative-references}

The following documents are referenced in normative portions of this specification. Implementers MUST understand these documents to correctly implement the M4P protocol.

- **[RFC2119]** Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, March 1997. Referenced in [Section 1.3](#13-conventions) for MUST/SHOULD/MAY keyword interpretation.

- **[FIPS180-4]** National Institute of Standards and Technology, "Secure Hash Standard (SHS)", FIPS PUB 180-4, August 2015. SHA-256 is used in address derivation ([Section 11.1](#111-address-derivation-and-versioning)), nonce construction ([Section 12.2.2](#1222-nonce-derivation), *Nonce construction*), and client address fingerprint ([Appendix A.6](#a6-client-address-fingerprint)).

- **[FIPS197]** National Institute of Standards and Technology, "Advanced Encryption Standard (AES)", FIPS PUB 197, November 2001. AES-256 is the block cipher underlying the M4P payload cipher and CMAC authentication.

- **[SP800-38A]** Dworkin, M., "Recommendation for Block Cipher Modes of Operation: Methods and Techniques", NIST Special Publication 800-38A, December 2001. Defines AES-CTR mode used by the M4P payload cipher ([Section 12.2](#122-m4p-payload-cipher)).

- **[SP800-38B]** Dworkin, M., "Recommendation for Block Cipher Modes of Operation: The CMAC Mode for Authentication", NIST Special Publication 800-38B, May 2005. Defines AES-CMAC used for the authentication tag ([Section 12.2.3](#1223-authentication-tag), *Tag computation*).

- **[RFC5869]** Krawczyk, H. and P. Eronen, "HMAC-based Extract-and-Expand Key Derivation Function (HKDF)", RFC 5869, May 2010. Defines HKDF; pinned as HKDF-SHA-256 for epoch keys ([Section 12.4.1](#1241-payload-cipher-key)) and for payload form keys and tag keys ([Section 12.7](#127-payload-form-keys)).

- **[DCCL]** GobySoft, "Dynamic Compact Control Language (DCCL)", version 5.0.0, https://libdccl.org (source: https://github.com/GobySoft/dccl, tag `5.0.0`). Defines the encoding of the compressed payload form ([Section 9.11.1](#9111-compressed-encoding)); `compressed_encoding_version` 1 uses this version ([Section 12.7.2](#1272-type-identity)).

- **[DCCL-RS]** Poseidon's Forge, Inc., "dccl-rs: Rust wrapper for DCCL v5", crate `dccl` version 0.1.0, commit `212b2b155e8d3eca5274e02bbff206481c6ccdaf`, https://github.com/Poseidons-Forge/dccl-rs. Its `MessageFingerprint` computation defines the per-type fingerprint in the type identity ([Section 12.7.2](#1272-type-identity)).

<!-- PSFI-3515 (per-link compression) [DCCL] version and [DCCL-RS] entry drafted by a Claude agent. -->

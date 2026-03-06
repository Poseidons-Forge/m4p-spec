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

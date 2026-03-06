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

## 15. Informative References {#15-informative-references}

The following documents are referenced for background and context. They are not required for implementation.

- **[RFC9171]** Burleigh, S., Fall, K., and E. Birrane, "Bundle Protocol Version 7", RFC 9171, January 2022. The IETF's delay-tolerant networking protocol; M4P references the Bundle Protocol's custody transfer model in [Section 2.8](#28-relationship-to-existing-standards-non-normative) as a design contrast.

- **[RFC5050]** Scott, K. and S. Burleigh, "Bundle Protocol Specification", RFC 5050, November 2007. The predecessor DTN Bundle Protocol, referenced alongside RFC 9171.

- **[RFC3552]** Rescorla, E. and B. Korver, "Guidelines for Writing RFC Text on Security Considerations", BCP 72, RFC 3552, July 2003. Guidance document for security analysis methodology.

- **[RFC5869]** Krawczyk, H. and P. Eronen, "HMAC-based Extract-and-Expand Key Derivation Function (HKDF)", RFC 5869, May 2010. HKDF is recommended for epoch key derivation in [Section 12.4.1](#1241-payload-cipher-key).

- **[SP800-108r1]** Chen, L., "Recommendation for Key Derivation Using Pseudorandom Functions", NIST Special Publication 800-108 Revision 1, August 2022. Alternative KDF referenced in [Section 12.4.1](#1241-payload-cipher-key) guidance.

---

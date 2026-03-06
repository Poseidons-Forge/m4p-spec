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

## 1. Introduction {#1-introduction}

### 1.1 Purpose

This document specifies the Multi-Modal Maritime Mesh Protocol (M4P), a delay-tolerant, store-carry-forward networking protocol designed for heterogeneous maritime communication environments. M4P provides reliable message exchange across multiple data link modalities — including, but not limited to, acoustic, radio, satellite, and IP-based links — under conditions of intermittent connectivity, extreme bandwidth constraints, and dynamic network topology.

### 1.2 Scope

This specification defines:

- The on-wire packet formats for all M4P message classes.
- The identity and addressing model used to identify nodes and application endpoints.
- The transport layer semantics governing message instance tracking, deduplication, expiration, fragmentation, store-carry-forward forwarding, and transmission scheduling.
- The DataLink abstraction boundary that separates protocol logic from modality-specific mechanics.
- The network layer protocols for address assignment, conflict resolution, peer discovery, and fleet membership.
- The encryption model for payload confidentiality and integrity, including the M4P payload cipher and DataLink-layer security.

This specification does not define:

- Application-layer message payload schemas or type allocations (these are deployment-specific).
- Implementation-specific APIs, deployment configurations, or runtime architectures.

### 1.3 Conventions

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

### 1.4 Normative Classification

Requirements in this specification fall into three categories, indicated by markers at the beginning of each major section:

**[WIRE FORMAT]** — On-wire protocol requirements. These define packet formats, field encodings, Message Instance ID (MIID) computation, Network Control (NC) message payload structures, encryption nonce construction, and any other aspect that two independent implementations MUST agree on to exchange packets. Deviation from a WIRE FORMAT requirement produces interoperability failure.

**[BEHAVIORAL]** — Node behavior requirements for protocol correctness. These define how a conformant node MUST process, store, forward, deduplicate, and expire packets. Two implementations that follow different behavioral rules may still exchange packets (the wire format is compatible), but the network will not function correctly — messages may loop, duplicates may propagate, conflicts may not resolve.

**[GUIDANCE]** — Recommended implementation practices. These define scheduling heuristics, priority scoring formulas, resend strategies, modality classification, and application design advice. An implementation MAY deviate from guidance without affecting interoperability or correctness, though following the guidance produces better operational behavior.

### 1.5 Conformance

A conformant M4P implementation MUST implement all [WIRE FORMAT] and [BEHAVIORAL] requirements defined in this specification. [GUIDANCE] sections are non-normative; implementations MAY deviate from guidance without affecting conformance or interoperability.

The following features are optional. A conformant implementation MAY omit them:

- **M4P payload cipher** (Section 12). When not supported, the node operates without payload encryption.
- **Authentication tag** (Section 12). When not supported, the `AUTH_TAG_SIZE` field is set to `00` (no tag) on originated packets; received packets with `AUTH_TAG_SIZE ≠ 00` are forwarded without modification.
- **Client address fingerprint** ([Section 5.7.6](#576-optional-field-definitions), [Section 11.9.4](#1194-accelerated-client-address-convergence)). When not supported, the `CA_FINGERPRINT_PRESENT` flag is never set.

Group addressing (`ADDITIONAL_DEST_PRESENT` flag and `additional_destinations` optional field) is a required feature of this protocol version. All conformant implementations MUST parse and correctly handle group Request headers.

Two conformant implementations MUST agree on the following network-wide parameters to interoperate: `network_id`, addressing mode, and (if the payload cipher is used) the cipher key.

### 1.6 Notation

- All multi-byte integers are encoded in **big-endian** (network) byte order.
- Bitfields are shown most-significant bit (MSB) first, bit 7 to bit 0 within each byte.
- Field sizes are specified in bits (b) or bytes (B). Where a field spans a non-byte-aligned boundary, the bit width is given explicitly.
- "(CTE)" denotes Compact Type Encoding as defined in [Section 4.2](#42-compact-type-encoding-cte).

---

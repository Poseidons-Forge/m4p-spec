# M4P: Multi-Modal Maritime Mesh Protocol

Underwater and maritime platforms — autonomous vehicles, sensor buoys, surface relays, shore stations — increasingly need to cooperate as distributed systems. But the networking layer that every other domain takes for granted doesn't exist here. Current options are proprietary, vendor-locked, or simply nonexistent. Every cross-platform integration ends up as a bespoke engineering effort.

M4P aspires to be the open standard that fills that gap: an open, hardware-agnostic networking protocol designed for delay-tolerant maritime mesh networking, where connectivity is intermittent, throughput is scarce, and topology is never fully known.

The physical constraints make this uniquely challenging:

- **Intermittent connectivity.** Vehicles submerge, surface, drift out of range. Contact windows are irregular and unpredictable.
- **Unknown, changing topology.** Mobile nodes make global routing tables impossible to maintain.
- **Extremely constrained throughput.** Some acoustic links carry payloads measured in tens of bytes. TCP/IP headers alone (40+ bytes) can exceed the entire payload budget.
- **Cross-modality communication.** A vehicle might communicate acoustically while submerged, switch to radio on the surface, then relay through satellite to reach shore. A single message may traverse all three link types.

## What M4P Does

M4P defines both a wire protocol and a middleware architecture. The wire protocol specifies compact packet formats, addressing, and encryption. The middleware specifies how a node should behave: how it stores, prioritizes, and forwards messages across links, how it discovers peers, and how it resolves address conflicts. Together, they give applications a single networking layer that works across any combination of acoustic, radio, satellite, and IP links.

This repository contains the **protocol specification** — the document that defines the wire formats and behavioral requirements for an interoperable implementation. For a reference implementation of the middleware, see [Related Projects](#related-projects) below.

Applications send typed messages into the middleware. M4P uses **store-carry-forward** delivery: nodes don't assume end-to-end paths exist. A node stores messages locally and forwards them whenever a transmission opportunity arises on any available link. Messages propagate opportunistically until they reach their destination or expire.

### Architecture

The specification defines three protocol layers:

- **Transport** — packet formats, deduplication, TTL expiration, fragmentation/reassembly, priority scheduling, and store-carry-forward forwarding.
- **Network** — decentralized address assignment, conflict resolution, peer discovery, and fleet membership. No central authority required.
- **DataLink Abstraction** — a narrow interface that separates M4P from physical communication hardware. Each modem or radio implements a simple adapter, making the protocol hardware-agnostic.

Applications interact through four message classes: **Status** (periodic telemetry, latest-value-wins), **Event** (append-retained observations), and **Request/Response** (directed command-and-control with stateless correlation).

### Key Design Points

- **Wire efficiency.** A Status packet header is 8 bytes, compared to ~26 for Bundle Protocol and 40+ for TCP/IP. On a 64-byte acoustic payload, M4P leaves 56 bytes for mission data.
- **Deduplication with zero wire overhead.** Message Instance IDs are computed from fields already in the header, so deduplication costs no additional bytes.
- **Throughput-transparent applications.** Applications produce messages without regard to link capacity. On constrained links, the scheduler selects the highest-value packets that fit the available payload budget.
- **Decentralized addressing.** Nodes derive their own addresses via SHA-256 hash. No pre-mission address planning. Conflicts are resolved deterministically.
- **Cross-modality fragmentation.** A message arriving over a LAN link can be forwarded as fragments over a constrained acoustic link, reassembled at the destination.
- **Security.** AES-256-CTR end-to-end encryption with zero ciphertext expansion. Optional CMAC authentication. Separate DataLink-layer encryption for per-hop protection.

## Reading the Specification

- **PDF** — download the latest rendered specification from the [Releases](../../releases) page.
- **Source** — read the specification directly in the [`sections/`](sections/) folder, ordered by [`sections/order.txt`](sections/order.txt).

To build the PDF yourself, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Feedback

We welcome feedback on the specification. Please join the discussion on the [OceanSoft Forum](https://forum.oceansoft.org/t/introducing-m4p-an-open-protocol-for-delay-tolerant-maritime-mesh-networking/46).

## Related Projects

An open-source reference implementation of the M4P middleware is under active development and will be released soon, including DataLink adapters and Rust and Python SDKs.

## License

The specification is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

[![License: CC BY 4.0](https://licensebuttons.net/l/by/4.0/88x31.png)](https://creativecommons.org/licenses/by/4.0/)

You are free to share and adapt this material for any purpose, including commercial, provided you give appropriate credit to Poseidon's Forge, Inc. and indicate if changes were made. The 'M4P' and 'Maritime Multi-Modal Mesh Protocol' names are unregistered trademarks of Poseidon's Forge, Inc. — modified versions of this specification may not use these names to imply official status or endorsement without written permission. This license applies to the specification documents only — the software implementation is licensed separately under the Apache License 2.0.

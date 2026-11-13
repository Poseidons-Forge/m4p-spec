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

## Appendix C: Application Integration Guidelines (Non-Normative) {#appendix-c-application-integration-guidelines-non-normative}

This appendix provides guidance for application developers on message payload design and effective use of M4P. The recommendations here are non-normative — they represent best practices but are not required for protocol conformance.

**UID-based application API.** Applications interact with M4P exclusively through UIDs (see [Section 2.7](#27-application-layer-responsibilities), [Section 3.1](#31-global-identities)). If the destination ClientUID's address mapping is not yet known at submission time, the transport queues the message in a **pending address resolution** state (see [Section 9.2](#92-per-node-message-store)). Nodes that bootstrap via NC_NETWORK_STATE_REQUEST ([Section 11.7.3](#1173-nc_network_state_response-32002) guidance) will have mappings available shortly after startup, minimizing resolution delay.

**Message Type ID allocation.** M4P does not define or govern specific Message Type IDs within the application ranges (Status `0-7,999`, Event `8,000-9,999`, and Request/Response `10,000-31,998`). Each deployment defines its own message type catalog — the set of type IDs, their payload schemas, and their per-type configuration defaults (priority, TTL). There is no protocol-level registry or coordination mechanism for application type IDs — type allocation is fully owned by each application or deployment. See [Section 4.1](#41-message-type-id-ranges) for the range definitions and [Section 2.4.3](#243-recommended-configuration-should) for per-type configuration guidance.

### C.1 Message Payload Design

Application message payloads SHOULD be designed with the following principles:

**Use compact encoding.** On constrained links where payload budgets may be measured in tens of bytes, encoding efficiency directly determines mission capability. Applications SHOULD:

- Use binary encoding rather than text-based formats (JSON, XML) where feasible.
- Employ fixed-width fields or variable-length encoding appropriate to the data range.
- Avoid redundant or optional metadata that can be inferred from context.
- Consider domain-specific compression for telemetry and sensor data.

**Design for the operating environment.** Effective M4P applications require deliberate message design:

- Prioritize mission-critical information over nice-to-have data.
- Design command payloads to be compact and unambiguous.
- Use bounded Event TTLs on constrained deployments. Event messages are append-retained per message instance, so high-rate event streams can accumulate until expiration.
- Consider the fragmentation threshold: messages requiring fragmentation consume more transmission opportunities and have lower delivery probability on lossy links. This is especially important for Status messages, which are subject to supersession — if a newer Status value arrives before all fragments of the older value are reassembled, the older fragments represent wasted bandwidth and the reassembly buffer is discarded ([Section 8.4.2](#842-status-reassembly-supersession)). Status payloads SHOULD be sized to fit within the smallest expected link budget for any modality the message targets, avoiding fragmentation entirely where possible.

### C.2 Data Link Integration

Data-link adaptation follows the two-mode model in [Section 10.4](#104-data-link-adaptation): link-managed MAC and M4P-managed TDMA.

**Link-managed integration pattern.** The application (or autonomy stack) remains responsible for modem-specific MAC policy in link-managed mode. Typical actions include selecting contention parameters, power profiles, and local TDMA tables through modem-specific control interfaces. M4P remains schedule-agnostic in this mode and consumes only transmission opportunities and budgets from the adapter. Example sequence:

1. A new AUV is deployed mid-mission. It broadcasts NC_NODE_ADDRESS_CLAIM and NC_NODE_SUMMARY.
2. Each existing node's application observes the new peer in the peer registry.
3. Each application reconfigures its local acoustic adapter's TDMA schedule to include a slot for the new node, using the adapter's modem-specific command interface.

M4P is uninvolved in scheduling decisions. The transport layer receives transmission opportunities from the adapter regardless of the underlying MAC state.

**M4P-managed TDMA integration pattern.** In M4P-managed mode, participant convergence and slot assignment are protocol behaviors (NC_TDMA_JOIN, NC_TDMA_SCHEDULE, and the [Section 11.7.18.1](#117181-slot-assignment-algorithm) algorithm). Applications provide baseline timing configuration and operational policy; the M4P runtime derives slot ownership from converged network state and paces send opportunities accordingly. No application logic is needed for TDMA coordination. Example join sequence:

1. A new AUV is deployed mid-mission. It broadcasts NC_NODE_ADDRESS_CLAIM and obtains a CONFIRMED address.
2. The AUV broadcasts NC_TDMA_JOIN for its acoustic modality on all available links.
3. Existing peers receive the join, add the new node to the participant list, and the designated responder broadcasts NC_TDMA_SCHEDULE.
4. All nodes (including the newcomer) compute deterministic slot assignments from the participant list and push updated schedules to their acoustic adapters.
5. On subsequent join/departure events, schedule convergence updates slot ownership without requiring application-level slot-table rewrites.

**What remains application-specific.** M4P does not choose mission policy (for example, which links use link-managed vs M4P-managed mode, how conservative contention timing should be, or which modem-level knobs to tune by mission phase). Applications continue to own those decisions. Temporary schedule inconsistency during transitions is acceptable — M4P's transport layer is schedule-agnostic and sends when the adapter offers an opportunity.

### C.3 Payload Forms and Catalogs {#c3-payload-forms-and-catalogs}

<!-- PSFI-3515 (per-link compression) section drafted by a Claude agent. -->

**What moves.** Messages travel as plain protobuf on links that declare the plain form, and are compressed with DCCL only on links that need it ([Section 9.11](#911-payload-forms)). Clients always submit and receive plain protobuf; the compressed form exists only inside the transport. A node compresses a message when it puts it on a compressed link. No node expands a compressed copy back into the plain form, so a compressed copy stays compressed; a node that holds the plain form still sends plain on links that declare the plain form. <!-- PSFI-3515 (per-link compression) compression path and catalog pairing corrected in review; drafted by a Claude agent. -->

The node that compresses a message, not its origin, must agree with the destination on the type's definition: the destination decodes a compressed copy correctly only when its catalog matches the compressing node's for that type ([Section 12.7.2](#1272-type-identity)). When the origin itself puts the message on the compressed link, the origin and the destination are that pair. When a separate node compresses, such as a topside or cloud gateway, its catalog must track the destination's.

**Which nodes need what.** Every node with a compressed link SHOULD carry the message catalog (the DCCL definitions and retention priorities) and, when the payload cipher is in use, the PSK. Without the catalog a node cannot compress, degrade or decode a type: a plain copy goes out plain on a compressed link, one byte larger, a status that does not fit is not shrunk, and on an encrypted network a tagged compressed packet cannot be re-fragmented ([Section 9.11.5](#9115-re-encoding-at-relays)). A node that holds the PSK can read every payload it relays ([Section 12.6.2](#1262-what-this-model-does-not-provide)).

**Plain-only types.** A message type with no DCCL definition travels plain on every link its modality mask permits. Give a type a DCCL definition when it rides compressed links often enough for its size to matter, and restrict its modality mask when it must never ride them.

**Catalog changes.** A change to a type's DCCL definition or to the retention priority of one of its fields changes its type identity ([Section 12.7.2](#1272-type-identity)) and is a wire change for that type's compressed form. Renaming a field or enum value, editing a comment, or changing `max_bytes`, the type's transport priority, its TTL or its modality mask is not.

---

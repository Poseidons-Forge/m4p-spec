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

Adaptive data link behaviors are the application's responsibility (see [Section 10.4](#104-data-link-adaptation)).

**Example: Acoustic TDMA adaptation.** Consider a deployment using acoustic modems with configurable TDMA scheduling. On startup, the application pre-provisions the TDMA schedule based on the expected fleet composition (matching the M4P network state obtained via NC_NETWORK_STATE_REQUEST/RESPONSE per [Section 11.7.3](#1173-nc_network_state_response-32002) guidance). During operation:

1. A new AUV is deployed mid-mission. It broadcasts NC_NODE_ADDRESS_CLAIM and NC_NODE_SUMMARY.
2. Each existing node's M4P network layer receives the summary and updates its peer registry.
3. Each existing node's application observes the new peer in the registry.
4. Each application reconfigures its local acoustic adapter's TDMA schedule to include a slot for the new node, using the adapter's modem-specific command interface.
5. The new node's application similarly configures its acoustic adapter based on the fleet state it learns from NC_NETWORK_STATE_RESPONSE broadcasts or accumulated NC_NODE_SUMMARY broadcasts.

The M4P protocol is uninvolved in steps 3–5. The transport layer continues to receive transmission opportunities from the adapter and build transmissions — it does not know or care that the TDMA schedule changed. This separation means the same M4P transport code works with TDMA modems, CSMA modems, unscheduled modems, or any future MAC protocol, with only the application-layer integration logic changing.

**What M4P does not provide.** M4P does not guarantee that all nodes will converge on the same TDMA schedule simultaneously. Schedule convergence depends on NC message propagation latency and the application's adaptation logic. During the transition period, some nodes may operate with the old schedule while others have updated. This is acceptable because M4P's transport layer is schedule-agnostic — it sends when the adapter offers an opportunity, regardless of the underlying MAC state. Temporary schedule inconsistency may reduce acoustic throughput but does not cause protocol-level failures.

---

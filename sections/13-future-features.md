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

## 13. Future Features (Non-Normative) {#13-future-features-non-normative}

This section is non-normative. It describes features under consideration for future protocol versions. RFC 2119 keywords are not used; language describes design intent, not binding requirements.

The following capabilities were considered during protocol design and deliberately deferred. The current specification reserves space for their addition in future versions.

### 13.1 Runtime Network ID Management

The `network_id` is currently a static deployment-time parameter ([Section 2.4.2](#242-required-configuration-must)). A future version could define a protocol-native mechanism for runtime `network_id` reassignment, allowing cross-network node management. This requires bypassing `network_id` scoping isolation — a core protocol invariant — likely via unscoped messages addressed by UID rather than CA. Until specified, deployments requiring runtime reconfiguration can use out-of-band mechanisms (e.g., a LAN-based management interface).

### 13.2 Graceful Network Departure

Currently, node departure is detected passively via claim expiration after `expiration_interval` ([Section 11.3](#113-claim-expiration-and-renewal)). A future **NC_NODE_DEPARTURE** message (Announce propagation) would accelerate address reclamation by broadcasting an incremented `address_version` that supersedes the active claim. Claim expiration remains the correctness backstop for unreachable nodes. Key challenges include distinguishing departure from conflict-triggered re-addressing, handling stale state in partitioned networks, and surfacing departure events to the application layer.

### 13.3 Message Type Defaults Synchronization

Per-message-type defaults (priority, TTL, modality mask) are currently static deployment-time parameters ([Section 2.4.3](#243-recommended-configuration-should)). A future version will add NC messages for querying peers' defaults and detecting configuration mismatches.

**On-demand query.** A Query/Answer pair (following the pattern in [Section 11.6.2](#1162-propagation-models)) would allow a node encountering an unknown `message_type_id` to flood a query that is absorbed by any node with configured defaults. Transitive resolution (as with NC_CLIENT_UID_QUERY) would enable learned defaults to propagate. Queries would need rate-limiting to prevent floods from bursts of unknown-type traffic.

**Bulk exchange.** An Announce request/response pair (following the NC_NETWORK_STATE_REQUEST/RESPONSE pattern) would enable rapid bootstrapping and link-local convergence on high-bandwidth links. The response payload (`2 + count × 5` bytes) could require fragmentation, which interacts with the NC no-fragment rule — this interaction needs resolution.

**Mismatch handling.** Unlike address conflicts, default mismatches have no protocol-level resolution; the protocol would detect and surface mismatches to the application layer for operator intervention. NC message type IDs for these four messages are not yet allocated.

### 13.4 Graceful TDMA Departure

Currently, TDMA participant departure is detected passively via claim expiration ([Section 11.3](#113-claim-expiration-and-renewal)). A departed node's TDMA slot remains occupied until its claim expires, wasting airtime on each cycle. More critically, nodes that hold different `claim_renewal_timestamp` values for the departed peer compute different expiration times, producing divergent schedules during the convergence window. Unlike join-case divergence, which the sender-slot mismatch reconciliation mechanism ([Section 11.10.7](#11107-schedule-divergence-and-reconciliation)) can resolve via NC_TDMA_SCHEDULE exchange, departure-case divergence cannot be reconciled by exchanging participant lists — each node's local expiration computation is authoritative for its own view, and the disagreement persists until all nodes independently expire the departed peer's claim.

A future **NC_TDMA_DEPARTURE** message (Announce propagation) would allow a node to explicitly announce withdrawal from one or more TDMA modalities, enabling immediate schedule recomputation by remaining participants. Because the departure signal is an explicit event (not a locally-computed expiration), all nodes that receive it can act simultaneously, eliminating the convergence gap. This feature parallels the graceful network departure concept in [Section 13.2](#132-graceful-network-departure) and may be combined with it (e.g., NC_NODE_DEPARTURE triggers removal from all TDMA schedules). Claim expiration remains the correctness backstop for nodes that depart without sending the message (crash, link loss, power failure). Key challenges include distinguishing voluntary TDMA departure from full network departure, and handling stale departure messages in partitioned networks.

---

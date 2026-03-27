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

## Appendix B: Glossary {#appendix-b-glossary}

| Term | Definition |
|---|---|
| **AUTH_TAG_SIZE** | A 2-bit flag field (bits [7:6] for Status/Event/Request, bits [6:5] for Response) that controls the presence and size of the AES-CMAC authentication tag: `00` = no tag, `01` = 4 bytes, `10` = 8 bytes, `11` = 16 bytes. See [Section 12.2.3](#1223-authentication-tag) for details. |
| **Broadcast** | A packet with `destination = 0`, intended for all reachable nodes and clients. |
| **Client** | An application-layer endpoint that originates or consumes Messages. Identified globally by a ClientUID and locally by a Client Address (CA). |
| **Client Address (CA)** | An 8-bit or 16-bit local address identifying a client endpoint on the wire. Appears in the `source` and `destination` fields of packet headers. |
| **ClientUID** | A globally unique, persistent string identifying a specific client instance. Does not appear in transport layer packet headers. |
| **Compact Type Encoding (CTE)** | Variable-length encoding for Message Type IDs: 1 byte for values 0-127, 2 bytes for values 128-32,767. |
| **DataLink** | A modality adapter that connects M4P to a physical communication layer. Reports transmission opportunities and payload budgets. |
| **Event** | A broadcast application message class for fact records ("what happened") retained per message instance until TTL expiry; newer Events do not supersede older ones. |
| **Fragment** | A portion of a larger message, carried in a packet with the `IS_FRAGMENT` flag set. Each fragment's `offset` field identifies its starting byte position within the original ciphertext payload. Any node may further split (re-fragment) a received fragment; the resulting sub-fragments carry correct byte offsets and are interchangeable with fragments produced by any other node. |
| **MAC Management Mode** | Per-link configuration that determines who owns transmission-opportunity timing. **Link-managed** (default): the DataLink adapter decides when opportunities exist. **M4P-managed TDMA**: the M4P runtime decides when opportunities exist from NC-derived schedule state. See [Section 10.4](#104-data-link-adaptation). |
| **Message** | An application-layer unit (status update, event, command, query, response) produced or consumed by a Client. Directed messages (Request/Response) specify their destination by ClientUID; the transport layer resolves to an on-wire Client Address internally. |
| **Message Instance ID (MIID)** | A unique identifier derived from packet header fields, used for deduplication and request/response correlation. |
| **Message Type ID** | An unsigned integer classifying the packet payload and determining its transport semantics (Status `0-7,999`, Event `8,000-9,999`, Request/Response `10,000-31,998`, or Network Control `32,000-32,767`). |
| **Modality** | A class of data link (acoustic, radio, satellite, LAN, IP/MQTT). |
| **Network Control** | Reserved message types (32,000-32,767) used for transport-internal and network layer coordination. Not delivered to application clients. |
| **Node** | A physical participant in the M4P network. Runs the M4P transport, hosts zero or more Clients, and connects to one or more DataLinks. Identified globally by a NodeUID and locally by a Node Address (NA). |
| **Node Address (NA)** | An 8-bit or 16-bit local address identifying a node for transport and forwarding purposes. Does not appear in transport layer data packet headers; carried in transmission metadata and network layer messages. |
| **NodeUID** | A globally unique, persistent string identifying a physical node. Does not appear in transport layer packet headers. |
| **One-hop** | A transmission mode (`ttl_override = 0`) where the packet is sent once and not forwarded by receiving nodes. |
| **Packet** | The smallest addressable unit within a Transmission. Contains a packet header and carries a complete Message or a Fragment. |
| **Request** | A directed application message class used for command/query interactions. Requests are retained per message instance, may be retried under resend policy, and are correlated to Responses by MIID. |
| **Response** | A directed application message class sent to answer a Request. Carries the corresponding `request_MIID` for correlation and is retained per response instance subject to TTL and resend policy. |
| **Status** | A broadcast application message class for current-state snapshots ("what is true now"). Status values supersede older values per `(source CA, message_type_id, status_key)` variant. |
| **Store-carry-forward (SCF)** | The delay-tolerant forwarding model where nodes store packets locally and forward them opportunistically when link opportunities arise. |
| **Transmission** | One send operation on a specific data link modality, carrying one or more serialized Packets plus transmission metadata. |
| **TTL (Time-to-Live)** | The maximum duration a packet remains valid in the network. Expired packets are discarded and not forwarded. |

---

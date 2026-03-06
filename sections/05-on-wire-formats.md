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

## 5. On-Wire Formats {#5-on-wire-formats}
**[WIRE FORMAT]**

M4P defines four application-facing packet header formats (Status, Event, Request, Response) and two Network Control header formats (NC Announce, NC Targeted).

The notation `(CA: 8b or 16b)` indicates that the field width depends on the network-wide addressing mode.

**Bit layout of `timestamp_24h | msg_counter` (3 bytes).** This packing is used in all header formats except Response (which substitutes its own variant; see [Section 5.4](#54-response-packet-header)):

```text
 0                   1                   2
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          timestamp_24h (17b)      |msg_ctr (7)|
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 5.1 Status Packet Header

Applies to Message Type IDs 0 - 7,999.

```text
Offset  Field                          Width
──────  ─────                          ─────
 0      message_type_id                CTE: 1B or 2B
 +1/+2  source                         CA: 1B or 2B
  ...   timestamp_24h | msg_counter    3B (bit layout above)
  ...   payload_length                 2B
  ...   flags                          1B
  ...   [optional fields per flags]    variable
  ...   payload                        payload_length B
```

**Minimum header size:** 8 bytes (8-bit addressing, 1-byte CTE, no optional fields) to 10 bytes (16-bit addressing, 2-byte CTE, no optional fields).

### 5.2 Event Packet Header

Applies to Message Type IDs 8,000 - 9,999.

```text
Offset  Field                          Width
──────  ─────                          ─────
 0      message_type_id                CTE: 2B
 +2     source                         CA: 1B or 2B
  ...   timestamp_24h | msg_counter    3B (bit layout above)
  ...   payload_length                 2B
  ...   flags                          1B
  ...   [optional fields per flags]    variable
  ...   payload                        payload_length B
```

Event packets use the Status-like broadcast header shape: no destination field and no class-specific key field. Event flags bit 4 is reserved (see [Section 5.7.2](#572-event-packet-flags-8-bits)).

**Minimum header size:** 9 bytes (8-bit addressing) to 10 bytes (16-bit addressing), excluding optional fields.

### 5.3 Request Packet Header

Applies to Message Type IDs 10,001 - 31,997 (odd values only).

```text
Offset  Field                          Width
──────  ─────                          ─────
 0      message_type_id                2B
 +2     destination                    CA: 1B or 2B
  ...   source                         CA: 1B or 2B
  ...   timestamp_24h | msg_counter    3B (bit layout above)
  ...   payload_length                 2B
  ...   flags                          1B
  ...   [optional fields per flags]    variable
  ...   payload                        payload_length B
```

Request Message Type IDs always fall in the 2-byte CTE range; the `message_type_id` field is always 16 bits.

**Minimum header size:** 10 bytes (8-bit addressing) to 12 bytes (16-bit addressing), excluding optional fields.

**Group destination.** When the `ADDITIONAL_DEST_PRESENT` flag is set, the Request targets multiple CAs. The `destination` field contains the lowest CA in the group; additional CAs appear in the `additional_destinations` optional field (see [Section 5.7.6](#576-optional-field-definitions)).

### 5.4 Response Packet Header

Applies to Message Type IDs 10,000 - 31,998 (even values only).

```text
Offset  Field                                       Width
──────  ─────                                       ─────
 0      message_type_id                              2B
 +2     destination                                  CA: 1B or 2B
  ...   source                                       CA: 1B or 2B
  ...   timestamp_24h_request | msg_counter_request  3B (same packing as above)
  ...   payload_length                               2B
  ...   timestamp_24h_response | flags               3B (see bit layout below)
  ...   [optional fields per flags]                  variable
  ...   payload                                      payload_length B
```

Response packets carry two timestamps: the original request's timestamp (for correlation) and the response's own timestamp. Response Message Type IDs always fall in the 2-byte CTE range; the `message_type_id` field is always 16 bits. The `timestamp_24h_request | msg_counter_request` field uses the same 17b+7b packing defined above.

**Bit layout of `timestamp_24h_response | flags` (3 bytes):**

```text
 0                   1                   2
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    timestamp_24h_response (17b)   | flags (7) |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

Where `flags` = 7 bits (see [Section 5.7.4](#574-response-packet-flags-7-bits)). Response flags are 7 bits (not 8) because the `timestamp_24h_response` field consumes the high bit of the third byte.

**Minimum header size:** 12 bytes (8-bit addressing) to 14 bytes (16-bit addressing), excluding optional fields.

> **Design rationale:** Why two timestamps in Response? The Response carries copies of the Request's `timestamp_24h` and `msg_counter` (as `timestamp_24h_request` and `msg_counter_request`) to enable stateless MIID reconstruction for request correlation ([Section 6.3](#63-response-correlation)). The Response's own `timestamp_24h_response` (17 bits) and `flags` (7 bits) are bit-packed into 3 bytes — see the bit layout above.

### 5.5 Network Control Packet Headers

Network Control (NC) messages (Message Type IDs 32,000–32,767) use dedicated header formats that differ from the application-facing headers in three ways:

1. **Address fields contain Node Addresses (NAs), not Client Addresses (CAs).** NC messages are exchanged between nodes, not between application clients.
2. **No flags field.** NC messages do not carry optional fields — no fragmentation, no priority override, no modality mask, no TTL override, no CA fingerprint, and no authentication tag.
3. **NC messages MUST NOT be fragmented.** NC payloads are designed to fit within a single packet. The transport MUST NOT set `IS_FRAGMENT` on an NC message, and MUST NOT apply intermediate fragmentation to NC messages.

Two NC header variants are defined, corresponding to the two NC transport patterns:

#### 5.5.1 NC Announce Header

Used by NC messages with Announce or Query propagation (see [Section 11.6.2](#1162-propagation-models)). Broadcast to all nodes; no destination field.

```text
Offset  Field                          Width
──────  ─────                          ─────
 0      message_type_id                2B
 +2     source                         NA: 1B or 2B
  ...   timestamp_24h | msg_counter    3B (bit layout above)
  ...   payload_length                 2B
  ...   payload                        payload_length B
```

**Header size:** 7 bytes (8-bit addressing) or 8 bytes (16-bit addressing).

#### 5.5.2 NC Targeted Header

Used by NC messages with Targeted propagation (see [Section 11.6.2](#1162-propagation-models)). Addressed to a specific destination node.

```text
Offset  Field                          Width
──────  ─────                          ─────
 0      message_type_id                2B
 +2     destination                    NA: 1B or 2B
  ...   source                         NA: 1B or 2B
  ...   timestamp_24h | msg_counter    3B (bit layout above)
  ...   payload_length                 2B
  ...   payload                        payload_length B
```

**Header size:** 8 bytes (8-bit addressing) or 10 bytes (16-bit addressing).

### 5.6 Field Definitions

**Field Purposes**

| Field | Width | Purpose | Present In |
|-------|-------|---------|-----------|
| `message_type_id` | CTE: 1 or 2 B | Classifies the message type | All packets |
| `source` | CA/NA: 8b or 16b | Address of the originating endpoint | All packets |
| `destination` | CA/NA: 8b or 16b | On-wire address of the intended recipient, resolved from the application-provided destination ClientUID by the transport layer; `0` = broadcast. For group Requests (`ADDITIONAL_DEST_PRESENT` set), contains the lowest CA in the destination list. | Request, Response, NC Targeted |
| `timestamp_24h` | 17b | Seconds since midnight when the message was originated; used for MIID and TTL | Status, Event, Request, NC Announce, NC Targeted |
| `msg_counter` | 7b | Per-source rolling counter (0–127); combined with `source` and `timestamp_24h` to form the MIID | Status, Event, Request, NC Announce, NC Targeted |
| `timestamp_24h_request` | 17b | Copied from the original Request; used for correlation via MIID | Response only |
| `msg_counter_request` | 7b | Copied from the original Request; used for correlation via MIID | Response only |
| `timestamp_24h_response` | 17b | When the Response was generated; used for TTL computation | Response only |
| `payload_length` | 16b | Length of the payload in bytes | All packets |
| `flags` | 8b or 7b | Bit field controlling presence of optional fields (see [Section 5.7](#57-flags-and-optional-fields)) | Status, Event, Request, Response |
| `payload` | `payload_length` B | Message content; interpretation determined by `message_type_id` | All packets |

**Compact Type Encoding (CTE).** See [Section 4.2](#42-compact-type-encoding-cte). The `message_type_id` field uses CTE in Status packets (types 0–127 encode in 1 byte, 128–7,999 in 2 bytes). Event, Request, Response, and NC packets always use the 2-byte encoding (values are always >= 8,000).

**Source and Destination.** Valid values: `1` to `255` (8-bit mode) or `1` to `65,535` (16-bit mode). The `destination` field contains the on-wire Client Address resolved from the destination ClientUID (see [Section 9.2](#92-per-node-message-store)). The destination value `0` denotes broadcast (see [Section 9.8.1](#981-broadcast-semantics)). Status and Event messages are broadcast classes and delivered to all local clients on each receiving node; client-side filtering by message type is an application concern. For Request packets with `ADDITIONAL_DEST_PRESENT` set, the transport delivers the Request to each locally-hosted CA in the destination list (see [Section 5.7.6](#576-optional-field-definitions)). For NC messages (message_type_id 32,000–32,767), these fields contain Node Addresses (see [Section 11.6.1](#1161-transport-properties)).

**Timestamp Encoding and Age Calculation.** The `timestamp_24h` field wraps at midnight. To correctly calculate packet age across the midnight boundary, implementations MUST use modular arithmetic with normalization to a +/-12 hour range:

```text
age = current_time_24h - packet_timestamp_24h

if age > 43,200:
    age = age - 86,400
else if age < -43,200:
    age = age + 86,400

age = max(0, age)
```

**Constraint:** Timestamps are only unambiguous within +/-12 hours of the current time. Packets whose timestamps appear to be in the future after normalization MUST be clamped to age `0`.

**Message Counter.** `msg_counter` is a 7-bit rolling counter, range `0`–`127`, maintained independently per source address. Each Client Address hosted on a node has its own counter, and the node itself maintains a separate counter for Network Control messages (which use the Node Address as source, per [Section 11.6.1](#1161-transport-properties)). A node hosting *n* clients therefore maintains *n* + 1 independent counters. Each counter is incremented for every new message originated by that source and rolls over to `0` after `127`.

**Payload Length and Payload.** `payload_length` maximum value: `65,535`. The interpretation of the payload is determined by the `message_type_id` and is outside the scope of this specification (except for Network Control messages, whose payload formats are defined in [Section 11.7](#117-nc-message-catalog)).

### 5.7 Flags and Optional Fields

Each packet class defines a flags field that controls the presence of optional fields. Optional fields, when present, appear in the order defined below, immediately after the flags field and before the payload.

#### 5.7.1 Status Packet Flags (8 bits)

All flag-gated optional fields are defined in [Section 5.7.6](#576-optional-field-definitions).

| Bit | Name | When Set |
|---:|---|---|
| 0 | `IS_FRAGMENT` | Fragment fields are present. |
| 1 | `PRIORITY_OVERRIDE_PRESENT` | `priority_override` field is present. |
| 2 | `MODALITY_MASK_PRESENT` | `modality_mask` field is present. |
| 3 | `TTL_OVERRIDE_PRESENT` | `ttl_override` field is present. |
| 4 | `STATUS_KEY_PRESENT` | `status_key_length` and `status_key_string` fields are present. |
| 5 | `CA_FINGERPRINT_PRESENT` | `ca_fingerprint` field is present. |
| [7:6] | `AUTH_TAG_SIZE` | 2-bit field selecting authentication tag size. |

#### 5.7.2 Event Packet Flags (8 bits)

| Bit | Name | When Set |
|---:|---|---|
| 0 | `IS_FRAGMENT` | Fragment fields are present. |
| 1 | `PRIORITY_OVERRIDE_PRESENT` | `priority_override` field is present. |
| 2 | `MODALITY_MASK_PRESENT` | `modality_mask` field is present. |
| 3 | `TTL_OVERRIDE_PRESENT` | `ttl_override` field is present. |
| 4 | `RESERVED` | Reserved for future use; MUST be `0` in this version. |
| 5 | `CA_FINGERPRINT_PRESENT` | `ca_fingerprint` field is present. |
| [7:6] | `AUTH_TAG_SIZE` | 2-bit field selecting authentication tag size. |

Event does not define `STATUS_KEY_PRESENT`, and no Event-specific optional field occupies position 5.

#### 5.7.3 Request Packet Flags (8 bits)

| Bit | Name | When Set |
|---:|---|---|
| 0 | `IS_FRAGMENT` | Fragment fields are present. |
| 1 | `PRIORITY_OVERRIDE_PRESENT` | `priority_override` field is present. |
| 2 | `MODALITY_MASK_PRESENT` | `modality_mask` field is present. |
| 3 | `TTL_OVERRIDE_PRESENT` | `ttl_override` field is present. |
| 4 | `ADDITIONAL_DEST_PRESENT` | `additional_destinations` field is present. |
| 5 | `CA_FINGERPRINT_PRESENT` | `ca_fingerprint` field is present. |
| [7:6] | `AUTH_TAG_SIZE` | 2-bit field selecting authentication tag size. |

#### 5.7.4 Response Packet Flags (7 bits)

| Bit | Name | When Set |
|---:|---|---|
| 0 | `IS_FRAGMENT` | Fragment fields are present. |
| 1 | `PRIORITY_OVERRIDE_PRESENT` | `priority_override` field is present. |
| 2 | `MODALITY_MASK_PRESENT` | `modality_mask` field is present. |
| 3 | `TTL_OVERRIDE_PRESENT` | `ttl_override` field is present. |
| 4 | `CA_FINGERPRINT_PRESENT` | `ca_fingerprint` field is present. |
| [6:5] | `AUTH_TAG_SIZE` | 2-bit field selecting authentication tag size. |

#### 5.7.5 Optional Field Ordering

When multiple optional fields are present, they MUST appear in the following order after the flags field:

1. Fragment fields (`IS_FRAGMENT`)
2. `priority_override` (`PRIORITY_OVERRIDE_PRESENT`)
3. `modality_mask` (`MODALITY_MASK_PRESENT`)
4. `ttl_override` (`TTL_OVERRIDE_PRESENT`)
5. `additional_dest_count` + `additional_dest[]` (`ADDITIONAL_DEST_PRESENT`, Request packets only) / `status_key_length` + `status_key_string` (`STATUS_KEY_PRESENT`, Status packets only). Event packets define no class-specific optional field in this position.
6. `ca_fingerprint` (`CA_FINGERPRINT_PRESENT`)
7. `authentication_tag` (`AUTH_TAG_SIZE != 00`) -- 4, 8, or 16 bytes as determined by the `AUTH_TAG_SIZE` field. For any given `AUTH_TAG_SIZE` value, the field size is deterministic from the flags alone, consistent with the fixed-size design constraint.

**Design constraint:** All flag-gated optional fields are fixed-size, with field sizes determined by the flags byte alone. This property is relied upon by the packet parser to locate the payload after the optional fields block. There are two exceptions, both variable-length but self-delimiting: (1) the `status_key` field (Status packets only, gated by `STATUS_KEY_PRESENT`), where the `status_key_length` byte precedes the key string, allowing the parser to compute the field's total size (1 + `status_key_length` bytes) and skip past it; and (2) the `additional_destinations` field (Request packets only, gated by `ADDITIONAL_DEST_PRESENT`), where the `additional_dest_count` byte precedes the CA array, allowing the parser to compute the field's total size (1 + `additional_dest_count` × CA_width bytes) and skip past it. These two fields occupy the same position (position 5) but apply to different packet classes — `STATUS_KEY_PRESENT` is bit 4 in Status flags, while `ADDITIONAL_DEST_PRESENT` is bit 4 in Request flags — so they never coexist in the same packet. Event bit 4 is reserved in this version and MUST NOT gate any field. All other optional fields have sizes that are fully determined by the flags value without inspecting field contents.

#### 5.7.6 Optional Field Definitions

| Field | Flag | Size | Description |
|---|---|---:|---|
| `offset` | `IS_FRAGMENT` | 15 bits | Byte offset into the original ciphertext payload, zero-based. |
| `end` | `IS_FRAGMENT` | 1 bit | `1` for the final fragment; `0` otherwise. |
| `priority_override` | `PRIORITY_OVERRIDE_PRESENT` | 8 bits | Priority value `0`–`255` (higher = higher priority). Replaces the message type's default priority. |
| `modality_mask` | `MODALITY_MASK_PRESENT` | 8 bits | Bitmask of permitted data link modalities for this packet. |
| `ttl_override` | `TTL_OVERRIDE_PRESENT` | 8 bits | Piecewise-linear encoded TTL replacing the message type's default. |
| `additional_dest_count` | `ADDITIONAL_DEST_PRESENT` | 8 bits | Number of additional destination CAs beyond the `destination` header field. Request packets only. |
| `additional_dest[]` | `ADDITIONAL_DEST_PRESENT` | `additional_dest_count` × CA width | The additional destination CAs, in ascending CA order. Request packets only. |
| `status_key_length` | `STATUS_KEY_PRESENT` | 8 bits | Length of the status key string in bytes (0–255). Status packets only. |
| `status_key_string` | `STATUS_KEY_PRESENT` | variable | UTF-8 key string (`status_key_length` bytes). Status packets only. |
| `ca_fingerprint` | `CA_FINGERPRINT_PRESENT` | 16 bits | `SHA-256(ClientUID \|\| CA \|\| address_version)` truncated to 2 bytes. |
| `authentication_tag` | `AUTH_TAG_SIZE != 00` | 4/8/16 bytes | Truncated AES-CMAC tag for integrity and authentication. |

##### Fragment Fields

Present when `IS_FRAGMENT` is set. The two sub-fields (`offset` and `end`) occupy 16 bits (2 bytes) total. See [Section 8](#8-fragmentation-and-reassembly) for full fragmentation semantics.

##### Modality Mask

Present when `MODALITY_MASK_PRESENT` is set. The bit assignments are:

| Bit | Modality |
|---:|---|
| 0 | Acoustic |
| 1 | Radio |
| 2 | Satellite |
| 3 | LAN |
| 4 | IP/MQTT |
| 5–7 | Reserved |

When absent, the message type's default modality mask applies. Nodes MUST NOT transmit a packet on a modality not permitted by the effective modality mask.

##### TTL Override

Present when `TTL_OVERRIDE_PRESENT` is set. Uses a piecewise-linear encoding optimized for maritime operations:

| Wire Value `n` | Decoded TTL |
|---:|---|
| `0` | One-hop only (see [Section 7](#7-time-to-live-and-packet-expiration)) |
| `1`–`60` | `n` seconds (1-second precision) |
| `61`–`120` | `(n - 60) * 10 + 60` seconds (10-second precision, 70–660 s) |
| `121`–`180` | `(n - 120) * 60 + 660` seconds (1-minute precision, 720–4,260 s) |
| `181`–`255` | `(n - 180) * 300 + 4,260` seconds (5-minute precision, 4,560–26,760 s) |

> **Design rationale:** The maximum encodable TTL (~7.4 hours) remains within the +/-12 hour unambiguity window imposed by the 24-hour timestamp. Short-lived messages retain high precision. The one-hop mode (`n = 0`) enables efficient local flooding control.

**Representative values:**

| Wire Value | Decoded TTL |
|---:|---|
| `0` | One-hop |
| `30` | 30 seconds |
| `60` | 1 minute |
| `90` | 6 minutes |
| `120` | 11 minutes |
| `150` | 41 minutes |
| `180` | ~71 minutes |
| `200` | ~2.8 hours |
| `255` | ~7.4 hours |

**Additional destinations (group addressing).** Present when `ADDITIONAL_DEST_PRESENT` is set (Request packets only). The `additional_dest_count` field specifies the number of additional destination CAs beyond the `destination` header field. The `additional_dest[]` array contains those CAs, each encoded at the network's CA width (1 byte in 8-bit mode, 2 bytes in 16-bit mode).

The total group size is 1 (the `destination` field) + `additional_dest_count`. The `additional_dest_count` value MUST be >= 1; a group Request with `additional_dest_count = 0` is malformed (use a standard unicast Request instead).

The full destination list (`destination` field + `additional_dest[]`) MUST be sorted in ascending CA order. The `destination` header field contains the lowest CA; `additional_dest[]` contains the remaining CAs in ascending order. This provides a canonical representation — the same set of destination CAs always produces the same header bytes. The full destination list MUST NOT contain duplicate CAs. When the application submits a group Request by ClientUID, the transport MUST resolve ClientUIDs to CAs and deduplicate before constructing the header.

A group Request with `destination = 0` or any `additional_dest[] = 0` is malformed. CA 0 is reserved for broadcast addressing ([Section 3.2](#32-local-addresses)); broadcast semantics are accessed via the existing broadcast mechanism, not via group Requests.

When a node receives a Request with `ADDITIONAL_DEST_PRESENT` set, it reads the full destination CA list (`destination` field + `additional_dest[]`), checks if any CA in the list is hosted locally, and delivers the Request to each locally-hosted CA in the list. The packet is also stored for forwarding per standard store-carry-forward behavior ([Section 9.1](#91-store-carry-forward-model)).

##### Status Key

Present when `STATUS_KEY_PRESENT` is set (Status packets only).

The status key enables multiple concurrent Status messages with the same Message Type ID to coexist without overriding each other. Without a status key, stored Status messages of the same `(source CA, message_type_id)` supersede older messages. With a status key, Status messages are keyed by `(source CA, message_type_id, status_key)`, and supersession occurs only within the same variant.

The absence of a status key constitutes a distinct variant; `key=None` never supersedes or is superseded by any keyed variant.

> [GUIDANCE] On bandwidth-constrained links, the status key's overhead (1 + key_length bytes) is significant. Applications SHOULD use short status keys (1–4 bytes) or numeric identifiers encoded as short strings (e.g., "1", "2") when operating over constrained modalities. Alternatively, applications MAY avoid the status key entirely by allocating distinct Message Type IDs for each variant, which eliminates per-packet overhead at the cost of consuming type ID space.

##### Client Address Fingerprint

Present when `CA_FINGERPRINT_PRESENT` is set. See [Section 11.9.4](#1194-accelerated-client-address-convergence) for the full construction, injection frequency, and receiver behavior. Used by receiving nodes to detect stale client address mappings without waiting for periodic NC_NODE_SUMMARY broadcasts. On mismatch, the receiver queries the current identity via NC_CLIENT_UID_QUERY.

##### Authentication Tag

Present when `AUTH_TAG_SIZE != 00`. The `AUTH_TAG_SIZE` field is a 2-bit value located at bits [7:6] in Status, Event, and Request flags, and bits [6:5] in Response flags. It encodes the following tag sizes:

| `AUTH_TAG_SIZE` | Meaning | Tag Size |
|---|---|---|
| `00` | No tag | 0 bytes |
| `01` | Standard tag | 4 bytes |
| `10` | Extended tag | 8 bytes |
| `11` | Full tag | 16 bytes |

The tag provides integrity protection and message authentication for the encrypted payload. It appears in the header's optional field area, after all other optional fields and before the payload. The `payload_length` field reflects only the payload (ciphertext) size and does not include the tag. The tag computation, verification procedure, and security properties are defined in [Section 12.2.3](#1223-authentication-tag).

The `AUTH_TAG_SIZE` field MUST only be set to a non-zero value when the M4P payload cipher is active (a PSK is configured). If `AUTH_TAG_SIZE != 00` on a packet received by a node without a configured PSK, the node MUST forward the packet as-is without modification.

### 5.8 Transmission Encoding

A Transmission is the unit of data exchanged between nodes over a DataLink. It consists of the transmitting node's address followed by one or more serialized packets.

```text
+-----------------------------------------------+
| node_address_sender    (NA: 8b or 16b)        |
+-----------------------------------------------+
| packet₁ || packet₂ || ... || packetₙ          |
+-----------------------------------------------+
```

The `node_address_sender` field contains the Node Address of the transmitting node, encoded as an 8-bit or 16-bit unsigned integer matching the network-wide addressing mode. The remainder of the Transmission is a concatenation of serialized M4P packets (headers + payloads as defined in Sections [5.1](#51-status-packet-header)–[5.5](#55-network-control-packet-headers)). The packets within a single Transmission may belong to different message classes, originate from different source clients, target different destinations, and include both locally-originated and forwarded packets.

**Parsing.** The receiving node reads the `node_address_sender`, then parses packets sequentially — the `message_type_id` CTE encoding and `payload_length` field provide the information needed to determine packet boundaries. Any trailing bytes insufficient to form a valid packet header MUST be discarded. Implementations SHOULD NOT pad Transmissions with trailing bytes; if padding is required by the DataLink layer, the adapter MUST strip it before delivering the Transmission to the transport.

**DataLink adaptation.** The encoding above is the canonical Transmission wire format. A DataLink adapter MAY omit the `node_address_sender` prefix when the underlying link protocol natively provides the sender's identity (e.g., an acoustic modem's source address field). In this case, the receiving adapter MUST reconstruct the full Transmission by prepending the `node_address_sender` derived from link-layer metadata before delivering it to the transport. This optimization is encapsulated within the DataLink adapter pair — the transport layer always receives the canonical format. See [Section 10.3](#103-transmission-metadata) for adapter responsibilities.

---

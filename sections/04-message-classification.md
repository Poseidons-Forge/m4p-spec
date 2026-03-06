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

## 4. Message Classification {#4-message-classification}
**[WIRE FORMAT]**

### 4.1 Message Type ID Ranges

Message Type IDs are unsigned integers partitioned into the following ranges. M4P defines only the range boundaries and the transport semantics associated with each range (Status, Event, Request/Response, Network Control). The specific Message Type IDs within the application ranges (0–31,998 excluding 31,999) are defined by each application or deployment — the protocol does not allocate or reserve individual type IDs within these ranges. Only the Network Control range (32,000–32,767) contains type IDs defined by this specification. The following table summarizes the range partitioning.

This range-based classification is deliberate: class semantics are inferred from `message_type_id`, so packet headers do not need a separate class field. On constrained links, avoiding that fixed byte of overhead on every packet is a primary design goal.

| Range | Class | Description |
|---:|---|---|
| 0 - 7,999 | **Status** | Broadcast state information (e.g., navigation, health, telemetry) with latest-value semantics. Status messages have no destination — every node that receives a Status message delivers it to all locally hosted clients. The transport layer maintains only the latest value per `(source CA, message_type_id, status_key)` variant; newer Status messages supersede older ones. |
| 8,000 - 9,999 | **Event** | Broadcast event/fact information with append-retained semantics. Event messages have no destination and are delivered to all locally hosted clients. Event messages are retained and forwarded per message instance until TTL expiry; newer Events MUST NOT supersede older Events. |
| 10,000 - 31,998 | **Request / Response** | Command-and-control or query messages that follow a request/response pattern. Odd values (10,001 - 31,997) denote Requests. Even values (10,000 - 31,998) denote Responses. The Response type for a given Request is `request_type_id + 1`. The value `10,000` is reserved as a generic Response type. |
| 32,000 - 32,767 | **Network Control** | Reserved for transport-internal and network layer control traffic (discovery, address management, fragment control, link probes). Network Control packets MUST NOT be delivered to application clients. |

Message Type ID `31,999` is reserved. Values `32,768` and above cannot be encoded with the current 2-byte Compact Type Encoding and are reserved for future protocol versions that define extended encoding schemes.

| Range | Class | CTE Width | Notes |
|---:|:---|:---|:---|
| 0 – 127 | Status | 1 byte | Most common status types use 1-byte encoding |
| 128 – 7,999 | Status | 2 bytes | Extended status types |
| 8,000 – 9,999 | Event | 2 bytes | Event class; no 1-byte encoding range |
| 10,000 – 31,998 | Request/Response | 2 bytes (always) | Odd = Request, Even = Response; `type + 1` pairs them |
| 31,999 | *Reserved* | — | Reserved for future use |
| 32,000 – 32,767 | Network Control | 2 bytes (always) | Internal to transport; never delivered to clients |
| ≥ 32,768 | *Reserved* | — | Cannot be encoded with current 2-byte CTE |

> **CTE boundary at 128:** Status types 0–127 use a single-byte Compact Type Encoding (MSB = 0), saving 1 byte per packet on the most bandwidth-sensitive state class. Event, Request/Response, and Network Control ranges always use 2-byte CTE (MSB = 1).

### 4.2 Compact Type Encoding (CTE)

To minimize header overhead on constrained links, Message Type IDs are encoded using a variable-length Compact Type Encoding:

**1-byte encoding** (values 0 - 127): The most-significant bit of the byte is `0`. The remaining 7 bits encode the value directly.

```text
Byte 0:  0 x x x x x x x
         ^ |           |
         | +-----------+
        MSB=0  value (7 bits)
```

**2-byte encoding** (values 128 - 32,767): The most-significant bit of the first byte is `1`. The remaining 15 bits across both bytes encode the value in big-endian order.

```text
Byte 0:  1 x x x x x x x    Byte 1:  x x x x x x x x
         ^ |           |             |             |
         | +-----------+ - - - - - - +-------------+
        MSB=1          value (15 bits, big-endian)
```

Receivers MUST infer the encoding length from the MSB of the first byte.

---

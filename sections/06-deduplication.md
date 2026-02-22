## 6. Message Instance Tracking and Deduplication {#6-message-instance-tracking-and-deduplication}
**[WIRE FORMAT + BEHAVIORAL]**

### 6.1 Message Instance ID (MIID)

Every message in M4P is assigned a Message Instance ID (MIID) derived from packet header fields. MIIDs are computed from the on-wire `source` address field — the Client Address for application packets, or the Node Address for NC packets (see [Section 11.6.1](#1161-transport-properties)). They do not depend on UIDs.

MIIDs serve three functions:

1. **Deduplication**: Identifying and suppressing duplicate packets in a store-carry-forward network where the same message may arrive via multiple paths.
2. **Request/Response correlation**: Linking Response packets back to their originating Request.
3. **Caching**: Keying cached Responses for duplicate Request suppression.

**Rate constraint.** The `msg_counter` field provides 128 unique values (0–127) per source CA per second. A source CA MUST NOT originate more than 128 messages per second. If this rate is exceeded, MIID collisions will occur, causing valid messages to be suppressed by deduplication.

> **Design rationale:** The 7-bit counter width balances MIID compactness against uniqueness capacity. A wider counter would reduce the collision window but expand the MIID beyond 32 bits (8-bit mode) or 40 bits (16-bit mode), increasing per-packet overhead on every transmission. At 128 values per source CA per second, the counter provides ample headroom for maritime communication rates while keeping the MIID within a single 32-bit or 64-bit integer.

> [GUIDANCE] In practice, the bandwidth constraints of maritime communication links make the 128 messages-per-second limit unreachable under normal operation.

### 6.2 MIID Computation

For Status, Event, and Request packets, the MIID is computed as:

```text
MIID = (source_CA << 24) | ((timestamp_24h & 0x1FFFF) << 7) | (msg_counter & 0x7F)
```

- `source_CA`: Client Address (8 bits in 8-bit addressing mode, 16 bits in 16-bit mode).
- `timestamp_24h`: 17-bit seconds-since-midnight value.
- `msg_counter`: 7-bit rolling counter.

The width of `source_CA` determines the total MIID width. In 8-bit addressing mode the result is a 32-bit unsigned integer (MIID32). In 16-bit addressing mode the result is a 40-bit unsigned integer (MIID40). Implementations MUST store MIID40 values in an unsigned 64-bit integer type.

### 6.3 Response Correlation

Response packets correlate to their originating Request using the Request's MIID, reconstructed from fields in the Response header:

```text
Request_MIID = (destination_CA << 24) | ((timestamp_24h_request & 0x1FFFF) << 7) | (msg_counter_request & 0x7F)
```

- `destination_CA`: The Response's `destination` field (which is the original requester's CA).
- `timestamp_24h_request`: Copied from the original Request.
- `msg_counter_request`: Copied from the original Request.

Any node can therefore correlate a Response to its originating Request without maintaining request state.

**Request → Response Field Mapping**

| Request Field | → | Response Field | Role in Correlation |
|:---|:---:|:---|:---|
| `source` (requester CA) | → | `destination` | First component of Request MIID |
| `timestamp_24h` | → | `timestamp_24h_request` | Second component of Request MIID |
| `msg_counter` | → | `msg_counter_request` | Third component of Request MIID |
| — | | `source` (responder CA) | Distinguishes responses from different responders |
| — | | `timestamp_24h_response` | TTL computation only — not part of dedup key |

### 6.4 MIID Bit Layout

| Mode | Bits | Field |
|---|---|---|
| **MIID32** | 31–24 | `source_CA` (8 bits) |
| | 23–7 | `timestamp_24h` (17 bits) |
| | 6–0 | `msg_counter` (7 bits) |
| **MIID40** | 39–24 | `source_CA` (16 bits) |
| | 23–7 | `timestamp_24h` (17 bits) |
| | 6–0 | `msg_counter` (7 bits) |

The same MIID components (`source_ca`, `timestamp_24h`, `msg_counter`) also appear in the AES-CTR nonce construction for the M4P payload cipher (see [Section 12.2.2](#1222-nonce-derivation), *Nonce construction*).

### 6.5 Deduplication Rules
**[BEHAVIORAL]**

Nodes MUST maintain a deduplication cache. The message-level deduplication key depends on packet class:

| Packet Class | Deduplication Key |
|---|---|
| Status / Event / Request | `(MIID, message_type_id)` |
| Response | `(request_MIID, message_type_id, source_CA)` |

For fragmented packets, nodes MUST track a per-message received byte-range set keyed by the reassembly key defined in [Section 8.4](#84-reassembly): `(MIID, message_type_id)` for Status/Event/Request fragments, `(request_MIID, message_type_id, source_CA)` for Response fragments. A fragment is redundant if its byte range `[offset, offset + payload_length)` is entirely covered by the received-byte-range set for that message. Nodes MUST discard redundant fragments and MUST NOT forward them.

An unfragmented packet is considered a **duplicate** if a packet with the same deduplication key has been previously received and has not yet expired. Nodes MUST NOT forward duplicate packets.

- Nodes MUST NOT deliver duplicate packets to local clients.
- The deduplication cache SHOULD retain entries for at least the duration of the packet's effective TTL.

**Response deduplication.** Response packets do not carry their own `msg_counter` field and do not have an independent MIID. Instead, Response deduplication relies on the following transport-enforced invariant:

**The transport layer MUST reject a Response submission from a local client if a Response with the same `(request_MIID, message_type_id, source_CA)` has already been accepted.** Accepting a duplicate Response would produce an AES-CTR nonce collision (see [Section 12.2.2](#1222-nonce-derivation)), breaking payload confidentiality. The transport MUST return an error to the submitting client and MUST NOT encrypt or transmit the duplicate Response.

Given this invariant, the composite key `(request_MIID, message_type_id, source_CA)` uniquely identifies each Response: two Responses to different Requests have different `request_MIID` values; two Responses from different responders to the same Request have different `source_CA` values; and the one-response-per-request invariant ensures a given responder does not produce duplicate Responses to the same Request. The `request_MIID` is reconstructed from the Response header fields `destination_CA`, `timestamp_24h_request`, and `msg_counter_request` as defined in [Section 6.3](#63-response-correlation).

> [GUIDANCE] On memory-constrained nodes, the deduplication cache MAY implement bounded storage with least-recently-seen eviction. If a cache entry is evicted before its TTL expires, the node may fail to suppress a late-arriving duplicate. Implementations SHOULD size the cache to accommodate the expected traffic volume within the maximum configured TTL. In practice, the bandwidth constraints of maritime links limit the achievable message rate to well below the theoretical MIID capacity.

---


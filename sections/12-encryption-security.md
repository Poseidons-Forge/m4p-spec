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

## 12. Encryption and Security {#12-encryption-and-security}

**[WIRE FORMAT + BEHAVIORAL]**

This section defines M4P's two-layer security model. Because store-carry-forward relays must read headers for forwarding and deduplication, payload confidentiality is applied end-to-end via the optional M4P payload cipher while DataLink adapters apply per-hop link protection. The layers are independent and complementary. The payload cipher uses AES-CTR with zero ciphertext expansion, preserving payload budget on constrained links.

Figure 12 shows this interaction across a three-node path.

```mermaid
---
config:
  theme: default
  layout: elk
  themeVariables:
    background: '#ffffff'
---
flowchart TD
    subgraph A["Node A (Originator)"]
        direction LR
        A_PT["Plaintext"]:::green
        A_ENC["M4P Encrypt"]:::crypto
        A_CT["Ciphertext"]:::gray
        A_TLS["DL Encrypt"]:::linkenc
        A_PT --> A_ENC --> A_CT --> A_TLS
    end

    subgraph B["Node B (Relay)"]
        direction LR
        B_TLS1["DL Decrypt"]:::linkenc
        B_CT["Ciphertext<br>(unchanged)"]:::gray
        B_TLS2["DL Encrypt"]:::linkenc
        B_TLS1 --> B_CT --> B_TLS2
    end

    subgraph C["Node C (Destination)"]
        direction LR
        C_TLS["DL Decrypt"]:::linkenc
        C_CT["Ciphertext"]:::gray
        C_DEC["M4P Decrypt"]:::crypto
        C_PT["Plaintext"]:::green
        C_TLS --> C_CT --> C_DEC --> C_PT
    end

    A ==>|"Link"| B
    B ==>|"Link"| C

    classDef green fill:#82e0aa,color:#2c3e50,stroke:#27ae60,stroke-width:2px
    classDef crypto fill:#5dade2,color:#2c3e50,stroke:#1a5276,stroke-width:2px
    classDef gray fill:#bdc3c7,color:#2c3e50,stroke:#95a5a6,stroke-width:2px
    classDef linkenc fill:#85c1e9,color:#2c3e50,stroke:#2980b9,stroke-width:2px
```

**Figure 12 — M4P Two-Layer Encryption Architecture**

*DL = DataLink-layer encryption (TLS / IPsec / COMSEC). Originator: M4P encrypt + DL encrypt; relay: DL decrypt/re-encrypt only; destination: DL decrypt + M4P decrypt. Node B is a relay without the PSK. A relay that holds the PSK may also re-encode a payload for a compressed link ([Section 12.3.3](#1233-gateway-and-bridge-behavior)).*

### 12.1 Responsibility Summary

The following table summarizes the division of security responsibilities across protocol layers.

| Responsibility | Owner |
|---|---|
| Application payload encryption/decryption | M4P transport (when PSK is configured) |
| Authentication tag computation/verification | M4P transport (when enabled) |
| Nonce derivation | M4P transport (from its own header fields) |
| NC message payloads | Not encrypted |
| Identity obfuscation (UID obfuscation) | Application (see [Section 12.5](#125-identity-obfuscation)) |
| Link-layer encryption (TLS, IPsec, etc.) | DataLink adapter |
| Key provisioning (PSK, certificates) | Deployment operations |

### 12.2 M4P Payload Cipher

**Configuration.** The payload cipher is controlled by one optional network-wide parameter: **`payload_cipher_key`** (PSK; see [Section 2.4.2](#242-required-configuration-must)). When configured, the transport encrypts outgoing application payloads and decrypts incoming payloads before local delivery. When absent, payloads are carried in the clear. All nodes that host clients and use the payload cipher MUST use the same PSK. Relay-only nodes do not need the PSK and forward ciphertext as opaque bytes. A relay that holds the PSK may re-encode the payloads it relays, and so reads them ([Section 12.3.3](#1233-gateway-and-bridge-behavior)).

**Algorithm.** The payload cipher uses **AES-256-CTR** (Counter mode) as defined in NIST SP 800-38A. Key size: 256 bits (32 bytes). Ciphertext expansion: zero (AES-CTR is a stream cipher mode; the ciphertext is the same length as the plaintext). Padding: none required.

#### 12.2.1 What Is Encrypted

The payload cipher operates on **application message payloads only** (see Figure 12 for the two-layer architecture). The following are NOT encrypted:

- All transport-layer packet header fields: `message_type_id`, `source`, `destination`, `timestamp_24h`, `msg_counter`, `payload_length`, `flags`, and all optional header fields.
- All transmission-level metadata: `node_address_sender`.
- Network control (NC) message payloads (message types 32,000–32,767).

Headers and transmission metadata remain visible so intermediate nodes can perform MIID deduplication, scheduling, TTL checks, forwarding, and fragmentation during store-carry-forward operation.

**Design Note (Non-Normative):** NC payloads remain visible so nodes can process discovery, claim, and conflict state without endpoint payload keys; network-layer convergence stays independent of application payload confidentiality.

#### 12.2.2 Nonce Derivation

AES-CTR requires a unique nonce (IV) for each encrypted payload or fragment. The M4P transport derives the nonce from packet header fields available at both sender and receiver, so nonce bytes are not transmitted:

```text
nonce = AES-CTR-NONCE(network_id, source_ca, timestamp_24h, msg_counter, message_type_id, fragment_offset)
```

**Nonce construction.** The nonce is constructed as a 16-byte (128-bit) value:

```text
+-----------------------------------------------+
| network_id_hash          (4 bytes)             |
+-----------------------------------------------+
| source_ca                (2 bytes, zero-padded)|
+-----------------------------------------------+
| timestamp_24h            (3 bytes)             |
+-----------------------------------------------+
| msg_counter              (1 byte)              |
+-----------------------------------------------+
| message_type_id          (2 bytes)             |
+-----------------------------------------------+
| fragment_offset          (2 bytes)             |
+-----------------------------------------------+
| reserved                 (2 bytes, 0x0000)     |
+-----------------------------------------------+
```

**Nonce Byte-Offset Summary**

| Byte Offset | Field | Size | Description |
|---|---|---|---|
| 0–3 | `network_id_hash` | 4 B | First 4 bytes of `SHA-256(network_id)`. Binds nonce to deployment. |
| 4–5 | `source_ca` | 2 B | Client Address, zero-padded to 2 bytes in 8-bit mode. |
| 6–8 | `timestamp_24h` | 3 B | 17-bit timestamp, zero-padded to 3 bytes. |
| 9 | `msg_counter` | 1 B | 7-bit message counter, zero-padded to 1 byte. |
| 10–11 | `message_type_id` | 2 B | Message type, big-endian. |
| 12–13 | `fragment_offset` | 2 B | Fragment byte offset. `0x0000` for unfragmented messages. |
| 14–15 | `reserved` | 2 B | Set to `0x0000`. |

**AES-CTR counter block.** The 16-octet nonce is the initial 128-bit counter block for AES-CTR encryption of the payload (NIST SP 800-38A). Implementations MUST increment the counter as a single 128-bit big-endian integer, by one per 16-octet cipher block, with octet 15 the least-significant counter octet and octet 0 the most-significant. This convention is mandatory for interoperability: a node that increments differently produces a different keystream and cannot exchange encrypted payloads. Because `payload_length` is a 16-bit field (maximum `65,535` octets, i.e. at most 4,096 cipher blocks), the block counter for a single payload never exceeds `4,095`; it is confined to the two low counter octets (14–15) — the `reserved` octets, which are `0x0000` in the initial block — and never carries into octet 13 (part of `fragment_offset`) or any higher-order nonce octet.

**Response packet nonce fields.** For Response packets, the nonce fields are populated as follows:

| Nonce Field | Response Header Source |
|---|---|
| `source_ca` | The Response's `source` field (the responder's CA) |
| `timestamp_24h` | `timestamp_24h_request` (the original Request's timestamp) |
| `msg_counter` | `msg_counter_request` (the original Request's counter) |

The `(source_ca, timestamp_24h_request, msg_counter_request, message_type_id)` tuple is unique per requester, not across requesters. Each requester numbers its own Requests, so two requesters can send Requests with equal timestamp and counter to one responder, and the two Responses then carry the same nonce. The Response key ([Section 12.7.1](#1271-key-derivation)) binds the requester's CA, the Response's `destination`, so those Responses are encrypted under different keys. With the requester's CA in the key, one key and nonce belong to one Response, by the one-response-per-request invariant in [Section 6.5](#65-deduplication-rules). <!-- PSFI-3515 (per-link compression) Response key (D17) drafted by a Claude agent. -->

**Nonce uniqueness.** Uniqueness is scoped by the tuple `(network_id_hash, source_ca, timestamp_24h, msg_counter, message_type_id, fragment_offset)`:

| Component | Ensures uniqueness per... |
|---|---|
| `(source_ca, timestamp_24h, msg_counter)` (MIID core) | Message |
| `message_type_id` | Packet class |
| `fragment_offset` | Fragment |
| `network_id_hash` | Deployment |

Under correct protocol behavior, distinct plaintexts do not reuse the same key and nonce tuple. The nonce does not depend on the payload form or on `payload_length`: every form and length of one message shares one nonce, and the payload keys of [Section 12.7](#127-payload-form-keys) keep them apart.

**24-hour wrap behavior.** Because `timestamp_24h` wraps every 24 hours, long-lived periodic traffic repeats nonce tuples daily (aperiodic traffic has lower alignment risk).

Deployments that use the payload cipher MUST mitigate nonce reuse with time-based epoch rotation that meets [Section 12.7.6](#1276-epoch-rotation-requirement), deriving short-lived epoch keys from the master PSK as described in [Section 12.4.1](#1241-payload-cipher-key) and [Section 12.4.3](#1243-key-rotation).

**Timing jitter (secondary).** Periodic publishers SHOULD also add small random jitter (seconds) to transmission timing to avoid deterministic timestamp alignment across days. Jitter does not replace epoch rotation: two messages with the same nonce inputs are kept apart only by falling in different epochs ([Section 12.7.6](#1276-epoch-rotation-requirement)). <!-- PSFI-3515 (per-link compression) origin-time epochs (D12 r6) drafted by a Claude agent. -->

#### 12.2.3 Authentication Tag

The M4P transport MAY append an authentication tag (4, 8, or 16 bytes) to encrypted payloads. Applications request tagging per message by setting `AUTH_TAG_SIZE` to a non-zero value. The node that encrypts or fragments a packet computes its tag; a node that would deliver the message verifies it before client delivery. A node that computes a new tag for a message it received MUST first verify the received tag ([Section 12.7.3](#1273-tag-keys)).

**[GUIDANCE] Deployment policy.** Deployments with elevated integrity requirements SHOULD tag all messages. Command-and-control and safety-critical traffic SHOULD use `AUTH_TAG_SIZE = 10` or `11` (8- or 16-byte tags). Constrained telemetry MAY use `AUTH_TAG_SIZE = 01` (4-byte tags).

**Tag computation.** Tags use AES-CMAC (NIST SP 800-38B), truncated to N bytes based on `AUTH_TAG_SIZE`:

| `AUTH_TAG_SIZE` | N (tag bytes) |
|---|---|
| `01` | 4 |
| `10` | 8 |
| `11` | 16 |

```text
tag = TRUNCATE_N(AES-CMAC(key, nonce || header_aad || ciphertext))
```

`key` is the packet's tag key ([Section 12.7.3](#1273-tag-keys)): the active key for a plain packet (for a Response, the Response key of [Section 12.7.1](#1271-key-derivation)), and the compressed tag key of the message's type for a compressed packet. `nonce` is the 16-byte value from [Section 12.2.2](#1222-nonce-derivation), and `header_aad` is immutable non-encrypted header data in wire order.

**Header AAD construction.** The `header_aad` fields depend on the packet class:

| Packet Class | `header_aad` Fields |
|---|---|
| Status | `flags` (1 byte) ‖ [`offset` (15 bits) ‖ `end` (1 bit) — 2 bytes] ‖ [`carriage` (1 byte)] ‖ `payload_length` (2 bytes) |
| Event | `flags` (1 byte) ‖ [`offset` (15 bits) ‖ `end` (1 bit) — 2 bytes] ‖ [`carriage` (1 byte)] ‖ `payload_length` (2 bytes) |
| Request | `destination` (1 or 2 bytes) ‖ `flags` (1 byte) ‖ [`offset` (15 bits) ‖ `end` (1 bit) — 2 bytes] ‖ [`carriage` (1 byte)] ‖ [`additional_dest_count` (1 byte) ‖ `additional_dest[]` (`additional_dest_count` × CA width)] ‖ `payload_length` (2 bytes) |
| Response | `destination` (1 or 2 bytes) ‖ `payload_length` (2 bytes) ‖ `timestamp_24h_response` (17 bits) ‖ `flags` (7 bits) — packed into 3 bytes ‖ [`offset` (15 bits) ‖ `end` (1 bit) — 2 bytes] ‖ [`carriage` (1 byte)] |

<!-- PSFI-3515 (per-link compression) fragment field added to header_aad (D15); drafted by a Claude agent. -->
Packet class is determined from `message_type_id` ranges (see [Section 4.1](#41-message-type-id-ranges)), so sender and receiver agree on AAD shape. The optional fields in `header_aad` keep their wire order ([Section 5.7.5](#575-optional-field-ordering)). In every class the **fragment field**, the 2-byte `offset` and `end` of [Section 8.2](#82-fragment-structure) exactly as on the wire, follows `flags` and is present only when `IS_FRAGMENT` is set. The `carriage` byte ([Section 5.7.6](#576-optional-field-definitions)) follows the fragment field, or `flags` when the packet is not a fragment, and is present only when `CARRIAGE_PRESENT` is set. In a Response, `flags` are the last 7 bits of the packed 3 bytes, so both fields follow those bytes. For Request packets, the bracketed destination-list fields are present only when `ADDITIONAL_DEST_PRESENT` is set. Because `flags` is authenticated, tampering with the presence of any of these fields invalidates the tag.

The fragment field is authenticated so that a node without the key cannot flip the `end` bit to make a receiver complete a truncated message. The `offset` is also bound through the nonce ([Section 12.2.2](#1222-nonce-derivation)). Earlier revisions of this specification left `end` unauthenticated; that gap predates per-link compression. <!-- PSFI-3515 (per-link compression) fragment field in header_aad (D15) drafted by a Claude agent. -->

The carriage byte is authenticated so that neither the modality mask nor the `PLAIN` bit, which selects the payload key and the tag key ([Section 12.7](#127-payload-form-keys)), can be rewritten in transit undetected. No node changes the mask bits, so authenticating them costs nothing.

`header_aad` fields are authenticated but not encrypted.

When `AUTH_TAG_SIZE != 00`, the tag appears as an optional field after all other optional fields and before payload (see [Section 5.7.5](#575-optional-field-ordering)). `payload_length` covers ciphertext only and excludes tag bytes. When `AUTH_TAG_SIZE = 00`, the tag field is absent.

**Security strength (guidance).**

| `AUTH_TAG_SIZE` | Tag Length | Forgery Resistance |
|---|---|---|
| `01` | 4 bytes | ~1 in 2^32 per attempt |
| `10` | 8 bytes | ~1 in 2^64 per attempt |
| `11` | 16 bytes | ~1 in 2^128 per attempt (full CMAC strength) |

**Flag bit allocation.** `AUTH_TAG_SIZE` occupies Status bits [7:6], Event bits [7:6], Request bits [7:6], and Response bits [6:5]. Event bit 4 is reserved in this protocol version. **[Section 5.7](#57-flags-and-optional-fields) is authoritative** for bit positions. The field MUST be non-zero only when the payload cipher is active (PSK configured). If a node without a PSK receives a packet where `AUTH_TAG_SIZE != 00`, it MUST forward the packet unchanged.

#### 12.2.4 Transport Pipeline

The payload cipher is applied by the node that encodes a payload form for sending — the origin, or a relay that compresses ([Section 9.11.5](#9115-re-encoding-at-relays)) — and by the node that delivers the message. A relay that only forwards performs no cryptographic operation on the payload.

**Originating node (encryption).** When a client sends a message and a PSK is configured:

1. The client submits the plain payload, optionally setting `AUTH_TAG_SIZE`. The transport validates it ([Section 9.11.4](#9114-submit-validation)) and stores the message.
2. When the transport sends the message on a link, it takes the payload form chosen for that link ([Section 9.11.3](#9113-form-selection-per-link)), constructs the packet header fields and the 16-byte nonce, and derives that form's payload key from the epoch key of the message's origin time ([Section 12.4.1](#1241-payload-cipher-key), [Section 12.7](#127-payload-form-keys)).
3. The transport encrypts the whole payload of that form with AES-CTR.
4. If `AUTH_TAG_SIZE != 00`, the transport computes the authentication tag over `nonce || header_aad || ciphertext` under the form's tag key and places it in the optional-field area.

If fragmentation is required, ordering is defined in [Section 12.2.5](#1225-fragmentation-interaction): encrypt first, then fragment, with per-fragment tags when enabled.

**Destination node (decryption).** When a packet is for local delivery and a PSK is configured:

1. Derive the epoch key of the message's origin time ([Section 12.4.1](#1241-payload-cipher-key)). If `AUTH_TAG_SIZE != 00`, reconstruct `header_aad` and nonce, select the tag key from the `PLAIN` bit ([Section 12.7.5](#1275-receiver-key-selection)), verify the tag under that epoch, and on mismatch MUST discard the packet (or fragment).
2. For fragmented messages, reassemble verified fragments of one form to reconstruct its full ciphertext.
3. Derive the form's payload key from the same epoch key, reconstruct the nonce with `fragment_offset = 0`, decrypt with AES-CTR, decode a compressed payload ([Section 9.11.1](#9111-compressed-encoding)), and deliver.

<!-- PSFI-3515 (per-link compression) origin-time epochs (D12 r6) drafted by a Claude agent. -->

**Intermediate nodes (forwarding).** A relay without the PSK stores, schedules, and forwards ciphertext as opaque bytes. A relay that holds the PSK forwards ciphertext unchanged too, except when it re-encodes a message for a compressed link: it verifies the received tag, decrypts, produces the compressed form, encrypts it under the epoch of the message's origin time, and computes a new tag ([Section 9.11.5](#9115-re-encoding-at-relays)). It never re-encodes a copy that carries no tag. Such a relay reads the payloads it re-encodes. <!-- PSFI-3515 (per-link compression) origin-time epoch (D12 r6) and untagged copies (D14) drafted by a Claude agent. -->

**NC bypass.** Network control messages (types 32,000–32,767) bypass this pipeline and are not encrypted.

**Exception: fragmentation and re-fragmentation.** Splitting ciphertext itself requires no cryptographic operation. However, when `AUTH_TAG_SIZE != 00`, any node that creates new fragments MUST compute fresh per-fragment tags (see [Section 12.2.5](#1225-fragmentation-interaction)), which requires the PSK and, for a compressed packet, the type identity of its message type ([Section 12.7.3](#1273-tag-keys)). Nodes without the PSK MUST NOT fragment or re-fragment authenticated packets, and nodes without the type identity MUST NOT fragment or re-fragment authenticated compressed packets of that type; such oversized packets are skipped on that link.

#### 12.2.5 Fragmentation Interaction

When a message is fragmented (see [Section 8](#8-fragmentation-and-reassembly)), each fragment has its own `fragment_offset`; because `fragment_offset` is part of the nonce, each fragment has a distinct nonce.

Canonical ordering is:

1. Encrypt the whole payload of one form using the nonce with `fragment_offset = 0` and that form's payload key ([Section 12.7.1](#1271-key-derivation)). For the compressed form the key depends on the payload's total length.
2. Fragment the ciphertext as needed (including intermediate-node fragmentation or re-fragmentation; see [Section 8.3.2](#832-who-may-fragment)). Fragments are byte slices of that one ciphertext.
3. If `AUTH_TAG_SIZE != 00`, compute a per-fragment tag under the form's tag key ([Section 12.7.3](#1273-tag-keys)) using that fragment's nonce (`fragment_offset = <byte_offset>`), `header_aad`, and ciphertext slice; place the tag in each fragment header. Every fragment carries the same `AUTH_TAG_SIZE` value as the original message.
4. If `AUTH_TAG_SIZE != 00`, verify each fragment tag as fragments arrive and discard failures.
5. Reassemble verified fragments of one form to reconstruct its full ciphertext ([Section 8.4](#84-reassembly)).
6. Derive the form's payload key — for the compressed form from the total length, now known — and decrypt the reassembled ciphertext using the nonce with `fragment_offset = 0`.

`header_aad` MUST be derived from each fragment's own header fields: that fragment's `flags`, fragment field (`offset` and `end`), `carriage` and `payload_length` are included in its AAD ([Section 12.2.3](#1223-authentication-tag)). Per-fragment authentication allows immediate rejection of tampered fragments before reassembly, including a fragment whose `end` bit was flipped. <!-- PSFI-3515 (per-link compression) fragment field in header_aad (D15) drafted by a Claude agent. -->

Only the plain form and the full compressed form are fragmented; a degraded rung always travels in one packet ([Section 8.3.2](#832-who-may-fragment)). Each of these two forms is one ciphertext per message on every node, so fragments cut by different nodes are slices of the same bytes. <!-- PSFI-3515 (per-link compression) fragmentable forms (D15) drafted by a Claude agent. -->

Every copy and every fragment of a message is encrypted under the epoch of its origin time ([Section 12.4.1](#1241-payload-cipher-key)), whichever node encrypts it and whenever. A node that holds the PSK (and, for the compressed form, the type identity) can therefore re-slice a received ciphertext without decrypting it, and tags the new fragments under that same epoch key. <!-- PSFI-3515 (per-link compression) origin-time epochs (D12 r6) drafted by a Claude agent. -->

Figure 13 illustrates the encrypt-then-fragment and verify-then-reassemble-then-decrypt ordering at the originating and destination nodes.

```mermaid
---
config:
  theme: default
  layout: elk
  themeVariables:
    background: '#ffffff'
---
flowchart TD
    subgraph orig["Originating Node"]
        direction LR
        O1["1. Plaintext"]:::green
        O2["2. Encrypt whole payload<br>(nonce: fragment_offset=0)"]:::crypto
        O3["3. Fragment ciphertext;<br>auth tag per fragment"]:::blue
        O1 --> O2 --> O3
    end

    subgraph dest["Destination Node"]
        direction LR
        D1["1. Receive fragments"]:::blue
        D2["2. Verify auth tag<br>per fragment"]:::crypto
        D2F["Discard corrupted"]:::red
        D3["3. Reassemble;<br>decrypt full ciphertext"]:::crypto
        D4["4. Deliver plaintext"]:::green
        D1 --> D2
        D2 -->|"pass"| D3
        D2 -->|"fail"| D2F
        D3 --> D4
    end

    orig ==>|"SCF"| dest

    classDef green fill:#82e0aa,color:#2c3e50,stroke:#27ae60,stroke-width:2px
    classDef crypto fill:#5dade2,color:#2c3e50,stroke:#1a5276,stroke-width:2px
    classDef blue fill:#85c1e9,color:#2c3e50,stroke:#2980b9,stroke-width:2px
    classDef red fill:#f1948a,color:#2c3e50,stroke:#e74c3c,stroke-width:2px
```

**Figure 13 — Fragmentation and Encryption Interaction**

**Note:** Implementations MAY decrypt per fragment by adjusting the AES-CTR counter to the fragment offset, but whole-message decrypt after reassembly is RECOMMENDED.

### 12.3 DataLink-Layer Encryption

**[GUIDANCE]**

#### 12.3.1 Role

DataLink-layer encryption provides **per-hop confidentiality and integrity** on individual link segments. It is the responsibility of each DataLink adapter and operates below the M4P transport layer. The transport layer is unaware of whether a DataLink encrypts its transmissions.

DataLink-layer encryption complements the M4P payload cipher (see Figure 12 for the two-layer interaction across a multi-hop path):

**M4P Payload Cipher vs. DataLink-Layer Encryption**

| Property | M4P Payload Cipher | DataLink Layer |
|---|---|---|
| Scope | Originating node to destination node | Per-hop (single link segment) |
| Confidentiality | Yes (AES-CTR) | Yes (when using TLS, IPsec, etc.) |
| Integrity / Authentication | Optional (4/8/16-byte auth tag per `AUTH_TAG_SIZE`) | Yes (when using TLS, IPsec, etc.) |
| Header protection | No (headers in the clear) | Yes (entire transmission encrypted) |
| What is protected | Application message payloads only | All M4P data including headers and NC messages |
| Intermediate node involvement | None without the PSK — ciphertext forwarded as-is; a relay with the PSK may re-encode for a compressed link | Each hop encrypts/decrypts |
| Key source | Master PSK → HKDF epoch derivation | Per-modality provisioning |
| Key rotation | Epoch-based (e.g., 6–12 hours) | Modality-specific procedures |
| Transition window | None — each message's epoch comes from its origin time | N/A (per-hop, immediate) |
| Relay nodes need key? | No to forward ciphertext as-is; yes to compress onto a compressed link | Yes — per-hop encrypt/decrypt |
| Independence | Not derived from DataLink keys | Not derived from M4P PSK |

#### 12.3.2 Recommended DataLink Security by Modality

Deployments SHOULD enable DataLink-layer encryption on IP-based links, which are typically the easiest to intercept or inject.

- **IP/MQTT.** SHOULD use TLS 1.2+ with mutual authentication (client certificates). This protects all M4P traffic on that hop (including headers and NC payloads), authenticates peers and broker, and mitigates man-in-the-middle attacks on IP networks. TLS overhead is below M4P and does not consume M4P payload budget.
- **LAN.** SHOULD use IPsec (ESP) or equivalent link protection (for example, WireGuard or MACsec). This protects confidentiality and integrity on the LAN segment; overhead is at the IP/link layer, not the M4P payload budget.
- **Acoustic.** Link-layer encryption is often unavailable. The M4P payload cipher provides payload confidentiality, and integrity-sensitive traffic SHOULD set `AUTH_TAG_SIZE != 00` (see [Section 12.2.3](#1223-authentication-tag)). If modem-native link encryption exists, it SHOULD be enabled as an additional layer.
- **Radio.** SHOULD enable radio COMSEC or waveform-provided encryption when available. If unavailable, the M4P payload cipher still protects payload confidentiality.
- **Satellite.** SHOULD use TLS or DTLS when the terminal provides IP transport. Proprietary terminal encryption MAY provide an additional layer when available.

#### 12.3.3 Gateway and Bridge Behavior

When a node bridges traffic between modalities with different DataLink-layer encryption capabilities, DataLink-layer encryption and decryption are handled independently by each DataLink adapter at each hop. What the bridge does with the M4P payload depends on what it holds.

**A bridge without the PSK never modifies M4P ciphertext.** It:

1. Receives a transmission on one DataLink (e.g., LAN with IPsec). The DataLink adapter decrypts at the link layer, yielding M4P packets with encrypted payloads.
2. Stores the packets in the local message store (payload ciphertext intact).
3. When a transmission opportunity arises on another DataLink (e.g., acoustic), packs the packets into a transmission. The acoustic DataLink transmits them — the payload ciphertext is unchanged.

No re-encryption, tag stripping, or modality-aware crypto logic is required.

**A bridge with the PSK may re-encode.** A bridge that holds the PSK and the type's definition compresses a message it puts onto a compressed link ([Section 9.11.5](#9115-re-encoding-at-relays)): it verifies the received tag, decrypts, encodes the compressed form, encrypts it under the epoch of the message's origin time with the key of [Section 12.7](#127-payload-form-keys), and computes a new tag. Such a bridge may also build degraded rungs of a degradable message it relays ([Section 9.11.5](#9115-re-encoding-at-relays)). It never fragments a degraded rung, whether it built the rung or received it ([Section 8.3.2](#832-who-may-fragment)). It never re-encodes or degrades a copy that carries no tag. A bridge that re-encodes therefore reads the payloads it relays; it is inside the deployment's trust domain ([Section 12.6.2](#1262-what-this-model-does-not-provide)). It never produces the plain form from a compressed one. <!-- PSFI-3515 (per-link compression) relay degradation permitted in this revision (D8); origin-time epoch (D12 r6), untagged copies (D14) and rungs never fragmented (D15); drafted by a Claude agent. -->

**A bridge without a type's identity** ([Section 12.7.2](#1272-type-identity)) forwards that type's compressed packets as received. On an encrypted network it cannot re-fragment them when they are tagged, because each new fragment needs a tag keyed by the type identity. It still re-fragments plain packets when it holds the PSK.

### 12.4 Key Management

#### 12.4.1 Payload Cipher Key

The M4P payload cipher uses the deployment PSK (see [Section 2.4.2](#242-required-configuration-must)). PSK provisioning is outside this specification and handled by deployment operations.

All nodes that host clients producing or consuming messages MUST use the same PSK. Relay-only nodes (no hosted clients) do not need the PSK and forward ciphertext as opaque bytes. A node with a compressed link SHOULD hold the PSK and the message catalog so that it can compress what it relays ([Section 9.11.5](#9115-re-encoding-at-relays), [Appendix C.3](#c3-payload-forms-and-catalogs)). Every node that holds the PSK can read every payload it relays.

**Epoch keys.** A deployment that uses the payload cipher MUST treat the provisioned PSK as a **master key** from which short-lived **epoch keys** are derived, and MUST rotate them on a time-based schedule that meets [Section 12.7.6](#1276-epoch-rotation-requirement).

<!-- PSFI-3515 (per-link compression) epoch key derivation made normative; drafted by a Claude agent. -->

**Epoch key derivation.** Every node MUST derive epoch keys as follows, so that all nodes derive the same key for the same epoch:

```text
epoch_key = HKDF-Expand(
    PRK    = master_psk,
    info   = "M4P-epoch" || network_id || epoch_number,
    L      = 32  (AES-256 key length)
)

epoch_number = floor(origin_time / P)
```

- **HKDF** is HKDF-Expand ([RFC5869]) with SHA-256, as for the payload form keys ([Section 12.7.1](#1271-key-derivation)). `PRK` is the master PSK itself; nodes do not apply HKDF-Extract.
- **`"M4P-epoch"`** is the 9-octet ASCII string `M4P-epoch`.
- **`network_id`** is the deployment's `network_id` ([Section 2.4.2](#242-required-configuration-must)) as its UTF-8 bytes, with no length prefix or terminator.
- **`epoch_number`** is an unsigned 64-bit integer encoded as 8 big-endian octets.
- **`origin_time`** is the message's origin time (below) in whole seconds since 1970-01-01T00:00:00Z, and **`P`** is the rotation period in seconds.

<!-- PSFI-3515 (per-link compression) origin-time epochs (D12 r6) drafted by a Claude agent. -->

**Origin time.** A message's origin time is the absolute time of the timestamp in its nonce ([Section 12.2.2](#1222-nonce-derivation)): `timestamp_24h` for a Status, Event or Request, and `timestamp_24h_request` for a Response, whose nonce carries its request's timestamp. A node expands that 24-hour timestamp into an absolute time as the latest instant at or before its own clock plus 3,600 seconds whose UTC seconds since midnight equal the timestamp:

```text
origin_time = (clock + 3600) - ((clock + 3600 - timestamp) mod 86400)
```

where `clock` is the node's current time in whole seconds since 1970-01-01T00:00:00Z and `mod` returns a value from 0 to 86,399. The 3,600 seconds are a clock-skew allowance. The 23 hours the expansion reaches back cover a Response encrypted up to about 14.9 hours after its request (two maximum TTLs, 2 × 26,760 s; [Section 5.7.6](#576-optional-field-definitions)). This expansion is separate from the ±12-hour age normalization of [Section 5.6](#56-field-definitions), which still governs age and TTL; that normalization would place a timestamp more than 12 hours old a day too late.

The derived epoch key is the active payload cipher key for every message whose origin time falls in that epoch, at every node that encrypts, verifies or decrypts the message. It avoids nonce reuse across epoch boundaries (see [Section 12.2.2](#1222-nonce-derivation), *24-hour wrap behavior*). This assumes the master PSK is uniformly random 256-bit key material. If it comes from a passphrase or other low-entropy source, the deployment SHOULD derive the 32-octet master PSK from it with HKDF-Extract ([RFC5869]) before provisioning, so that every node holds the same master PSK.

A deployment that uses the master PSK directly, without epoch rotation, does not meet [Section 12.7.6](#1276-epoch-rotation-requirement) and reuses keystream across the 24-hour wrap described in [Section 12.2.2](#1222-nonce-derivation), *24-hour wrap behavior*.

See [Section 12.3.1](#1231-role) for a comparison of the M4P payload cipher and DataLink-layer encryption, including key management properties.

#### 12.4.2 Key Scope

The PSK is scoped to a deployment (network ID). Different deployments SHOULD use different keys. Combined with the `network_id_hash` in the nonce, this ensures that ciphertext from one deployment is not decryptable with another deployment's key, even if message header fields happen to collide.

#### 12.4.3 Key Rotation

<!-- PSFI-3515 (per-link compression) origin-time epochs (D12 r6) drafted by a Claude agent. -->

**Epoch rotation.** Epoch rotation needs no transition window. Every node derives a message's epoch from its origin time ([Section 12.4.1](#1241-payload-cipher-key)), so the origin, every relay and every receiver use the same epoch key for that message, whenever they handle it. A receiver derives that one epoch's key, which it MAY cache, and verifies and decrypts with exactly that key; it does not try a second key. A node needs no stored previous keys, because it can derive the key of any epoch from the master PSK.

**Manual PSK replacement.** Replacing the master PSK requires DTN-aware coordination, because nodes may not change over simultaneously and nodes holding different PSKs cannot exchange encrypted payloads.

**Epoch synchronization.** All nodes derive from the same master PSK and the same period *P*. They do not need to agree on the current epoch, because a message's epoch comes from the origin time in its header. A node's clock enters only the expansion of the 24-hour timestamp ([Section 12.4.1](#1241-payload-cipher-key)), which allows for a sender's clock running up to one hour ahead of the receiver's. Deployments MUST choose a rotation period that meets [Section 12.7.6](#1276-epoch-rotation-requirement), at most 24 hours, and SHOULD use 12 hours.

The nonce's `reserved` octets (14–15) are the low octets of the AES-CTR counter ([Section 12.2.2](#1222-nonce-derivation)). They stay `0x0000` in the initial counter block and do not carry a key epoch identifier.

#### 12.4.4 DataLink-Layer Keys

DataLink-layer key management is modality-specific:

- **MQTT/TLS:** X.509 certificates or PSK, managed per standard TLS provisioning practices.
- **IPsec:** Pre-shared keys or certificates, managed per standard IPsec/IKE provisioning.
- **Radio COMSEC:** Managed per the radio system's key management procedures.
- **Satellite:** Managed per the satellite terminal's security provisioning.

DataLink-layer keys are independent of the M4P payload cipher PSK.

### 12.5 Identity Obfuscation

NodeUIDs and ClientUIDs are opaque strings from M4P's perspective: transport and network logic do not interpret UID content. Applications MAY provide obfuscated UIDs (for example, pseudonyms instead of `vehicle-123`), and M4P uses them unchanged for address derivation, NC payloads, and conflict handling. This preserves protocol behavior while reducing identity exposure in NC traffic, which is not encrypted by the payload cipher.

Identity obfuscation is an application-layer responsibility. M4P does not define the mechanism, but all nodes in a deployment MUST apply the same scheme so the same logical identity maps to the same obfuscated UID. Deployments in contested environments SHOULD obfuscate all NodeUIDs and ClientUIDs (for example, HMAC-based pseudonymization) to reduce passive fleet enumeration.

### 12.6 Security Properties and Limitations

#### 12.6.1 What This Model Provides

- **Payload confidentiality from originating node to destination node** across all modalities, against every node that does not hold the PSK. Intermediate forwarding nodes without the PSK cannot access plaintext payloads. A relay that holds the PSK can, and re-encodes payloads for compressed links ([Section 12.3.3](#1233-gateway-and-bridge-behavior)).
- **Per-message payload integrity and authentication** via the optional authentication tag (`AUTH_TAG_SIZE`: 4, 8, or 16 bytes).
- **Per-hop integrity and confidentiality** on IP-based links (LAN, MQTT) via standard link-layer security (TLS, IPsec).
- **Defense in depth:** The M4P payload cipher and DataLink-layer encryption operate independently. Compromise of one layer does not compromise the other.
- **Transparent bridging:** Gateway nodes without the PSK forward ciphertext payloads without cryptographic awareness or processing.
- **Transparent to applications:** Clients publish and subscribe as usual; M4P transport handles cryptographic operations when PSK is configured.

#### 12.6.2 What This Model Does Not Provide

- **Application-to-application confidentiality.** Originating and destination M4P transports see plaintext payloads. Applications that require confidentiality from M4P SHOULD encrypt payloads before submission. Such a payload has no compressed form and travels in the plain form on every link.
- **Confidentiality from relays that hold the PSK.** A relay that holds the PSK can decrypt every payload it relays, and one with a compressed link does so to compress ([Section 12.3.3](#1233-gateway-and-bridge-behavior)).
- **Header confidentiality (end-to-end).** Transport headers (source/destination CA, message type, timestamps, payload length) remain in the clear; observers can infer communication patterns. DataLink encryption protects headers per-hop on supported links, not end-to-end.
- **Protection against traffic analysis.** Even with the payload cipher and DataLink-layer encryption, packet sizes, timing, and addressing patterns are observable. M4P does not provide traffic flow confidentiality.
- **NC message payload confidentiality (end-to-end).** NC payloads containing NodeUIDs and ClientUIDs are not encrypted by the payload cipher; they rely on DataLink-layer encryption where available. Identity obfuscation (see [Section 12.5](#125-identity-obfuscation)) mitigates passive exposure.

**Design Note (Non-Normative): Threat model alignment.** This model targets autonomous maritime deployments where fleet nodes share a trust domain. Every node that holds the PSK is inside that trust domain: it can read, re-encode and re-tag the payloads it relays. Primary threats and mitigations:

- **Passive IP eavesdropping:** Mitigated by DataLink-layer TLS/IPsec plus the M4P payload cipher.
- **Active IP interception/injection:** Mitigated by DataLink mutual authentication and integrity protections.
- **Passive acoustic eavesdropping:** Mitigated by the M4P payload cipher.
- **Active acoustic tampering:** Mitigated when `AUTH_TAG_SIZE != 00` is used (see [Section 12.2.3](#1223-authentication-tag)).

**Standards alignment.** M4P specifies AES-256-CTR (NIST SP 800-38A) and AES-CMAC (NIST SP 800-38B). Deployments requiring FIPS 140-2/3 assurances SHOULD use validated modules. Independent payload-cipher and DataLink layers support defense in depth (for example, CSfC). AES-256 satisfies CNSA 2.0 symmetric baseline requirements.

### 12.7 Payload Form Keys {#127-payload-form-keys}

<!-- PSFI-3515 (per-link compression) section drafted by a Claude agent; supersedes the unmerged representation-keying section of m4p-spec PR #1. -->

An application payload travels in one of two forms ([Section 9.11](#911-payload-forms)): the **plain form**, the protobuf bytes the origin's client submitted, or the **compressed form**, the type's full DCCL encoding or one of its degraded rungs. The nonce ([Section 12.2.2](#1222-nonce-derivation)) is derived only from identity header fields, so every form and every length of one message share one nonce. AES-CTR requires distinct plaintexts under one nonce to use distinct keys, otherwise they reuse keystream. This section derives one payload key for the plain form and one per type identity and total length for the compressed form, and a tag key for each form. A Response's keys also bind the requester's CA, because its nonce does not carry it. It applies to every application payload whenever the payload cipher is active, fragmented or not.

#### 12.7.1 Key Derivation {#1271-key-derivation}

```text
plain_key = HKDF-Expand(
    PRK  = <active payload cipher key>,
    info = "M4P-plain",
    L    = 32)

compressed_key = HKDF-Expand(
    PRK  = <active payload cipher key>,
    info = "M4P-comp" || type_identity || total_length_be16,
    L    = 32)
```

- **`"M4P-plain"`** is the 9-octet ASCII string `M4P-plain`; **`"M4P-comp"`** is the 8-octet ASCII string `M4P-comp`.
- **`type_identity`** is the 32-octet identity of the message's type ([Section 12.7.2](#1272-type-identity)).
- **`total_length_be16`** is the length of the whole compressed payload as two big-endian octets: the `payload_length` of an unfragmented packet, or the length of the reassembled payload of a fragmented one. The `info` string is 42 octets.

**One ciphertext per form and length.** The sender encrypts the whole payload of one form and length once, with the nonce at `fragment_offset = 0` and that form's key, and every fragment is a byte slice of that ciphertext ([Section 12.2.5](#1225-fragmentation-interaction)). A receiver derives the compressed key after reassembly, when the total length is known. A node that holds the PSK and the type identity can therefore re-slice a received compressed ciphertext without decrypting it.

**HKDF-SHA-256 is pinned.** Payload form keys MUST use HKDF ([RFC5869]) with SHA-256. Every node derives these keys independently from cleartext header fields with no negotiation, so the construction is fixed network-wide. Epoch key derivation ([Section 12.4.1](#1241-payload-cipher-key)) is fixed the same way. <!-- PSFI-3515 (per-link compression) sentence updated with the normative epoch derivation; drafted by a Claude agent. -->

**PRK provenance.** `PRK` is the active payload cipher key: the epoch key of the epoch the message's origin time falls in when epoch rotation is configured ([Section 12.4.1](#1241-payload-cipher-key)), or the master PSK when it is not. Every node that encrypts, verifies or decrypts the message uses that same epoch ([Section 12.7.6](#1276-epoch-rotation-requirement)). <!-- PSFI-3515 (per-link compression) origin-time epochs (D12 r6) drafted by a Claude agent. -->

**Response key.** A Response's nonce carries the responder's CA and the Request's timestamp and counter, but not the requester's CA ([Section 12.2.2](#1222-nonce-derivation)). For a Response, the active payload cipher key is therefore first expanded with the requester's CA:

```text
response_key = HKDF-Expand(
    PRK  = <active payload cipher key>,
    info = "M4P-response" || requester_ca_be16,
    L    = 32)
```

- **`"M4P-response"`** is the 12-octet ASCII string `M4P-response`. **`requester_ca_be16`** is the Response's `destination`, the requester's CA, as two big-endian octets, zero-padded in 8-bit addressing as `source_ca` is in the nonce. The `info` string is 14 octets.
- For a Response, `response_key` takes the place of the active payload cipher key in every derivation of this section: it is the `PRK` of the Response's payload keys and compressed tag key, and its plain tag key ([Section 12.7.3](#1273-tag-keys)). Status, Event and Request keys are derived from the active payload cipher key directly.
- No wire bytes are added: the `destination` is in every Response header. <!-- PSFI-3515 (per-link compression) Response key (D17) drafted by a Claude agent. -->

#### 12.7.2 Type Identity {#1272-type-identity}

A message type with a DCCL definition has a **type identity**: SHA-256 over everything that decides its compressed bytes.

```text
type_identity = SHA-256(
    fingerprint                   32 octets
    drop_order_count              uint32, big-endian
    for each drop-order entry, in ladder order:
        path_length               uint32, big-endian
        field_number[path_length] uint32 each, big-endian, root to leaf
        retention_priority        uint8
    compressed_encoding_version   uint32, big-endian)
```

<!-- PSFI-3515 (per-link compression) fingerprint and compressed_encoding_version made implementable from the text; drafted by a Claude agent. -->

- **`fingerprint`** is the 32-octet per-type DCCL fingerprint that `MessageFingerprint` computes in the dccl-rs crate `dccl` 0.1.0 at commit `212b2b155e8d3eca5274e02bbff206481c6ccdaf` ([DCCL-RS]). This specification adopts that computation by normative reference: SHA-256 over a canonical walk of the type's DCCL definition. It covers what determines the full compressed encoding: field numbers, labels, types and order, DCCL bounds and codec options, the DCCL message id, and the same for every nested message. Names, comments, defaults, `max_bytes`, transport priority, TTL and routing or retention annotations do not affect it. A self-contained definition of the fingerprint is forthcoming in an appendix.
- **The drop order** lists every field that carries a retention priority ([Section 9.11.2](#9112-degraded-rungs)) and is reachable from the message through singular message fields: never through repeated or map fields, and never into a message type already on the path from the root. It is listed in the ladder order of [Section 9.11.2](#9112-degraded-rungs): ascending retention priority, ties broken by lexicographic comparison of root-to-leaf field-number paths. Field paths are field numbers, so renaming a field does not change the identity.
- **`compressed_encoding_version`** is assigned by this specification; an implementation does not choose it. Value `1` identifies the compressed encoding of [Section 9.11.1](#9111-compressed-encoding) and the ladder of [Section 9.11.2](#9112-degraded-rungs) as this revision defines them, with the DCCL encoding of DCCL 5.0.0 ([DCCL]), the version the reference codec uses. An implementation whose encoder or ladder produces different bytes for any message does not conform to this revision, and choosing another value does not make it conform. A later revision that changes the compressed encoding or the ladder assigns a new value. The test vectors of [Appendix D](#appendix-d-test-vectors-forthcoming) pin version 1.

Two nodes that compute the same type identity for a type produce byte-identical compressed forms of the same message ([Section 9.11.2](#9112-degraded-rungs)). A type with no DCCL definition has no type identity and only the plain form.

#### 12.7.3 Tag Keys {#1273-tag-keys}

```text
plain_tag_key      = <active payload cipher key>

compressed_tag_key = HKDF-Expand(
    PRK  = <active payload cipher key>,
    info = "M4P-comp-tag" || type_identity,
    L    = 32)
```

`"M4P-comp-tag"` is the 12-octet ASCII string `M4P-comp-tag`. The tag is computed and verified as in [Section 12.2.3](#1223-authentication-tag), per packet and per fragment, under the tag key of the packet's form. No wire bytes are added.

- Any node that holds the PSK can verify, re-tag and re-fragment a plain packet, whatever its message catalog.
- Verifying, re-tagging or re-fragmenting a compressed packet also requires the type identity. A node without it MUST treat the tag of a compressed packet as unverifiable: it forwards the packet as received, and MUST NOT re-tag or re-fragment it.
- A compressed packet made under a different type identity fails the tag.
- A node MUST NOT compute a new tag for a message it did not originate, re-encoded or re-sliced, unless that message's inbound tag verified. A node MUST NOT give an unverified packet a valid tag. <!-- PSFI-3515 (per-link compression) requirement rephrased; drafted by a Claude agent. -->
- A node that would deliver a message MUST discard a copy whose tag fails. That copy is neither stored nor delivered, and it does not suppress a later copy ([Section 6.5](#65-deduplication-rules)).

#### 12.7.4 Shared Nonce and Counter Discipline {#1274-shared-nonce-and-counter-discipline}

Every form and length of one message is encrypted under the standard nonce ([Section 12.2.2](#1222-nonce-derivation)) with `fragment_offset = 0x0000` and the `reserved` octets (14–15) at `0x0000`, and under the epoch of the message's origin time ([Section 12.4.1](#1241-payload-cipher-key)). Separation between forms and lengths comes entirely from their keys. Two rules follow: <!-- PSFI-3515 (per-link compression) frozen-slice rule removed with origin-time epochs (D12 r6); rungs-travel-whole rule added (D15); drafted by a Claude agent. -->

- **Equal key, equal bytes.** Under one type identity, every node that produces a compressed form of a message of a given total length produces the same bytes ([Section 9.11.2](#9112-degraded-rungs)), and the ladder keeps each rung strictly shorter than the last. A node MUST NOT encrypt two different compressed payloads of one message with equal total length under one type identity.
- **Rungs travel whole.** Two degraded rungs of one message share its nonce and its compressed tag key ([Section 12.7.3](#1273-tag-keys)), and a fragment's tag binds its offset but not the rung it was cut from. Fragments of two rungs could therefore be spliced into one payload whose every fragment verifies. A degraded rung is never fragmented ([Section 8.3.2](#832-who-may-fragment)); only the plain form and the full compressed form, each one byte string per message, are. This is a rule for senders: the receiver still selects keys without knowing which types are degradable ([Section 12.7.5](#1275-receiver-key-selection)). <!-- PSFI-3515 (per-link compression) rungs travel whole (D15) drafted by a Claude agent. -->

**Counter discipline.** Octet 15 is the least-significant counter octet ([Section 12.2.2](#1222-nonce-derivation)), so the low nonce octets lie inside the counter's increment region. A per-form discriminator in those octets would put forms on overlapping counter runs and reuse keystream; these keys avoid that by leaving the nonce fixed and varying the key. A 16-bit payload length confines each payload's counter to octets 14–15, so they are `0x0000` in the initial counter block of every form.

#### 12.7.5 Receiver Key Selection {#1275-receiver-key-selection}

A receiver selects both keys from the authenticated header ([Section 12.2.3](#1223-authentication-tag)) and its own message catalog:

```text
active key = epoch key of the message's origin time (Section 12.4.1)
if the packet is a Response:
    active key = response_key(active key, destination)   (Section 12.7.1)

if the carriage byte is present and PLAIN is set:
    tag key     = plain_tag_key
    payload key = plain_key
else:
    tag key     = compressed_tag_key(type_identity of message_type_id)
    payload key = compressed_key(type_identity, total length)
```

The carriage byte is part of `header_aad`, so `PLAIN` cannot be flipped without failing the tag. The receiver does not need to know which types are degradable: a degraded rung and the full compressed form differ only in length. A receiver without the type identity of a compressed packet cannot verify or decrypt it, and only forwards it. The receiver verifies and decrypts with keys derived from that one epoch key ([Section 12.4.3](#1243-key-rotation)) and makes no attempt under another epoch. Untagged traffic is decrypted under the same keys, with no integrity signal. <!-- PSFI-3515 (per-link compression) origin-time epochs (D12 r6) drafted by a Claude agent. -->

#### 12.7.6 Epoch Rotation Requirement {#1276-epoch-rotation-requirement}

Every node encrypts, verifies and decrypts a message under the epoch its origin time falls in ([Section 12.4.1](#1241-payload-cipher-key)): the origin, re-encoding relays and receivers alike, however long the message is held. The timestamp in the nonce repeats every 24 hours ([Section 12.2.2](#1222-nonce-derivation)), so two messages with the same nonce inputs have origin times at least 24 hours apart. They fall in different epochs whenever the period *P* is at most 24 hours.

A deployment that enables the payload cipher MUST therefore use time-based epoch rotation ([Section 12.4.1](#1241-payload-cipher-key), [Section 12.4.3](#1243-key-rotation)) with a period *P* of at most 24 hours. A 12-hour period is RECOMMENDED. Timing jitter does not replace epoch rotation. An implementation SHOULD warn when it is configured with the payload cipher and a period above 24 hours, and SHOULD NOT refuse to run because of it. <!-- PSFI-3515 (per-link compression) origin-time epochs (D12 r6) drafted by a Claude agent. -->

---

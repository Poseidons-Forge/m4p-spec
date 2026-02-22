## 7. Time-to-Live and Packet Expiration {#7-time-to-live-and-packet-expiration}
**[WIRE FORMAT + BEHAVIORAL]**

**Default TTL.** Every Message Type ID has a configured default TTL (see [Section 2.4.3](#243-recommended-configuration-should)). If a node has no configured default TTL for a given Message Type ID, it MUST fall back to an implementation-defined generic default TTL as required by [Section 2.4.3](#243-recommended-configuration-should). Deployments SHOULD ensure that per-message-type TTL defaults are configured for all expected Message Type IDs to avoid reliance on this fallback.

**Effective TTL.** The effective TTL for a packet is determined as follows:

- If `TTL_OVERRIDE_PRESENT` is set: the effective TTL is `decode_ttl(ttl_override)` (see [Section 5.7.6](#576-optional-field-definitions)).
- Otherwise: the effective TTL is the message type's configured default TTL.

**TTL override encoding.** The `ttl_override` field uses the piecewise-linear encoding defined in [Section 5.7.6](#576-optional-field-definitions).

**Special case — one-hop semantics (`ttl_override = 0`):** When `ttl_override` is `0`, the packet is governed by transmission-count semantics rather than time-based expiration. The originating node transmits the packet once per DataLink adapter instance; receiving nodes MUST NOT forward it further. One-hop packets are still subject to MIID-based deduplication.

**Expiration rules.** A packet is **expired** if:

```text
calculate_packet_age(current_time_24h, packet_timestamp_24h) > effective_TTL_seconds
```

Where `calculate_packet_age` uses the modular arithmetic defined in [Section 5.6](#56-field-definitions).

- Nodes MUST discard expired packets from their message stores.
- Nodes MUST NOT forward expired packets.
- Nodes MUST NOT deliver expired packets to local clients.

Status and Event differ in retention semantics while sharing the same expiration rules: Status entries are latest-value by variant, while Event messages are retained as independent message instances until expiration.

---


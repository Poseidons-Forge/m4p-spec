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

### 11.11 Demand-State Record {#1111-demand-state-record}

**[WIRE FORMAT + BEHAVIORAL]**

*Drafted by a Codex agent for PSFI-1347, 2026-08-31.*

`NC_DEMAND_STATE` is the compact, network-control representation of requests that a node still
wants answered and request/response pairs that it knows are satisfied. It is an NC Announce
current-state record with Message Type ID `32,040`, forwarding scope **Everywhere**, default
priority `120`, and default TTL `120` seconds. It is not bootstrap-exempt: pending local claim and
remote-data-forwarding policy apply to it in the same way as application data.

The record is a statement by one node about demand belonging to the clients that node hosts. It
does not carry a route, a peer-knowledge estimate, or a channel estimate.

#### 11.11.1 Payload Encoding

The payload is encoded in the following exact order. `CA width` is one byte in 8-bit addressing
mode and two bytes, big-endian, in 16-bit addressing mode.

```text
Field                                      Width
-----------------------------------------  -------------------------
group_count                                1 byte

repeated group_count times:
  requester_ca                             CA width
  wanting_count                            1 byte
  satisfied_count                          1 byte
  wanting request-MIID remainders          wanting_count * 3 bytes
  satisfied entries                        satisfied_count * (3 bytes + CA width)
```

Each satisfied entry contains its three-byte request-MIID remainder followed immediately by its
`responder_ca`. Counts are unsigned eight-bit integers; therefore a payload contains at most 255
requester groups and each group contains at most 255 wanting and 255 satisfied entries. Zero
groups and groups with zero entries are valid encodings. A receiver MUST reject a truncated
payload, a count that cannot be satisfied by the remaining bytes, an invalid address, an invalid
request timestamp, or trailing bytes after the declared groups.

A request MIID is normally `requester_ca ++ timestamp_24h[17] ++ msg_counter[7]`. The demand NC
header, however, is sourced by a Node Address and cannot supply the requester's Client Address.
For that reason each group carries `requester_ca` once, followed by source-free request-MIID
remainders:

```text
 0                   1                   2
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          timestamp_24h (17b)      |msg_ctr (7)|
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

`timestamp_24h` MUST be in the range `0` through `86,399`. The requester prefix plus the
three-byte remainder MUST reconstruct the canonical Request MIID for the deployment's addressing
mode.

For address width `A` bytes, `G` groups, and per-group counts `W_g` and `S_g`, the payload size is:

```text
1 + sum(g = 1..G, A + 2 + 3*W_g + (3 + A)*S_g)
```

The NC Announce header contributes `6 + A` bytes. Consequently, one group containing one wanting
entry and no satisfied entry occupies 14 bytes on the wire in 8-bit mode and 16 bytes in 16-bit
mode.

#### 11.11.2 Authorship, Validation, and Supersession

There is at most one retained demand-state version per source Node Address. A receiver MUST accept
the source as the single writer only when its current address table maps every `requester_ca` in
the payload to the NC header's source Node Address. If any requester address is unknown or mapped
to another host, the receiver MUST reject the entire record as malformed; it MUST NOT apply a
partial payload.

An originator MUST publish a fresh demand-state MIID only when it adds a wanting entry or a
satisfied entry. Removing an answered or expired entry does not by itself create a new version;
removals are reflected when the next addition creates a version. If no later addition occurs, an
empty state expires without an empty replacement.

For `NC_DEMAND_STATE`, a receiver MUST replace retained state only with a newer MIID from the same
source. Newness is determined by `timestamp_24h` modulo 86,400 using a half-day comparison window;
within the same second, the greater seven-bit message counter is newer. A same-MIID, same-payload,
same-content, or older version is a duplicate and MUST NOT regress retained state. This ordering
allows supersession across midnight while rejecting replayed versions.

#### 11.11.3 Originator Lifecycle

A locally originated Request with a nonzero TTL becomes a wanting entry after the configured
demand-join interval if it remains unanswered. The recommended default join interval is three
seconds. A TTL-zero Request is one-hop traffic and MUST NOT join demand state.

A wanting Request is **covered** when at least one confirmed peer is known to hold it, excluding
the origin host when that host is known. If the local demand-state record is present in the final
packing plan for a link opportunity, the originator suppresses each covered Request represented by
that record for that opportunity. If the record does not fit or otherwise loses packing, it
suppresses nothing. An uncovered Request continues to travel in its full form because a compact
want cannot restore content that no peer is known to hold.

For each covered Request, the originator counts successful demand-record sends that suppressed the
Request. After the configured dry-send limit, the full Request is allowed through once and the
count resets after that Request succeeds. The recommended default dry-send limit is three.

The originator adds a satisfied entry `(request_miid, responder_ca)` when it receives that
response through a relay or when the corresponding want has previously been advertised. Each
destination of a group Request has its own satisfied entry. A wanting entry remains logically
unresolved until every destination has a satisfied entry; as with every removal, its disappearance
is carried by the next addition-driven version.

#### 11.11.4 Receiver Behavior

Receivers and carriers store and forward the demand record verbatim. They MUST NOT copy remote
wants into their own demand state, and they do not fetch a Request that they do not already hold.
After the trust and supersession checks above, a receiver applies the following evidence:

| Evidence | Trigger | Required effect |
|---|---|---|
| E6 — wanting | A wanting entry names Request `r` from requester host `v`. | For each locally held, not-satisfied Response to `r`, clear knowledge that `v` holds that Response and reopen its spacing state on the inbound link. If the node holds `r` but no Response to it, clear only soft knowledge in the Request row and reopen the Request's spacing; confirmed holding facts remain. |
| E7 — satisfied | A satisfied entry names `(r, d)` from requester host `v`. | Confirm that `v` holds the locally retained Response from `d`, mark destination `d` answered for the retained Request, and, when `d` resolves to a host, confirm that host holds the Request. Response carriage toward `v` is then terminal; a Request is terminal after every destination is answered. |

E6 and E7 are applied once when a carried demand version is first accepted. A repeated hearing of
that same version reapplies E6/E7 only when the wire sender is also the record's source Node
Address. This lets the requester's own repeated statement reopen a stale gradient without allowing
an arbitrary carrier replay to do so.

#### 11.11.5 Forwarding and Mixed Fleets

Demand state follows the ordinary retained-record forwarding path: it competes by priority and
audience novelty, obeys the common spacing ladder, and remains eligible on infrastructure and mesh
links because its scope is Everywhere. Its alternative grouping with covered Requests is a packing
decision, not a priority exception.

An older receiver that does not recognize type `32,040` retains the packet as an undecoded NC
Announce instance. Because no registry entry is available, that receiver uses its configured
generic default priority and TTL and applies no NC scope restriction. The packet follows the
ordinary novelty and spacing path until expiry, including forwarding across multiple hops when
opportunities arise. This is bounded store-and-forward behavior, not one-pass carriage. With the
stock core configuration, the generic defaults are priority `50` and TTL `60` seconds.

---

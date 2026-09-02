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

## 10. DataLink Abstraction {#10-datalink-abstraction}

**[GUIDANCE + BEHAVIORAL]**

<!-- PSFI-1399 rewrite drafted by a Codex agent. -->

The DataLink abstraction is the fact boundary between M4P and a physical or
link-layer implementation. A DataLink adapter reports facts about its medium;
the M4P core alone reduces those facts into channel and message-holding belief.
The adapter MUST NOT compute or report reachability estimates, inferred message
holding, forwarding decisions, or any other belief.

### 10.1 DataLink Contract

**[BEHAVIORAL]**

Every adapter registers one link instance and supplies the mandatory facets in
the table below. Optional facets use a closed, typed vocabulary and MUST be
declared at registration. An adapter that declares no optional facets is fully
conformant; M4P then operates from receipt recency and the link descriptors.

| Facet | Adapter fact | Declaration | Core consumer |
| -- | -- | -- | -- |
| Receipt (mandatory) | One complete canonical Transmission and its sender Node Address | none | E1/E2 holding evidence, presence, and the recency prior |
| Send outcome (mandatory) | `sent`, `busy`, `failed`, or `timed_out` | none | ladder `n` on `sent`; directed pairwise `f` on a targeted `failed` or `timed_out`; diagnostics for broadcast failure |
| Delivery confirmation | Which peers accepted the transmission | `delivery_confirmation`: `none`, `link_accepted`, or `delivered_to_peers` | E3 and pairwise success counts |
| Reception quality | Any declared subset of `snr_db`, `pdsnr_db`, `rssi_dbm`, and `decode_confidence` on a receipt | `evidence_capabilities`: `reception_quality` with its field list | channel-prior curve |
| Range | A measured range to a peer | `evidence_capabilities`: `range` | range table on the self row |
| Peer receipt | A named peer acknowledged a named send or receive opportunity | `evidence_capabilities`: `peer_receipts` | E12 through the shared opportunity table |
| Descriptors | Modality, class, addressing, scheduling mode, MAC management, operating envelope, collision domain, maximum transmission duration, and endpoint set | fixed registration or descriptor fields | selection of the applicable core rules |
| Diagnostics and decode events | Any other adapter measurement or event | free-form observability API | observability only; never evidence |

An implementation MUST reject an unknown or malformed evidence capability at
registration. It MUST ignore no declared vocabulary extension silently. Adding
a new optional facet therefore requires a protocol revision and exactly one
named reducer in the core. Values outside the closed reception-quality list,
including velocity and Doppler measurements, are diagnostics rather than
reception-quality evidence.

The registration descriptors have these meanings:

- `operating_envelope` is `surface`, `subsurface`, or `both`. Its default is
  `surface` for radio, LAN, WAN, and satellite links and `both` for acoustic
  links. A link MAY override its modality default. It is an input to the peer
  surface-state prior only; it is not reachability evidence.
- `collision_domain` identifies link instances backed by one physical
  opportunity domain. Absence means the link has no declared sibling.
- `max_transmission_duration` is a positive integer number of milliseconds: the time needed to transmit
  `max_transmission_bytes`, including turnaround. It is a fact about the medium,
  not a slot request. The future TDMA slot-duration rule consumes this fact by
  taking the maximum over participants; an adapter does not compute that rule.
- The endpoint set of a unicast link is the set of endpoints the adapter can
  currently address. It is an address-table fact, never a reachability claim.

Registration protocol versions are deployment-wide contracts. A daemon MUST
reject a registration below its minimum supported version. All adapters in a
deployment MUST be upgraded and re-registered with the corresponding daemon.

### 10.2 Transmission and Opportunity Interface

**[BEHAVIORAL]**

For each physical send opportunity, the owner supplies a payload budget. In
link-managed mode the adapter reports `LinkReady`; in M4P-managed TDMA mode the
runtime derives the opportunity from the agreed schedule and directs the
adapter. The core builds a complete canonical Transmission no larger than that
budget and the adapter carries it as opaque bytes.

The canonical Transmission wire format and parsing rules are defined in
[Section 5.8](#58-transmission-encoding). The adapter MUST deliver the complete
canonical form, including `node_address_sender`, on receive. When an underlying
link carries the sender address out of band, both adapters for that link MAY
omit the prefix on the physical medium, but the receiving adapter MUST restore
it before reporting the Transmission to M4P.

A received Transmission MAY carry a driver-chosen `opportunity_ref`, an
unsigned 32-bit correlation value local to that link. The value names that
receive opportunity for a later peer receipt. It is not the daemon's receive
transmission id, because the daemon assigns that id only after the adapter's
report.

An adapter declaring `peer_receipts` MAY report
`PeerReceipt { peer_node_address, subject }`. The subject is exactly one of:

- a daemon-assigned transmission id previously sent on this link or a sibling
  in the same collision domain; or
- an `opportunity_ref` previously attached to a received Transmission on this
  same link.

The core MUST resolve the subject through its opportunity table and feed the
referenced records to E12, the same reducer used by protocol receipt envelopes.
A whole record is confirmed immediately. A fragmented record accumulates only
the byte ranges carried by referenced opportunities and is confirmed only when
those ranges cover the complete retained payload. An unknown, expired, or
malformed subject MUST be counted and dropped and MUST NOT mutate belief.

Evidence-plane fields and correlation values are local API data. They MUST NOT
be encoded into an M4P packet or forwarded to another node. The only receipt
facts sent on an M4P DataLink are the protocol-owned transmission envelopes in
[Section 5.8](#58-transmission-encoding).

### 10.3 Send-Outcome Semantics

**[BEHAVIORAL]**

`sent` means that the link accepted the bytes: modem transmission completed,
broker publication completed, an endpoint POST completed, or a mobile-originated
message entered its queue. It MUST NOT mean or imply peer delivery. Peer
delivery requires delivery confirmation or receipt evidence.

Every `sent` outcome increments the opportunity's spacing-ladder send count
`n`, except a fragment that strictly extends sent coverage while leaving the
record incomplete; such a continuation is neither gated by the ladder nor
counted by it. The fragment completing sent coverage increments `n`, as do
unfragmented sends and fragments repeating already-covered ranges. A `failed`
or `timed_out` outcome for a targeted send increments the
directed pairwise failure count `f`. A broadcast failure has no sound peer to
which a failure can be assigned and is therefore diagnostics only. `busy`
declines the opportunity and is neither a send nor peer evidence.

### 10.4 MAC Management and Collision Domains

**[BEHAVIORAL + GUIDANCE]**

A link instance uses exactly one MAC-management mode for its registered
lifetime:

- **Link-managed.** The adapter owns waveform, contention, duty cycle, and
  transmission-opportunity timing. M4P assumes no particular MAC algorithm.
- **M4P-managed TDMA.** Participant convergence and slot assignment follow
  [Section 11.10](#1110-tdma-slot-allocation). The runtime owns slot timing and
  gives the adapter only the schedule information needed to time its local
  slot. The adapter MUST NOT derive forwarding or belief from the schedule.

All sibling links with the same non-empty `collision_domain` share one physical
opportunity domain. The adapter layer MUST report `LinkReady` on exactly one
sibling for each physical opportunity, and the core MUST NOT offer one slot to
two siblings. Siblings share peer presence, peer-restart evidence, and
message-holding cells. Their channel prior `p`, spacing ladder, receipt bitmap,
directed pairwise history, and range table remain per-link. Thus a receipt on
one sibling can confirm a record sent on another without merging their channel
histories.

For a link-managed link registered with canonical modality `wan`, the transport
MUST insert and consume the WAN receipt envelope from
[Section 5.8](#58-transmission-encoding). An M4P-managed TDMA link uses the TDMA
receipt envelope instead, regardless of modality. Exactly one receipt-envelope
form applies to a link. LAN and acoustic links MUST NOT use the WAN envelope.

Application or autonomy logic MAY tune adapter-owned settings such as waveform,
power, or proprietary MAC policy. It MAY also supply context hints to the core.
Neither path authorizes the adapter to consume fleet beliefs or to make M4P
forwarding decisions.

### 10.5 Evidence Reduction and Conformance

**[BEHAVIORAL]**

Each optional facet has the single consumer named in [Section 10.1](#101-datalink-contract).
The core MUST validate that reported evidence belongs to the facet and fields
declared by the link. Missing, stale, or unusable optional evidence MUST bias
toward more forwarding, never suppression.

The following are hard conformance requirements:

1. The driver reports measurements and protocol facts, never reachability,
   message-holding belief, novelty, or a forwarding decision.
2. Evidence-plane data is consumed only by the local core and is never
   forwarded.
3. A TDMA schedule is used by an adapter only for local opportunity timing.
4. A link declaring no optional facet registers and forwards correctly from
   mandatory receipts, send outcomes, descriptors, and recency-only priors.
5. A declared facet is typed, validated, and reduced only by its named core
   consumer; diagnostics never enter a belief reducer.
6. Unknown capabilities fail registration, while unknown peer-receipt subjects
   are counted and dropped without applying evidence.

Hardware capabilities outside M4P networking, such as USBL positioning, MAY be
exposed directly to applications. If their facts are later admitted to the
evidence plane, they require a vocabulary and reducer change under this
contract.

---

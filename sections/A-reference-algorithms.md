## Appendix A: Reference Algorithms {#appendix-a-reference-algorithms}

The following reference implementations are provided for clarity. They are non-normative; any implementation that produces equivalent results is conformant.

### A.1 Compact Type Encoding

```python
def encode_cte(type_id: int) -> bytes:
    """Encode a Message Type ID using Compact Type Encoding."""
    if type_id <= 127:
        return bytes([type_id])
    else:
        return bytes([0x80 | ((type_id >> 8) & 0x7F), type_id & 0xFF])


def decode_cte(data: bytes, offset: int) -> tuple[int, int]:
    """Decode a CTE value. Returns (type_id, bytes_consumed)."""
    if data[offset] & 0x80 == 0:
        return (data[offset], 1)
    else:
        value = ((data[offset] & 0x7F) << 8) | data[offset + 1]
        return (value, 2)
```

### A.2 TTL Encoding and Decoding

```python
def encode_ttl(seconds: int) -> int:
    """Encode a TTL value in seconds to the wire format (0-255)."""
    if seconds == 0:
        return 0  # One-hop
    elif seconds <= 60:
        return seconds
    elif seconds <= 660:
        return min(60 + (seconds - 60) // 10, 120)
    elif seconds <= 4260:
        return min(120 + (seconds - 660) // 60, 180)
    else:
        return min(180 + (seconds - 4260) // 300, 255)


def decode_ttl(n: int) -> int:
    """Decode a wire TTL value to seconds. 0 = one-hop only."""
    if n == 0:
        return 0  # One-hop only
    elif n <= 60:
        return n
    elif n <= 120:
        return (n - 60) * 10 + 60
    elif n <= 180:
        return (n - 120) * 60 + 660
    else:  # 181-255
        return (n - 180) * 300 + 4260
```

### A.3 Timestamp Age Calculation

```python
def calculate_packet_age(current_time_24h: int, packet_timestamp_24h: int) -> int:
    """Calculate packet age in seconds, handling 24-hour wraparound."""
    diff = current_time_24h - packet_timestamp_24h

    if diff > 43200:
        diff = diff - 86400
    elif diff < -43200:
        diff = diff + 86400

    return max(0, diff)
```

### A.4 MIID Computation

```python
def pack_miid32(src_ca: int, ts_seconds: int, counter: int) -> int:
    """Compute MIID32 for 8-bit addressing mode."""
    ts24 = int(ts_seconds) % 86400
    return ((src_ca & 0xFF) << 24) | ((ts24 & 0x1FFFF) << 7) | (counter & 0x7F)


def unpack_miid32(miid32: int) -> tuple[int, int, int]:
    """Decompose MIID32 into (source_ca, timestamp_24h, msg_counter)."""
    src_ca = (miid32 >> 24) & 0xFF
    ts24 = (miid32 >> 7) & 0x1FFFF
    ctr = miid32 & 0x7F
    return (src_ca, ts24, ctr)


def pack_miid40(src_ca: int, ts_seconds: int, counter: int) -> int:
    """Compute MIID40 for 16-bit addressing mode."""
    ts24 = int(ts_seconds) % 86400
    return ((src_ca & 0xFFFF) << 24) | ((ts24 & 0x1FFFF) << 7) | (counter & 0x7F)


def unpack_miid40(miid40: int) -> tuple[int, int, int]:
    """Decompose MIID40 into (source_ca, timestamp_24h, msg_counter)."""
    src_ca = (miid40 >> 24) & 0xFFFF
    ts24 = (miid40 >> 7) & 0x1FFFF
    ctr = miid40 & 0x7F
    return (src_ca, ts24, ctr)
```

### A.5 Address Derivation

```python
import hashlib

PRIME_STEP = 7919

def derive_address_base(network_id: str, uid: str, address_space: int) -> int:
    """Derive the base address for a UID within a network."""
    nid_bytes = network_id.encode('utf-8')
    hash_input = len(nid_bytes).to_bytes(2, 'big') + nid_bytes + uid.encode('utf-8')
    digest = hashlib.sha256(hash_input).digest()
    raw = int.from_bytes(digest[:4], 'big')
    return raw % address_space


def derive_address(network_id: str, uid: str, version: int,
                   address_space: int, occupied: set[int]) -> tuple[int, int]:
    """Derive an address, skipping broadcast (0) and occupied addresses.
    Returns (address, version) after any necessary increments."""
    base = derive_address_base(network_id, uid, address_space)
    while True:
        addr = (base + version * PRIME_STEP) % address_space
        if addr != 0 and addr not in occupied:
            return (addr, version)
        version += 1
```

### A.6 Client Address Fingerprint

```python
def compute_ca_fingerprint(client_uid: str, ca: int, address_version: int) -> int:
    """Compute the 16-bit client address fingerprint."""
    digest = hashlib.sha256(
        client_uid.encode('utf-8')
        + ca.to_bytes(2, 'big')
        + address_version.to_bytes(2, 'big')
    ).digest()
    return (digest[0] << 8) | digest[1]
```

### A.7 Authentication Tag (CMAC with Header AAD)

**Compatibility note.** Earlier draft reference code mapped Network Control Message Type IDs (`32,000-32,767`) to `"request"` in `get_packet_class` with an inline warning comment. This version raises `ValueError` for NC Message Type IDs so NC exclusion from payload encryption/header-AAD handling is explicit.

```python
from cryptography.hazmat.primitives.cmac import CMAC
from cryptography.hazmat.primitives.ciphers.algorithms import AES


# --- Packet class determination ---

# Status:   message_type_id 0 - 7,999
# Event:    message_type_id 8,000 - 9,999
# Request:  message_type_id 10,001 - 31,997 (odd)
# Response: message_type_id 10,000 - 31,998 (even)
# NC:       message_type_id 32,000 - 32,767 (not encrypted in this version)

def get_packet_class(message_type_id: int) -> str:
    """Determine the packet class from the message_type_id."""
    if message_type_id <= 7999:
        return "status"
    elif message_type_id <= 9999:
        return "event"
    elif message_type_id == 31999:
        raise ValueError("Message Type ID 31,999 is reserved")
    elif message_type_id >= 32000:
        raise ValueError(
            "NC packets are not encrypted in this version and do not use header_aad"
        )
    elif message_type_id % 2 == 1:
        return "request"
    else:
        return "response"


# --- Header AAD construction ---

def build_header_aad_status(flags: int, payload_length: int) -> bytes:
    """Construct header_aad for a Status or Event packet.

    header_aad = flags (1 byte) || payload_length (2 bytes, big-endian)
    """
    return (
        flags.to_bytes(1, 'big')
        + payload_length.to_bytes(2, 'big')
    )


def build_header_aad_request(destination: int, flags: int,
                             payload_length: int,
                             is_16bit_addressing: bool,
                             additional_dests: list[int] | None = None) -> bytes:
    """Construct header_aad for a Request packet.

    header_aad = destination (1 or 2 bytes) || flags (1 byte)
                 || [additional_dest_count (1 byte)
                     || additional_dest[] (count * addr_size bytes)]
                 || payload_length (2 bytes, big-endian)

    The bracketed fields are present only when ADDITIONAL_DEST_PRESENT
    (bit 4) is set in flags.
    """
    addr_size = 2 if is_16bit_addressing else 1
    aad = (
        destination.to_bytes(addr_size, 'big')
        + flags.to_bytes(1, 'big')
    )
    if flags & (1 << 4):  # ADDITIONAL_DEST_PRESENT
        dests = additional_dests or []
        aad += len(dests).to_bytes(1, 'big')
        for ca in dests:
            aad += ca.to_bytes(addr_size, 'big')
    aad += payload_length.to_bytes(2, 'big')
    return aad


def build_header_aad_response(destination: int,
                               timestamp_24h_response: int,
                               flags_7bit: int,
                               payload_length: int,
                               is_16bit_addressing: bool) -> bytes:
    """Construct header_aad for a Response packet.

    header_aad = destination (1 or 2 bytes)
                 || payload_length (2 bytes, big-endian)
                 || timestamp_24h_response (17 bits) + flags (7 bits)
                    packed into 3 bytes

    Fields are concatenated in wire order per Section 5.4.
    """
    addr_size = 2 if is_16bit_addressing else 1
    # Pack timestamp_24h_response (17 bits) and flags (7 bits) into 3 bytes
    packed_ts_flags = (timestamp_24h_response << 7) | (flags_7bit & 0x7F)
    return (
        destination.to_bytes(addr_size, 'big')
        + payload_length.to_bytes(2, 'big')
        + packed_ts_flags.to_bytes(3, 'big')
    )


def build_header_aad(message_type_id: int, flags: int,
                     payload_length: int,
                     is_16bit_addressing: bool,
                     destination: int = 0,
                     timestamp_24h_response: int = 0,
                     additional_dests: list[int] | None = None) -> bytes:
    """Construct header_aad for any packet class.

    Args:
        message_type_id: Determines the packet class.
        flags: 8-bit flags for Status/Event/Request, 7-bit for Response.
        payload_length: Payload length in bytes.
        is_16bit_addressing: True for 16-bit addressing mode.
        destination: Destination address (Request/Response only).
        timestamp_24h_response: Response timestamp (Response only).
        additional_dests: Additional destination CAs (group Requests only).
    """
    packet_class = get_packet_class(message_type_id)
    if packet_class in ("status", "event"):
        return build_header_aad_status(flags, payload_length)
    elif packet_class == "request":
        return build_header_aad_request(
            destination, flags, payload_length, is_16bit_addressing,
            additional_dests
        )
    else:
        return build_header_aad_response(
            destination, timestamp_24h_response, flags,
            payload_length, is_16bit_addressing
        )


# --- AUTH_TAG_SIZE mapping ---

AUTH_TAG_SIZE_MAP = {
    0b01: 4,   # Standard tag
    0b10: 8,   # Extended tag
    0b11: 16,  # Full tag (untruncated CMAC)
}


def get_tag_length(auth_tag_size: int) -> int:
    """Return the tag length in bytes for a given AUTH_TAG_SIZE value.

    auth_tag_size: 2-bit value from the flags field (0b00 = no tag).
    Raises ValueError if auth_tag_size is 0b00 (no tag) or invalid.
    """
    if auth_tag_size not in AUTH_TAG_SIZE_MAP:
        raise ValueError(f"Invalid AUTH_TAG_SIZE: {auth_tag_size:#04b}")
    return AUTH_TAG_SIZE_MAP[auth_tag_size]


# --- Tag computation and verification ---

def compute_auth_tag(key: bytes, nonce: bytes, header_aad: bytes,
                     ciphertext: bytes,
                     auth_tag_size: int = 0b01) -> bytes:
    """Compute the authentication tag.

    tag = TRUNCATE_N(AES-CMAC(key, nonce || header_aad || ciphertext))

    where N is determined by auth_tag_size:
        0b01 -> 4 bytes (standard)
        0b10 -> 8 bytes (extended)
        0b11 -> 16 bytes (full CMAC output)
    """
    tag_len = get_tag_length(auth_tag_size)
    c = CMAC(AES(key))
    c.update(nonce + header_aad + ciphertext)
    full_mac = c.finalize()
    return full_mac[:tag_len]


def verify_auth_tag(key: bytes, nonce: bytes, header_aad: bytes,
                    ciphertext: bytes, received_tag: bytes,
                    auth_tag_size: int = 0b01) -> bool:
    """Verify a received authentication tag. Returns True if valid."""
    expected_tag = compute_auth_tag(key, nonce, header_aad, ciphertext,
                                   auth_tag_size)
    # Note: production implementations SHOULD use a constant-time comparison
    # function (e.g., hmac.compare_digest). This reference uses hmac for
    # correctness; a simple byte-by-byte comparison would be vulnerable to
    # timing side channels.
    import hmac
    return hmac.compare_digest(expected_tag, received_tag)
```

---


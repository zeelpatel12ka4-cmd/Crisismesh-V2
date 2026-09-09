# Crisis Mesh — Phase 8 Architecture Specification
## Private 1-to-1 End-to-End Encrypted (E2EE) Messaging + QR Key Exchange

**Status:** Approved in Principle with Corrections Applied  
**Version:** 2.0.0 (Phase 8 Revised)  
**Date:** September 8, 2026  

---

### Executive Summary & Scope

Phase 8 introduces private, 1-to-1 asynchronous end-to-end encrypted (E2EE) messaging between Crisis Mesh devices over Bluetooth / Nearby Connections mesh networks with store-and-forward relaying.

#### Non-Goals & Invariants
- **No Group Chat:** Strictly pairwise (1-to-1) private messaging.
- **Preserve Existing Protocols:** SOS broadcast logic, 48-hour SOS expiry, responder PIN authentication, battery duty-cycling, and SQLite `messages` table for public SOS broadcasts are completely untouched.
- **No Mathematical Key Conversion:** Under no circumstances is Ed25519 mathematically mapped or converted to X25519. Two distinct keypairs are generated and maintained.
- **Zero Plaintext Leakage:** Plaintext never touches intermediate relays, Firebase collections, or application loggers.

---

### 1. Cryptographic Roles & Separation

| Role | Algorithm | Purpose | Key Type |
|---|---|---|---|
| **Identity & Signing** | Ed25519 (`package:cryptography`) | Device identity (`DEV-XXXXXXXX`), envelope provenance authentication, tamper-proof headers. | 32-byte private seed / 32-byte public key |
| **Key Agreement** | X25519 (`package:cryptography`) | Asynchronous offline Diffie-Hellman key agreement for pairwise encryption. | 32-byte private key / 32-byte public key |
| **Key Derivation** | HKDF-SHA256 (`package:cryptography`) | RFC 5869 key derivation with strict domain separation and canonical parameter encoding. | Symmetric 32-byte output keys |
| **Authenticated Encryption** | ChaCha20-Poly1305 (`Chacha20.poly1305Aead()`) | RFC 8439 AEAD encryption of private message payloads with Authenticated Additional Data (AAD). | 32-byte MEK, 12-byte CSPRNG Nonce, 16-byte Poly1305 MAC |

---

### 2. Implementation Gate: The 9 Precise Specifications

#### Gate 1: Exact HKDF Inputs & Two-Tier Key Derivation
To protect against static key wear-out and guarantee that every message has a unique symmetric encryption key, a two-tier derivation architecture is implemented:

```
[Sender X25519 Priv] + [Recipient X25519 Pub]
                    ↓ (X25519 Key Agreement)
            [Raw Shared Secret] (32 bytes)
                    ↓
   Tier 1 HKDF-SHA256 (Canonical Domain Salt & Sorted Key IDs)
                    ↓
         Pairwise Master Key (PMK) (32 bytes)
                    ↓
   Tier 2 HKDF-SHA256 (Per-Message CSPRNG Nonce & Message ID)
                    ↓
       Message Encryption Key (MEK) (32 bytes)
```

1. **Shared Secret Computation:**
   ```dart
   final sharedSecret = await X25519().sharedSecretKey(
     keyPair: myX25519KeyPair,
     remotePublicKey: peerX25519PublicKey,
   );
   final sharedSecretBytes = await sharedSecret.extractBytes(); // 32 bytes
   ```
2. **Tier 1 — Pairwise Master Key (PMK):**
   - **IKM:** `sharedSecretBytes` (32 bytes)
   - **Salt:** 32 bytes generated via SHA-256: `sha256.convert(utf8.encode('crisis-mesh-pmk-salt-v1')).bytes`
   - **Info:** Canonical UTF-8 domain separation with lexicographically sorted X25519 public keys:
     ```dart
     final sortedKeys = [senderX25519KeyB64, recipientX25519KeyB64]..sort();
     final info = utf8.encode('crisis-mesh-pmk-v1:${sortedKeys[0]}:${sortedKeys[1]}');
     ```
   - **Output Length:** 32 bytes.
   - *Property:* Both sender and recipient derive the exact identical PMK regardless of who initiates communication.
3. **Tier 2 — Message Encryption Key (MEK):**
   - **IKM:** `PMK` (32 bytes)
   - **Salt:** 12-byte per-message CSPRNG nonce (`messageNonce`)
   - **Info:** Canonical UTF-8 info string containing message ID:
     ```dart
     final info = utf8.encode('crisis-mesh-mek-v1:$messageId');
     ```
   - **Output Length:** 32 bytes.
   - *Property:* Every message is encrypted under a unique, freshly derived symmetric key.

---

#### Gate 2: Exact HKDF Salt & Info Canonicalization
All HKDF inputs are deterministically formatted without string ambiguity:

```dart
// Tier 1 Salt: Exactly 32 bytes from SHA-256
static final List<int> pmkSalt = sha256.convert(utf8.encode('crisis-mesh-pmk-salt-v1')).bytes;

// Tier 1 Info: Deterministic sorted Base64 public keys
static List<int> computePmkInfo(String keyA_b64, String keyB_b64) {
  final sorted = [keyA_b64, keyB_b64]..sort();
  return utf8.encode('crisis-mesh-pmk-v1:${sorted[0]}:${sorted[1]}');
}

// Tier 2 Salt: Exactly the 12-byte per-message CSPRNG nonce
// Tier 2 Info: UTF-8 encoding of prefixed message_id
static List<int> computeMekInfo(String messageId) {
  return utf8.encode('crisis-mesh-mek-v1:$messageId');
}
```

---

#### Gate 3: Exact AAD (Authenticated Additional Data) Canonical Bytes
ChaCha20-Poly1305 cryptographically binds envelope metadata to the ciphertext so that headers cannot be modified in transit without decryption failing.

**Rule:** AAD contains **only immutable fields**.
`hop_count` and relay routing headers are **strictly excluded** because they mutate during mesh forwarding.

**Canonical AAD Format:**
```dart
final aadString = 'v1|'
    '${envelope.messageId}|'
    '${envelope.conversationId}|'
    '${envelope.senderDeviceId}|'
    '${envelope.recipientDeviceId}|'
    '${envelope.senderKeyId}|'
    '${envelope.recipientKeyId}|'
    '${envelope.timestampMs}';
final Uint8List aadBytes = Uint8List.fromList(utf8.encode(aadString));
```
*Verification:* If a malicious relay tampers with `recipientDeviceId` or rewires the `conversationId`, the Poly1305 MAC check will fail and `Chacha20.poly1305Aead().decrypt` will throw a `SecretBoxAuthenticationError`.

---

#### Gate 4: Exact Ed25519 Signed Envelope Bytes
The sender signs the encrypted envelope with their Ed25519 private signing key to guarantee authenticity and non-repudiation.

**Rule:** The signature covers the ciphertext and immutable metadata. It does not sign plaintext, nor does it sign `hop_count`.

**Canonical Signing Payload:**
```dart
final signPayloadString = 'crisis-mesh-envelope-sig-v1|'
    '${envelope.messageId}|'
    '${envelope.conversationId}|'
    '${envelope.senderDeviceId}|'
    '${envelope.recipientDeviceId}|'
    '${envelope.senderKeyId}|'
    '${envelope.recipientKeyId}|'
    '${envelope.timestampMs}|'
    '${envelope.nonceB64}|'
    '${envelope.ciphertextB64}|'
    '${envelope.authTagB64}';
final Uint8List signBytes = Uint8List.fromList(utf8.encode(signPayloadString));
```
The resulting 64-byte Ed25519 signature is Base64 encoded and placed in the envelope field `"signature"`.

---

#### Gate 5: Exact SecretBox Serialization
Using `package:cryptography` 2.9.0 `Chacha20.poly1305Aead()`:
- `SecretBox` contains:
  1. `nonce` (12 bytes)
  2. `cipherText` (variable byte length)
  3. `mac` (16 bytes in `mac.bytes`)

**Wire / JSON Serialization:**
```json
{
  "protocol_version": 1,
  "type": "private_chat",
  "message_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "conversation_id": "conv-a1b2c3d4",
  "sender_device_id": "DEV-A1B2C3D4",
  "recipient_device_id": "DEV-E5F6A7B8",
  "sender_key_id": "X25519-9B21FA3C",
  "recipient_key_id": "X25519-4A77D01E",
  "timestamp": 1757328000000,
  "hop_count": 0,
  "ttl_days": 7,
  "nonce": "<12-byte-nonce-base64>",
  "ciphertext": "<aes-or-chacha-ciphertext-base64>",
  "auth_tag": "<16-byte-poly1305-mac-base64>",
  "sender_ed25519_pub": "<32-byte-ed25519-public-key-base64>",
  "sender_x25519_pub": "<32-byte-x25519-public-key-base64>",
  "signature": "<64-byte-ed25519-signature-base64>"
}
```
**Reconstruction on Decryption:**
```dart
final secretBox = SecretBox(
  base64.decode(envelope.ciphertextB64),
  nonce: base64.decode(envelope.nonceB64),
  mac: Mac(base64.decode(envelope.authTagB64)),
);
final decryptedBytes = await Chacha20.poly1305Aead().decrypt(
  secretBox,
  secretKey: SecretKey(mekBytes),
  aad: aadBytes,
);
final plaintext = utf8.decode(decryptedBytes);
```
No custom authentication tags, no second MAC, and no manual Poly1305 calculations.

---

#### Gate 6: Exact Nonce Generation & Storage
- **Length:** 12 bytes (96 bits), required by RFC 8439.
- **Generator:** `Random.secure()` cryptographically strong pseudo-random number generator.
- **Generation:**
  ```dart
  final nonce = Uint8List(12);
  final rng = Random.secure();
  for (int i = 0; i < 12; i++) {
    nonce[i] = rng.nextInt(256);
  }
  ```
- **Storage:** Included in the wire envelope as Base64 string (`nonce`).
- **Uniqueness Assurance:** Never reused under the same key. Combined with Tier-2 HKDF (where `nonce` and `messageId` feed the MEK derivation), key-nonce pairs are mathematically distinct for every message.

---

#### Gate 7: Static X25519 Key Lifecycle & Security Bounds
- **Lifecycle:**
  - Generated once on device first launch: `await X25519().newKeyPair()`.
  - The 32-byte private seed is persisted in `KeyStorage` (`FlutterSecureStorage` with Android `EncryptedSharedPreferences`).
  - Storage key: `crisis_mesh_x25519_seed_v1`.
  - Public key is exported as 32 bytes and stored/cached.
- **Security Limitations (Explicit Claims):**
  - **No Forward Secrecy:** Because static X25519 keys are used without ephemeral ratcheting, compromise of a device's long-term X25519 private key allows decryption of previously recorded ciphertexts for that key.
  - **No Double Ratchet in MVP:** This MVP does not implement the Signal Double Ratchet protocol due to offline asynchronous mesh constraints where parties may be offline for days.
  - **Prohibited Claims:** The system will **never** claim "forward secure", "perfect forward secrecy (PFS)", or "future compromise resistant".
  - **Future Upgrade Path:** An ephemeral ratchet layer can be added atop this pairwise key foundation in future phases.

---

#### Gate 8: Contact Trust Model & QR Key Exchange
1. **Contact Model Attributes:**
   - `deviceId` (`DEV-XXXXXXXX`, Ed25519 derived)
   - `displayName` (User-assigned contact alias)
   - `signingPublicKey` (Ed25519 Base64)
   - `encryptionPublicKey` (X25519 Base64)
   - `fingerprint` (Hex representation of SHA-256 of concatenated public keys)
   - `trustStatus`:
     - `UNVERIFIED`: Discovered over mesh or entered manually without QR confirmation.
     - `QR_VERIFIED`: Exchanged and verified via physical in-person QR scan.
     - `KEY_CHANGED`: Security alert state when an existing contact identifier presents different cryptographic keys.
2. **QR Payload Specification:**
   - Public data ONLY. Contains **zero private keys, zero seeds, zero credentials**.
   ```json
   {
     "v": 1,
     "type": "crisis_mesh_contact",
     "dev_id": "DEV-A1B2C3D4",
     "name": "Alice Responder",
     "sign_pub": "<base64-ed25519-public-key>",
     "enc_pub": "<base64-x25519-public-key>",
     "fp": "A1B2:C3D4:E5F6:7890"
   }
   ```
3. **Explicit User Confirmation Flow:**
   - Scanning a QR code opens a verification dialog displaying the name, device ID, and cryptographic fingerprint.
   - The key is saved as `QR_VERIFIED` **only** upon explicit user confirmation (tapping "Trust Contact").

---

#### Gate 9: Key-Change Detection & Protection
If an incoming message, mesh beacon, or QR scan matches an existing `deviceId` but contains a different `signingPublicKey` or `encryptionPublicKey`:
1. The contact's status in SQLite is immediately changed to `ContactTrustStatus.KEY_CHANGED`.
2. Existing key material is **never silently overwritten**.
3. In the 1-to-1 chat UI, an unmissable red alert banner appears:
   > ⚠️ **SECURITY WARNING: Security keys for this contact have changed!**  
   > This could indicate an impersonation attempt or device reinstallation. Outgoing messages are blocked until you re-verify this contact in person via QR code.
4. Outgoing message transmission to this contact is disabled until the user explicitly resolves the alert by scanning the contact's new QR code.

---

### 3. Expiry Policies (Strict Separation)

SOS broadcasts and private 1-to-1 messages serve completely distinct operational functions and have strictly independent expiration policies:

| Message Type | TTL Duration | Early Termination Trigger | Policy Constant | Storage Location |
|---|---|---|---|---|
| **Public SOS Broadcast** | **48 Hours** | None (persists 48 hours for responders) | `CrisisMeshConstants.sosMessageTtl = Duration(hours: 48)` | `messages` SQLite table |
| **Private 1-to-1 Message** | **7 Days** | Delivery Acknowledgment (`ACK`) received | `CrisisMeshConstants.privateMessageTtl = Duration(days: 7)` | `private_messages` SQLite table |

---

### 4. Replay Protection & Delivery Acknowledgments

1. **Replay Protection:**
   - Every private message carries a unique UUID v4 `message_id`.
   - On receipt of a private message envelope addressed to the local device:
     - The database checks if `message_id` exists in `private_messages`.
     - If already present, the message is ignored and not re-added to the conversation.
     - A delivery ACK is still returned to ensure the sender updates delivery status.
2. **Delivery Acknowledgment (`ACK`) Protocol:**
   - When Recipient $B$ successfully decrypts a message from Sender $A$, $B$ broadcasts a lightweight signed ACK envelope over the mesh:
     ```json
     {
       "type": "private_ack",
       "ack_message_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
       "sender_device_id": "DEV-B",
       "recipient_device_id": "DEV-A",
       "timestamp": 1757328050000,
       "signature": "<ed25519-signature-over-ack-bytes>"
     }
     ```
   - When Sender $A$ receives the ACK:
     - Message status updates from `SENT` to `DELIVERED`.
     - The message is marked as acknowledged in the local store.

---

### 5. Transport & Relay Rules

1. **Intermediate Mesh Relays:**
   - Relays inspect only routing headers: `recipient_device_id`, `message_id`, `hop_count`, and `timestamp`.
   - If `recipient_device_id != localDeviceId`:
     - Relays increment `hop_count` by 1.
     - Relays re-broadcast the message if `hop_count < maxHops (5)`.
     - Relays do not attempt decryption and have no access to the private key.
2. **Firebase Transport Bridge:**
   - When an internet connection is available, encrypted envelopes may sync to Firestore collection `/private_messages`.
   - **Privacy Guarantee:** Firestore documents contain only the ciphertext envelope (`nonce`, `ciphertext`, `auth_tag`, `sender_device_id`, `recipient_device_id`, `signature`).
   - Firestore security rules allow reads only if `auth.uid` matches either the recipient or sender.
   - Plaintext and private keys never touch Firestore.

---

### 6. Database Schema (SQLite Upgrade to Version 4)

Upgrading SQLite schema from version 3 to 4 with two new dedicated tables:

```sql
-- Contacts Table
CREATE TABLE contacts (
    device_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    signing_public_key TEXT NOT NULL,
    encryption_public_key TEXT NOT NULL,
    fingerprint TEXT NOT NULL,
    trust_status TEXT NOT NULL DEFAULT 'UNVERIFIED', -- 'UNVERIFIED', 'QR_VERIFIED', 'KEY_CHANGED'
    created_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL
);

-- Private Messages Table
CREATE TABLE private_messages (
    message_id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    sender_device_id TEXT NOT NULL,
    recipient_device_id TEXT NOT NULL,
    plaintext_body TEXT, -- Null on pure transit nodes, populated on sender/recipient
    ciphertext TEXT NOT NULL,
    nonce TEXT NOT NULL,
    auth_tag TEXT NOT NULL,
    sender_x25519_pub TEXT NOT NULL,
    sender_ed25519_pub TEXT NOT NULL,
    signature TEXT NOT NULL,
    status TEXT NOT NULL, -- 'PENDING', 'SENT', 'DELIVERED', 'FAILED', 'RECEIVED'
    timestamp INTEGER NOT NULL,
    expires_at INTEGER NOT NULL, -- timestamp + 7 days
    is_outgoing INTEGER NOT NULL DEFAULT 0,
    acknowledged INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_private_messages_conv ON private_messages(conversation_id);
CREATE INDEX idx_private_messages_recipient ON private_messages(recipient_device_id);
CREATE INDEX idx_private_messages_expires ON private_messages(expires_at);
```

---

### 7. Verification & Testing Matrix

Before Phase 8 completion, the test suite must prove:

1. **A encrypts $\to$ B decrypts:** Perfect round-trip message delivery with valid payload.
2. **Wrong Key $\to$ Failure:** Message encrypted for B cannot be decrypted by C (`SecretBoxAuthenticationError`).
3. **Modified Ciphertext $\to$ Failure:** Single bit flip in ciphertext causes AEAD authentication rejection.
4. **Modified Nonce $\to$ Failure:** Single bit flip in nonce causes AEAD authentication rejection.
5. **Modified AAD $\to$ Failure:** Modification of `recipient_device_id` or `timestamp` triggers decryption failure.
6. **Replay $\to$ Rejected:** Ingestion of a duplicate `message_id` does not create a duplicate conversation entry.
7. **7-Day Expiry:** Expired private messages are pruned by cleanup routine; 48-hour SOS expiry is unaffected.
8. **QR Content Privacy:** QR export JSON contains strictly public keys; zero private seeds present.
9. **Relay Forwarding:** Intermediate node with different keypair increments `hop_count` and forwards envelope without breaking Ed25519 signature or AEAD integrity.
10. **Key Change Alert:** Attempting to store a new key for an existing contact triggers `KEY_CHANGED` and prevents silent overwrite.

---

### Summary of Corrections Incorporated

1. **Correction 1 (Expiry Scope):** Private message TTL = 7 days or until ACK (`privateMessageTtl`). SOS TTL = 48 hours (`sosMessageTtl`). Strict separation.
2. **Correction 2 (Security Claims):** Explicitly documented that static-static X25519 does not provide forward secrecy. No claims of "forward secure" or "Double Ratchet".
3. **Correction 3 (ChaCha20-Poly1305 SecretBox):** Standard `package:cryptography` `Chacha20.poly1305Aead()` producing `SecretBox(nonce, cipherText, mac)`. No manual MACs.
4. **Correction 4 (AAD Canonicalization):** Canonical pipe-delimited string containing all immutable metadata; `hop_count` strictly excluded.
5. **Correction 5 (Cryptographic Separation):** Ed25519 (signatures/identity), X25519 (key agreement), HKDF-SHA256 (KDF), ChaCha20-Poly1305 (AEAD). Zero cross-role key conversions.
6. **Correction 6 (Key Derivation):** Two-tier HKDF with SHA-256 salt, lexicographically sorted public keys, and message-specific nonce + ID.
7. **Correction 7 (Conversation Key Design):** Static-static PMK + fresh per-message MEK derived from PMK, CSPRNG nonce, and message ID.
8. **Correction 8 (Nonce Generation):** 12-byte CSPRNG nonce generated per message and carried in envelope.
9. **Correction 9 (Envelope Signature):** Deterministic Ed25519 signature over immutable envelope fields.
10. **Correction 10 (Firebase Privacy):** Only encrypted envelopes transported; zero plaintext or private keys.
11. **Correction 11 (QR Payload):** Public keys and fingerprints only; explicit user confirmation before trusting.
12. **Correction 12 (Key Change Protection):** Detection of `KEY_CHANGED`, warning banner, and prevention of silent overwrites.
13. **Correction 13 (Replay Protection):** Tracked by `message_id` and database state.

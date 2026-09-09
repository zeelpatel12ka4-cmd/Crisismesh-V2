# 🚨 Crisis Mesh

> **When the network goes down, Crisis Mesh turns nearby smartphones into a temporary emergency communication network.**

Crisis Mesh is an **offline-first emergency communication and incident coordination platform** designed for situations where cellular networks, Wi‑Fi, or centralized infrastructure may be unavailable.

It combines:

- 🆘 Offline emergency SOS creation
- 📡 Bluetooth mesh store-and-forward relaying
- 💾 Local SQLite persistence
- 🔐 Ed25519 message authenticity
- 🔒 X25519 + HKDF + ChaCha20-Poly1305 private messaging
- 📷 QR-based trusted-contact exchange
- ☁️ Firebase / Firestore synchronization
- 🧭 Responder Command Center
- 📍 Incident clustering and explainable confidence scoring
- 👮 Firebase Authentication + RBAC
- 📋 Immutable operational audit logging
- 🎬 Deterministic disaster simulation
- 🛰️ Satellite-ready last-resort transport architecture

---

## 📱 Screenshots

### Emergency SOS & mesh/cloud status

<p align="center">
  <img src="docs/screenshots/sos_home.png" width="300" alt="Crisis Mesh SOS screen" />
  <img src="docs/screenshots/sos_history.png" width="300" alt="Crisis Mesh SOS history" />
</p>

### Trusted contacts & E2EE QR exchange

<p align="center">
  <img src="docs/screenshots/trusted_contact_qr.png" width="300" alt="Crisis Mesh emergency QR" />
  <img src="docs/screenshots/add_trusted_contact.png" width="300" alt="Add trusted contact" />
</p>

---

## 🎯 The Problem

During a disaster, the communication infrastructure people normally depend on can become unreliable or completely unavailable.

A conventional emergency application can become ineffective when:

```text
Phone → Internet → Cloud
```

is no longer possible.

But a disaster zone may still contain many nearby smartphones.

Crisis Mesh is built around the idea that those nearby devices can temporarily become part of an emergency communication layer.

---

## 💡 The Solution

Crisis Mesh uses a **hybrid, store-and-forward transport strategy**:

```text
                    CRISIS MESH
                         │
                        SOS
                         │
                 ┌───────▼────────┐
                 │ Transport      │
                 │ Manager        │
                 └───────┬────────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
      INTERNET       BLUETOOTH      SATELLITE
         #1              #2              #3
     Preferred        Mesh-first      Last resort
          │              │              │
          └──────────────┼──────────────┘
                         ▼
                 LOCAL PENDING QUEUE
                         │
                         ▼
                    CLOUD / BRIDGE
                         │
                         ▼
                RESPONDER OPERATIONS
```

### Transport priority

1. **Internet** — preferred
2. **Bluetooth Mesh** — used when Internet is unavailable and useful peers exist
3. **Satellite** — last resort when neither Internet nor useful Bluetooth mesh is available
4. **Local Pending Queue** — preserves the SOS when no transport is available

The satellite layer is intentionally **capability-aware** and does not claim unrestricted access to a phone's satellite radio.

---

# 🚨 Core Capabilities

| Capability | Description | Status |
|---|---|---|
| Offline SOS | Create emergency reports without Internet | ✅ Implemented |
| SQLite persistence | Preserve SOS locally | ✅ Implemented |
| Severity engine | Deterministic local triage | ✅ Implemented |
| Bluetooth Mesh | Store-and-forward multi-hop relay | ✅ Implemented |
| 7-hop limit | Prevent uncontrolled forwarding | ✅ Implemented |
| Deduplication | Suppress duplicate/multi-path packets | ✅ Implemented |
| Pending queue | Preserve messages until a transport returns | ✅ Implemented |
| Hybrid transport manager | Select best available transport | ✅ Implemented |
| Ed25519 authenticity | Detect modified / forged messages | ✅ Implemented |
| Private E2EE | X25519 + HKDF + ChaCha20-Poly1305 | ✅ Implemented |
| QR trust exchange | Exchange public identity material | ✅ Implemented |
| Firebase bridge | Synchronize when connectivity returns | ✅ Implemented |
| Incident clustering | Spatial-temporal corroboration | ✅ Implemented |
| Confidence scoring | Explainable 0–100 evidence score | ✅ Implemented |
| Responder Command Center | Operational incident management | ✅ Implemented |
| Firebase Auth / RBAC | Citizen / responder / admin access control | ✅ Implemented |
| Audit logging | Operational action history | ✅ Implemented |
| Disaster simulation | Deterministic end-to-end demo engine | ✅ Implemented |
| Satellite capability detection | Detect supported/unavailable state | ✅ Implemented |
| Satellite simulation | Isolated emergency uplink simulation | ✅ Implemented |
| Live satellite uplink | Real satellite transmission | ⚠️ Not validated |
| Production Cloud Functions deployment | Live production backend | ⚠️ Not deployed |
| Full iOS physical validation | Real-device iOS field test | ⚠️ Requires macOS/Xcode |

---

# 🆘 Offline Emergency Flow

Crisis Mesh keeps emergency creation independent from authentication and cloud connectivity.

```text
SOS CREATED
     ↓
LOCAL TRIAGE
     ↓
ED25519 SIGNING
     ↓
SQLITE STORAGE
     ↓
   ┌───────────────┐
   │ Transport?    │
   └───────┬───────┘
           │
   ┌───────┼──────────────┐
   ▼       ▼              ▼
Internet  Bluetooth    Satellite
   │       Mesh        Last Resort
   │       │              │
   └───────┴──────────────┘
           │
           ▼
      DELIVERED
```

If no transport is available:

```text
SOS → SQLite → PENDING
```

When connectivity returns:

```text
PENDING
   ↓
READY
   ↓
UPLOADING
   ↓
DELIVERED
```

The original message identity remains unchanged.

---

# 📡 Bluetooth Mesh

Crisis Mesh supports multi-hop store-and-forward communication.

Example:

```text
Phone A
   │
   ▼
Phone B
   │
   ▼
Phone C
   │
   ▼
Phone D
   │
   ▼
Bridge / Internet
```

During relay:

- `messageId` remains unchanged
- `senderId` remains unchanged
- signature remains unchanged
- `hopCount` increments
- forwarding stops at the 7-hop ceiling
- duplicate copies are rejected

### Multi-path deduplication

```text
          ┌──→ Phone B ──┐
Phone A ──┤              ├──→ Phone D
          └──→ Phone C ──┘
```

If Phone D receives the same logical message through both paths, only the first accepted copy becomes new evidence.

---

# 🔐 Message Authenticity

Every emergency message is digitally signed with the device's Ed25519 identity.

Conceptually:

```text
Device
  │
  ├── message payload
  ├── timestamp
  ├── identity
  └── canonical signed fields
          │
          ▼
      Ed25519 signature
```

Recipients and the authoritative cloud path can verify the signature.

Security checks include:

- signature verification
- freshness validation
- future-timestamp protection
- replay detection
- rate limiting
- immutable message identity across transports

Transport layers are treated as **untrusted pipes**.

---

# 🔒 Private 1-to-1 E2EE

Private messaging is designed so that the cloud infrastructure does not receive plaintext message content.

```text
Sender
  │
  ├── X25519 key agreement
  ├── HKDF-SHA256
  └── ChaCha20-Poly1305
        │
        ▼
     Ciphertext
        │
        ├── Bluetooth relay
        ├── Firebase
        └── Cloud processing
                 │
                 ▼
            Still opaque
                 │
                 ▼
             Recipient
```

### Security components

- X25519 key agreement
- HKDF-SHA256
- ChaCha20-Poly1305
- Additional authenticated data (AAD)
- QR-based public identity exchange
- Local secure key storage
- Relay-blind ciphertext transport

Private keys are never uploaded to the backend.

---

# 📷 Trusted Contacts / QR Exchange

Crisis Mesh supports public-key exchange through a QR-based trusted-contact flow.

The QR contains public identity information needed to establish trust. Private keys remain on the device.

The current application includes:

- emergency QR display
- trusted-contact addition
- public key payload handling
- trust verification workflow

---

# 📍 Incident Clustering

Individual SOS reports are preserved while the backend can form incident aggregates.

A candidate cluster requires:

- compatible need type
- approximately **50 m** spatial proximity
- approximately **10 min** temporal proximity
- acceptable authenticity state

### Confidence scoring

```text
1 device      → 20
2–4 devices   → 50
5+ devices    → 80

Within 50m    → +15
Within 10min  → +5
```

Maximum:

```text
100
```

### Important distinction

**Severity ≠ Confidence**

- **Severity** = how urgent the emergency is
- **Confidence** = how strongly multiple trusted reports corroborate the incident

Repeated reports from the same device do not automatically increase the unique-device contribution.

---

# 👮 Responder Command Center

The responder workflow is designed around operational clarity.

```text
INCIDENT
   ↓
ASSIGNED
   ↓
EN ROUTE
   ↓
RESOLVED
```

The responder view can expose information such as:

- incident location
- severity
- confidence
- report count
- unique device count
- status
- assignment
- operational history

Actions are recorded through the audit layer.

---

# 👤 Authentication & RBAC

Crisis Mesh supports:

### Citizen

- emergency SOS
- safety-related functionality
- private messaging
- personal operational access

### Responder

- citizen functionality where appropriate
- incident operations
- assignment
- status changes
- responder dashboard

### Admin

- administrative access
- audit visibility
- responder administration

### Emergency Bypass

Authentication does **not** block local emergency SOS creation.

```text
Unauthenticated
      │
      ▼
Emergency SOS
      │
      ▼
Local SQLite + Mesh
```

Cloud operational access remains protected by authentication and authorization.

---

# 📋 Audit Logging

Operational actions are recorded with immutable audit entries.

Core events include:

```text
INCIDENT_CREATED
INCIDENT_UPDATED
INCIDENT_ASSIGNED
INCIDENT_STATUS_CHANGED
INCIDENT_RESOLVED
```

Audit records capture information such as:

- audit ID
- actor UID
- actor role
- incident ID
- timestamp
- metadata

Audit records are designed to be append-only from the application perspective.

---

# 🎬 Disaster Simulation

Crisis Mesh includes a deterministic simulation engine that demonstrates the full emergency lifecycle without polluting production data.

Example:

```text
NETWORK DOWN
      ↓
SOS CREATED
      ↓
SIGNED
      ↓
LOCAL STORAGE
      ↓
A → B → C → D
      ↓
DEDUPLICATION
      ↓
BRIDGE RECOVERY
      ↓
CLOUD INGESTION
      ↓
INCIDENT CLUSTERING
      ↓
RESPONDER ASSIGNED
      ↓
EN ROUTE
      ↓
RESOLVED
```

### Scenario presets

- **Mall Network Outage**
- **Earthquake**
- **Flood**
- **Hospital Blackout & Tamper Rejection**
- **Free-form Disaster Playground**
- **Total Infrastructure Failure** with satellite simulation

The simulation uses isolated in-memory components and is clearly separated from production data.

---

# 🛰️ Satellite Architecture

Satellite is deliberately designed as the **third transport**, not the first.

```text
Internet available
      ↓
   INTERNET

Internet unavailable
      ↓
Bluetooth peers available?
      ↓
      YES
      ↓
 BLUETOOTH MESH

Internet unavailable
      ↓
No useful Bluetooth peers
      ↓
Satellite capability available?
      ↓
      YES
      ↓
    SATELLITE

Nothing available
      ↓
LOCAL PENDING QUEUE
```

### Current satellite status

#### Implemented

- `TransportManager`
- satellite transport abstraction
- capability detection
- compact emergency payload
- fallback logic
- isolated satellite simulation

#### Architected

- Android satellite integration
- iOS carrier/service constrained satellite integration
- external satellite modem/gateway integration

#### Not validated

- live civilian satellite transmission
- unrestricted third-party satellite radio access
- production satellite-provider integration

This is intentional: the application does not pretend that every phone can directly transmit arbitrary data to satellites.

---

# 🏗️ Architecture

```text
                           CRISIS MESH
                                │
                         Emergency Message
                                │
                  ┌─────────────▼─────────────┐
                  │       Local Device        │
                  │                           │
                  │ SQLite + Severity Engine  │
                  │ Ed25519 + E2EE            │
                  └─────────────┬─────────────┘
                                │
                 ┌──────────────┼──────────────┐
                 ▼              ▼              ▼
             Internet       Bluetooth       Satellite
                #1              #2              #3
             Preferred       Mesh-first      Last resort
                 │              │              │
                 └──────────────┼──────────────┘
                                ▼
                         Pending / Bridge
                                │
                                ▼
                           Firestore
                                │
                                ▼
                         Cloud Functions
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
        Validation         Clustering          Audit
              │                 │                 │
              └─────────────────┼─────────────────┘
                                ▼
                     Responder Command Center
```

---

# 🧱 Project Structure

```text
lib/
├── core/
├── domain/
│   ├── entities/
│   └── services/
├── infrastructure/
│   ├── auth/
│   ├── datasource/
│   └── transport/
├── presentation/
│   ├── controllers/
│   ├── screens/
│   └── widgets/
└── simulation/

functions/
├── src/
│   ├── index.ts
│   ├── clustering.ts
│   ├── incident_service.ts
│   ├── signature_verifier.ts
│   └── audit_service.ts

test/

Doc/
```

---

# 🛠️ Technology Stack

| Layer | Technology |
|---|---|
| Mobile / UI | Flutter |
| Language | Dart |
| Authentication | Firebase Authentication |
| Database / Sync | Cloud Firestore |
| Local persistence | SQLite |
| Android mesh | Nearby Connections |
| Cryptography | Ed25519, X25519, HKDF-SHA256, ChaCha20-Poly1305 |
| Backend | Firebase Cloud Functions |
| Backend language | TypeScript |
| Mapping | Flutter map stack used by the project |
| Simulation | Custom deterministic simulation engine |
| Platforms | Android, iOS architecture, Web |

Versions should be read from the repository's `pubspec.yaml` and `functions/package.json`.

---

# 🚀 Getting Started

## Clone

```bash
git clone https://github.com/zeelpatel12ka4-cmd/Crisismesh-V2.git
cd Crisismesh-V2
```

## Install Flutter dependencies

```bash
flutter pub get
```

## Run Web

```bash
flutter run -d edge
```

The Web target is intended for UI, Firebase-backed operational views, and simulation. Real phone Bluetooth mesh is platform-dependent and is not provided by the browser.

## Run on Android

```bash
flutter devices
flutter run -d <android-device-id>
```

## Build APK

```bash
flutter build apk --debug
```

## Build Web

```bash
flutter build web
```

## Build Cloud Functions

```bash
npm --prefix functions install
npm --prefix functions run build
```

---

# 🧪 Testing

Run:

```bash
flutter analyze
flutter test
```

Backend:

```bash
npm --prefix functions run build
```

The project combines:

- unit tests
- domain tests
- security/authorization tests
- simulation tests
- widget tests
- transport tests
- protocol tests

The exact latest passing test count should be taken from the most recent project verification report.

---

# ✅ REAL vs SIMULATED vs ARCHITECTED

| Capability | State |
|---|---|
| Offline SOS | ✅ Real |
| SQLite persistence | ✅ Real |
| Severity engine | ✅ Real |
| Ed25519 signing | ✅ Real |
| Android Bluetooth mesh | ✅ Real |
| 7-hop relay rules | ✅ Real |
| Deduplication | ✅ Real |
| Pending queue | ✅ Real |
| Firebase synchronization | ✅ Real |
| Responder operations | ✅ Real |
| Incident clustering logic | ✅ Real |
| Authentication / RBAC | ✅ Real |
| Audit model | ✅ Real |
| Disaster simulation | 🟦 Simulated |
| Satellite simulation | 🟦 Simulated |
| Android satellite native integration | 🟨 Architected |
| iOS satellite integration | 🟨 Architected |
| External satellite modem | 🟨 Architected |
| Live satellite uplink | ⚠️ Not validated |
| Production Cloud Functions deployment | ⚠️ Deployment-dependent |
| Large-scale 20+ physical phone mesh | ⚠️ Not validated |

---

# 📊 Development Milestones

```text
Phase 1   → Offline SOS Core
Phase 2    → Bluetooth Mesh
Phase 3    → Hybrid Firebase Sync
Phase 4    → Responder Command Center
Phase 5    → Pending SOS + Background Mesh + Adaptive Battery
Phase 6    → Peer Reliability
Phase 7    → Message Authenticity
Phase 8    → Private E2EE + QR Trust
Phase 9    → Incident Clustering + Confidence
Phase 10   → Authentication + RBAC + Backend Authority
Phase 11   → Disaster Simulation Engine
Phase 12   → Hybrid Transport + Satellite-Ready Architecture
```

---

# 🎯 2-Minute Demo Flow

A strong demonstration can follow this sequence:

```text
1. Show Crisis Mesh dashboard
2. Create an emergency SOS
3. Disable Internet
4. Show local storage / pending state
5. Demonstrate Bluetooth relay
6. Show hop count progression
7. Demonstrate duplicate suppression
8. Restore the bridge
9. Show cloud synchronization
10. Show incident clustering
11. Show confidence
12. Assign responder
13. Change status to EN ROUTE
14. Resolve incident
15. Open audit history
16. Run Total Infrastructure Failure simulation
17. Show satellite last-resort simulation
```

---

# 🌐 Platform Notes

### Android

Primary platform for physical Bluetooth mesh testing.

### iOS

The project contains an iOS architecture and platform abstraction, but physical iOS builds require macOS/Xcode and should only be described as physically validated after real-device testing.

### Web

Useful for:

- responder dashboard
- maps
- Firebase-backed operational views
- authentication
- disaster simulation

Real Bluetooth mesh is not expected to operate directly from the browser.

---

# 🔐 Security Philosophy

Crisis Mesh follows a layered security model:

| Layer | Protection |
|---|---|
| Device identity | Ed25519 |
| Message integrity | Digital signature |
| Private messaging | X25519 + HKDF + ChaCha20-Poly1305 |
| Replay defense | Message IDs + freshness |
| Rate limiting | Per-key policy |
| Cloud access | Firebase Authentication |
| Authorization | RBAC + Firestore rules |
| Operations | Audit logging |
| Transport | Untrusted transport principle |

The design prioritizes **privacy, authenticity, resilience, and evidence preservation** without claiming absolute security.

---

# 🗺️ Roadmap

- [x] Offline SOS
- [x] SQLite persistence
- [x] Bluetooth mesh
- [x] 7-hop forwarding
- [x] Deduplication
- [x] Pending queue
- [x] Firebase synchronization
- [x] Responder Command Center
- [x] Ed25519 authenticity
- [x] Private E2EE
- [x] QR trust
- [x] Incident clustering
- [x] Confidence scoring
- [x] Authentication / RBAC
- [x] Audit logging
- [x] Disaster simulation
- [x] Hybrid transport manager
- [x] Satellite-ready architecture
- [ ] Production Cloud Functions deployment
- [ ] Full iOS physical validation
- [ ] Expanded large-scale physical mesh testing
- [ ] Real satellite provider/modem integration
- [ ] Large-scale field validation

---

# ⚠️ Known Limitations

- Browser environments cannot provide the same native Bluetooth capabilities as mobile platforms.
- Actual satellite transmission depends on supported hardware, operating system, service/provider, region, and any required platform entitlements.
- The satellite layer currently provides architecture, capability detection, compact-payload handling, and simulation rather than universal live satellite transmission.
- Production Cloud Functions and Firestore rule deployment must be validated in the target Firebase environment.
- Large-scale physical mesh behavior depends on device models, operating-system restrictions, radio environment, range, and battery conditions.

---

# 🤝 Contributing

1. Fork the repository.
2. Create a feature branch.
3. Preserve existing security and offline behavior.
4. Add or update tests.
5. Run:

```bash
flutter analyze
flutter test
```

6. Document architectural changes.

---

# 📄 License

No license was specified in the supplied project materials. Add a `LICENSE` file before distributing Crisis Mesh as an open-source project.

---

# 🚨 Crisis Mesh

> **When infrastructure fails, the network can still exist around you.**

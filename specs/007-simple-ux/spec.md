# Feature Specification: 007 — Simple UX (Non-Technical User Mode & Community Profiles)

**Feature Branch**: `007-simple-ux`  
**Created**: 2026-09-29  
**Status**: Draft  
**Input**: [Mostro Simple UX: Modelo compacto de aplicación para usuario final no técnico](file:///home/umbrel/work/mostro-app/specs/007-simple-ux/spec.md)  
**Golden Rule**:
> *The operator understands Mostro.*  
> *The software understands Nostr.*  
> *The user understands buying and selling Bitcoin.*

---

> **Amendment — 2026-10-03: single community.** The app now serves the
> BitMaxis community only. Its node is compiled in
> (`rust/src/config.rs::DEFAULT_MOSTRO_PUBKEY`) and nothing in the UI selects,
> adds or scans another one. That supersedes **User Story 1** (community QR
> onboarding), **§3.2 / FR-006 – FR-009** (community profiles and deep links),
> **SC-001**'s QR step and **SC-002**, and the node switcher that User Story 6
> and **SC-003** list under Advanced Mode. The Simple Mode badge shows the
> community name and is not a control. **FR-010**'s "community payment
> methods" are the ones on the community's signed card, which the core now
> reads from the node's relays instead of from a scan (kind 30078,
> `d = mostro-community-card`, signed by the node; the card's own signature
> is checked too): a method the operator adds in the panel appears without a
> new build. Until the node publishes a card the screens use a built-in list.
> The Sell tab offers the card's list exactly; the Buy tab filters by that
> list plus every method an offer on the book carries, and starts on "all",
> so no offer is hidden behind a method the list does not know.

## 1. Context & Rationale

### 1.1 What exists today

Mostro v2 (`MostroP2P/app`) is a high-performance, self-sovereign mobile and desktop client for the Mostro P2P protocol. It pairs a Flutter/Dart UI shell with a Rust core (`nostr-sdk`, `flutter_rust_bridge`, `mostro-core`).

Currently, the interface is primarily tailored for technical users who understand Nostr and Lightning mechanics:
- **Order Book view**: Raw list of maker orders with NIP-69 tags and technical terminology.
- **Node & Relay Management**: Users manually configure Nostr relays (NIP-65), add custom Mostro node pubkeys in hex or `npub`, and inspect low-level network parameters.
- **Protocol Terminology**: UI copy and trade cards frequently mention concepts like "Hold Invoices", "Maker/Taker Bonds", "HTLCs", "Relays", and "Open Dispute".
- **Navigation**: 3 tabs (`Order Book`, `My Trades`, `Chat`) with technical settings in an overlay drawer.

### 1.2 The Problem

Peer-to-peer Bitcoin adoption in local communities (Latin America, Africa, local circular economies) stalls because regular non-technical users find Nostr concepts intimidating:
1. Users are overwhelmed by `npub`, `nsec`, relays, PoW, hold invoices, and node pubkeys.
2. Joining a community requires manual entry of relays and 64-character node hex keys.
3. Trade steps feel technical rather than transactional ("Pay bond invoice" instead of "Security guarantee").
4. If a problem arises, "Opening a dispute" sounds adversarial rather than asking for community mediation assistance.

### 1.3 The Solution: Dual-Mode Architecture (Simple Mode Default)

We introduce a first-class **Simple Mode** into Mostro App as the default experience, while preserving the full sovereign power of **Advanced Mode** for technical users:

```text
Mostro App
├── Simple Mode      ← Default (Clean, guided, non-technical)
└── Advanced Mode    ← Toggleable (Full protocol control, relays, keys, nodes)
```

#### Core Tenets of Simple Mode:
- **Zero Nostr Jargon**: Hide relays, npub/nsec, PoW, NIP-44, node pubkeys, hold invoices, and HTLCs by default.
- **5-Destination Navigation**: `Comprar Bitcoin` (Buy), `Vender Bitcoin` (Sell), `Mis operaciones` (My Trades), `Perfil` (Profile), `Ayuda` (Help).
- **Community QR & Deep Links**: Operators of communities (e.g. using *Mostro Community Manager for Umbrel*) generate signed community profiles. Users scan a single QR code or tap a deep link (`mostro://community/<signed-profile>`) to automatically configure the node, relays, currency, and accepted payment methods.
- **Humanized Transaction Lifecycle**: Progress mapped to straightforward real-world actions: *"Garantía bloqueada"*, *"Bitcoin protegido"*, *"Envía $X [YA PAGUÉ]"*, *"Verifica tu cuenta [RECIBÍ EL DINERO]"*.
- **Mediation over Disputes**: Replace raw disputes with a reassuring *"¿Hay un problema? [PEDIR AYUDA]"* workflow that connects the user with the community's trusted mediator.

### 1.4 What This Feature Is NOT (Non-Goals)

To preserve the decentralization, privacy, and sovereignty of Mostro:
- **NOT a custodial wallet**: Users always maintain their own keys and Lightning wallet (via NWC or direct invoices).
- **NOT a centralized account system**: No email, passwords, phone numbers, or centralized database.
- **NOT mandatory KYC**: No real-name identity verification, government ID capture, or surveillance.
- **NOT a parallel protocol**: Does NOT alter or replace Mostro protocol v2 or wire communications. It is purely an ergonomic abstraction layer over existing protocol messages.
- **NOT a permanent fork**: Designed specifically to be contributed upstream to `MostroP2P/app`.

---

## 2. User Scenarios & Testing

### User Story 1 — Instant Community Onboarding via QR Code (Priority: P1)

**Persona**: A newcomer attending a local Bitcoin meetup who wants to buy Bitcoin without knowing what Nostr or Lightning hold invoices are.

**Narrative**:  
The user installs Mostro App. On the welcome screen, the app prompts: *"Escanear QR de tu comunidad"* or *"Entrar al mercado general"*. The user points their camera at the QR code displayed by the local community organizer (generated by Mostro Community Manager on Umbrel).  
The app validates the signed profile and displays a clean card:
```text
┌───────────────────────────────────────┐
│         Bitcoin Medellín ✓            │
│                                       │
│  Moneda: COP                          │
│  Métodos: Bancolombia, Nequi, Efectivo│
│  Operador verificado                  │
│                                       │
│         [ ENTRAR AL MERCADO ]         │
└───────────────────────────────────────┘
```
Upon tapping **"Entrar al mercado"**, the app silently sets the active Mostro node, registers the community relays, selects COP as the primary fiat currency, and filters payment methods. The user is now inside the community market.

**Why this priority**: Eliminates 100% of the manual configuration barrier for new users joining local circular economies.

**Independent Test**:  
Can be tested by feeding a valid signed `CommunityProfile` JSON/bech32 payload to the QR scanner or deep link handler and verifying that:
1. Active node matches the profile pubkey.
2. Relays are added to the pool.
3. Default fiat currency and payment methods are updated.
4. No technical error or Nostr prompt is shown.

**Acceptance Scenarios**:
1. **Given** an unconfigured app on first launch, **When** scanning a valid Community QR, **Then** show community name, currency, payment methods, and an "Entrar al mercado" confirmation button.
2. **Given** a confirmed community profile, **When** entering the market, **Then** the active node pubkey and community relays are persisted in Rust, and the buy/sell screens reflect that community's fiat currency.
3. **Given** a corrupted, tampered, or invalid signature on a Community QR, **Then** reject the profile with a clear warning: *"Código de comunidad no válido o no verificado"* without crashing or altering current node settings.

---

### User Story 2 — Guided Amount-First Buy Flow (Priority: P1)

**Persona**: A user wanting to purchase $50 USD of Bitcoin using a bank transfer.

**Narrative**:  
In Simple Mode, the user selects **"Comprar Bitcoin"** from the navigation bar. Instead of an overwhelming order book, they are presented with a simple 3-step wizard:
1. *"¿Cuánto quieres comprar?"* (User inputs 50 USD, sees estimated sats based on current rate).
2. *"Selecciona tu método de pago"* (Presents community payment methods, e.g., Zelle, Bank Transfer).
3. *"Seleccionar vendedor"* (Displays filtered active sellers with 5-star rating, completed trades count, and price premium/discount).
4. *"Revisar y confirmar"* (Summarizes sats to receive, fee, and temporary refundable security guarantee).  
Upon tapping **"Comprar"**, the trade initiates and moves directly to the humanized trade timeline.

**Why this priority**: Matches the standard mental model of consumer financial applications (Amazon, Uber, fintech apps: choose amount -> choose payment -> confirm).

**Independent Test**:  
Can be tested by selecting an amount and payment method and asserting that matching public sell orders are queried, filtered, and presented with humanized reputation metrics.

**Acceptance Scenarios**:
1. **Given** the user selects 50 USD and "Bancolombia", **When** searching for sellers, **Then** only active sell orders matching USD and Bancolombia within range are displayed.
2. **Given** an order selection, **When** reviewing the confirmation card, **Then** display:
   - "Recibes: X sats"
   - "Comisión: $Y"
   - "Garantía temporal: …" **only when the node bonds takers** — read from
     its Kind 38385 info event (`bond_enabled`, `bond_apply_to`), with the
     node's own figure. With bonds off, or before the node has answered, no
     guarantee is shown at all; no default percentage exists.
3. **Given** the user confirms the purchase, **Then** the taker order request is dispatched via Mostro protocol v2 and navigates to the trade timeline.

---

### User Story 3 — Humanized Trade Timeline & Actions (Priority: P1)

**Persona**: A buyer or seller going through an active trade.

**Narrative**:  
Rather than cryptic protocol statuses (`waiting-buyer-invoice`, `waiting-server-payment`, `fiat-sent`), the user sees a clear, progressive vertical step tracker:
```text
Compra de Bitcoin

✓ Oferta aceptada
✓ Garantía bloqueada
✓ Bitcoin protegido por Mostro

→ Envía $50 por Bancolombia
  Datos de pago:
  Cuenta: 123-456-789 (Ahorros)
  Titular: Carlos M.

  [ YA PAGUÉ ]

○ Esperando que el vendedor confirme
○ Bitcoin recibido en tu wallet
```
Once the buyer taps **"[ YA PAGUÉ ]"**, the seller receives an immediate push notification and in-app status update:
```text
→ El comprador indica que envió el dinero.
  Verifica tu cuenta bancaria antes de confirmar.

  [ RECIBÍ EL DINERO ]
```

**Why this priority**: Prevents user anxiety, mistakes, and accidental premature releases.

**Independent Test**:  
Can be tested with simulated or live trade state updates, verifying that every wire status maps to the correct human-readable milestone and context-sensitive action button.

**Acceptance Scenarios**:
1. **Given** status is `WaitingServerPayment`, **Then** the buyer and seller see: *"Protegiendo Bitcoin: Mostro está asegurando los fondos en custodia temporal"*.
2. **Given** status is `Active` (fiat payment phase) for the buyer, **Then** display counterparty payment details and the primary action button `[ YA PAGUÉ ]`.
3. **Given** status is `FiatSent` for the seller, **Then** display a safety banner (*"Confirma únicamente después de ver el dinero en tu propia cuenta bancaria"*) and the action button `[ RECIBÍ EL DINERO ]`.
4. **Given** status is `Success`, **Then** show a success celebration (*"¡Operación completada! Bitcoin recibido"*).

---

### User Story 4 — Simplified Mediation ("Pedir Ayuda") (Priority: P2)

**Persona**: A user whose counterparty is unresponsive or has an issue with payment.

**Narrative**:  
Instead of an intimidating "Open Dispute" or technical error code, the user sees a permanent option inside their active trade:
```text
¿Tienes algún problema con esta operación?
[ PEDIR AYUDA ]
```
When tapped, a modal opens:
```text
Un mediador de la comunidad revisará tu operación.
Explícanos brevemente qué ocurrió:
[____________________________________]

[ Solicitar Asistencia ]
```
Upon submission, the trade transitions to a clear assistance timeline:
```text
● Solicitud recibida
● Mediador de la comunidad asignado
○ Esperando resolución
```
The in-trade chat is automatically connected to the community solver via Nostr dispute chat envelopes without exposing the solver's pubkey or ephemeral key mechanisms.

**Why this priority**: Humanizes conflict resolution and prevents panic in P2P trading.

**Independent Test**:  
Triggering "Pedir Ayuda" calls the internal dispute API (`dispute_order`), opens the dispute chat room, and updates the UI timeline without showing technical Nostr tags.

**Acceptance Scenarios**:
1. **Given** an active trade, **When** tapping `[ PEDIR AYUDA ]`, **Then** require a brief reason and send the dispute request to the Mostro node.
2. **Given** a mediator accepts the dispute, **Then** the in-trade chat displays a banner: *"El mediador comunitario está en la sala para ayudarles a resolver la situación"*.

---

### User Story 5 — Zero-Jargon Onboarding & Recovery (Priority: P2)

**Persona**: A user creating a profile for the first time, or restoring an existing profile on a new phone.

**Narrative**:  
On first run:
- Screen 1: *"Crea tu perfil"* -> Generates BIP39 mnemonic and Nostr keys in Rust silently.
- Screen 2: *"Guarda tus palabras de recuperación"* -> Displays 12 words with a clear message: *"Estas palabras son tu llave de acceso. Anótalas en papel. Las necesitarás si pierdes o cambias de teléfono."*
- Screen 3: *"Conectar tu wallet Lightning"* -> Connect via NWC QR scan or paste.

Recovery flow:
- Screen: *"Recuperar mi perfil"* -> Prompts for 12 words. Restores identity and trade history without mentioning "nsec" or "NIP-06".

**Why this priority**: Guarantees true non-custodial ownership without cognitive friction.

**Acceptance Scenarios**:
1. **Given** a new install, **When** creating a profile, **Then** mnemonic derivation happens entirely in Rust, with no raw hex or nsec displayed to the user.
2. **Given** a user restoring from 12 words, **When** valid words are submitted, **Then** the account is successfully restored and active trades/history are re-indexed.

---

### User Story 6 — Seamless Switching between Simple and Advanced Mode (Priority: P3)

**Persona**: A technical power user or community operator who needs access to relay diagnostics, custom Mostro nodes, or raw Nostr keys.

**Narrative**:  
In the **Perfil** (Profile) screen, at the bottom, there is an option:
```text
Ajustes avanzados
[ Activar Modo Avanzado ]
```
When toggled:
- The navigation updates to the power-user interface (Order Book, Relays, Node Selector, nsec/npub viewer, PoW settings, Log viewer).
- A persistent chip in the header indicates: `Modo Avanzado (Técnico) [ Cambiar a Modo Simple ]`.
- Toggling back restores Simple Mode instantly without losing any settings.

**Why this priority**: Ensures upstream acceptance by never stripping away features for existing power users.

**Acceptance Scenarios**:
1. **Given** Simple Mode is active, **When** toggling "Modo Avanzado", **Then** the app router and UI shell immediately switch to the full advanced view.
2. **Given** Advanced Mode is active, **When** switching back to Simple Mode, **Then** the 5-destination simple shell is rendered and technical views are hidden.
3. **Given** the mode selection, **Then** the choice is persisted in local storage (`Sembast`).

---

## 3. Functional Requirements

### 3.1 Mode & Navigation Architecture
- **FR-001**: The system MUST support two UI modes: `Simple` and `Advanced`.
- **FR-002**: `Simple` mode MUST be the default mode for all fresh installations.
- **FR-003**: In `Simple` mode, the primary navigation MUST provide exactly 5 destinations:
  1. `Comprar` (`/simple/buy`)
  2. `Vender` (`/simple/sell`)
  3. `Mis operaciones` (`/simple/trades`)
  4. `Perfil` (`/simple/profile`)
  5. `Ayuda` (`/simple/help`)
- **FR-004**: The user MUST be able to switch between `Simple` and `Advanced` mode from the Profile/Settings screen at any time.
- **FR-005**: In `Simple` mode, the UI MUST NOT display Nostr keys (`npub`, `nsec`), relay lists, PoW settings, node hex pubkeys, hold invoice preimages, or HTLC parameters.

### 3.2 Community QR & Deep Linking
- **FR-006**: The system MUST parse and validate Community Profiles from:
  1. Deep link URIs: `mostro://community/<payload>`
  2. Web fallbacks: `https://mostro.network/c/<payload>`
  3. Raw scanned QR payloads (JSON, Bech32 encoded `nprofile`, or Base64URL).
- **FR-007**: The `CommunityProfile` payload MUST contain:
  - `name`: Human-readable community name.
  - `pubkey`: 64-character lowercase hex pubkey of the Mostro node.
  - `relays`: List of WebSocket relay URLs.
  - `currency`: Primary ISO 4217 fiat code (e.g. `COP`, `VES`, `EUR`, `USD`).
  - `payment_methods`: Array of accepted payment methods.
  - `fee_bps`: Community fee in basis points.
  - `bond_percent`: Required security guarantee percentage.
  - `website`: Optional URL.
  - `contact`: Optional operator contact info (Nostr, email, or handle).
  - `sig`: Schnorr signature over the canonical payload by the community operator key.
- **FR-008**: The system MUST verify the profile's digital signature in the Rust core before applying changes.
- **FR-009**: Upon user confirmation of a Community Profile, the app MUST:
  1. Call `set_active_mostro_node(pubkey)` in Rust.
  2. Seed and connect to the community relays.
  3. Set the default fiat currency.
  4. Cache the community's payment methods for filtering.

### 3.3 Transaction & Order Workflows
- **FR-010**: The Buy flow MUST allow the user to specify an amount in fiat, select from available community payment methods, and present a curated list of active sellers. The amount is a **whole number**; the list holds only orders still `pending` on the public book that are not the user's own; a range order is taken for the amount typed and only when it lies inside the order's limits — never for a default.
- **FR-011**: The Sell flow MUST allow the user to create an offer specifying amount, receive method, and payment details without exposing raw Nostr event structures. The offer is always published **at market price** (no sats; the node fixes them when it is taken and applies the premium then), for a whole amount, and cannot be published while the amount field holds anything else.
- **FR-012**: All anti-abuse bonds MUST be labeled as **"Garantía temporal"** (Temporary Security Guarantee) with an explanatory tooltip: *"Se devuelve automáticamente al completar la operación con éxito"*. A guarantee is shown only where one exists: before a trade, when the node's Kind 38385 policy bonds the user's side; in a trade, when its row carries a bond. Never a default figure.
- **FR-013**: The active trade screen MUST present a progressive vertical timeline mapping internal Mostro wire states to clear human-readable milestones:
  - `WaitingMakerBond` / `WaitingTakerBond` -> *Garantía temporal en proceso* (the milestone exists only for a trade that has a bond)
  - `InProgress` -> *Operación tomada, esperando al nodo*. This is the public book's "taken" bucket, which lasts from the take until the trade ends: it is **not** `Active`, offers no payment action, and tells the buyer not to send money yet.
  - `WaitingBuyerInvoice` -> *Conectando wallet de recepción*
  - `WaitingServerPayment` -> *Bitcoin protegido en custodia*
  - `Active` -> *Realizar / esperar pago fiat*
  - `FiatSent` -> *Verificar cuenta bancaria*
  - `SettledHoldInvoice` / `Success` -> *Operación completada*
  - `DisputeInitiatedByYou` / `DisputeInitiatedByPeer` -> *En mediación comunitaria*
- **FR-013b**: The trade view MUST NOT assume a status or a side it has not read. While either is unknown it shows a loading state, never the `Active` buyer view.
- **FR-014**: Before marking payment as sent, the app MUST display a safety checkpoint: *"Verifica cuidadosamente los datos de pago antes de continuar"*.
- **FR-015**: Before releasing Bitcoin, the app MUST display an irreversible action checkpoint: *"Confirma únicamente después de ver el dinero reflejado en tu propia cuenta bancaria. Esta acción no se puede deshacer."*

### 3.4 Assistance & Mediation ("Pedir Ayuda")
- **FR-016**: The active trade view MUST feature a prominent `[ PEDIR AYUDA ]` button instead of "Open Dispute".
- **FR-017**: Tapping `[ PEDIR AYUDA ]` MUST prompt the user for an explanation, trigger the dispute mechanism on the Mostro node, and connect the in-trade chat to the community solver.
- **FR-018**: The mediation view MUST show the status of the case (*Caso recibido*, *Mediador asignado*, *Esperando decisión*).

### 3.5 Localization & Jargon Prevention
- **FR-019**: All user-facing strings MUST be defined in Flutter ARB files (`lib/l10n/app_{en,es,fr,de,it,nl}.arb`).
- **FR-020**: Rust core MUST return stable markers or typed data; no localized user-facing prose may be hard-coded in Rust.

---

## 4. Key Entities & Data Models

### 4.1 CommunityProfile (Rust Core)

Defined in `rust/src/api/community.rs`:

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CommunityProfile {
    pub version: u32,
    pub name: String,
    pub pubkey: String,
    pub relays: Vec<String>,
    pub currency: String,
    pub payment_methods: Vec<String>,
    pub fee_bps: u32,
    pub bond_percent: u32,
    pub website: Option<String>,
    pub contact: Option<String>,
    pub signature: String,
}
```

### 4.2 UiMode (Dart / Sembast)

Defined in `lib/core/ui_mode.dart`:

```dart
enum UiMode {
  simple,
  advanced,
}
```

Persisted under `app_preferences` store key `ui_mode`. Defaults to `UiMode.simple`.

### 4.3 HumanTradeStep (Dart View Model)

```dart
enum HumanTradeStep {
  accepted,           // Offer matched
  bondLocked,         // Temporary guarantee secured
  escrowSecured,      // Bitcoin protected by Mostro
  fiatPending,        // Send fiat / waiting fiat
  fiatSent,           // Verify bank account / release
  completed,          // Finished successfully
  inMediation,        // Community mediator assisting
  canceled,           // Canceled cooperatively or expired
}
```

---

## 5. Security & Architectural Integrity

1. **The Golden Rule**:
   - All cryptography, Nostr message handling, signature verification, key derivation, and relay communication stay in **Rust**.
   - Dart manages UI widgets, view-model mapping, navigation, and local UI state preferences.
   - **No cryptography in Dart.**
2. **Community Signature Verification**:
   - The signature in `CommunityProfile` is validated in Rust using Schnorr verification (`schnorr::Signature`) over the SHA-256 hash of the canonical serialized JSON fields.
   - Prevents malicious relay operators or MITM attackers from spoofing node pubkeys or payment instructions.
3. **Data Isolation & Ephemeral State**:
   - Sensitive user payment details (bank account numbers, phone numbers) are shared **only** over end-to-end encrypted Kind 14 chat envelopes (NIP-44) directly with the trade peer.
   - No payment details are ever published in cleartext or logged in analytics.
4. **Push Notifications**:
   - Adheres strictly to the Mostro doorbell pattern (`docs/PUSH_NOTIFICATIONS.md`): push notifications are content-free wake-up signals (`trade_update`, `chat_wake`). Sensitive details are retrieved directly from Nostr relays upon app wake-up.

---

## 6. Measurable Success Criteria

- **SC-001**: A new user can complete first-run setup (profile creation + community QR scan) in **under 60 seconds** without encountering a single technical Nostr term (`npub`, `nsec`, `relay`, `HTLC`).
- **SC-002**: 100% of Community Profiles generated by *Mostro Community Manager for Umbrel* decode, verify, and configure Mostro App in a single user confirmation tap.
- **SC-003**: 0% regression in Advanced Mode functionality: power users can toggle to Advanced Mode and access all existing features (custom relays, node switcher, Nostr key export, raw logs).
- **SC-004**: All unit tests in `rust` and widget tests in `test/` pass warning-free (`cargo test && cargo clippy`, `flutter analyze && flutter test`).
- **SC-005**: 100% of user-facing copy in Simple Mode is localized across all 6 supported languages (`en`, `es`, `fr`, `de`, `it`, `nl`).

---

## 7. Phased Implementation Roadmap

To ensure smooth upstream contributions to `MostroP2P/app`, this specification is structured into 5 incremental, independently reviewable phases:

| Phase | Scope | Target Deliverable |
|---|---|---|
| **Phase 1** | Specification & Contracts | `specs/007-simple-ux/spec.md` (this document), `data-model.md`, and contracts. |
| **Phase 2** | Community Profile in Rust Core | `rust/src/api/community.rs`, parser, Schnorr signature verification, QR decoder, and FRB bridge generation. |
| **Phase 3** | UI Mode Shell & Navigation | `uiModeProvider`, persistent mode toggle, 5-destination Simple Mode navigation bar, and screen scaffolding. |
| **Phase 4** | Amount-First Buy & Sell Wizards | Simplified order creation, community payment method filters, and friendly seller reputation cards. |
| **Phase 5** | Humanized Trade Timeline & Help | Progressive step timeline, safety warnings, and the *"¿Hay un problema? [PEDIR AYUDA]"* mediation flow. |

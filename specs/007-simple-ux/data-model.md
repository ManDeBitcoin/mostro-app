# Data Model: 007 — Simple UX & Community Profiles

**Feature Branch**: `007-simple-ux`  
**Created**: 2026-09-29  
**Status**: Draft  

---

## 1. Entities

### 1.1 CommunityProfile (Rust Core & Storage)

Represents a community configuration signed by the community node operator (e.g. from *Mostro Community Manager*).

| Field | Type | Description |
|---|---|---|
| `version` | `u32` | Schema version (currently `1`) |
| `name` | `String` | Display name of the community (e.g., "Bitcoin Medellín") |
| `pubkey` | `String` | 64-char lowercase hex Nostr public key of the Mostro daemon |
| `relays` | `Vec<String>` | List of WebSocket relay URLs used by the community node |
| `currency` | `String` | ISO 4217 fiat currency code (e.g., "COP", "USD", "EUR") |
| `payment_methods` | `Vec<String>` | Prioritized accepted payment methods (e.g., `["Bancolombia", "Nequi"]`) |
| `fee_bps` | `u32` | Operator fee in basis points (e.g., `60` = 0.6%) |
| `bond_percent` | `u32` | Security guarantee percentage (e.g., `3` = 3%) |
| `website` | `Option<String>` | Optional community web link |
| `contact` | `Option<String>` | Optional operator contact (Nostr npub, Telegram, or email) |
| `signature` | `String` | 64-byte hex (128 char) Schnorr signature over canonical payload |

**Validation Rules**:
- `pubkey` MUST be a valid 64-character lowercase hex string.
- `relays` MUST contain at least one valid `ws://` or `wss://` URI.
- `currency` MUST be exactly 3 uppercase ASCII letters matching ISO 4217.
- `signature` MUST verify against `pubkey` using BIP-340 Schnorr verification over the SHA-256 hash of the canonical JSON representation.

---

### 1.2 UiModePreference (Dart / Sembast)

Stores the user's selected interface complexity mode.

| Field | Type | Description |
|---|---|---|
| `mode` | `String` | `"simple"` (default) or `"advanced"` |
| `updated_at` | `int` | Unix epoch milliseconds of the last change |

**Storage Key**: `settings.ui_mode` in the local Sembast store.

---

### 1.3 HumanTradeView (Dart View Model)

Projects complex protocol states and counterparty tags into a humanized view model for the Simple Mode UI.

| Field | Type | Description |
|---|---|---|
| `order_id` | `String` | Trade / Order UUID |
| `kind` | `String` | `"buy"` or `"sell"` from the user's perspective |
| `human_status` | `HumanTradeStep` | Progressive visual milestone enum |
| `fiat_amount` | `double` | Fiat total to pay or receive |
| `fiat_code` | `String` | Currency symbol / code |
| `sats_amount` | `int` | Estimated or confirmed satoshis |
| `payment_method` | `String` | Selected payment method |
| `payment_details` | — | Not a field of the view. The seller's payment details reach the buyer as a message in the trade's chat (`spec.md` FR-015b); the buyer's view points at the chat, the seller's sends them |
| `temporary_bond_sats` | `int` | Refundable security deposit in satoshis |
| `counterparty_name` | `String` | Humanized identifier (e.g. "Usuario 7F3A") |
| `counterparty_rating` | `double` | 0.0 to 5.0 star rating |
| `counterparty_trades` | `int` | Number of completed operations |
| `counterparty_days` | `int` | Days active in the community |
| `can_pay` | `bool` | Whether `[ YA PAGUÉ ]` is currently actionable |
| `can_release` | `bool` | Whether `[ RECIBÍ EL DINERO ]` is currently actionable |
| `can_request_help` | `bool` | Whether `[ PEDIR AYUDA ]` is currently actionable |
| `mediator_active` | `bool` | Whether a community solver is actively assigned |

---

## 2. State Machine Mapping: Protocol v2 to Simple UX

The table below defines the strict mapping between low-level Mostro wire statuses and the Simple Mode visual milestone:

| Internal Mostro Status | Maker/Taker Context | Visible Milestone (`HumanTradeStep`) | Primary Action Button | Human Copy / Guidance |
|---|---|---|---|---|
| `WaitingMakerBond` | Maker | `bondLocked` (in progress) | *None (processing)* | "Asegurando tu garantía temporal..." |
| `WaitingTakerBond` | Taker | `bondLocked` (in progress) | *None (processing)* | "Asegurando tu garantía temporal..." |
| `WaitingBuyerInvoice` | Buyer | `accepted` | `[ Conectar Wallet ]` | "Conectando wallet de recepción..." |
| `WaitingServerPayment` | Seller | `escrowSecured` (in progress)| *None (waiting daemon)* | "Mostro está protegiendo el Bitcoin..." |
| `Active` | Buyer | `fiatPending` | `[ YA PAGUÉ ]` | "Envía el dinero a tu contraparte" |
| `Active` | Seller | `fiatPending` | *Waiting peer* | "Esperando que el comprador envíe el dinero" |
| `FiatSent` | Buyer | `fiatSent` | *Waiting peer* | "Esperando confirmación del vendedor" |
| `FiatSent` | Seller | `fiatSent` | `[ RECIBÍ EL DINERO ]` | "Verifica tu cuenta bancaria y confirma" |
| `SettledHoldInvoice` / `Success` | Both | `completed` | `[ Nueva Operación ]` | "¡Operación completada con éxito!" |
| `DisputeInitiatedByYou` | Initiator | `inMediation` | `[ Chat con Mediador ]` | "Mediador comunitario asignado" |
| `DisputeInitiatedByPeer` | Counterparty| `inMediation` | `[ Chat con Mediador ]` | "Operación en revisión por mediador" |
| `CooperativelyCanceled` | Both | `canceled` | `[ Cerrar ]` | "Operación cancelada de mutuo acuerdo" |

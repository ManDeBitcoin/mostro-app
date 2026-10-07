# Contract: Payment Details API

**Module**: `rust/src/api/payment_details.rs` (bridge surface) over
`rust/src/mostro/payment_details.rs` (rules and storage).

How a seller is paid — account number, holder, phone — kept on the device
per payment method, and handed to the buyer over the trade's chat once the
escrow is locked.

## Why it exists

A sell order names the ways its seller takes the money (the `pm` tag) and
nothing else about them: the order is public (Kind 38383). The account
behind a method is what the buyer needs at exactly one moment, when the
seller's sats are locked and it is the buyer's turn to pay.

The only private channel between the two exists from that same moment. In
Lightning mode mostrod names each party's trade key to the other in
`buyer-took-order` (to the seller) and `hold-invoice-payment-accepted` (to
the buyer), the two messages that announce `active` (v0.19.2,
`flow.rs::hold_invoice_paid`, `app/add_invoice.rs`); the `pay-invoice`
payload carries neither. The chat keys are derived from both keys
(`contracts/messages.md`), so before the lock there is nothing to encrypt
to. In Cashu mode the seller learns the buyer's key earlier, at
`waiting-payment` (`show_cashu_escrow_request`) — which is why the rule
below is the trade's status and not "a chat exists".

## What is kept

Both in the settings store, both **identity-scoped**
(`settings_keys::IDENTITY_SCOPED_PREFIXES`): `delete_identity` erases them
with the rest of what the identity produced (`contracts/identity.md`).

| Key | Value |
|---|---|
| `payment_details:saved` | JSON array of `{method, details}`, in the order each method was first saved |
| `payment_details_sent:<order_id>` | unix seconds (decimal) of the chat message that carried the details for that order |

A method is told from another without regard to case or outer spaces
(`Banco X` = ` banco x `), as Simple Mode tells them apart. The details are
free text, at most 1000 characters per method; a method's name at most 100.

Nothing in either module logs a method's details: log lines carry an error
or a shortened order id (a test reads the source to hold that).

## Types

```
PaymentDetails {
  method: String     # the method's name, as an order or the community's card writes it
  details: String    # free text; empty when nothing is kept
}
```

## Functions

### saved_payment_details() → Vec<PaymentDetails>
Every method the device keeps details for. Empty when it keeps none.

### payment_details_for(methods: Vec<String>) → Vec<PaymentDetails>
What is kept for each of `methods`, in their order and their spelling;
`details` is empty where nothing is kept, and an empty name is skipped.

### save_payment_details(method: String, details: String) → ()
Keeps `details` for `method` in place of what was kept for it. Empty
`details` forget the method. Concurrent saves all land (the one document is
written under a lock).

**Errors**: `InvalidPaymentMethod` (no name, or one past 100 characters),
`PaymentDetailsTooLong`. Nothing is written when refused.

### send_payment_details(order_id: String, content: String) → ChatMessage
Sends `content` — the message as the buyer will read it, composed in Dart
because it is prose — to the counterparty of `order_id` over the peer chat
envelope.

**The rule** (`mostro::payment_details::may_send`), checked before anything
is sent:

- the trade row exists and this user is its **seller**;
- the row's status is `active`, `fiat-sent` or `dispute` — the escrow is
  locked — and the row has no outcome.

The status is the trade row's, which only the node's private messages
move; the public book's `in-progress` is "taken", never "locked".

**Delivery**: unlike `send_message`, which keeps a message it could not
publish and returns it like one that left, this returns only once a relay
accepted the envelope (`api::messages::send_delivered`). Refused or failed,
nothing is stored in the conversation and no mark is written. On success
the message is in the conversation, the peer is woken as for any chat
message, and `payment_details_sent:<order_id>` holds its timestamp.

**Errors** (markers): `StorageUnavailable`, `MessageEmpty`,
`PaymentDetailsNoTrade`, `PaymentDetailsNotSeller`,
`PaymentDetailsEscrowNotLocked`, `PaymentDetailsPeerUnknown` (the buyer's
key has not reached this device yet — it arrives with the message that
announces the lock, and a trade rebuilt by a restore can be a replay
behind), `NoRelayAccepted`, `MessageTooLarge`, `SendFailed`.

### payment_details_sent_at(order_id: String) → i64?
When the details of `order_id` were sent from this device, or `null`.

## What Dart does with it (Simple Mode)

- **Sell tab**: a field per chosen payment method, opened with what the
  device keeps and kept as it is typed. The confirmation sheet shows the
  details and says they are not published; `NewOrderParams` has no field
  for them.
- **Trade view, seller**: while the status is `active`, a card with the
  details of each of the order's methods (editable, each with a tick) and
  one button that sends them. Nothing is sent without that tap. Once sent,
  the card says so and offers to send again; at `fiat-sent` and `dispute`
  it shows only that.
- **Trade view, buyer**: at `active`, where the account comes from (the
  chat), a button into it and how many messages wait unread.

The message is plain text — a header line and a block per method — so any
Mostro client shows it as written.

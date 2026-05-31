---
name: cart-checkout-orders
description: >-
  Build multi-vendor cart, checkout, and order management. Use for shopping cart,
  checkout flow, multi-vendor order splitting, order lifecycle/state machine,
  returns/RMA, cancellations, and refunds. Covers the one-cart→many-sub-orders
  pattern, inventory reservation, idempotent checkout, and order tracking.
---

# Cart, Checkout & Orders (multi-vendor)

The buyer journey: cart with items from many sellers → one checkout/payment → **split into
per-vendor sub-orders** → each fulfilled and tracked independently.

## Cart
- Server-side cart keyed by user (+ guest cart merged on login); Redis for speed.
- Group line items **by seller/vendor** in the UI and model.
- Validate at view + checkout: price changes, stock, min-order (food), delivery availability.
- Cart ≠ reservation — only reserve stock at order/payment.

## Checkout flow

```
1. Address / delivery method (per vendor: shipping option or delivery slot)
2. Recompute: per-vendor subtotal, shipping/delivery fee, service fee, tax, discounts
3. Apply promotions/coupons (platform-funded vs seller-funded — track who pays)
4. Reserve inventory (atomic) → create Order (pending)
5. Take ONE payment for the whole cart (idempotency key!)
6. On payment success → split into SUB-ORDERS per vendor → notify each vendor
7. On failure → release reservation, fail order
```
Wrap creation in a DB transaction; make checkout **idempotent** (retry must not double-charge or
double-create orders).

## Order model (split)

```
Order (buyer, total, payment_id, address, status)
 └─ SubOrder (vendor_id, subtotal, commission, payout, fulfillment_type, status)  ← per vendor
     └─ OrderItem (offer/variant, qty, unit_price, modifiers[, tax])
Each SubOrder has its OWN lifecycle (a buyer order can be partly delivered, partly cancelled).
```

## Order lifecycle (state machine — per sub-order)

```
Product:  PLACED → CONFIRMED → PACKED → SHIPPED → OUT_FOR_DELIVERY → DELIVERED
                 ↘ CANCELLED            ↘ RETURN_REQUESTED → RETURNED → REFUNDED
Food:     PLACED → ACCEPTED → PREPARING → READY → PICKED_UP → DELIVERED
                 ↘ REJECTED (auto-refund)        ↘ CANCELLED
```
- Enforce valid transitions only; record every transition (who/when) for audit + tracking.
- Vendor accept/reject window (food) with auto-cancel + refund on timeout.

## Returns / RMA / cancellations
- Return request → vendor/admin approval → return label/pickup → inspect → refund (full/partial).
- Cancellation rules by state (free before shipped/accepted; penalties after).
- Refund flows back through payment + **clawback** from vendor payout (link payments skill).

## Notifications & tracking
- Buyer: order confirmed, status changes, tracking link, delivery ETA.
- Vendor: new order, reminders; Admin: exceptions (failed/stuck/disputed).
- Real-time updates via WebSocket/push (essential for food/delivery).

## Checklist
```
- [ ] Server cart grouped by vendor; validate price/stock/min-order at checkout
- [ ] Single payment + idempotency key; reserve stock atomically
- [ ] Split into per-vendor sub-orders, each with own state machine
- [ ] Promotions (platform vs seller funded) tracked for payout accuracy
- [ ] Returns/RMA + cancellation rules + partial refunds + payout clawback
- [ ] Full transition audit + buyer/vendor/admin notifications + tracking
```

## Anti-patterns
- One flat order with no per-vendor sub-orders (can't fulfill/pay/refund independently).
- Non-idempotent checkout → duplicate orders/charges on retry.
- Reserving stock at add-to-cart; not releasing on abandonment.
- Free-text order status instead of an enforced state machine.
- Refunding the buyer without clawing back from the seller payout.

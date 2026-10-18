# Working with arbitrary-width bitsets

Read, combine and serialize masks while preserving every unsigned bit.

## Overview

### Parse the wire representation

Discord permission masks are decimal strings. A machine integer may fit today's known flags while silently excluding a future high bit. ``UnsignedBitSet`` retains the complete value and accepts leading decimal zeroes without retaining that formatting.

```swift
import DiscordBits

let original = try UnsignedBitSet(decimalString: "00018446744073709551616")
assert(original.contains(64))
assert(original.description == "18446744073709551616")
let selected = try UnsignedBitSet(bits: [3, 10, 64])
let combined = original.union(selected)
assert(combined.contains(10))
assert(combined.bitWidth == 65)
```

`contains` returns false for negative positions or positions beyond stored words. Insertion validates its inclusive `maximumBit` before changing the value. Clearing an absent bit does not allocate new storage.

### Apply finite set algebra

Use `union` for either operand's bits, `intersection` for their shared bits, `symmetricDifference` for differences and `subtracting` to clear a finite mask. Subtraction is bounded by the left operand's finite width; there is no infinite complement or implicit truncation to 64 bits.

```swift
let grants = try UnsignedBitSet(bits: [4, 65, 80])
let removed = try UnsignedBitSet(bits: [65])
let effective = grants.subtracting(removed)
assert(effective.contains(4))
assert(!effective.contains(65))
assert(effective.contains(80))
```

These operations describe bits only. Guild owner rules, administrator semantics, role aggregation, channel overwrites, thread membership and visibility require complete domain facts. A mask parsed from a client or a cache is not current authorization.

### Encode without numeric conversion

The Codable form is a canonical decimal JSON string. Keep that string when forwarding a mask to another service. Converting through `Double`, a JavaScript number or a signed machine integer loses information or narrows the range. Equality compares numeric bit content, so zero padding does not create distinct masks.

Set operations scale with stored word count. Decimal formatting performs long division and is more expensive than `contains`; format once at a display or wire boundary instead of repeatedly inside a hot permission loop.

### Related reading

- <doc:BitSetValidation>
- ``UnsignedBitSet``

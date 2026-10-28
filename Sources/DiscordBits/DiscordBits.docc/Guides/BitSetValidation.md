[//]: # "File: Sources/DiscordBits/DiscordBits.docc/Guides/BitSetValidation.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Validating masks at trust boundaries

Choose finite parsing and insertion limits and test rejected input explicitly.

## Overview

### Separate syntax from allocation policy

`init(decimalString:maximumDigits:)` accepts only nonempty ASCII digits. Signs, exponent notation, separators, Unicode numerals and whitespace are invalid. Its default limit is 16,384 digits; lower that bound when a public protocol needs far smaller values. Leading zeroes count toward the input limit even though output is canonical.

`init(bits:maximumBit:)` and `set(_:to:maximumBit:)` use an inclusive bit-position boundary. The default boundary is 1,048,575. The limit is an application resource policy, not a statement that every bit has a supported Discord meaning. Keep unknown bits when reading and validate operation-specific allowed bits when constructing requests.

```swift
import DiscordBits
import Testing

/// Exercises future-bit preservation, malformed syntax and the inclusive allocation cap.
/// Synthetic values require no network resources or shared state.
/// - Throws: Unexpected errors while constructing the valid boundary fixture.
@Test("Parsing keeps future bits and rejects malformed input")
func bitSetBoundaryExample() throws {
    let future = try UnsignedBitSet(bits: [100], maximumBit: 100)
    #expect(future.contains(100))
    #expect(throws: UnsignedBitSet.ValidationError.self) {
        try UnsignedBitSet(decimalString: "+1", maximumDigits: 8)
    }
    #expect(throws: UnsignedBitSet.ValidationError.self) {
        try UnsignedBitSet(bits: [101], maximumBit: 100)
    }
}
```

This is a standalone test pattern. Put it in a Swift Testing target that depends on DiscordBits. The assertions check preservation and both syntax and allocation rejection; no credentials, clocks or network peers are required.

### Handle failures without retaining input

Validation errors are closed categories: invalid decimal syntax, excessive input, invalid limits and invalid bit positions. They do not copy the submitted mask into a diagnostic. Record the error category and your configured limit when useful; avoid logging whole untrusted payloads merely to explain a rejected value.

A failed insertion leaves the existing mask unchanged. Test that invariant when using masks as part of a larger transactional update. For bulk untrusted inputs, also bound the number of masks and aggregate widths; one finite per-value cap alone does not bound total request work.

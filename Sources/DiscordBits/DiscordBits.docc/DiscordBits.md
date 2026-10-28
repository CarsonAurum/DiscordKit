[//]: # "File: Sources/DiscordBits/DiscordBits.docc/DiscordBits.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordBits``

Preserve arbitrary-width unsigned masks without losing future permission bits.

## Overview

Use this small independent product when a wire value is a decimal bitset rather than a machine-sized integer. ``UnsignedBitSet`` owns parsing, bounded insertion, set algebra, comparison and canonical Codable representation. It performs no network work and does not infer authorization from named or unknown bits.

Start with <doc:WorkingWithBitSets>, then use <doc:BitSetValidation> to choose resource bounds for untrusted input. Permission inheritance belongs to the separate DiscordCache product.

## Topics

### Learning path

- <doc:WorkingWithBitSets>
- <doc:BitSetValidation>

### API reference

- <doc:APIReference>

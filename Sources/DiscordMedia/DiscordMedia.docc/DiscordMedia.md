# ``DiscordMedia``

Represent, process, stream and pace bounded portable PCM and encoded media.

## Overview

This product owns media values and deterministic processing, independently of devices, codecs and network sessions. PCM uses interleaved normalized Float samples with exact integer sample-frame clocks. Constructors start no I/O. Select streaming ownership, queue budgets, resampling quality and cancellation explicitly rather than treating a block of samples as a realtime device.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:PCMAndTime>
- <doc:StreamingAndResampling>

### Core APIs

- ``PCMFormat``
- ``PCMBuffer``
- ``MediaTime``
- ``PCMSampleClock``
- ``PCMFrameStream``
- ``PCMFrameQueue``
- ``PCMStreamingResampler``
- ``PCMBandlimitedResampler``
- ``PCMFramePacer``
- ``PCMSpeechActivityDetector``

### Complete API reference

- <doc:APIReference>

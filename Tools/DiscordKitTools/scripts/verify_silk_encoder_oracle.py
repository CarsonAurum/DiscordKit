#!/usr/bin/env python3
"""Offline owned mono/stereo PCM SILK encoders -> ordinary libopus 1.6.1 decode.

Verifies a separately supplied pinned source archive and builds unmodified libopus
only in temporary storage. No downloads, native product linkage, device, network or
credential is used. Voiced/unvoiced/inactive encoding at 8/12/16 kHz and 10/20ms,
optional next-packet LBRR, actual recovery selection and subsequent ordinary packets
are covered. Reference perceptual encoder equivalence, DTX, complete codec
conformance and realtime qualification are not claimed.
"""
import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import platform
import random
import tempfile

from verify_opus_range_oracle import (
    ARCHIVE_BYTE_COUNT, ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION,
    digest, extract_verified_archive, run,
)
from verify_silk_mono_oracle import run_at
from verify_silk_stereo_oracle import (
    C_DRIVER, OWNED_PATHS as DECODER_PATHS, OFFICIAL_PATHS, commands,
)
from verify_silk_frame_oracle import parse_outputs
from verify_silk_pulse_oracle import compare_results
from verify_silk_loss_oracle import C_DRIVER as LOSS_C_DRIVER, SWIFT_DRIVER as LOSS_SWIFT_DRIVER, commands as loss_commands

OWNED_PATHS = DECODER_PATHS + tuple("Sources/DiscordVoiceCodecs/" + name + ".swift" for name in (
    "SILKFrameParameterEncoder", "SILKFrameQuantization", "SILKMonoEncoder", "SILKStereoEncoder"))
MEDIA_PATH = "Sources/DiscordMedia/PCM.swift"

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable { let rate:Int; let milliseconds:Int; let channels:Int; let cap:Int; let fec:Bool; let frames:[[Int16]] }
struct Output: Encodable { let pcm:[Int16]; let ranges:[UInt32]; let bits:[Int]; let activity:[[[Bool]]]; let redundancy:[[[Bool]]] }
struct Stream: Encodable { let rate:Int; let packets:[[UInt8]]; let decoded:[Output]; let rejected:Int }
@main struct Driver {
 static func main() throws {
  while let line=readLine() {
   let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   var mono=try SILKMonoEncoder(sampleRate:input.rate,frameDurationMilliseconds:input.milliseconds,maximumPayloadBytes:input.cap,enableInBandFEC:input.fec)
   var stereo=try SILKStereoEncoder(sampleRate:input.rate,frameDurationMilliseconds:input.milliseconds,maximumPayloadBytes:input.cap,enableInBandFEC:input.fec)
   var decoder=try SILKStereoDecoder(sampleRate:input.rate)
   var packets:[[UInt8]]=[];var decoded:[Output]=[];var rejected=0
   for pcm in input.frames {
    do {
     let packet:OpusPacket;let range:UInt32;let bits:Int
     if input.channels==1 {let encoded=try mono.encode(pcm);packet=encoded.packet;range=encoded.finalRange;bits=encoded.bitsUsed}
     else {let encoded=try stereo.encode(pcm);packet=encoded.packet;range=encoded.payload.finalRange;bits=encoded.payload.bitsUsed}
     let output=try decoder.decode(packet)
     guard output.payloads[0].finalRange==range,output.payloads[0].bitsUsed==bits else {throw CocoaError(.coderInvalidValue)}
     packets.append([UInt8](packet.data))
     decoded.append(Output(pcm:output.pcm48k,ranges:output.payloads.map(\.finalRange),bits:output.payloads.map(\.bitsUsed),activity:output.payloads.map(\.voiceActivity),redundancy:output.payloads.map(\.redundancy)))
    } catch SILKMonoEncoderError.payloadBudgetExceeded {rejected += 1}
   }
   print(String(decoding:try JSONEncoder().encode(Stream(rate:input.rate,packets:packets,decoded:decoded,rejected:rejected)),as:UTF8.self))
  }
 }
}
'''


def requests():
    """Build all formats/caps over silence, tones, identical/opposed stereo, noise and extrema."""
    result = []
    for rate in (8000, 12000, 16000):
        for milliseconds in (10, 20):
            for channels in (1, 2):
                for cap in (64, 128, 1275):
                    frames = []
                    rng = random.Random(rate + milliseconds * channels)
                    count = rate * milliseconds // 1000
                    for pattern in range(8):
                        frame = []
                        for index in range(count):
                            t = (index + pattern * count) / rate
                            frequency = 200 if pattern == 2 else 310 if pattern == 3 else 440
                            left = int(10000 * math.sin(2 * math.pi * frequency * t))
                            right = int(8000 * math.sin(2 * math.pi * 731 * t))
                            if pattern == 0 or pattern == 7:
                                left = right = 0
                            elif pattern == 2:
                                right = left
                            elif pattern == 3:
                                right = -left
                            elif pattern == 4:
                                left, right = rng.randrange(-32768, 32768), rng.randrange(-32768, 32768)
                            elif pattern == 5:
                                left, right = ((-32768, 32767) if index % 2 else (32767, -32768))
                            elif pattern == 6:
                                left, right = 1234, -2345
                            frame.append(left)
                            if channels == 2:
                                frame.append(right)
                        frames.append(frame)
                    for fec in (False, True):
                        result.append(dict(rate=rate, milliseconds=milliseconds, channels=channels, cap=cap, fec=fec, frames=frames))
    return result


def validate_encoded(inputs, streams):
    """Check admission accounting, framing/mode/size and finite per-packet sample dimensions."""
    if len(inputs) != len(streams):
        raise RuntimeError("Encoder output stream count differs")
    for index, (request, stream) in enumerate(zip(inputs, streams)):
        packets = stream["packets"]
        if not packets or len(packets) + stream["rejected"] != len(request["frames"]):
            raise RuntimeError(f"Invalid admission accounting in stream {index}")
        if len(packets) != len(stream["decoded"]):
            raise RuntimeError(f"Missing decoded evidence in stream {index}")
        for packet, decoded in zip(packets, stream["decoded"]):
            expected_config = (request["rate"] // 4000 - 2) * 4 if request["rate"] != 16000 else 8
            expected_config += request["milliseconds"] // 10 - 1
            if (not 2 <= len(packet) <= request["cap"] + 1 or packet[0] & 3
                    or packet[0] >> 3 != expected_config
                    or (2 if packet[0] & 4 else 1) != request["channels"]):
                raise RuntimeError(f"Invalid ordinary SILK packet in stream {index}")
            if len(decoded["pcm"]) != request["milliseconds"] * 96:
                raise RuntimeError(f"Invalid stereo-output PCM dimensions in stream {index}")
            if not request.get("fec", False) and any(decoded["redundancy"][0][channel][0] for channel in range(request["channels"])):
                raise RuntimeError("Conservative encoder unexpectedly emitted redundancy")


def recovery_requests(streams):
    """Lose one actual preceding packet, select its owned LBRR, then decode following audio.

    Every accepted sequence runs cold absent-FEC selection and independent losses at
    every packet position. This includes inactive gaps, both/mid/side-only redundancy,
    abrupt gain/pitch changes and both API output layouts. A new decoder owns each
    case so normal-prefix state is independent of other recovery trials.
    """
    inputs = []
    for stream in streams:
        packets = stream["packets"]
        for channels in (1, 2):
            inputs.append(dict(rate=stream["rate"], channels=channels, generalized=True,
                               operations=[dict(mode=2, ms=0, packet=packets[0]),
                                           dict(mode=0, ms=0, packet=packets[0])]))
            for missing in range(len(packets) - 1):
                operations = [dict(mode=0, ms=0, packet=packet) for packet in packets[:missing]]
                operations.append(dict(mode=2, ms=0, packet=packets[missing + 1]))
                operations.extend(dict(mode=0, ms=0, packet=packet) for packet in packets[missing + 1:])
                inputs.append(dict(rate=stream["rate"], channels=channels, generalized=True, operations=operations))
    return inputs


def main():
    """Build temporary independent reference and require exact decoding of every accepted packet."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    repository = args.repository.resolve()
    with tempfile.TemporaryDirectory(prefix="discordkit-silk-encoder-") as temporary:
        directory = Path(temporary).resolve()
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        for name in ("configure", "install-sh", "missing", "depcomp", "compile", "config.guess", "config.sub"):
            (upstream / name).chmod(0o755)
        build = directory / "reference-build"
        build.mkdir()
        configuration = ["--disable-shared", "--enable-static", "--disable-intrinsics", "--disable-asm",
                         "--disable-rtcd", "--disable-dependency-tracking", "--disable-extra-programs", "--disable-doc", "--disable-deep-plc", "--disable-osce"]
        run_at(["sh", str(upstream / "configure")] + configuration + ["CC=" + args.cc], build)
        run_at(["make", "-j4"], build)
        reference_driver = directory / "oracle.c"
        reference_driver.write_text(C_DRIVER)
        reference = directory / "oracle"
        run([args.cc, "-std=c99", "-O2", "-DHAVE_CONFIG_H", "-I" + str(build)]
            + ["-I" + str(upstream / path) for path in ("include", "celt", "silk", "src")]
            + [str(reference_driver), str(build / ".libs/libopus.a"), "-lm", "-o", str(reference)])
        swift_driver = directory / "driver.swift"
        swift_driver.write_text(SWIFT_DRIVER)
        run([args.swiftc, "-O", "-emit-module", "-emit-library", "-module-name", "DiscordMedia",
             "-module-cache-path", str(directory / "module-cache"), str(repository / MEDIA_PATH),
             "-emit-module-path", str(directory / "DiscordMedia.swiftmodule"), "-o", str(directory / "libDiscordMedia.dylib")])
        owned = directory / "encoder"
        run([args.swiftc, "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated",
             "-I", str(directory), "-L", str(directory), "-lDiscordMedia", "-Xlinker", "-rpath", "-Xlinker", str(directory)]
            + [str(repository / path) for path in OWNED_PATHS] + [str(swift_driver), "-o", str(owned)])
        inputs = requests()
        streams = parse_outputs(run([str(owned)], ("\n".join(json.dumps(item) for item in inputs) + "\n").encode()), len(inputs), arrays=False)
        validate_encoded(inputs, streams)
        expected = parse_outputs(run([str(reference)], commands(streams)), len(streams))
        actual = [stream["decoded"] for stream in streams]
        compare_results(inputs, expected, actual, 0)
        recovery_inputs = recovery_requests(streams)
        loss_driver = directory / "loss-oracle.c"
        loss_driver.write_text(LOSS_C_DRIVER)
        loss_reference = directory / "loss-oracle"
        run([args.cc, "-std=c99", "-O2", "-DHAVE_CONFIG_H", "-I" + str(build)]
            + ["-I" + str(upstream / path) for path in ("include", "celt", "silk", "src")]
            + [str(loss_driver), str(build / ".libs/libopus.a"), "-lm", "-o", str(loss_reference)])
        loss_swift = directory / "loss-driver.swift"
        loss_swift.write_text(LOSS_SWIFT_DRIVER)
        loss_owned = directory / "loss-owned"
        run([args.swiftc, "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated",
             "-I", str(directory), "-L", str(directory), "-lDiscordMedia", "-Xlinker", "-rpath", "-Xlinker", str(directory)]
            + [str(repository / path) for path in OWNED_PATHS] + [str(loss_swift), "-o", str(loss_owned)])
        recovery_expected = parse_outputs(run([str(loss_reference)], loss_commands(recovery_inputs)), len(recovery_inputs))
        recovery_actual = parse_outputs(run([str(loss_owned)], ("\n".join(json.dumps(item) for item in recovery_inputs) + "\n").encode()), len(recovery_inputs))
        compare_results(recovery_inputs, recovery_expected, recovery_actual, 0)
        selected_fec = [result for item, results in zip(recovery_inputs, recovery_expected)
                        for operation, result in zip(item["operations"], results) if operation["mode"] == 2]
        masks = {tuple(channel[0] for channel in result["redundancy"][0]) for result in selected_fec}
        required_masks = {(False,), (True,), (False, False), (True, False), (False, True), (True, True)}
        if not required_masks.issubset(masks):
            raise RuntimeError(f"Missing selected owned-LBRR channel cases: {required_masks - masks}")
        report = dict(
            verifiedOn=datetime.now(timezone.utc).date().isoformat(),
            scope="Owned voiced/unvoiced/inactive mono/stereo PCM16 SILK encoding at 8/12/16kHz, 10/20ms, bounded caps and optional prior-active-frame LBRR. Independent normal decoding and actual missing-packet LBRR selection followed by ordinary current/following packets. Excludes perceptual delayed-decision/reference encoder equivalence, DTX, complete codec conformance, devices and realtime qualification",
            officialVersion=VERSION, officialReleaseURL=RELEASE_URL, sourceArchiveURL=SOURCE_URL,
            sourceArchiveSHA256=ARCHIVE_SHA256, sourceArchiveByteCount=ARCHIVE_BYTE_COUNT,
            sourceLicense="Unmodified upstream COPYING retained in temporary build; owned parameter adaptation retains source notice",
            sourceLicenseSHA256=digest(upstream / "COPYING"), referenceConfiguration=configuration,
            officialSourceSHA256={path: digest(upstream / path) for path in OFFICIAL_PATHS},
            ownedSwiftSHA256={path: digest(repository / path) for path in OWNED_PATHS + (MEDIA_PATH,)},
            verifierSHA256=digest(Path(__file__)), pythonVersion=platform.python_version(),
            compiler=run([args.cc, "--version"]).decode().splitlines()[0],
            swiftCompiler=run([args.swiftc, "--version"]).decode().splitlines()[0], host=platform.platform(),
            encodedStreams=len(streams), encodedPackets=sum(len(stream["packets"]) for stream in streams),
            recoveryStreams=len(recovery_inputs),
            recoveryOperations=sum(len(item["operations"]) for item in recovery_inputs),
            selectedFECOperations=len(selected_fec),
            selectedFECChannelMasks=[list(mask) for mask in sorted(masks)],
            recoveryPCM16Values=sum(len(result["pcm"]) for results in recovery_expected for result in results),
            recoveryVerifierSHA256=digest(repository / "Tools/DiscordKitTools/scripts/verify_silk_loss_oracle.py"),
            boundedRejectedFrames=sum(stream["rejected"] for stream in streams),
            decodedPCM16Values=sum(len(packet["pcm"]) for stream in expected for packet in stream),
            comparison="Exact every 48kHz interleaved stereo PCM16 value, per-payload final range/bit count and VAD/LBRR flags for every accepted owned mono/stereo packet; exact every PCM16 value/range/bit/LBRR flag for selected-LBRR recovery and subsequent normal packets",
            result="passed")
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

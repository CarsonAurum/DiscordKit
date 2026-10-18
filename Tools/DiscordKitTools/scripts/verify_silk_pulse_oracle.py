#!/usr/bin/env python3
"""Offline compressed SILK pulse verification against unmodified libopus 1.6.1.

Supply the pinned source archive separately. No network or native codec enters
normal tests or consumer builds. This verifies pulse syntax, exact entropy bytes,
rate selection and accounting only; it does not verify full codec/decoded-PCM,
parameter decoding, gain/LPC/LTP orchestration, hybrid, PLC/FEC or devices.
"""

import argparse
import ast
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import random
import re
import tempfile

from verify_opus_range_oracle import (
    ARCHIVE_BYTE_COUNT, ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION,
    digest, extract_verified_archive, run,
)

OWNED_PATHS = ("Sources/DiscordVoiceCodecs/OpusRangeCoding.swift",
               "Sources/DiscordVoiceCodecs/SILKExcitation.swift",
               "Sources/DiscordVoiceCodecs/SILKPulseTables.swift",
               "Sources/DiscordVoiceCodecs/SILKPulseCoding.swift")
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/SILKPulseOracleFixtures.swift"
OFFICIAL_PATHS = ("silk/encode_pulses.c", "silk/decode_pulses.c", "silk/shell_coder.c",
                  "silk/code_signs.c", "silk/tables_pulses_per_block.c", "silk/tables_other.c",
                  "celt/entenc.c", "celt/entdec.c", "celt/entcode.c")
SAMPLE_COUNTS = (80, 120, 160, 240, 320)

# Original reference driver invokes complete unmodified official routines.
C_DRIVER = r'''
#include <stdio.h>
#include <string.h>
#include "main.h"
#include "entenc.h"
#include "entdec.h"
int main(void) {
    char kind; int signal,offset,count,storage,value;
    while(scanf(" %c %d %d %d %d",&kind,&signal,&offset,&count,&storage)==5) {
        if(signal<0||signal>2||offset<0||offset>1||storage<0||storage>1275||
           !(count==80||count==120||count==160||count==240||count==320)) return 2;
        unsigned char data[1275]={0}; opus_int16 decoded[336]={0}; ec_dec dec;
        if(kind=='E') {
            opus_int8 pulses[336]={0}; ec_enc enc,unused; ec_dec peek;
            for(int j=0;j<count;j++) {
                if(scanf("%d",&value)!=1||value < -127||value>127) return 3;
                pulses[j]=value;
            }
            ec_enc_init(&enc,data,1275); silk_encode_pulses(&enc,signal,offset,pulses,count);
            int bits=ec_tell(&enc),frac=ec_tell_frac(&enc); unsigned range=enc.rng;
            if(storage==0) storage=(bits+7)/8;
            ec_enc_shrink(&enc,storage); ec_enc_done(&enc); if(enc.error) return 4;
            ec_dec_init(&peek,data,storage);
            int rate=ec_dec_icdf(&peek,silk_rate_levels_iCDF[signal>>1],8);
            printf("{\"rate\":%d,\"range\":%u,\"bits\":%d,\"fractional\":%d,\"bytes\":[",rate,range,bits,frac);
            for(int j=0;j<storage;j++) printf("%s%d",j?",":"",data[j]);
            printf("],");
        } else if(kind=='D') {
            for(int j=0;j<storage;j++) {
                if(scanf("%d",&value)!=1||value<0||value>255) return 3;
                data[j]=value;
            }
            printf("{");
        } else return 2;
        ec_dec_init(&dec,data,storage); silk_decode_pulses(&dec,decoded,signal,offset,count);
        printf("\"decoded\":[");
        for(int j=0;j<(count+15)/16*16;j++) printf("%s%d",j?",":"",decoded[j]);
        printf("],\"decodeRange\":%u,\"decodeBits\":%d,\"decodeFractional\":%u}\n",dec.rng,ec_tell(&dec),ec_tell_frac(&dec));
    }
    return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable {
    let signal: Int; let offset: Int; let sampleCount: Int; let pulses: [Int16]?; let bytes: [UInt8]?
}
struct Output: Encodable {
    let rate: Int?; let range: UInt32?; let bits: Int?; let fractional: Int?; let bytes: [UInt8]?
    let decoded: [Int16]; let decodeRange: UInt32; let decodeBits: Int; let decodeFractional: Int
}
@main struct Driver {
    /// Runs bounded pulse cases; output omits optional encoder fields on decode-only cases.
    static func main() throws {
        while let line = readLine() {
            let input = try JSONDecoder().decode(Input.self, from: Data(line.utf8))
            let signal = SILKSignalType(rawValue: input.signal)!
            let offset = SILKQuantizationOffset(rawValue: input.offset)!
            var bytes = input.bytes
            var encoder: OpusRangeEncoder?
            var rate: Int?
            if let pulses = input.pulses {
                var working = try OpusRangeEncoder(frameByteCount: 1_275)
                rate = try SILKPulseCoding.encode(pulses, to: &working, signalType: signal, quantizationOffset: offset)
                let minimumBytes = (working.bitsUsed + 7) / 8
                working = try OpusRangeEncoder(frameByteCount: minimumBytes)
                try SILKPulseCoding.encode(pulses, to: &working, signalType: signal, quantizationOffset: offset)
                bytes = Array(try working.finalize())
                encoder = working
            }
            var decoder = try OpusRangeDecoder(frame: Data(bytes!))
            let frame = try SILKPulseCoding.decode(from: &decoder, sampleCount: input.sampleCount, signalType: signal, quantizationOffset: offset)
            let output = Output(rate: rate, range: encoder?.finalRange, bits: encoder?.bitsUsed,
                fractional: encoder?.fractionalBitsUsed, bytes: encoder == nil ? nil : bytes,
                decoded: frame.signedPulses + frame.discardedPadding, decodeRange: decoder.finalRange,
                decodeBits: decoder.bitsUsed, decodeFractional: decoder.fractionalBitsUsed)
            print(String(decoding: try JSONEncoder().encode(output), as: UTF8.self))
        }
    }
}
'''


def committed_fixtures(repository):
    """Read literal fixture records without executing Swift or production encoders."""
    source = (repository / FIXTURE_PATH).read_text()
    records = []
    for line in source.splitlines():
        match = re.fullmatch(r"\s*SILKPulseOracleFixture\((.*)\),", line)
        if match:
            fields = re.sub(r"\b([a-zA-Z]+):", r'"\1":', match.group(1))
            records.append(ast.literal_eval("{" + fields + "}"))
    if not records:
        raise RuntimeError("No committed SILK pulse fixtures found")
    return records


def fixture_inputs(fixtures):
    """Expand finite repeated pulse patterns into the fixture's exact frame length."""
    return [dict(signal=f["signal"], offset=f["offset"], sampleCount=f["sampleCount"],
                 pulses=[f["pattern"][i % len(f["pattern"])] for i in range(f["sampleCount"])])
            for f in fixtures]


def boundary_inputs():
    """Exercise all frame/context combinations with silence, sparse and large pulses."""
    result = []
    for count in SAMPLE_COUNTS:
        for signal in range(3):
            for offset in range(2):
                for magnitude in (0, 1, 8, 32, 127):
                    result.append(dict(signal=signal, offset=offset, sampleCount=count,
                                       pulses=[magnitude * (-1 if i % 3 == 0 else 1) if i % 4 == 0 else 0
                                               for i in range(count)]))
    return result


def mixed_inputs(count, seed):
    """Generate deterministic varied-density frames within the official encoder range."""
    rng = random.Random(seed)
    result = []
    for _ in range(count):
        samples = rng.choice(SAMPLE_COUNTS)
        magnitude = rng.randint(1, 127)
        density = rng.randint(1, 16)
        result.append(dict(signal=rng.randrange(3), offset=rng.randrange(2), sampleCount=samples,
                           pulses=[rng.randint(-magnitude, magnitude) if rng.randrange(16) < density else 0
                                   for _ in range(samples)]))
    return result


def extended_inputs():
    """Cover all LSB depths/signs beyond the reference encoder's int8 input API."""
    return [dict(signal=signal, offset=offset, sampleCount=80,
                 pulses=[sign * (8 << depth)] + [0] * 79)
            for signal in range(3) for offset in range(2)
            for depth in range(11) for sign in (-1, 1)]


def malformed_inputs(seed):
    """Bound decoder-only arbitrary-byte cases, retaining normative zero extension."""
    rng = random.Random(seed)
    return [dict(signal=signal, offset=offset, sampleCount=count,
                 bytes=[rng.randrange(256) for _ in range(length)])
            for signal in range(3) for offset in range(2)
            for count in SAMPLE_COUNTS for length in (0, 1, 2, 7, 64)]


def commands(inputs):
    """Serialize bounded encoder or decoder inputs for the original reference driver."""
    lines = []
    for item in inputs:
        encoding = "pulses" in item
        values = item["pulses"] if encoding else item["bytes"]
        lines.append(f"{'E' if encoding else 'D'} {item['signal']} {item['offset']} "
                     f"{item['sampleCount']} {0 if encoding else len(values)} " + " ".join(map(str, values)))
    return ("\n".join(lines) + "\n").encode()


def parse_outputs(data, count):
    """Require one JSON object per case, without silently accepting truncated results."""
    try:
        values = [json.loads(line) for line in data.decode().splitlines()]
    except (ValueError, UnicodeError) as error:
        raise RuntimeError("Invalid pulse oracle output") from error
    if len(values) != count or any(not isinstance(value, dict) for value in values):
        raise RuntimeError("Pulse oracle output count or shape mismatch")
    return values


def compare_results(inputs, expected, actual, seed):
    """Compare exact whole output objects with a bounded diagnostic at first mismatch."""
    if len(inputs) != len(expected) or len(inputs) != len(actual):
        raise RuntimeError("Pulse comparison case count mismatch")
    for index, (item, reference, owned) in enumerate(zip(inputs, expected, actual)):
        if reference != owned:
            raise RuntimeError(json.dumps(dict(case=index, seed=seed, input=item, expected=reference, actual=owned)))


def compare_fixtures(fixtures, outputs):
    """Require exact literal bytes/rate/range/accounting from independent reproduction."""
    if len(fixtures) != len(outputs):
        raise RuntimeError("Pulse fixture count mismatch")
    for fixture, output in zip(fixtures, outputs):
        expected = {key: fixture[key] for key in ("rate", "range", "bits", "fractional", "bytes")}
        actual = {key: output.get(key) for key in expected}
        if expected != actual:
            raise RuntimeError("Committed SILK pulse fixture mismatch")


def main():
    """Compile temporary references, compare bounded frames and write scoped evidence."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=67164278)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error("--cases must be 1...10000 and --seed nonnegative")
    repository = args.repository.resolve()
    fixtures = committed_fixtures(repository)
    fixed = fixture_inputs(fixtures)
    boundaries = boundary_inputs()
    inputs = fixed + boundaries + mixed_inputs(args.cases, args.seed)
    extended = extended_inputs()
    malformed = malformed_inputs(args.seed)
    with tempfile.TemporaryDirectory(prefix="discordkit-silk-pulses-") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        driver = directory / "oracle.c"
        driver.write_text(C_DRIVER)
        reference = directory / "official-oracle"
        run([args.cc, "-std=c99", "-O0", "-DOPUS_BUILD", "-DVAR_ARRAYS"]
            + ["-I" + str(upstream / path) for path in ("include", "celt", "silk")]
            + [str(driver)] + [str(upstream / path) for path in OFFICIAL_PATHS]
            + ["-lm", "-o", str(reference)])
        swift_driver = directory / "driver.swift"
        swift_driver.write_text(SWIFT_DRIVER)
        owned = directory / "owned-driver"
        run([args.swiftc, "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated"]
            + [str(repository / path) for path in OWNED_PATHS] + [str(swift_driver), "-o", str(owned)])
        expected = parse_outputs(run([str(reference)], commands(inputs)), len(inputs))
        actual = parse_outputs(run([str(owned)], ("\n".join(json.dumps(i) for i in inputs) + "\n").encode()), len(inputs))
        compare_results(inputs, expected, actual, args.seed)
        compare_fixtures(fixtures, expected[:len(fixed)])
        extended_outputs = parse_outputs(run([str(owned)], ("\n".join(json.dumps(i) for i in extended) + "\n").encode()), len(extended))
        decode_inputs = [dict(signal=i["signal"], offset=i["offset"], sampleCount=i["sampleCount"], bytes=o["bytes"])
                         for i, o in zip(extended, extended_outputs)] + malformed
        decoded_expected = parse_outputs(run([str(reference)], commands(decode_inputs)), len(decode_inputs))
        decoded_actual = parse_outputs(run([str(owned)], ("\n".join(json.dumps(i) for i in decode_inputs) + "\n").encode()), len(decode_inputs))
        compare_results(decode_inputs, decoded_expected, decoded_actual, args.seed)
        for item, result in zip(extended, decoded_actual):
            if result["decoded"] != item["pulses"]:
                raise RuntimeError("Extended SILK pulse reconstruction mismatch")
        report = dict(
            verifiedOn=datetime.now(timezone.utc).date().isoformat(),
            scope="SILK compressed pulse syntax only; no complete frame parameters, PCM codec conformance, hybrid, PLC/FEC, devices or realtime qualification",
            officialVersion=VERSION, officialReleaseURL=RELEASE_URL, sourceArchiveURL=SOURCE_URL,
            sourceArchiveSHA256=ARCHIVE_SHA256, sourceArchiveByteCount=ARCHIVE_BYTE_COUNT,
            sourceLicense="Unmodified upstream COPYING retained during temporary compilation; normative table adaptation retains source notice",
            sourceLicenseSHA256=digest(upstream / "COPYING"),
            officialSourceSHA256={path: digest(upstream / path) for path in OFFICIAL_PATHS},
            ownedSwiftSHA256={path: digest(repository / path) for path in OWNED_PATHS},
            fixtureSHA256={FIXTURE_PATH: digest(repository / FIXTURE_PATH)},
            verifierSHA256=digest(Path(__file__)), pythonVersion=platform.python_version(),
            compiler=run([args.cc, "--version"]).decode().splitlines()[0],
            swiftCompiler=run([args.swiftc, "--version"]).decode().splitlines()[0],
            host=platform.platform(), seed=args.seed, fixtureCases=len(fixed), boundaryEncodeCases=len(boundaries),
            randomEncodeCases=args.cases, extendedDecodeCases=len(extended), arbitraryDecodeCases=len(malformed),
            totalCases=len(inputs) + len(decode_inputs),
            comparison="Exact rate, minimal entropy bytes, range, whole/eighth-bit accounting, signed pulses including padding; extended int16 inputs compare unmodified official decoder only",
            result="passed")
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/verify_celt_band_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Opt-in, offline CELT band quantizer verification against unmodified libopus 1.6.1.

The separately supplied official archive is size/SHA256/path-validated by the
shared entropy verifier. Nothing is downloaded, vendored or linked into products.
This compares scalar float pulse search, all spreading levels, collapse masks,
normalized coefficients, entropy bytes, final range and decode reconstruction.
It does not establish complete Opus, band allocation, recursive splitting,
SILK/hybrid, PLC/FEC, decoded-PCM conformance or realtime/device qualification.
"""

from publication import swift_header

import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import random
import struct
import tempfile

from verify_opus_range_oracle import (
    ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION, digest,
    extract_verified_archive, run,
)
from verify_celt_pulse_oracle import ORDINARY_DIMENSIONS, ORDINARY_MAX_PULSES, parse_outputs

OWNED_PATHS = ("Sources/DiscordVoiceCodecs/OpusRangeCoding.swift",
               "Sources/DiscordVoiceCodecs/CELTPulseCodebook.swift",
               "Sources/DiscordVoiceCodecs/CELTBandQuantizer.swift")
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/CELTBandOracleFixtures.swift"

C_DRIVER = r'''
#define CELT_C
#include <stdio.h>
#include "entenc.c"
#include "entdec.c"
#include "entcode.c"
#include "cwrs.c"
#include "vq.c"
int main(void) {
    int n,k,b,s;
    float gain;
    while(scanf("%d %d %d %d %f", &n,&k,&b,&s,&gain)==5) {
        if(n<2||n>176||k<1||k>128||b<1||n%b||s<0||s>3) return 2;
        float x[176], decoded[176];
        int pulses[176];
        unsigned char bytes[8]={0};
        for(int j=0;j<n;j++) if(scanf("%f",&x[j])!=1) return 2;
        ec_enc encoder;
        ec_dec decoder, pulse_decoder;
        ec_enc_init(&encoder,bytes,8);
        unsigned mask=alg_quant(x,n,k,s,b,&encoder,gain,1,0);
        ec_enc_done(&encoder);
        if(encoder.error) return 3;
        ec_dec_init(&decoder,bytes,8);
        unsigned decoded_mask=alg_unquant(decoded,n,k,s,b,&decoder,gain);
        ec_dec_init(&pulse_decoder,bytes,8);
        decode_pulses(pulses,n,k,&pulse_decoder);
        if(decoder.error||pulse_decoder.error) return 4;
        printf("{\"mask\":%u,\"decodedMask\":%u,\"range\":%u,\"decodedRange\":%u,\"pulses\":[",mask,decoded_mask,encoder.rng,decoder.rng);
        for(int j=0;j<n;j++) printf("%s%d",j?",":"",pulses[j]);
        printf("],\"coefficients\":[");
        for(int j=0;j<n;j++) printf("%s%.9g",j?",":"",x[j]);
        printf("],\"decoded\":[");
        for(int j=0;j<n;j++) printf("%s%.9g",j?",":"",decoded[j]);
        printf("],\"bytes\":[");
        for(int j=0;j<8;j++) printf("%s%u",j?",":"",bytes[j]);
        puts("]}");
    }
    return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable { let n:Int; let k:Int; let blocks:Int; let spread:Int; let gain:Float; let x:[Float] }
struct Output: Encodable {
    let mask:UInt8; let decodedMask:UInt8; let range:UInt32; let decodedRange:UInt32
    let pulses:[Int]; let coefficients:[Float]; let decoded:[Float]; let bytes:[UInt8]
}
@main struct Driver {
    /// Reads bounded development contexts, returning owned band/entropy outputs or a JSON error.
    /// Input/output is stdin/stdout only; errors propagate as mismatches to the Python verifier.
    static func main() throws {
        while let line=readLine() {
            do {
                let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
                let q=try CELTBandQuantizer(dimensions:input.n,pulseCount:input.k,
                    shortBlockCount:input.blocks,spreading:CELTSpreading(rawValue:input.spread)!)
                var encoder=try OpusRangeEncoder(frameByteCount:8)
                let band=try q.encode(input.x,gain:input.gain,into:&encoder)
                let bytes=try encoder.finalize()
                var decoder=try OpusRangeDecoder(frame:bytes)
                let decoded=try q.decode(from:&decoder,gain:input.gain)
                let output=Output(mask:band.collapseMask,decodedMask:decoded.collapseMask,
                    range:encoder.finalRange,decodedRange:decoder.finalRange,pulses:band.pulses,
                    coefficients:band.coefficients,decoded:decoded.coefficients,bytes:Array(bytes))
                print(String(data:try JSONEncoder().encode(output),encoding:.utf8)!)
            } catch { print("{\"error\":\"\(error)\"}") }
        }
    }
}
'''


def float32(value):
    """Round once to the scalar float representation accepted by both independent drivers."""
    return struct.unpack("f", struct.pack("f", value))[0]


def make_case(n, k, blocks, spread, values, gain=1):
    """Normalize a finite nonzero band to unit norm; zero bands preserve fallback coverage."""
    norm = math.sqrt(sum(x*x for x in values))
    return {"n": n, "k": k, "blocks": blocks, "spread": spread,
            "gain": float32(gain), "x": [float32(x/norm if norm else 0) for x in values]}


def fixed_cases():
    """Exercise fallback, signs, projection, greedy ties, secondary rotation and short blocks."""
    cases = []
    for spread in range(4):
        cases.append(make_case(8, 1, 1, spread, [1, -2, 3, -4, 5, -6, 7, -8]))
        cases.append(make_case(16, 3, 4, spread, [(-1)**j * (j+1) for j in range(16)], 0.75))
    for n, k, b in [(2, 128, 1), (3, 3, 1), (4, 4, 2), (8, 12, 8), (48, 6, 2), (176, 4, 8)]:
        cases.append(make_case(n, k, b, 2, [0]*n))
    cases.append(make_case(4, 3, 1, 0, [1]*4, 0))
    cases.append(make_case(8, 5, 2, 3, [(-1)**j for j in range(8)], 64))
    return cases


def random_cases(count, seed):
    """Produce reproducible admitted ordinary bands without relying on the owned codebook."""
    rng = random.Random(seed)
    cases = []
    for _ in range(count):
        index = rng.randrange(len(ORDINARY_DIMENSIONS))
        n, maximum = ORDINARY_DIMENSIONS[index], ORDINARY_MAX_PULSES[index]
        blocks = rng.choice([b for b in [1, 2, 4, 8] if n % b == 0])
        cases.append(make_case(n, rng.randint(1, maximum), blocks, rng.randrange(4),
                               [rng.uniform(-1, 1) for _ in range(n)], rng.choice([0, 0.25, 1, 4, 64])))
    return cases


def compare_results(inputs, expected, actual):
    """Require exact pulses/bytes/range/masks and bounded relative float reconstruction error."""
    if not len(inputs) == len(expected) == len(actual):
        raise RuntimeError("Unexpected comparison case count")
    for index, (context, reference, owned) in enumerate(zip(inputs, expected, actual)):
        for key in ["pulses", "bytes", "mask", "decodedMask", "range", "decodedRange"]:
            if key not in reference or reference[key] != owned.get(key):
                raise RuntimeError(json.dumps({"case": index, "input": context, "key": key,
                                               "expected": reference, "actual": owned}))
        if (len(reference["pulses"]) != context["n"]
                or sum(map(abs, reference["pulses"])) != context["k"]
                or reference["range"] != reference["decodedRange"]
                or reference["mask"] != reference["decodedMask"]):
            raise RuntimeError("Invalid independent pulse/entropy invariant")
        for key in ["coefficients", "decoded"]:
            left, right = reference.get(key, []), owned.get(key, [])
            if (len(left) != context["n"] or len(right) != len(left)
                    or any(not math.isfinite(a) or not math.isfinite(b)
                           or abs(a-b) > 2e-6 * max(1, context["gain"]) for a, b in zip(left, right))):
                raise RuntimeError(json.dumps({"case": index, "key": key, "expected": left, "actual": right}))


def fixture_records(path):
    """Read checked-in independent fixtures from a Swift raw JSON literal without executing it."""
    text = path.read_text()
    start, end = text.index('#"""') + 4, text.index('"""#')
    records = json.loads(text[start:end])
    if not isinstance(records, list) or len(records) != len(fixed_cases()):
        raise ValueError("Unexpected committed band fixture count")
    return records


def main():
    """Build isolated drivers and compare fixed/seeded cases; optionally emit fixtures/report."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-archive", required=True, type=Path)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=67164343)
    parser.add_argument("--write-fixtures", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error("--cases must be 1...10000; --seed must be nonnegative")
    repository = args.repository.resolve()
    fixed = fixed_cases()
    inputs = fixed + random_cases(args.cases, args.seed)
    with tempfile.TemporaryDirectory(prefix="discordkit-celt-band-") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        c_driver, swift_driver = directory / "oracle.c", directory / "driver.swift"
        c_driver.write_text(C_DRIVER)
        swift_driver.write_text(SWIFT_DRIVER)
        reference, owned = directory / "oracle", directory / "owned"
        run(["cc", "-O2", "-ffp-contract=off", "-DOPUS_BUILD", "-DVAR_ARRAYS", "-Wl,-dead_strip",
             "-I"+str(upstream/"include"), "-I"+str(upstream/"celt"), "-I"+str(upstream/"silk"),
             str(c_driver), "-lm", "-o", str(reference)])
        run(["swiftc", "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated"]
            + [str(repository / path) for path in OWNED_PATHS] + [str(swift_driver), "-o", str(owned)])
        commands = "\n".join(f'{c["n"]} {c["k"]} {c["blocks"]} {c["spread"]} {c["gain"]} '
                              + " ".join(map(str, c["x"])) for c in inputs).encode()
        expected = parse_outputs(run([str(reference)], commands), len(inputs), "Official band driver")
        actual = parse_outputs(run([str(owned)], "\n".join(map(json.dumps, inputs)).encode()), len(inputs), "Owned band driver")
        compare_results(inputs, expected, actual)
        records = [{"input": c, "output": e} for c, e in zip(fixed, expected)]
        fixture = repository / FIXTURE_PATH
        if args.write_fixtures:
            fixture.write_text(swift_header(FIXTURE_PATH) + '/// Independent libopus 1.6.1 band-search fixtures; generated only by the opt-in verifier.\n'
                               '/// No native codec is linked or executed by normal Swift tests.\n'
                               'enum CELTBandOracleFixtures {\n    static let json = #"""\n'
                               + json.dumps(records, separators=(",", ":")) + '\n"""#\n}\n')
        if fixture_records(fixture) != records:
            raise RuntimeError("Committed fixtures differ from independent oracle")
        report = {"verifiedOn": datetime.now(timezone.utc).date().isoformat(),
                  "scope": "CELT single-band pulse search/spreading/entropy only; no full codec or decoded-PCM conformance",
                  "officialVersion": VERSION, "officialReleaseURL": RELEASE_URL,
                  "sourceArchiveURL": SOURCE_URL, "sourceArchiveSHA256": ARCHIVE_SHA256,
                  "seed": args.seed, "randomCases": args.cases, "fixedCases": len(fixed), "comparedCases": len(inputs),
                  "coefficientAbsoluteTolerancePerGain": 2e-6,
                  "ownedSourceSHA256": {path: digest(repository/path) for path in OWNED_PATHS},
                  "fixtureSHA256": digest(fixture),
                  "oracleSourceSHA256": {"celt/"+name: digest(upstream/"celt"/name)
                                         for name in ["vq.c", "cwrs.c", "entcode.c", "entenc.c", "entdec.c"]},
                  "ccVersion": run(["cc", "--version"]).decode().splitlines()[0],
                  "swiftVersion": run(["swiftc", "--version"]).decode().strip(),
                  "verifierSHA256": digest(Path(__file__)),
                  "compared": ["signed pulses", "spreading levels 0...3", "short blocks 1/2/4/8",
                               "collapse masks", "entropy bytes", "final arithmetic ranges", "spectral reconstruction"]}
        if args.report:
            args.report.write_text(json.dumps(report, indent=2, sort_keys=True)+"\n")
        print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

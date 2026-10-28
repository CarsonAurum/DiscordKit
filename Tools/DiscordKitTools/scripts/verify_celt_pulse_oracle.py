#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/verify_celt_pulse_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Opt-in offline CELT integer-pulse differential verification against libopus 1.6.1.

Supply the official source archive separately, then run this script with
--source-archive /path/to/opus-1.6.1.tar.gz --cases 2000 --report result.json.
No files are downloaded. The shared entropy verifier checks the exact release
size/SHA256 and rejects unsafe archive paths and special members before extracting
temporary unmodified upstream sources, retaining their COPYING notice. No native
implementation, archive, dependency or executable enters a consumer product.

The original development drivers compare U/V counts, signed pulse enumeration,
inverse ranks, encoded entropy bytes and decoded integer vectors. They exercise
the forty committed fixtures, ordinary CELT band/pulse boundaries and seeded
admitted 32-bit codebooks. Only two owned Swift files are compiled, without a
package build or dependency resolution. Requires Python 3.9+, cc and Swift 6.4+.
Normal test discovery imports this module without compilers, an archive or I/O.
This is integer/entropy evidence only: no decoded PCM, CELT band decoder, SILK,
hybrid, PLC/FEC, complete Opus codec conformance or Discord/device qualification.
"""

import argparse
import ast
from datetime import datetime, timezone
import json
from math import comb
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
               "Sources/DiscordVoiceCodecs/CELTPulseCodebook.swift")
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/CELTPulseCodebookTests.swift"
# Exact non-Custom pn[] dimension list in official celt/tests/test_unit_cwrs32.c.
ORDINARY_DIMENSIONS = (2, 3, 4, 6, 8, 9, 11, 12, 16, 18, 22, 24, 32, 36, 44, 48,
                       64, 72, 88, 96, 144, 176)
# Matching pkmax[] values; some 32-bit codebooks above these ordinary allocations
# also fit the official table and remain eligible for the random primitive cases.
ORDINARY_MAX_PULSES = (128, 128, 128, 88, 36, 26, 18, 16, 12, 11, 9, 9, 7, 7,
                       6, 6, 5, 5, 5, 5, 4, 4)
UINT32_MAX = 2**32 - 1

# Original development driver. Included files remain the unmodified verified
# upstream source; inclusion exposes its private integer enumeration routines.
C_DRIVER = r'''
#define CELT_C
#include <stdio.h>
#include "entenc.c"
#include "entdec.c"
#include "entcode.c"
#include "cwrs.c"
int main(void) {
    int n, k;
    unsigned index;
    while (scanf("%d %d %u", &n, &k, &index) == 3) {
        if (n < 2 || n > 176 || k < 1 || k > 128) return 2;
        unsigned count = CELT_PVQ_V(n, k);
        if (index >= count) return 2;
        int vector[176] = {0}, decoded[176] = {0};
        unsigned char bytes[8] = {0};
        ec_enc encoder;
        ec_dec decoder;
        cwrsi(n, k, index, vector);
        unsigned rank = icwrs(n, vector);
        ec_enc_init(&encoder, bytes, 8);
        encode_pulses(vector, n, k, &encoder);
        ec_enc_done(&encoder);
        if (encoder.error) return 3;
        ec_dec_init(&decoder, bytes, 8);
        decode_pulses(decoded, n, k, &decoder);
        if (decoder.error) return 4;
        printf("{\"count\":%u,\"index\":%u,\"vector\":[", count, rank);
        for (int j = 0; j < n; j++) printf("%s%d", j ? "," : "", vector[j]);
        printf("],\"decoded\":[");
        for (int j = 0; j < n; j++) printf("%s%d", j ? "," : "", decoded[j]);
        printf("],\"bytes\":[");
        for (int j = 0; j < 8; j++) printf("%s%u", j ? "," : "", bytes[j]);
        printf("]}\n");
    }
    return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable { let n: Int; let k: Int; let index: UInt32 }
struct Output: Encodable {
    let count: UInt32; let index: UInt32; let vector: [Int]; let decoded: [Int]; let bytes: [UInt8]
}
@main struct Driver {
    /// Reads independent integer codebook requests and reports exact owned results.
    /// Errors become JSON mismatches; serialization failures propagate to the caller.
    static func main() throws {
        while let line = readLine() {
            do {
                let input = try JSONDecoder().decode(Input.self, from: Data(line.utf8))
                let book = try CELTPulseCodebook(dimensions: input.n, pulseCount: input.k)
                let vector = try book.vector(at: input.index)
                let index = try book.index(of: vector)
                var encoder = try OpusRangeEncoder(frameByteCount: 8)
                try book.encode(vector, into: &encoder)
                let bytes = try encoder.finalize()
                var decoder = try OpusRangeDecoder(frame: bytes)
                let decoded = try book.decode(from: &decoder)
                let output = Output(count: book.codewordCount, index: index, vector: vector,
                    decoded: decoded, bytes: Array(bytes))
                print(String(data: try JSONEncoder().encode(output), encoding: .utf8)!)
            } catch { print("{\"error\":\"\(error)\"}") }
        }
    }
}
'''


def codeword_count(dimensions, pulses):
    """Compute V(N,K) independently from its closed binomial sum, with exact Python integers."""
    if dimensions < 1 or pulses < 0:
        raise ValueError("Dimensions must be positive and pulses nonnegative")
    if pulses == 0:
        return 1
    return sum(2**used * comb(dimensions, used) * comb(pulses - 1, used - 1)
               for used in range(1, min(dimensions, pulses) + 1))


def admitted_codebooks():
    """List standard-mode dimensions/pulses fitting the official 32-bit enumeration table."""
    return [(n, k) for n in ORDINARY_DIMENSIONS for k in range(1, 129)
            if codeword_count(n, k) <= UINT32_MAX]


def indexed_cases(pairs):
    """Build five fixed boundary/interior indices for each admitted nonzero codebook pair."""
    cases = []
    for n, k in pairs:
        count = codeword_count(n, k)
        cases.extend({"n": n, "k": k, "index": index}
                     for index in [0, 1, count // 3, count // 2, count - 1])
    return cases


def fixture_cases():
    """Reproduce the exact forty independently generated committed Swift fixture contexts."""
    return indexed_cases([(2, 2), (3, 3), (4, 4), (6, 8), (8, 12), (16, 12), (48, 6), (176, 4)])


def boundary_cases():
    """Cover K1 and official pkmax for every ordinary pn dimension, including N176/K128."""
    pairs = [(n, k) for n, maximum in zip(ORDINARY_DIMENSIONS, ORDINARY_MAX_PULSES)
             for k in [1, maximum]]
    return indexed_cases(pairs)


def mixed_cases(count, seed):
    """Generate reproducible admitted contexts without changing Python's global random state."""
    generator = random.Random(seed)
    admitted = admitted_codebooks()
    cases = []
    for _ in range(count):
        n, k = generator.choice(admitted)
        cases.append({"n": n, "k": k, "index": generator.randrange(codeword_count(n, k))})
    return cases


def committed_fixtures(path):
    """Read only the explicit sparse integer fixtures from their Swift test, without execution."""
    source = path.read_text()
    _, separator, section = source.partition("@Test func officialCodewordFixtures() throws {")
    if not separator:
        raise ValueError("Missing committed official pulse fixture test")
    section = section.split("\n        ]", 1)[0]
    records = []
    pattern = r"^\s*\((\d+), (\d+), (\d+), (\d+), (\[.*\])\),?$"
    for n, k, count, index, sparse in re.findall(pattern, section, re.MULTILINE):
        vector = [0] * int(n)
        seen = set()
        for position, value in ast.literal_eval(sparse):
            if position in seen or not 0 <= position < int(n):
                raise ValueError("Invalid sparse fixture position")
            seen.add(position)
            vector[position] = value
        records.append({"n": int(n), "k": int(k), "count": int(count),
                        "index": int(index), "vector": vector})
    if len(records) != 40:
        raise ValueError("Expected exactly forty committed official pulse fixtures")
    return records


def parse_outputs(data, count, label):
    """Require one valid JSON result for every submitted context; omitted/extra lines fail."""
    lines = data.decode().splitlines()
    if len(lines) != count:
        raise RuntimeError(f"{label} returned an unexpected number of cases")
    results = [json.loads(line) for line in lines]
    if any(not isinstance(result, dict) for result in results):
        raise RuntimeError(f"{label} returned a non-object case")
    return results


def compare_results(inputs, expected, actual, seed):
    """Enforce every claimed comparison and independent count/norm/rank invariants."""
    if len(inputs) != len(expected) or len(inputs) != len(actual):
        raise RuntimeError("Unexpected number of comparison cases")
    for case, (context, reference, owned) in enumerate(zip(inputs, expected, actual)):
        vector = reference.get("vector", [])
        if (reference != owned or reference.get("count") != codeword_count(context["n"], context["k"])
                or reference.get("index") != context["index"] or len(vector) != context["n"]
                or sum(map(abs, vector)) != context["k"] or reference.get("decoded") != vector):
            raise RuntimeError(json.dumps({"mismatchCase": case, "seed": seed, "input": context,
                                          "expected": reference, "actual": owned}))


def compare_fixtures(fixtures, contexts, results):
    """Require the committed forty count/vector literals to agree with the official driver."""
    if len(fixtures) != len(contexts) or len(results) != len(contexts):
        raise RuntimeError("Committed fixture count mismatch")
    for fixture, context, result in zip(fixtures, contexts, results):
        if (any(fixture[key] != context[key] for key in ["n", "k", "index"])
                or fixture["count"] != result["count"] or fixture["vector"] != result["vector"]):
            raise RuntimeError(json.dumps({"fixtureMismatch": fixture, "expected": result}))


def main():
    """Compile isolated references, compare deterministic cases and optionally write a scoped report."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=67164342)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error("--cases must be 1...10000 and --seed must be nonnegative")
    repository = args.repository.resolve()
    fixtures = committed_fixtures(repository / FIXTURE_PATH)
    fixed, boundaries = fixture_cases(), boundary_cases()
    inputs = fixed + boundaries + mixed_cases(args.cases, args.seed)
    with tempfile.TemporaryDirectory(prefix="discordkit-celt-pulse-") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        driver = directory / "oracle.c"
        driver.write_text(C_DRIVER)
        reference = directory / "official-oracle"
        run([args.cc, "-O2", "-DOPUS_BUILD", "-DVAR_ARRAYS", "-I" + str(upstream / "include"),
             "-I" + str(upstream / "celt"), str(driver), "-lm", "-o", str(reference)])
        swift_driver = directory / "driver.swift"
        swift_driver.write_text(SWIFT_DRIVER)
        owned = directory / "owned-driver"
        run([args.swiftc, "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated"]
            + [str(repository / path) for path in OWNED_PATHS] + [str(swift_driver), "-o", str(owned)])
        commands = "\n".join(f'{value["n"]} {value["k"]} {value["index"]}' for value in inputs).encode()
        expected = parse_outputs(run([str(reference)], commands), len(inputs), "Official driver")
        encoded = "\n".join(json.dumps(value) for value in inputs).encode()
        actual = parse_outputs(run([str(owned)], encoded), len(inputs), "Owned driver")
        compare_results(inputs, expected, actual, args.seed)
        compare_fixtures(fixtures, fixed, expected[:len(fixed)])
        sources = [upstream / "celt" / name for name in ["cwrs.c", "entenc.c", "entdec.c", "entcode.c"]]
        report = {
            "verifiedOn": datetime.now(timezone.utc).date().isoformat(),
            "scope": "CELT integer pulse/entropy primitives only; no decoded PCM, CELT band decoder, SILK/hybrid, PLC/FEC or complete codec conformance",
            "officialVersion": VERSION, "officialReleaseURL": RELEASE_URL, "sourceArchiveURL": SOURCE_URL,
            "sourceArchiveSHA256": ARCHIVE_SHA256, "sourceArchiveByteCount": ARCHIVE_BYTE_COUNT,
            "sourceLicense": "Unmodified upstream COPYING retained during temporary reference compilation",
            "sourceLicenseSHA256": digest(upstream / "COPYING"),
            "officialSourceSHA256": {str(path.relative_to(upstream)): digest(path) for path in sources},
            "ownedSwiftSHA256": {path: digest(repository / path) for path in OWNED_PATHS},
            "swiftFixtureSHA256": digest(repository / FIXTURE_PATH), "swiftFixturePath": FIXTURE_PATH,
            "fixtureCount": len(fixed), "boundaryCases": len(boundaries), "stressCases": args.cases,
            "comparedCases": len(inputs), "seed": args.seed, "generator": "Python random.Random MT19937",
            "ordinaryDimensions": list(ORDINARY_DIMENSIONS), "pulseCountBounds": [1, 128],
            "ordinaryMaximumPulseCounts": list(ORDINARY_MAX_PULSES),
            "pythonVersion": platform.python_version(), "pythonImplementation": platform.python_implementation(),
            "compared": ["independent binomial V(N,K) counts", "official signed pulse vectors",
                         "inverse integer ranks", "final 8-byte entropy frames", "decoded integer vectors",
                         "forty committed Swift count/vector fixtures"],
            "ccVersion": run([args.cc, "--version"]).decode().splitlines()[0],
            "swiftVersion": run([args.swiftc, "--version"]).decode().splitlines()[0],
        }
        if args.report:
            args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

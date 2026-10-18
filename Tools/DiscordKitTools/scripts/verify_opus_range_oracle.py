#!/usr/bin/env python3
"""Opt-in, offline comparison of owned entropy coding with official libopus 1.6.1.

Obtain the source archive separately from the release linked below, then run:

    python3 Tools/DiscordKitTools/scripts/verify_opus_range_oracle.py \
        --source-archive /path/to/opus-1.6.1.tar.gz --cases 2000 --seed 67168251

This script never downloads files. It verifies the archive's published SHA256,
extracts into temporary storage, compiles unmodified official entropy sources and
the repository's owned Swift implementation, reproduces committed compact fixtures,
and compares deterministic mixed streams at their minimum conservative frame size.
The optional --write-fixtures regenerates only OpusRangeOracleFixtures.swift;
--report writes a machine-readable result. The C and Swift programs below are
original development drivers, not vendored libopus implementation code. The
archive's COPYING remains beside the unmodified official sources while compiled;
no external implementation or object enters a product or this repository.

Requires Python 3.9+, a C compiler and Swift 6.4+. It is deliberately named without
a test_ prefix: ordinary Python unit-test discovery needs no network or compilers.
This proves entropy-primitive agreement only. It does not decode PCM or establish
SILK/CELT/hybrid, PLC/FEC, complete Opus conformance or Discord voice readiness.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import random
import subprocess
import tarfile
import tempfile


VERSION = "1.6.1"
SOURCE_URL = "https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz"
RELEASE_URL = "https://opus-codec.org/release/stable/2026/01/14/libopus-1_6_1.html"
ARCHIVE_SHA256 = "6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"
ARCHIVE_BYTE_COUNT = 10_472_813
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/OpusRangeOracleFixtures.swift"
OWNED_PATH = "Sources/DiscordVoiceCodecs/OpusRangeCoding.swift"

# Original minimal driver; all entropy implementation is linked from verified,
# unmodified upstream files in temporary storage, retaining their COPYING notice.
C_DRIVER = r'''
#include <stdio.h>
#include <stdlib.h>
#include "entenc.h"
#include "entcode.h"
int main(int argc, char **argv) {
    unsigned char bytes[1275] = {0};
    ec_enc encoder;
    unsigned a, b, c;
    char type;
    if (argc != 2) return 2;
    int size = atoi(argv[1]);
    if (size < 0 || size > 1275) return 2;
    ec_enc_init(&encoder, bytes, size);
    printf("{\"states\":[[%u,%d,%u]", encoder.rng,
        ec_tell(&encoder), ec_tell_frac(&encoder));
    while (scanf(" %c %u %u %u", &type, &a, &b, &c) == 4) {
        switch (type) {
            case 'S': ec_encode(&encoder, a, b, c); break;
            case 'B': ec_enc_bit_logp(&encoder, a, b); break;
            case 'U': ec_enc_uint(&encoder, a, b); break;
            case 'R': if (b) ec_enc_bits(&encoder, a, b); break;
            default: return 2;
        }
        printf(",[%u,%d,%u]", encoder.rng,
            ec_tell(&encoder), ec_tell_frac(&encoder));
    }
    ec_enc_done(&encoder);
    printf("],\"error\":%d,\"bytes\":[", encoder.error);
    for (int i = 0; i < size; i++) printf("%s%u", i ? "," : "", bytes[i]);
    printf("]}\n");
    return encoder.error != 0;
}
'''

# Original standalone consumer of the owned public APIs, with no package build,
# native codec linkage or dependency resolution. Each line is an independent stream.
SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable { let size: Int; let ops: [[UInt32]] }
struct Output: Encodable { let bytes: [UInt8]; let states: [[UInt32]]; let decoded: [UInt32] }
@main struct Driver {
    /// Reads independent JSON operation streams, compares semantic decoding through the
    /// public owned APIs, and emits exact bytes/accounting without importing native code.
    /// Throws only for stdout serialization; individual stream failures become JSON errors.
    static func main() throws {
        while let line = readLine() {
            do {
                let input = try JSONDecoder().decode(Input.self, from: Data(line.utf8))
                var encoder = try OpusRangeEncoder(frameByteCount: input.size)
                var states: [[UInt32]] = [[encoder.finalRange, UInt32(encoder.bitsUsed), UInt32(encoder.fractionalBitsUsed)]]
                for op in input.ops {
                    switch op[0] {
                    case 0: try encoder.encodeBit(op[1] != 0, logProbability: Int(op[2]))
                    case 1: try encoder.encodeUniform(op[1], total: op[2])
                    case 2: try encoder.encodeRawBits(op[1], count: Int(op[2]))
                    default: try encoder.encodeSymbol(Int(op[1]), model: OpusProbabilityModel(frequencies: Array(op.dropFirst(3))))
                    }
                    states.append([encoder.finalRange, UInt32(encoder.bitsUsed), UInt32(encoder.fractionalBitsUsed)])
                }
                let bytes = try encoder.finalize()
                var decoder = try OpusRangeDecoder(frame: bytes)
                var decoded: [UInt32] = []
                for op in input.ops {
                    let value: UInt32
                    switch op[0] {
                    case 0: value = try decoder.decodeBit(logProbability: Int(op[2])) ? 1 : 0
                    case 1: value = try decoder.decodeUniform(total: op[2])
                    case 2: value = try decoder.decodeRawBits(count: Int(op[2]))
                    default: value = UInt32(try decoder.decodeSymbol(model: OpusProbabilityModel(frequencies: Array(op.dropFirst(3)))))
                    }
                    decoded.append(value)
                }
                print(String(data: try JSONEncoder().encode(Output(bytes: Array(bytes), states: states, decoded: decoded)), encoding: .utf8)!)
            } catch { print("{\"error\":\"\(error)\"}") }
        }
    }
}
'''


def run(command, input_bytes=None):
    """Run one compiler/driver without a shell and report useful diagnostics on failure."""
    result = subprocess.run(command, input=input_bytes, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command}\n"
                           f"{result.stdout.decode(errors='replace')}"
                           f"{result.stderr.decode(errors='replace')}")
    return result.stdout


def digest(path):
    """Hash a local file in bounded chunks without retaining the source archive in memory."""
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def extract_verified_archive(archive, directory):
    """Require the exact published archive and reject unsafe paths/links before extraction."""
    if archive.stat().st_size != ARCHIVE_BYTE_COUNT or digest(archive) != ARCHIVE_SHA256:
        raise ValueError("Archive does not match the official libopus 1.6.1 byte count and SHA256")
    with tarfile.open(archive, "r:gz") as source:
        members = source.getmembers()
        for member in members:
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != f"opus-{VERSION}":
                raise ValueError(f"Unsafe archive member: {member.name}")
            if not (member.isdir() or member.isfile()):
                raise ValueError(f"Unsupported archive member: {member.name}")
        for member in members:
            destination = directory / member.name
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as incoming, destination.open("wb") as output:
                    while True:
                        chunk = incoming.read(1024 * 1024)
                        if not chunk:
                            break
                        output.write(chunk)
    return directory / f"opus-{VERSION}"


def operation_commands(operations):
    """Convert public-operation records into exact official arithmetic calls, retaining totals."""
    commands = []
    for op in operations:
        kind, value, parameter = op[:3]
        if kind == 3:
            frequencies = op[3:]
            commands.append(f"S {sum(frequencies[:value])} {sum(frequencies[:value + 1])} {sum(frequencies)}")
        else:
            commands.append(f"{['B', 'U', 'R'][kind]} {value} {parameter} 0")
    return "\n".join(commands).encode()


def oracle_result(executable, size, operations):
    """Encode one bounded stream with the verified official entropy implementation."""
    return json.loads(run([str(executable), str(size)], operation_commands(operations)))


def fixture_cases():
    """Return the six fixed independent-oracle contexts retained by Swift unit tests."""
    return [
        ("empty", 0, []),
        ("intervalsAndZeroFrequencies", 8, [[3, 0, 0, 2, 0, 3, 5, 1], [3, 2, 0, 2, 0, 3, 5, 1],
            [3, 4, 0, 2, 0, 3, 5, 1], [3, 3, 0, 2, 0, 3, 5, 1], [3, 0, 0, 65534, 1],
            [3, 1, 0, 65534, 1], [3, 1, 0, 0, 1, 0]]),
        ("sharedFinalByte", 1, [[0, 1, 1], [2, 43, 6]]),
        ("uniformExtremes", 24, [[1, 0, 2], [1, 2, 3], [1, 254, 255], [1, 1, 256],
            [1, 256, 257], [1, 65534, 65535], [1, 4294967294, 4294967295], [2, 28036591, 25]]),
        ("mixedContexts", 32, [[3, 0, 0, 56, 100, 0, 100], [0, 0, 15], [2, 17, 5],
            [3, 3, 0, 56, 100, 0, 100], [1, 999, 1000], [0, 1, 15], [3, 1, 0, 56, 100, 0, 100],
            [2, 0, 0], [1, 123456789, 4294967295], [2, 33554431, 25], [0, 0, 1],
            [3, 3, 0, 2, 0, 3, 5, 1], [1, 0, 257], [0, 1, 2], [3, 0, 0, 2, 0, 3, 5, 1]]),
        ("carryPropagation", 24, [[0, 1, 1]] * 64 + [[0, 0, 1]] + [[0, 1, 1]] * 32
            + [[0, 0, 1], [3, 1, 0, 1, 65534], [2, 85, 7]]),
    ]


def fixture_text(executable):
    """Regenerate the complete Swift fixture source, including exact per-call accounting."""
    lines = [
        "// Compact independent oracle output generated from unmodified official libopus 1.6.1.",
        f"// {RELEASE_URL}", f"// Source archive SHA256: {ARCHIVE_SHA256}.",
        "// Generated 2026-10-17 by invoking ec_encode/ec_enc_bit_logp/ec_enc_uint/ec_enc_bits,",
        "// recording ec_tell/ec_tell_frac/rng after each call and frame bytes after ec_enc_done.",
        "// Oracle source and executable are development-only temporary files, never linked here.",
        "// These are entropy vectors, not full Opus decoded-PCM conformance vectors.", "",
        "enum OpusEntropyOperation: Sendable {", "    case symbol(Int, [UInt32])",
        "    case bit(Bool, Int)", "    case uniform(UInt32, UInt32)", "    case raw(UInt32, Int)", "}", "",
        "struct OpusEntropyFixture: Sendable {", "    let name: String", "    let bytes: [UInt8]",
        "    let operations: [OpusEntropyOperation]",
        "    let states: [(range: UInt32, bits: Int, fractional: Int)]", "}", "",
        "enum OpusEntropyOracleFixtures {", "    static let all: [OpusEntropyFixture] = [",
    ]
    for name, size, operations in fixture_cases():
        result = oracle_result(executable, size, operations)
        swift = []
        for op in operations:
            kind, value, parameter = op[:3]
            swift.append([
                f".bit({str(bool(value)).lower()}, {parameter})", f".uniform({value}, {parameter})",
                f".raw({value}, {parameter})", f".symbol({value}, {op[3:]})",
            ][kind])
        lines.extend([f'        OpusEntropyFixture(name: "{name}",', f'            bytes: {result["bytes"]},',
                      "            operations: ["])
        lines.extend("                " + ", ".join(swift[index:index + 4]) + "," for index in range(0, len(swift), 4))
        lines.extend(["            ],", "            states: ["])
        states = [f"({r}, {b}, {f})" for r, b, f in result["states"]]
        lines.extend("                " + ", ".join(states[index:index + 3]) + "," for index in range(0, len(states), 3))
        lines.append("            ]),")
    return "\n".join(lines + ["    ]", "}", ""])


def mixed_cases(count, seed):
    """Build deterministic valid public calls using a local seeded Python MT19937 instance."""
    generator = random.Random(seed)
    cases = []
    for _ in range(count):
        operations = []
        for _ in range(generator.randrange(1, 80)):
            kind = generator.randrange(4)
            if kind == 0:
                operation = [0, generator.randrange(2), generator.randrange(1, 16)]
            elif kind == 1:
                total = generator.choice([2, 3, 255, 256, 257, 65535, 65536, 65537,
                                          4294967295, generator.randrange(2, 2**32)])
                operation = [1, generator.randrange(total), total]
            elif kind == 2:
                bits = generator.randrange(26)
                operation = [2, generator.randrange(1 << bits), bits]
            else:
                frequencies = [generator.randrange(1, 1000) for _ in range(generator.randrange(1, 20))]
                operation = [3, generator.randrange(len(frequencies)), 0] + frequencies
            operations.append(operation)
        cases.append(operations)
    return cases


def main():
    """Compile temporary references, verify fixtures/stress and optionally save auditable evidence."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-archive", type=Path, required=True, help="Previously obtained official opus-1.6.1.tar.gz")
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cc", default="cc", help="C compiler executable, default cc")
    parser.add_argument("--swiftc", default="swiftc", help="Swift 6.4+ compiler executable, default swiftc")
    parser.add_argument("--cases", type=int, default=2000, help="Deterministic mixed streams, 1...10000")
    parser.add_argument("--seed", type=int, default=67168251, help="Nonnegative MT19937 fixture seed")
    parser.add_argument("--write-fixtures", action="store_true", help="Explicitly regenerate the single committed Swift fixture file")
    parser.add_argument("--report", type=Path, help="Optional machine-readable entropy-only evidence output")
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error("--cases must be 1...10000 and --seed must be nonnegative")
    repository = args.repository.resolve()
    with tempfile.TemporaryDirectory(prefix="discordkit-opus-range-") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        driver = directory / "oracle.c"
        driver.write_text(C_DRIVER)
        reference = directory / "official-oracle"
        includes = ["-I" + str(upstream / "include"), "-I" + str(upstream / "celt")]
        flags = ["-O2", "-DOPUS_BUILD", "-DVAR_ARRAYS"]
        sources = [upstream / "celt" / name for name in ["entenc.c", "entdec.c", "entcode.c"]]
        run([args.cc] + flags + includes + [str(driver)] + list(map(str, sources)) + ["-o", str(reference)])
        unit = directory / "official-unit"
        run([args.cc] + flags + includes + [str(upstream / "celt/tests/test_unit_entropy.c"), "-lm", "-o", str(unit)])
        run([str(unit), str(args.seed & 0xffff_ffff)])
        expected_fixtures = fixture_text(reference)
        fixture_path = repository / FIXTURE_PATH
        if args.write_fixtures:
            fixture_path.write_text(expected_fixtures)
        elif fixture_path.read_text() != expected_fixtures:
            raise RuntimeError("Committed oracle fixtures differ; inspect upstream/compiler output before --write-fixtures")
        swift_driver = directory / "driver.swift"
        swift_driver.write_text(SWIFT_DRIVER)
        owned = directory / "owned-driver"
        run([args.swiftc, "-O", "-module-cache-path", str(directory / "module-cache"),
             str(repository / OWNED_PATH), str(swift_driver), "-o", str(owned)])
        inputs = []
        expected = []
        for operations in mixed_cases(args.cases, args.seed):
            generous = oracle_result(reference, 1275, operations)
            size = max(1, (generous["states"][-1][1] + 7) // 8)
            expected.append(oracle_result(reference, size, operations))
            inputs.append({"size": size, "ops": operations})
        encoded = "\n".join(json.dumps(value) for value in inputs).encode()
        outputs = run([str(owned)], encoded).decode().splitlines()
        if len(outputs) != len(inputs):
            raise RuntimeError("Owned driver returned an unexpected number of streams")
        for index, (input_value, oracle, output) in enumerate(zip(inputs, expected, outputs)):
            actual = json.loads(output)
            if (actual.get("bytes") != oracle["bytes"] or actual.get("states") != oracle["states"]
                    or actual.get("decoded") != [op[1] for op in input_value["ops"]]):
                raise RuntimeError(json.dumps({"mismatchCase": index, "seed": args.seed,
                    "input": input_value, "expected": oracle, "actual": actual}))
        report = {
            "verifiedOn": datetime.now(timezone.utc).date().isoformat(),
            "scope": "Entropy primitives only; no decoded PCM, SILK/CELT/hybrid, PLC/FEC or complete codec conformance",
            "officialVersion": VERSION, "officialReleaseURL": RELEASE_URL, "sourceArchiveURL": SOURCE_URL,
            "sourceArchiveSHA256": ARCHIVE_SHA256, "sourceArchiveByteCount": ARCHIVE_BYTE_COUNT,
            "sourceLicense": "Unmodified upstream COPYING retained during temporary reference compilation",
            "sourceLicenseSHA256": digest(upstream / "COPYING"),
            "officialEntropySourceSHA256": {str(path.relative_to(upstream)): digest(path) for path in sources},
            "ownedSwiftSHA256": digest(repository / OWNED_PATH), "swiftFixtureSHA256": digest(fixture_path),
            "officialUnitTestPassed": True, "fixtureCount": len(fixture_cases()),
            "stressCases": args.cases, "seed": args.seed, "generator": "Python random.Random MT19937",
            "pythonVersion": platform.python_version(), "pythonImplementation": platform.python_implementation(),
            "operationCountBounds": [1, 79], "frameSizing": "max(1, ceil(final official ec_tell / 8))",
            "compared": ["final frame bytes", "every-operation rng/ec_tell/ec_tell_frac", "owned decoded input values"],
            "ccVersion": run([args.cc, "--version"]).decode().splitlines()[0],
            "swiftVersion": run([args.swiftc, "--version"]).decode().splitlines()[0],
        }
        if args.report:
            args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

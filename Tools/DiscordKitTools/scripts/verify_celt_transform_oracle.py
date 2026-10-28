#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/verify_celt_transform_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Opt-in offline CELT MDCT verification against pinned official libopus 1.6.1.

Provide --source-archive opus-1.6.1.tar.gz; no download occurs. The shared entropy
verifier validates the exact archive size/SHA256 and safe extraction policy.
Original development drivers compile unmodified upstream mdct/kiss_fft sources
and the owned Swift transform in temporary directories, retaining upstream COPYING.
No upstream code, archive, native dependency or compiler enters a consumer product.

Checks all bins of forward transforms and zero-state inverse samples, all ordinary
48 kHz CELT frame lengths and mono/stereo layouts, hostile finite bounds, and seeded
normalized PCM/arbitrary spectra. Also reproduces every complete committed float32
oracle fixture. This covers transform mathematics only: no Opus compressed packet,
band decoder, SILK/hybrid, PLC/FEC, complete codec or Discord/device conformance.
Requires Python 3.9+, cc and Swift 6.4+. Import starts no compilation, extraction,
network or subprocess work; normal Python discovery tests verifier guards only.
"""

import argparse
import base64
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import platform
import random
import re
import struct
import tempfile

from verify_opus_range_oracle import (
    ARCHIVE_BYTE_COUNT, ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION,
    digest, extract_verified_archive, run,
)


OWNED_PATH = "Sources/DiscordVoiceCodecs/CELTTransform.swift"
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/CELTTransformOracleFixtures.swift"
FRAME_SIZES = (120, 240, 480, 960)
FORWARD_TOLERANCE = (0.000002, 0.000001)
INVERSE_TOLERANCE = (0.0001, 0.000003)

# Original wrapper calls public internal upstream routines without modifying them.
# Upstream's window formula is evaluated in double and stored in float, as in modes.c.
C_DRIVER = r'''
#include <stdio.h>
#include <math.h>
#include "mdct.h"
int main(void) {
    int n, channels;
    float pcm[2160], spectrum[1920], forward[1920], inverse[1920];
    float input[1920], output[1920], window[120];
    for (int i = 0; i < 120; i++) {
        double inner = sin(.5 * M_PI * (i + .5) / 120);
        window[i] = sin(.5 * M_PI * inner * inner);
    }
    while (scanf("%d %d", &n, &channels) == 2) {
        if (!(n == 120 || n == 240 || n == 480 || n == 960)
                || channels < 1 || channels > 2) return 2;
        for (int i = 0; i < (n + 120) * channels; i++)
            if (scanf("%f", &pcm[i]) != 1) return 3;
        for (int i = 0; i < n * channels; i++)
            if (scanf("%f", &spectrum[i]) != 1) return 3;
        mdct_lookup plan;
        if (!clt_mdct_init(&plan, 2 * n, 0, 0)) return 4;
        for (int channel = 0; channel < channels; channel++) {
            for (int i = 0; i < n + 120; i++) input[i] = pcm[i * channels + channel];
            clt_mdct_forward_c(&plan, input, forward + channel, window, 120, 0, channels, 0);
            for (int i = 0; i < 1920; i++) output[i] = 0;
            clt_mdct_backward_c(&plan, spectrum + channel, output, window, 120, 0, channels, 0);
            for (int i = 0; i < n; i++) inverse[i * channels + channel] = output[i];
        }
        clt_mdct_clear(&plan, 0);
        printf("{\"forward\":[");
        for (int i = 0; i < n * channels; i++) printf("%s%.9g", i ? "," : "", forward[i]);
        printf("],\"inverse\":[");
        for (int i = 0; i < n * channels; i++) printf("%s%.9g", i ? "," : "", inverse[i]);
        printf("]}\n");
    }
    return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable { let n: Int; let channels: Int; let pcm: [Float]; let spectrum: [Float] }
struct Output: Encodable { let forward: [Float]; let inverse: [Float] }
@main struct Driver {
    /// Processes independently supplied PCM and spectra; failures become explicit comparison errors.
    /// JSON serialization errors propagate; no device, codec packet or network work occurs.
    static func main() throws {
        while let line = readLine() {
            do {
                let input = try JSONDecoder().decode(Input.self, from: Data(line.utf8))
                let plan = try CELTTransform(frameSampleCount: input.n, channelCount: input.channels)
                let forward = try plan.forward(input.pcm)
                let inverse = Array(try plan.inverse(input.spectrum).prefix(input.n * input.channels))
                let output = Output(forward: forward, inverse: inverse)
                print(String(data: try JSONEncoder().encode(output), encoding: .utf8)!)
            } catch { print("{\"error\":\"\(error)\"}") }
        }
    }
}
'''


def fixed_cases():
    """Reproduce the four committed full-vector contexts exactly with float32-exact inputs."""
    return [{"n": n, "channels": 1,
             "pcm": [((i * 37 + 11) % 101 - 50) / 64 for i in range(n + 120)],
             "spectrum": [((i * 37 + 11) % 101 - 50) / 64 for i in range(n)]}
            for n in FRAME_SIZES]


def boundary_cases():
    """Cover silence, extrema and both compact-window/channel edges at every length/layout."""
    contexts = []
    for n in FRAME_SIZES:
        for channels in (1, 2):
            for mode in range(5):
                pcm = [0.0] * ((n + 120) * channels)
                spectrum = [0.0] * (n * channels)
                if mode in (1, 2):
                    pcm = [(-1.0 if mode == 1 else 1.0)] * len(pcm)
                    spectrum = [(-4.0 if mode == 1 else 4.0)] * len(spectrum)
                elif mode in (3, 4):
                    pcm[0 if mode == 3 else -1] = 1.0
                    spectrum[0 if mode == 3 else -1] = 4.0
                contexts.append({"n": n, "channels": channels, "pcm": pcm, "spectrum": spectrum})
    return contexts


def mixed_cases(count, seed):
    """Generate reproducible float32-exact normalized PCM/spectra without global RNG mutation."""
    generator = random.Random(seed)
    contexts = []
    for _ in range(count):
        n = generator.choice(FRAME_SIZES)
        channels = generator.choice((1, 2))
        contexts.append({"n": n, "channels": channels,
                         "pcm": [generator.randint(-1024, 1024) / 1024
                                 for _ in range((n + 120) * channels)],
                         "spectrum": [generator.randint(-4096, 4096) / 1024
                                      for _ in range(n * channels)]})
    return contexts


def parse_outputs(data, count, label):
    """Require complete JSON object records; dropped/extra results cannot become evidence."""
    lines = data.decode().splitlines()
    if len(lines) != count:
        raise RuntimeError(f"{label} returned an unexpected number of cases")
    records = [json.loads(line) for line in lines]
    if any(not isinstance(record, dict) for record in records):
        raise RuntimeError(f"{label} returned a non-object case")
    return records


def compare_results(inputs, expected, actual, seed):
    """Check all bins/shapes/finite values under explicit absolute-plus-relative tolerances."""
    if not len(inputs) == len(expected) == len(actual):
        raise RuntimeError("Unexpected comparison case count")
    maxima = {"forward": 0.0, "inverse": 0.0}
    for index, (context, reference, owned) in enumerate(zip(inputs, expected, actual)):
        for key, (absolute, relative) in [("forward", FORWARD_TOLERANCE), ("inverse", INVERSE_TOLERANCE)]:
            target, candidate = reference.get(key), owned.get(key)
            length = context["n"] * context["channels"]
            if (not isinstance(target, list) or not isinstance(candidate, list)
                    or len(target) != length or len(candidate) != length):
                raise RuntimeError(f"Case {index} seed {seed} invalid {key} shape")
            for bin_index, (a, b) in enumerate(zip(target, candidate)):
                if (type(a) not in (int, float) or type(b) not in (int, float)
                        or not math.isfinite(a) or not math.isfinite(b)
                        or abs(a - b) > absolute + relative * abs(a)):
                    raise RuntimeError(json.dumps({"case": index, "seed": seed, "transform": key,
                                                   "bin": bin_index, "expected": a, "actual": b}))
                maxima[key] = max(maxima[key], abs(a - b))
    return maxima


def committed_fixtures(path):
    """Decode exact complete float32 fixture literals without executing Swift or relying on alignment."""
    pattern = r'^\s*\((120|240|480|960), "([A-Za-z0-9+/=]+)", "([A-Za-z0-9+/=]+)"\),$'
    records = []
    for count, forward, inverse in re.findall(pattern, path.read_text(), re.MULTILINE):
        record = {"n": int(count)}
        for key, encoded in [("forward", forward), ("inverse", inverse)]:
            data = base64.b64decode(encoded, validate=True)
            if len(data) != 4 * int(count):
                raise ValueError("Invalid complete transform fixture length")
            record[key] = list(struct.unpack("<" + "f" * int(count), data))
        records.append(record)
    if [record["n"] for record in records] != list(FRAME_SIZES):
        raise ValueError("Expected four ordered complete transform fixtures")
    return records


def compare_fixtures(fixtures, official):
    """Require every stored float32 reference bit pattern to reproduce from the official driver."""
    if len(fixtures) != 4 or len(official) != 4:
        raise RuntimeError("Unexpected transform fixture count")
    for fixture, reference in zip(fixtures, official):
        for key in ("forward", "inverse"):
            actual = [struct.unpack("<f", struct.pack("<f", value))[0] for value in reference[key]]
            if fixture[key] != actual:
                raise RuntimeError(f"Committed {fixture['n']} {key} fixture mismatch")


def main():
    """Compile isolated pinned sources, compare vectors and optionally write bounded evidence."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--cases", type=int, default=200)
    parser.add_argument("--seed", type=int, default=6716437)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 2000 or args.seed < 0:
        parser.error("--cases must be 1...2000 and --seed must be nonnegative")
    repository = args.repository.resolve()
    fixtures = committed_fixtures(repository / FIXTURE_PATH)
    inputs = fixed_cases() + boundary_cases() + mixed_cases(args.cases, args.seed)
    with tempfile.TemporaryDirectory(prefix="discordkit-celt-transform-") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        driver = directory / "oracle.c"
        driver.write_text(C_DRIVER)
        reference = directory / "official-oracle"
        sources = [upstream / "celt" / name for name in ["mdct.c", "kiss_fft.c", "entcode.c"]]
        run([args.cc, "-O2", "-DCUSTOM_MODES", "-DUSE_ALLOCA", "-I" + str(upstream / "include"),
             "-I" + str(upstream / "celt"), str(driver)] + [str(path) for path in sources]
            + ["-lm", "-o", str(reference)])
        swift_driver = directory / "driver.swift"
        swift_driver.write_text(SWIFT_DRIVER)
        owned = directory / "owned-driver"
        run([args.swiftc, "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated",
             str(repository / OWNED_PATH), str(swift_driver), "-o", str(owned)])
        commands = "\n".join(f"{value['n']} {value['channels']} "
                              + " ".join(str(number) for number in value["pcm"] + value["spectrum"])
                              for value in inputs).encode()
        expected = parse_outputs(run([str(reference)], commands), len(inputs), "Official driver")
        encoded = "\n".join(json.dumps(value) for value in inputs).encode()
        actual = parse_outputs(run([str(owned)], encoded), len(inputs), "Owned driver")
        maxima = compare_results(inputs, expected, actual, args.seed)
        compare_fixtures(fixtures, expected[:4])
        report = {
            "verifiedOn": datetime.now(timezone.utc).date().isoformat(),
            "scope": "CELT transform primitives only; no compressed-packet, band decoder, SILK/hybrid, PLC/FEC, complete codec or Discord/device conformance",
            "officialVersion": VERSION, "officialReleaseURL": RELEASE_URL, "sourceArchiveURL": SOURCE_URL,
            "sourceArchiveSHA256": ARCHIVE_SHA256, "sourceArchiveByteCount": ARCHIVE_BYTE_COUNT,
            "sourceLicense": "Unmodified upstream COPYING retained during temporary reference compilation",
            "sourceLicenseSHA256": digest(upstream / "COPYING"),
            "officialSourceSHA256": {str(path.relative_to(upstream)): digest(path) for path in sources},
            "ownedSwiftSHA256": {OWNED_PATH: digest(repository / OWNED_PATH)},
            "swiftFixtureSHA256": digest(repository / FIXTURE_PATH), "swiftFixturePath": FIXTURE_PATH,
            "fixtureCount": 4, "boundaryCases": len(boundary_cases()), "stressCases": args.cases,
            "comparedCases": len(inputs), "seed": args.seed, "generator": "Python random.Random MT19937",
            "frameSampleCounts": list(FRAME_SIZES), "channelCounts": [1, 2], "overlapSampleCount": 120,
            "forwardToleranceAbsoluteRelative": list(FORWARD_TOLERANCE),
            "inverseToleranceAbsoluteRelative": list(INVERSE_TOLERANCE), "maximumAbsoluteError": maxima,
            "pythonVersion": platform.python_version(), "pythonImplementation": platform.python_implementation(),
            "compared": ["every forward frequency bin", "every zero-state inverse output sample",
                         "four complete committed float32 fixture pairs"],
            "ccVersion": run([args.cc, "--version"]).decode().splitlines()[0],
            "swiftVersion": run([args.swiftc, "--version"]).decode().splitlines()[0],
        }
        if args.report:
            args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

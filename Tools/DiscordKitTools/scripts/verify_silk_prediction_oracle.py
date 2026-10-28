#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/verify_silk_prediction_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Offline SILK prediction/excitation differential verification against libopus 1.6.1.

Supply --source-archive /path/to/opus-1.6.1.tar.gz separately. This script never
downloads files. The shared verifier checks release size/SHA256 and safe members;
temporary unmodified sources retain COPYING and never enter a consumer product.
Original C/Swift drivers compare LPC analysis and inverse prediction gain, plus
the intermediate excitation buffer from the complete unmodified decode_core.c.
This checks primitives only: no compressed SILK syntax, complete LPC/LTP decoder,
decoded-PCM conformance, encoder, hybrid, PLC/FEC or device qualification.
Requires Python 3.9+, a C compiler and Swift 6.4+. Normal test imports start no work.
"""

import argparse
import ast
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import platform
import random
import re
import tempfile

from verify_opus_range_oracle import (
    ARCHIVE_BYTE_COUNT, ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION,
    digest, extract_verified_archive, run,
)
from verify_celt_pulse_oracle import parse_outputs

OWNED_PATHS = ("Sources/DiscordVoiceCodecs/SILKLinearPrediction.swift",
               "Sources/DiscordVoiceCodecs/SILKExcitation.swift")
FIXTURE_PATHS = ("Tests/DiscordVoiceCodecsTests/SILKLinearPredictionTests.swift",
                 "Tests/DiscordVoiceCodecsTests/SILKExcitationTests.swift")
OFFICIAL_PATHS = ("silk/float/LPC_analysis_filter_FLP.c", "silk/float/LPC_inv_pred_gain_FLP.c",
                  "silk/decode_core.c", "silk/LPC_analysis_filter.c", "silk/tables_other.c")
Q12 = [1024, 512, -256, 128, -64, 32, -16, 8, -4, 2, -2, 1, -1, 1, -1, 1]
PULSES = [0, 1, -1, 2, -2, 127, -128, 0]
RELATIVE_TOLERANCE = 0.000002
ABSOLUTE_TOLERANCE = 0.00002

# Original drivers call complete unmodified upstream routines. No upstream source
# is copied into this script, the repository, or the owned executable.
C_DRIVER = r'''
#include <stdio.h>
#include <string.h>
#include "main_FLP.h"
int main(void) {
    char kind;
    while(scanf(" %c", &kind)==1) {
        if(kind=='A') {
            int order,count,coefficient;
            float a[16],input[976],output[976];
            if(scanf("%d %d",&order,&count)!=2 || (order!=10 && order!=16) || count<0 || count>960) return 2;
            for(int j=0;j<order;j++) {
                if(scanf("%d",&coefficient)!=1 || coefficient < -32768 || coefficient > 32767) return 2;
                a[j]=coefficient/4096.0f;
            }
            for(int j=0;j<order+count;j++) if(scanf("%f",&input[j])!=1) return 2;
            silk_LPC_analysis_filter_FLP(output,a,input,order+count,order);
            printf("{\"gain\":%.17g,\"samples\":[",silk_LPC_inverse_pred_gain_FLP(a,order));
            for(int j=0;j<count;j++) printf("%s%.17g",j?",":"",output[order+j]);
            puts("]}");
        } else if(kind=='X') {
            int signal,offset,seed,count,pulse;
            if(scanf("%d %d %d %d",&signal,&offset,&seed,&count)!=4 || signal<0 || signal>2 || offset<0 || offset>1 || seed<0 || seed>3 || count<0 || count>320) return 2;
            silk_decoder_state state={0};
            silk_decoder_control control={0};
            opus_int16 pulses[MAX_FRAME_LENGTH]={0},output[MAX_FRAME_LENGTH]={0};
            for(int j=0;j<count;j++) {
                if(scanf("%d",&pulse)!=1 || pulse < -32768 || pulse > 32767) return 2;
                pulses[j]=(opus_int16)pulse;
            }
            state.frame_length=320; state.nb_subfr=4; state.subfr_length=80;
            state.ltp_mem_length=320; state.LPC_order=16; state.prev_gain_Q16=65536;
            state.indices.signalType=signal; state.indices.quantOffsetType=offset;
            state.indices.Seed=seed; state.indices.NLSFInterpCoef_Q2=4;
            control.LTP_scale_Q14=16384;
            for(int j=0;j<4;j++) { control.Gains_Q16[j]=65536; control.pitchL[j]=32; }
            silk_decode_core(&state,&control,output,pulses,0);
            printf("{\"excitation\":[");
            for(int j=0;j<count;j++) printf("%s%d",j?",":"",state.exc_Q14[j]/64);
            puts("]}");
        } else return 2;
    }
    return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable {
    let kind:String; let q12:[Int16]?; let history:[Double]?; let samples:[Double]?
    let signal:Int?; let offset:Int?; let seed:UInt8?; let pulses:[Int16]?
}
struct Analysis: Encodable { let gain:Double; let samples:[Double]; let recovered:[Double] }
struct Excitation: Encodable { let excitation:[Int32]; let seed:UInt32 }
@main struct Driver {
    /// Runs independent bounded primitive cases; failures become verifier mismatches.
    /// The isolated owned executable has no native codec or package dependencies.
    static func main() throws {
        while let line=readLine() {
            do {
                let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
                let encoded:Data
                if input.kind=="analysis" {
                    let coefficients=try SILKLinearPredictionCoefficients(q12:input.q12!)
                    var analysis=try SILKShortTermFilter(direction:.analysis,coefficients:coefficients,history:input.history!)
                    let residual=try analysis.process(input.samples!)
                    var synthesis=try SILKShortTermFilter(direction:.synthesis,coefficients:coefficients,history:input.history!)
                    encoded=try JSONEncoder().encode(Analysis(gain:coefficients.inversePredictionGain,samples:residual,recovered:try synthesis.process(residual)))
                } else {
                    var reconstructor=try SILKExcitationReconstructor(seed:input.seed!,signalType:SILKSignalType(rawValue:input.signal!)!,quantizationOffset:SILKQuantizationOffset(rawValue:input.offset!)!)
                    let excitation=try reconstructor.reconstruct(input.pulses!)
                    encoded=try JSONEncoder().encode(Excitation(excitation:excitation,seed:reconstructor.seed))
                }
                print(String(data:encoded,encoding:.utf8)!)
            } catch { print("{\"error\":\"\(error)\"}") }
        }
    }
}
'''


def analysis_case(order, q12=None, count=24):
    """Create the exact dyadic sample/history context of committed LPC fixtures."""
    source = [((index * 37) % 101 - 50) / 8 for index in range(order + count)]
    return {"kind": "analysis", "q12": Q12[:order] if q12 is None else q12,
            "history": source[:order], "samples": source[order:]}


def fixture_cases():
    """Reproduce two LPC and all twenty-four signal/offset/seed excitation fixtures."""
    return [analysis_case(10), analysis_case(16)] + [
        {"kind": "excitation", "signal": signal, "offset": offset, "seed": seed, "pulses": PULSES}
        for signal in range(3) for offset in range(2) for seed in range(4)]


def boundary_cases():
    """Exercise zero/maximum blocks, high-gain stable poles and full signed pulse bounds."""
    cases = [analysis_case(order, [first] + [0] * (order - 1), count)
             for order in [10, 16] for first in [0, -4094, 4094] for count in [0, 1, 960]]
    cases += [{"kind": "excitation", "signal": signal, "offset": offset, "seed": seed,
               "pulses": ([0, -32768, 32767, -1, 1] * 64)[:count]}
              for signal in range(3) for offset in range(2) for seed in range(4) for count in [0, 1, 320]]
    return cases


def mixed_cases(count, seed):
    """Generate bounded stable/dyadic contexts with a local reproducible RNG only."""
    generator = random.Random(seed)
    cases = []
    for index in range(count):
        if index % 2:
            cases.append({"kind": "excitation", "signal": generator.randrange(3),
                          "offset": generator.randrange(2), "seed": generator.randrange(4),
                          "pulses": [generator.randint(-32768, 32767) for _ in range(generator.randrange(321))]})
        else:
            order = generator.choice([10, 16])
            cases.append({"kind": "analysis", "q12": [generator.randint(-128, 128) for _ in range(order)],
                          "history": [generator.randint(-4096, 4096) / 128 for _ in range(order)],
                          "samples": [generator.randint(-4096, 4096) / 128 for _ in range(generator.randrange(961))]})
    return cases


def commands(inputs):
    """Convert admitted contexts to bounded whitespace-separated C-driver requests."""
    result = []
    for value in inputs:
        if value["kind"] == "analysis":
            values = ["A", len(value["q12"]), len(value["samples"])] + value["q12"] + value["history"] + value["samples"]
        else:
            values = ["X", value["signal"], value["offset"], value["seed"], len(value["pulses"])] + value["pulses"]
        result.append(" ".join(map(str, values)))
    return "\n".join(result).encode()


def committed_fixtures(repository):
    """Parse only the literal independently generated Swift fixture arrays, without execution."""
    source = (repository / FIXTURE_PATHS[0]).read_text()
    section = source.partition("@Test func officialAnalysisFixtures() throws {")[2].split("\n        ]", 1)[0]
    rows = re.findall(r"\((10|16), ([0-9.]+), (\[[\s\S]*?\])\)", section)
    if len(rows) != 2 or [int(order) for order, _, _ in rows] != [10, 16]:
        raise ValueError("Expected two committed LPC fixture rows")
    result = [{"gain": float(gain), "samples": ast.literal_eval(samples)} for _, gain, samples in rows]
    source = (repository / FIXTURE_PATHS[1]).read_text()
    section = source.partition("@Test func officialExcitationFixtures() throws {")[2].split("\n        ]", 1)[0]
    rows = re.findall(r"\((\d), (\d), (\d), (\[.*?\])\)", section)
    if len(rows) != 24 or [(int(a), int(b), int(c)) for a, b, c, _ in rows] != [
            (a, b, c) for a in range(3) for b in range(2) for c in range(4)]:
        raise ValueError("Expected twenty-four ordered excitation fixture rows")
    result += [{"excitation": ast.literal_eval(values)} for _, _, _, values in rows]
    return result


def close(actual, expected, relative=RELATIVE_TOLERANCE, absolute=ABSOLUTE_TOLERANCE):
    """Compare finite reconstruction values using explicit float-versus-Double tolerances."""
    return (type(actual) in (int, float) and type(expected) in (int, float)
            and math.isfinite(actual) and math.isfinite(expected)
            and math.isclose(actual, expected, rel_tol=relative, abs_tol=absolute))


def compare_results(inputs, expected, actual, seed):
    """Require every sample/gain, inverse recovery and exact excitation/seed invariant."""
    if len(inputs) != len(expected) or len(inputs) != len(actual):
        raise RuntimeError("Unexpected number of comparison cases")
    for index, (context, official, owned) in enumerate(zip(inputs, expected, actual)):
        valid = False
        if context["kind"] == "analysis":
            samples, recovered = owned.get("samples", []), owned.get("recovered", [])
            reference = official.get("samples", [])
            valid = (isinstance(samples, list) and isinstance(reference, list) and isinstance(recovered, list)
                     and len(samples) == len(reference) == len(recovered) == len(context["samples"])
                     and close(official.get("gain"), official.get("gain")) and 0 < official["gain"] <= 1
                     and close(official.get("gain"), owned.get("gain"), absolute=0.0000001)
                     and all(close(a, b) for a, b in zip(samples, reference))
                     and all(close(a, b, relative=1e-10, absolute=1e-10)
                             for a, b in zip(recovered, context["samples"])))
        else:
            final_seed = context["seed"]
            for pulse in context["pulses"]:
                final_seed = (final_seed * 196314165 + 907633515 + pulse) % 2**32
            valid = (isinstance(official.get("excitation"), list) and isinstance(owned.get("excitation"), list)
                     and len(official["excitation"]) == len(context["pulses"])
                     and official.get("excitation") == owned.get("excitation")
                     and owned.get("seed") == final_seed)
        if not valid:
            raise RuntimeError(json.dumps({"mismatchCase": index, "seed": seed, "input": context,
                                          "expected": official, "actual": owned}))


def compare_fixtures(fixtures, expected):
    """Require complete byte-for-byte numeric fixture reproduction from official routines."""
    if len(fixtures) != len(expected) or fixtures != expected:
        raise RuntimeError("Committed SILK fixture mismatch")


def main():
    """Compile isolated references, compare bounded contexts and write scoped evidence."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=67164279)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error("--cases must be 1...10000 and --seed must be nonnegative")
    repository = args.repository.resolve()
    fixtures = committed_fixtures(repository)
    fixed, boundaries = fixture_cases(), boundary_cases()
    inputs = fixed + boundaries + mixed_cases(args.cases, args.seed)
    with tempfile.TemporaryDirectory(prefix="discordkit-silk-prediction-") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        driver = directory / "oracle.c"
        driver.write_text(C_DRIVER)
        reference = directory / "official-oracle"
        run([args.cc, "-std=c99", "-O0", "-ffp-contract=off", "-DOPUS_BUILD", "-DVAR_ARRAYS"]
            + ["-I" + str(upstream / path) for path in ["include", "celt", "silk", "silk/float"]]
            + [str(driver)] + [str(upstream / path) for path in OFFICIAL_PATHS]
            + ["-lm", "-o", str(reference)])
        swift_driver = directory / "driver.swift"
        swift_driver.write_text(SWIFT_DRIVER)
        owned = directory / "owned-driver"
        run([args.swiftc, "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated"]
            + [str(repository / path) for path in OWNED_PATHS] + [str(swift_driver), "-o", str(owned)])
        expected = parse_outputs(run([str(reference)], commands(inputs)), len(inputs), "Official driver")
        encoded = "\n".join(json.dumps(value) for value in inputs).encode()
        actual = parse_outputs(run([str(owned)], encoded), len(inputs), "Owned driver")
        compare_results(inputs, expected, actual, args.seed)
        compare_fixtures(fixtures, expected[:len(fixed)])
        report = {
            "verifiedOn": datetime.now(timezone.utc).date().isoformat(),
            "scope": "SILK LPC analysis/inverse-gain and intermediate excitation primitives only; no compressed syntax, decoded PCM, complete codec conformance, hybrid, PLC/FEC or device qualification",
            "officialVersion": VERSION, "officialReleaseURL": RELEASE_URL, "sourceArchiveURL": SOURCE_URL,
            "sourceArchiveSHA256": ARCHIVE_SHA256, "sourceArchiveByteCount": ARCHIVE_BYTE_COUNT,
            "sourceLicense": "Unmodified upstream COPYING retained during temporary compilation",
            "sourceLicenseSHA256": digest(upstream / "COPYING"),
            "officialSourceSHA256": {path: digest(upstream / path) for path in OFFICIAL_PATHS},
            "ownedSwiftSHA256": {path: digest(repository / path) for path in OWNED_PATHS},
            "swiftFixtureSHA256": {path: digest(repository / path) for path in FIXTURE_PATHS},
            "driverSHA256": {"c": hashlib.sha256(C_DRIVER.encode()).hexdigest(),
                             "swift": hashlib.sha256(SWIFT_DRIVER.encode()).hexdigest()},
            "verifierSHA256": digest(Path(__file__).resolve()),
            "fixtureCount": len(fixed), "boundaryCases": len(boundaries), "stressCases": args.cases,
            "comparedCases": len(inputs), "seed": args.seed, "generator": "Python random.Random MT19937",
            "analysisRelativeTolerance": RELATIVE_TOLERANCE, "analysisAbsoluteTolerance": ABSOLUTE_TOLERANCE,
            "inverseGainAbsoluteTolerance": 0.0000001, "inverseRecoveryTolerance": 1e-10,
            "excitationComparison": "exact signed Q23 integers; final seed independently checked modulo 2^32",
            "pythonVersion": platform.python_version(), "pythonImplementation": platform.python_implementation(),
            "ccVersion": run([args.cc, "--version"]).decode().splitlines()[0],
            "swiftVersion": run([args.swiftc, "--version"]).decode().splitlines()[0],
        }
        if args.report:
            args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

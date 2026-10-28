#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/verify_silk_nlsf_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Opt-in offline fixed-point SILK NLSF/LPC verification against libopus 1.6.1.

The archive is supplied separately and validated by size/hash/member policy before
unmodified reference routines compile in temporary storage. Products and normal
tests never download, vendor or link native codec code. This verifies coefficient
conversion and stability, not full SILK/Opus decoded-PCM conformance or realtime.
"""

from publication import swift_header

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import random
import tempfile

from verify_opus_range_oracle import (
    ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION, digest,
    extract_verified_archive, run,
)
from verify_celt_pulse_oracle import parse_outputs

OWNED_PATH = "Sources/DiscordVoiceCodecs/SILKNLSF.swift"
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/SILKNLSFOracleFixtures.swift"
OFFICIAL_PATHS = ("silk/NLSF2A.c", "silk/LPC_fit.c", "silk/bwexpander_32.c",
                  "silk/LPC_inv_pred_gain.c", "silk/table_LSF_cos.c", "silk/Inlines.h")

C_DRIVER = r'''
#include <stdio.h>
#include "SigProc_FIX.h"
int main(void) {
    int kind, n, value;
    while(scanf("%d %d", &kind, &n)==2) {
        if((kind!=0 && kind!=1)||(n!=10 && n!=16)) return 2;
        opus_int16 input[16], coefficients[16];
        for(int j=0;j<n;j++) {
            if(scanf("%d",&value)!=1||value < -32768||value > 32767) return 2;
            input[j]=(opus_int16)value;
            if(kind==0 && (value<0||(j && value<input[j-1]))) return 2;
            coefficients[j]=input[j];
        }
        if(kind==0) silk_NLSF2A(coefficients,input,n,0);
        printf("{\"q12\":[");
        for(int j=0;j<n;j++) printf("%s%d", j?",":"", coefficients[j]);
        printf("],\"gain\":%d}\n",silk_LPC_inverse_pred_gain_c(coefficients,n));
    }
    return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable { let kind:Int; let values:[Int16] }
struct Output: Encodable { let q12:[Int16]; let gain:Int32 }
@main struct Driver {
    /// Processes bounded development cases over stdin/stdout, propagating errors to the verifier.
    /// This independent executable links only the owned Swift frequency conversion source.
    static func main() throws {
        while let line=readLine() {
            let input=try JSONDecoder().decode(Input.self, from:Data(line.utf8))
            let output:Output
            if input.kind==0 {
                let coefficients=try SILKNLSFCoefficients(q15:input.values)
                output=Output(q12:coefficients.lpcQ12,gain:coefficients.inversePredictionGainQ30)
            } else {
                output=Output(q12:input.values,gain:try SILKNLSFCoefficients.inversePredictionGain(q12:input.values))
            }
            print(String(data:try JSONEncoder().encode(output),encoding:.utf8)!)
        }
    }
}
'''


def fixed_cases():
    """Cover both orders, table endpoints, degeneracy, expansion and stable/unstable gains."""
    cases = []
    for n in (10, 16):
        for values in ([0]*n, [32767]*n, [0]*(n//2)+[32767]*(n//2),
                       [32768*(i+1)//(n+1) for i in range(n)],
                       list(range(n)), list(range(32768-n, 32768)),
                       [16384+i for i in range(n)],
                       [i*256 for i in range(n)],
                       [i*256+255 for i in range(n)]):
            cases.append({"kind": 0, "values": values})
        for values in ([0]*n, [4096]+[0]*(n-1), [-4096]+[0]*(n-1),
                       [1024, 512, -256, 128]+[0]*(n-4),
                       [32767]*n, [-32768]*n):
            cases.append({"kind": 1, "values": values})
    return cases


def random_cases(count, seed):
    """Generate sorted/clustered frequencies and independent arbitrary/stable Q12 predictors."""
    rng = random.Random(seed)
    result = []
    for index in range(count):
        n = rng.choice((10, 16))
        if index % 3:
            lower, upper = rng.choice(((0, 32767), (0, 255), (32000, 32767), (16000, 17000)))
            values = sorted(rng.randint(lower, upper) for _ in range(n))
            kind = 0
        else:
            bound = rng.choice((32, 128, 4096, 32767))
            values = [rng.randint(-bound, bound) for _ in range(n)]
            kind = 1
        result.append({"kind": kind, "values": values})
    return result


def fixture_records(path):
    """Read the single literal JSON payload without executing generated Swift code."""
    text = path.read_text()
    return json.loads(text.split('#"""', 1)[1].split('"""#', 1)[0])


def compare_results(inputs, expected, actual):
    """Require exact coefficient and Q30 gain equality for every independent case."""
    if len(inputs) != len(expected) or len(inputs) != len(actual):
        raise RuntimeError("Driver output count mismatch")
    for index, (case, reference, owned) in enumerate(zip(inputs, expected, actual)):
        for output in (reference, owned):
            if (not isinstance(output, dict) or set(output) != {"q12", "gain"}
                    or type(output["gain"]) is not int or not 0 <= output["gain"] <= 1 << 30
                    or not isinstance(output["q12"], list) or len(output["q12"]) != len(case["values"])
                    or any(type(v) is not int or not -32768 <= v <= 32767 for v in output["q12"])
                    or (case["kind"] == 1 and output["q12"] != case["values"])):
                raise RuntimeError(f"Invalid NLSF output for case {index}")
        if reference != owned:
            raise RuntimeError(f"NLSF case {index} mismatch: {case}; expected {reference}; actual {owned}")


def main():
    """Compile isolated drivers, reproduce committed fixtures and fingerprint exact evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-archive", required=True, type=Path)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=67167515)
    parser.add_argument("--write-fixtures", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error("--cases must be 1...10000; --seed must be nonnegative")
    repository = args.repository.resolve()
    fixed = fixed_cases()
    inputs = fixed + random_cases(args.cases, args.seed)
    with tempfile.TemporaryDirectory(prefix="discordkit-silk-nlsf-") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        c_driver, swift_driver = directory/"oracle.c", directory/"driver.swift"
        c_driver.write_text(C_DRIVER)
        swift_driver.write_text(SWIFT_DRIVER)
        reference, owned = directory/"oracle", directory/"owned"
        run(["cc", "-O2", "-fwrapv", "-DOPUS_BUILD", "-DVAR_ARRAYS",
             "-I"+str(upstream/"include"), "-I"+str(upstream/"celt"), "-I"+str(upstream/"silk"),
             str(c_driver)] + [str(upstream/path) for path in OFFICIAL_PATHS if path.endswith(".c")]
            + ["-o", str(reference)])
        run(["swiftc", "-O", "-module-cache-path", str(directory/"cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated",
             str(repository/OWNED_PATH), str(swift_driver), "-o", str(owned)])
        commands = "\n".join(f'{c["kind"]} {len(c["values"])} '+" ".join(map(str, c["values"])) for c in inputs).encode()
        expected = parse_outputs(run([str(reference)], commands), len(inputs), "Official NLSF driver")
        actual = parse_outputs(run([str(owned)], "\n".join(map(json.dumps, inputs)).encode()), len(inputs), "Owned NLSF driver")
        compare_results(inputs, expected, actual)
        records = [{"input": c, "output": e} for c, e in zip(fixed, expected)]
        fixture = repository/FIXTURE_PATH
        if args.write_fixtures:
            fixture.write_text(swift_header(FIXTURE_PATH) + '/// Independent unmodified libopus 1.6.1 scalar fixed-point NLSF/gain fixtures.\n'
                               '/// Generated only by the opt-in offline verifier; no native codec in normal tests.\n'
                               'enum SILKNLSFOracleFixtures {\n    static let json = #"""\n'
                               + json.dumps(records, separators=(",", ":"))+'\n"""#\n}\n')
        if fixture_records(fixture) != records:
            raise RuntimeError("Committed NLSF fixtures differ from independent oracle")
        report = {"verifiedOn": datetime.now(timezone.utc).date().isoformat(),
                  "scope": "Fixed-point SILK NLSF conversion and LPC gain only; no full codec or decoded-PCM conformance",
                  "officialVersion": VERSION, "officialReleaseURL": RELEASE_URL,
                  "sourceArchiveURL": SOURCE_URL, "sourceArchiveSHA256": ARCHIVE_SHA256,
                  "seed": args.seed, "fixedCases": len(fixed), "randomCases": args.cases,
                  "comparedCases": len(inputs), "ownedSourceSHA256": {OWNED_PATH: digest(repository/OWNED_PATH)},
                  "fixtureSHA256": digest(fixture), "oracleSourceSHA256": {p: digest(upstream/p) for p in OFFICIAL_PATHS},
                  "ccVersion": run(["cc", "--version"]).decode().splitlines()[0],
                  "swiftVersion": run(["swiftc", "--version"]).decode().strip(),
                  "verifierSHA256": digest(Path(__file__)),
                  "compared": ["exact Q12 coefficients", "exact Q30 inverse gain", "both SILK LPC orders",
                               "cosine interpolation", "fitting and stability expansion", "degenerate sorted frequencies"]}
        if args.report:
            args.report.write_text(json.dumps(report, indent=2, sort_keys=True)+"\n")
        print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

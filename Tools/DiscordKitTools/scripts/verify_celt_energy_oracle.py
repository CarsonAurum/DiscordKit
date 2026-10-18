#!/usr/bin/env python3
"""Opt-in offline CELT envelope verification against unmodified libopus 1.6.1.

A separately supplied archive is SHA256/path/size validated. No downloads, codec
runtime dependency, device work or authenticated calls occur. This checks coarse
prediction, all Laplace contexts, budget fallback syntax, fine and final refinement,
raw bytes, final ranges and whole-bit accounting. It is component evidence only;
full Opus decoding/encoding, PLC/FEC and official decoded-PCM conformance remain open.
The upstream encoder helper can retain an out-of-domain negative residual in its
one-bit fallback. Oracle comparisons constrain such scarce first-band residuals to
the canonical -1/0 decoder domain; separate Swift regressions check canonicalization
of arbitrary admitted residuals. This is an explicit encoder bookkeeping repair,
not a change to the normative one-bit decoder syntax.
"""
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
from verify_celt_pulse_oracle import parse_outputs

OWNED_PATHS = ("Sources/DiscordVoiceCodecs/OpusRangeCoding.swift",
               "Sources/DiscordVoiceCodecs/CELTEnergyQuantizer.swift")
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/CELTEnergyOracleFixtures.swift"
UPSTREAM_PATHS = ("celt/quant_bands.c", "celt/laplace.c", "celt/entenc.c",
                  "celt/entdec.c", "celt/entcode.c")

C_DRIVER = r'''
#define CELT_C
#include <stdio.h>
#include "entenc.c"
#include "entdec.c"
#include "entcode.c"
#include "laplace.c"
#include "quant_bands.c"
static void array(const float *x, int n) { putchar('['); for(int i=0;i<n;i++) printf("%s%.9g",i?",":"",x[i]); putchar(']'); }
int main(void) {
 int n,c,lm,start,end,bytes,prefix,intra,lfe,final;
 float decay;
 while(scanf("%d%d%d%d%d%d%d%d%f%d%d",&n,&c,&lm,&start,&end,&bytes,&prefix,&intra,&decay,&lfe,&final)==11) {
  if(n<1||n>21||c<1||c>2||bytes<0||bytes>128||start<0||end>n||start>=end||lm<0||lm>3) return 2;
  float old[42],target[42],energies[42],errors[42]={0},decoded[42]; int fine[21],previous[21],priority[21]; unsigned char data[128]={0};
  for(int i=0;i<n*c;i++) if(scanf("%f",&old[i])!=1) return 2;
  for(int i=0;i<n*c;i++) if(scanf("%f",&target[i])!=1) return 2;
  for(int i=0;i<n;i++) if(scanf("%d",&fine[i])!=1) return 2;
  for(int i=0;i<n;i++) if(scanf("%d",&previous[i])!=1) return 2;
  for(int i=0;i<n;i++) if(scanf("%d",&priority[i])!=1) return 2;
  for(int i=0;i<n*c;i++) energies[i]=decoded[i]=old[i];
  CELTMode mode={0}; mode.nbEBands=n;
  ec_enc enc; ec_enc_init(&enc,data,bytes);
  if(prefix) ec_enc_bits(&enc,0,prefix);
  intra = intra && (ec_tell(&enc)+3<=bytes*8);
  quant_coarse_energy_impl(&mode,start,end,target,energies,bytes*8,ec_tell(&enc),e_prob_model[lm][intra],errors,&enc,c,lm,intra,decay,lfe);
  printf("{\"intra\":%s,\"coarse\":",intra?"true":"false"); array(energies,n*c);
  printf(",\"coarseErrors\":"); array(errors,n*c); printf(",\"coarseBits\":%d,\"coarseRange\":%u",ec_tell(&enc),enc.rng);
  quant_fine_energy(&mode,start,end,energies,errors,previous,fine,&enc,c);
  printf(",\"fine\":"); array(energies,n*c); printf(",\"fineErrors\":"); array(errors,n*c); printf(",\"fineBits\":%d,\"fineRange\":%u",ec_tell(&enc),enc.rng);
  int count[21]; for(int i=0;i<n;i++)count[i]=fine[i]+previous[i];
  int available=bytes*8-ec_tell(&enc); if(available<0)available=0; if(final>available)final=available;
  quant_energy_finalise(&mode,start,end,energies,errors,count,priority,final,&enc,c);
  printf(",\"final\":"); array(energies,n*c); printf(",\"finalErrors\":"); array(errors,n*c); printf(",\"bits\":%d,\"range\":%u,\"finalBudget\":%d",ec_tell(&enc),enc.rng,final);
  ec_enc_done(&enc); if(enc.error) return 3;
  ec_dec dec; ec_dec_init(&dec,data,bytes); if(prefix) ec_dec_bits(&dec,prefix);
  int decodedIntra=ec_tell(&dec)+3<=bytes*8?ec_dec_bit_logp(&dec,3):0;
  unquant_coarse_energy(&mode,start,end,decoded,decodedIntra,&dec,c,lm);
  printf(",\"decodedCoarse\":"); array(decoded,n*c); printf(",\"decodedCoarseBits\":%d,\"decodedCoarseRange\":%u",ec_tell(&dec),dec.rng);
  unquant_fine_energy(&mode,start,end,decoded,previous,fine,&dec,c);
  printf(",\"decodedFine\":"); array(decoded,n*c);
  unquant_energy_finalise(&mode,start,end,decoded,count,priority,final,&dec,c);
  printf(",\"decoded\":"); array(decoded,n*c); printf(",\"decodedBits\":%d,\"decodedRange\":%u,\"bytes\":[",ec_tell(&dec),dec.rng);
  for(int i=0;i<bytes;i++) printf("%s%u",i?",":"",data[i]); puts("]}");
 }
 return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable {
 let n:Int; let c:Int; let lm:Int; let start:Int; let end:Int; let bytes:Int
 let prefix:Int; let intra:Bool; let decay:Float; let lfe:Bool; let final:Int
 let old:[Float]; let target:[Float]; let fine:[Int]; let previous:[Int]; let priority:[Int]
}
struct Output: Encodable {
 let intra:Bool; let coarse:[Float]; let coarseErrors:[Float]; let coarseBits:Int; let coarseRange:UInt32
 let fine:[Float]; let fineErrors:[Float]; let fineBits:Int; let fineRange:UInt32
 let final:[Float]; let finalErrors:[Float]; let bits:Int; let range:UInt32; let finalBudget:Int
 let decodedCoarse:[Float]; let decodedCoarseBits:Int; let decodedCoarseRange:UInt32
 let decodedFine:[Float]; let decoded:[Float]; let decodedBits:Int; let decodedRange:UInt32; let bytes:[UInt8]
}
@main struct Driver {
 /// Reads bounded development inputs and emits independent energy and entropy states as JSON.
 /// Errors terminate verification; no package dependency, device or network work occurs.
 static func main() throws {
  while let line=readLine() {
   let x=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   let q=try CELTEnergyQuantizer(frameSampleCount:120 << x.lm,channelCount:x.c,bandCount:x.n,startBand:x.start,endBand:x.end)
   var encoder=try OpusRangeEncoder(frameByteCount:x.bytes)
   if x.prefix>0 { try encoder.encodeRawBits(0,count:x.prefix) }
   let coarse=try q.encodeCoarse(target:x.target,previous:x.old,intra:x.intra,maximumDecay:x.decay,lowFrequencyEffects:x.lfe,into:&encoder)
   let coarseBits=encoder.bitsUsed, coarseRange=encoder.finalRange
   let fine=try q.encodeFine(coarse,bitCounts:x.fine,previousBitCounts:x.previous,into:&encoder)
   let fineBits=encoder.bitsUsed, fineRange=encoder.finalRange
   let finalBudget=min(x.final,max(0,x.bytes*8-encoder.bitsUsed))
   let final=try q.encodeFinal(fine,fineBitCounts:zip(x.fine,x.previous).map(+),priorities:x.priority,remainingBits:finalBudget,into:&encoder)
   let bits=encoder.bitsUsed, range=encoder.finalRange
   let data=try encoder.finalize()
   var decoder=try OpusRangeDecoder(frame:data)
   if x.prefix>0 { _=try decoder.decodeRawBits(count:x.prefix) }
   let decodedCoarse=try q.decodeCoarse(previous:x.old,from:&decoder)
   let decodedCoarseBits=decoder.bitsUsed, decodedCoarseRange=decoder.finalRange
   let decodedFine=try q.decodeFine(energies:decodedCoarse.energies,bitCounts:x.fine,previousBitCounts:x.previous,from:&decoder)
   let decoded=try q.decodeFinal(energies:decodedFine,fineBitCounts:zip(x.fine,x.previous).map(+),priorities:x.priority,remainingBits:finalBudget,from:&decoder)
   let output=Output(intra:coarse.intra,coarse:coarse.energies,coarseErrors:coarse.errors,coarseBits:coarseBits,coarseRange:coarseRange,fine:fine.energies,fineErrors:fine.errors,fineBits:fineBits,fineRange:fineRange,final:final.energies,finalErrors:final.errors,bits:bits,range:range,finalBudget:finalBudget,decodedCoarse:decodedCoarse.energies,decodedCoarseBits:decodedCoarseBits,decodedCoarseRange:decodedCoarseRange,decodedFine:decodedFine,decoded:decoded,decodedBits:decoder.bitsUsed,decodedRange:decoder.finalRange,bytes:Array(data))
   print(String(decoding:try JSONEncoder().encode(output),as:UTF8.self))
  }
 }
}
'''

def float32(value):
    """Round once to each driver's scalar float input representation."""
    return struct.unpack("f", struct.pack("f", value))[0]


def context(n=21, c=1, lm=0, start=0, end=None, byte_count=64, prefix=0,
            intra=False, decay=16, lfe=False, final=12):
    """Build bounded deterministic energy inputs with all public per-band decisions explicit."""
    return dict(n=n, c=c, lm=lm, start=start, end=end if end is not None else n,
                bytes=byte_count, prefix=prefix, intra=intra, decay=decay, lfe=lfe, final=final,
                old=[float32((i % 11 - 6) * 0.75) for i in range(n * c)],
                target=[float32((i % 13 - 6) * 0.625) for i in range(n * c)],
                fine=[i % 4 for i in range(n)], previous=[0] * n,
                priority=[i % 2 for i in range(n)])


def fixed_cases():
    """Cover all 168 Laplace contexts, modes/channels, scarce budgets and refinement branches."""
    result = [context(c=c, lm=lm, intra=intra) for lm in range(4)
              for intra in (False, True) for c in (1, 2)]
    for size in (0, 1, 2, 3, 4, 8):
        result.append(context(n=6, c=2, byte_count=size, intra=True, final=0))
    for remaining in (0, 1, 2, 3, 14, 15):
        # Start the coarse call after an artificial raw prefix to isolate admission boundaries.
        size = 2
        prefix = max(0, 15 - remaining)
        item = context(n=3, byte_count=size, prefix=prefix, final=0)
        # At sub-three-bit budgets no header fits. Keep first residual in the canonical {-1,0} path.
        item["old"] = [0] * 3
        item["target"] = [-0.75, 0.25, -0.5]
        result.append(item)
    result.append(context(c=2, lm=3, start=17, intra=True, lfe=True))
    result.append(context(c=2, lm=2, start=3, end=15, decay=0, lfe=True))
    fine_extremes = context(n=4, c=2, lm=1, final=16)
    fine_extremes["fine"] = [8, 0, 4, 2]
    fine_extremes["previous"] = [0, 8, 4, 5]
    fine_extremes["priority"] = [0, 0, 1, 1]
    result.append(fine_extremes)
    for values in ([80, -80, 0, 80], [-80, 80, -80, 0]):
        item = context(n=4, byte_count=64, intra=True, decay=128)
        item["old"] = [-12, 0, -9, 9]
        item["target"] = values
        result.append(item)
    return result


def random_cases(count, seed):
    """Generate reproducible finite contexts without relying on the Swift implementation."""
    rng = random.Random(seed)
    result = []
    for _ in range(count):
        n, c = rng.randint(1, 21), rng.randint(1, 2)
        start = rng.randrange(n)
        size = rng.randint(0, 96)
        item = context(n=n, c=c, lm=rng.randrange(4), start=start,
                       end=rng.randint(start + 1, n), byte_count=size,
                       prefix=rng.randint(0, min(7, max(0, size * 8 - 1))),
                       intra=bool(rng.randrange(2)), decay=rng.choice([0, 4, 16, 28, 128]),
                       lfe=bool(rng.randrange(2)), final=rng.randint(0, 40))
        item["old"] = [float32(rng.uniform(-16, 12)) for _ in range(n * c)]
        item["target"] = [float32(rng.uniform(-20, 16)) for _ in range(n * c)]
        if size <= 4:
            # Avoid upstream helper's noncanonical one-bit bookkeeping for scarce first bands.
            item["old"] = [0] * (n * c)
            item["target"] = [-0.5] * (n * c)
        item["fine"] = [rng.randrange(9) for _ in range(n)]
        item["previous"] = [rng.randint(0, 8 - f) for f in item["fine"]]
        item["priority"] = [rng.randrange(2) for _ in range(n)]
        result.append(item)
    return result


def commands(inputs):
    """Serialize validated verifier-generated contexts for the independent C driver."""
    lines = []
    for x in inputs:
        fields = [x[k] for k in ("n", "c", "lm", "start", "end", "bytes", "prefix")]
        fields += [int(x["intra"]), x["decay"], int(x["lfe"]), x["final"]]
        for key in ("old", "target", "fine", "previous", "priority"):
            fields += x[key]
        lines.append(" ".join(map(str, fields)))
    return "\n".join(lines).encode()


def compare_results(inputs, expected, actual):
    """Require exact wire/range/accounting and float-accurate all-pass prediction/residuals."""
    if len(inputs) != len(expected) or len(inputs) != len(actual):
        raise ValueError("case count mismatch")
    arrays = {"coarse", "coarseErrors", "fine", "fineErrors", "final", "finalErrors",
              "decodedCoarse", "decodedFine", "decoded"}
    for index, (x, e, a) in enumerate(zip(inputs, expected, actual)):
        exact = {"intra", "coarseBits", "coarseRange", "fineBits", "fineRange", "bits", "range",
                 "finalBudget", "decodedCoarseBits", "decodedCoarseRange", "decodedBits", "decodedRange", "bytes"}
        for result in (e, a):
            if set(result) != arrays | exact:
                raise ValueError(f"case {index}: output schema differs")
            if any(len(result[k]) != x["n"] * x["c"] or any(not math.isfinite(v) for v in result[k]) for k in arrays):
                raise ValueError(f"case {index}: invalid envelope shape or finiteness")
            if len(result["bytes"]) != x["bytes"] or any(type(v) is not int or not 0 <= v <= 255 for v in result["bytes"]):
                raise ValueError(f"case {index}: invalid frame bytes")
            if any(type(result[k]) is not int or not 0 < result[k] <= 0xffffffff for k in exact if k.endswith("Range") or k == "range"):
                raise ValueError(f"case {index}: invalid arithmetic range")
            if any(type(result[k]) is not int or not 1 <= result[k] <= max(1, x["bytes"] * 8) for k in exact if k.endswith("Bits") or k == "bits"):
                raise ValueError(f"case {index}: invalid bit accounting")
            if type(result["intra"]) is not bool or not 0 <= result["finalBudget"] <= max(0, x["bytes"] * 8 - result["fineBits"]):
                raise ValueError(f"case {index}: invalid header or final budget")
            if result["coarseRange"] != result["decodedCoarseRange"] or result["range"] != result["decodedRange"] or result["bits"] != result["decodedBits"]:
                raise ValueError(f"case {index}: encoder/decoder entropy states disagree")
            for encoded, decoded in (("coarse", "decodedCoarse"), ("fine", "decodedFine"), ("final", "decoded")):
                if any(abs(v - w) > 2e-5 for v, w in zip(result[encoded], result[decoded])):
                    raise ValueError(f"case {index}: encoder/decoder envelopes disagree")
        for key in e:
            if key in arrays:
                if len(e[key]) != len(a[key]) or any(not math.isfinite(v) or abs(v - w) > 2e-5
                                                    for v, w in zip(a[key], e[key])):
                    raise ValueError(f"case {index} {key}: {a[key]} != {e[key]}; input={x}")
            elif e[key] != a[key]:
                raise ValueError(f"case {index} {key}: {a[key]} != {e[key]}; input={x}")


def main():
    """Run explicit development-only compilation and bounded comparisons; optionally refresh fixtures."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=6716432)
    parser.add_argument("--write-fixtures", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error("--cases must be 1...10000 and seed must be nonnegative")
    repository = args.repository.resolve()
    fixed = fixed_cases()
    inputs = fixed + random_cases(args.cases, args.seed)
    with tempfile.TemporaryDirectory(prefix="discordkit-celt-energy-", dir="/private/tmp") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        c_driver, swift_driver = directory / "oracle.c", directory / "driver.swift"
        c_driver.write_text(C_DRIVER)
        swift_driver.write_text(SWIFT_DRIVER)
        reference, owned = directory / "oracle", directory / "owned"
        run(["cc", "-O2", "-ffp-contract=off", "-DOPUS_BUILD", "-DVAR_ARRAYS", "-Wl,-dead_strip",
             "-I" + str(upstream / "include"), "-I" + str(upstream / "celt"),
             "-I" + str(upstream / "silk"), str(c_driver), "-lm", "-o", str(reference)])
        run(["swiftc", "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated"]
            + [str(repository / path) for path in OWNED_PATHS] + [str(swift_driver), "-o", str(owned)])
        expected = parse_outputs(run([str(reference)], commands(inputs)), len(inputs), "Official energy driver")
        actual = parse_outputs(run([str(owned)], "\n".join(map(json.dumps, inputs)).encode()), len(inputs), "Owned energy driver")
        compare_results(inputs, expected, actual)
        records = [{"input": x, "output": e} for x, e in zip(fixed, expected)]
        fixture = repository / FIXTURE_PATH
        if args.write_fixtures:
            fixture.write_text('/// Independent libopus 1.6.1 envelope fixtures, refreshed only by the opt-in verifier.\n'
                               'enum CELTEnergyOracleFixtures {\n    static let json = #"""\n'
                               + json.dumps(records, separators=(",", ":")) + '\n"""#\n}\n')
        if not fixture.exists():
            raise ValueError("missing fixture; use --write-fixtures")
        fixture_json = fixture.read_text().split('#"""', 1)[1].split('"""#', 1)[0]
        if json.loads(fixture_json) != records:
            raise ValueError("committed fixtures differ; review and use --write-fixtures")
        report = {"verifiedAt": datetime.now(timezone.utc).isoformat(), "scope": "CELT energy component only",
                  "version": VERSION, "releaseURL": RELEASE_URL, "sourceURL": SOURCE_URL,
                  "archiveSHA256": ARCHIVE_SHA256, "seed": args.seed, "randomCases": args.cases,
                  "fixedCases": len(fixed), "totalCases": len(inputs), "floatTolerance": 2e-5,
                  "exact": ["encoded bytes", "range", "whole-bit accounting", "intra selection"],
                  "compatibilityDecision": "One-bit encoder fallback clamps reconstruction to canonical decoder -1/0; unlike upstream helper for out-of-domain residuals.",
                  "oracleInputLimit": "Very scarce first-band reference residuals are canonical; Swift separately tests extreme one-bit residuals.",
                  "excluded": ["full Opus codec", "PLC/FEC", "official decoded-PCM conformance", "devices", "realtime"],
                  "ownedSources": {p: digest(repository / p) for p in OWNED_PATHS},
                  "upstreamSources": {p: digest(upstream / p) for p in UPSTREAM_PATHS},
                  "fixture": {"path": FIXTURE_PATH, "sha256": digest(fixture)},
                  "verifierSHA256": digest(Path(__file__)),
                  "ccVersion": run(["cc", "--version"]).decode().splitlines()[0],
                  "swiftVersion": run(["swiftc", "--version"]).decode().splitlines()[0]}
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

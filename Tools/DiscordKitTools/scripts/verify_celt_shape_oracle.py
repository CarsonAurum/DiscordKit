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
               "Sources/DiscordVoiceCodecs/CELTPulseCodebook.swift",
               "Sources/DiscordVoiceCodecs/CELTBandQuantizer.swift",
               "Sources/DiscordVoiceCodecs/CELTAllocationTables.swift",
               "Sources/DiscordVoiceCodecs/CELTBitAllocation.swift",
               "Sources/DiscordVoiceCodecs/CELTShapeTables.swift",
               "Sources/DiscordVoiceCodecs/CELTShapeCoding.swift")
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/CELTShapeOracleFixtures.swift"
UPSTREAM_PATHS = ("celt/bands.c", "celt/vq.c", "celt/rate.h", "celt/mathops.h",
                  "celt/mathops.c", "celt/static_modes_float.h", "celt/cwrs.c",
                  "celt/entenc.c", "celt/entdec.c", "celt/entcode.c")

C_DRIVER = r'''
#define CELT_C
#include <stdio.h>
#include "entenc.c"
#include "entdec.c"
#include "entcode.c"
#include "mathops.c"
#include "cwrs.c"
#include "vq.c"
#include "modes.c"
#include "bands.c"
static void array(const float *x,int n) { putchar('[');for(int i=0;i<n;i++)printf("%s%.9g",i?",":"",x[i]);putchar(']'); }
int main(void) {
 int band,lm,c,transient,tf,spread,intensity,disable,avoid,round,bytes,b,remaining,fill,haslow; unsigned seed;
 while(scanf("%d%d%d%d%d%d%d%d%d%d%d%d%d%u%d%d",&band,&lm,&c,&transient,&tf,&spread,&intensity,&disable,&avoid,&round,&bytes,&b,&remaining,&seed,&fill,&haslow)==16) {
  if(band<0||band>20||lm<0||lm>3||c<1||c>2||bytes<0||bytes>1275) return 2;
  const CELTMode *mode=opus_custom_mode_create(48000,960,NULL);
  int n=(mode->eBands[band+1]-mode->eBands[band])<<lm,blocks=transient?1<<lm:1;
  float x[176],y[176],dx[176]={0},dy[176]={0},low[176],dlo[176],fold[176]={0},dfold[176]={0},scratch[176],energy[42]={0};
  float l,r; if(scanf("%f%f",&l,&r)!=2)return 2;energy[band]=l;energy[21+band]=r;
  for(int j=0;j<n;j++)if(scanf("%f",&x[j])!=1)return 2;
  if(c==2)for(int j=0;j<n;j++)if(scanf("%f",&y[j])!=1)return 2;
  if(haslow)for(int j=0;j<n;j++){if(scanf("%f",&low[j])!=1)return 2;dlo[j]=low[j];}
  unsigned char data[1275]={0};ec_enc enc;ec_enc_init(&enc,data,bytes);
  struct band_ctx ctx={0};ctx.encode=1;ctx.resynth=1;ctx.m=mode;ctx.i=band;ctx.intensity=intensity;ctx.spread=spread;ctx.tf_change=tf;ctx.ec=&enc;ctx.remaining_bits=remaining;ctx.bandE=energy;ctx.seed=seed;ctx.theta_round=round;ctx.disable_inv=disable;ctx.avoid_split_noise=avoid;
  unsigned mask=c==2?quant_band_stereo(&ctx,x,y,n,b,blocks,haslow?low:NULL,lm,fold,scratch,fill):quant_band(&ctx,x,n,b,blocks,haslow?low:NULL,lm,fold,1,scratch,fill);
  printf("{\"coefficients\":");float combined[352];for(int j=0;j<n;j++)combined[j]=x[j];if(c==2)for(int j=0;j<n;j++)combined[n+j]=y[j];array(combined,n*c);
  printf(",\"folding\":");array(fold,n);printf(",\"mask\":%u,\"remaining\":%d,\"seed\":%u,\"range\":%u,\"bits\":%d,\"fraction\":%u",mask,ctx.remaining_bits,ctx.seed,enc.rng,ec_tell(&enc),ec_tell_frac(&enc));
  ec_enc_done(&enc);if(enc.error)return 3;
  ec_dec dec;ec_dec_init(&dec,data,bytes);ctx.encode=0;ctx.ec=&dec;ctx.remaining_bits=remaining;ctx.seed=seed;
  unsigned dmask=c==2?quant_band_stereo(&ctx,dx,dy,n,b,blocks,haslow?dlo:NULL,lm,dfold,scratch,fill):quant_band(&ctx,dx,n,b,blocks,haslow?dlo:NULL,lm,dfold,1,scratch,fill);
  for(int j=0;j<n;j++)combined[j]=dx[j];if(c==2)for(int j=0;j<n;j++)combined[n+j]=dy[j];
  printf(",\"decoded\":");array(combined,n*c);printf(",\"decodedFolding\":");array(dfold,n);
  printf(",\"decodedMask\":%u,\"decodedRemaining\":%d,\"decodedSeed\":%u,\"decodedRange\":%u,\"decodedBits\":%d,\"decodedFraction\":%u,\"bytes\":[",dmask,ctx.remaining_bits,ctx.seed,dec.rng,ec_tell(&dec),ec_tell_frac(&dec));
  for(int j=0;j<bytes;j++)printf("%s%u",j?",":"",data[j]);puts("]}");
 }
 return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable {
 let band:Int; let lm:Int; let c:Int; let transient:Bool; let tf:Int; let spread:Int
 let intensity:Int; let disable:Bool; let avoid:Bool; let round:Int; let bytes:Int; let b:Int
 let remaining:Int; let seed:UInt32; let fill:UInt8; let energy:[Float]; let x:[Float]; let low:[Float]?
}
struct Output: Encodable {
 let coefficients:[Float];let folding:[Float];let mask:UInt8;let remaining:Int;let seed:UInt32
 let range:UInt32;let bits:Int;let fraction:Int
 let decoded:[Float];let decodedFolding:[Float];let decodedMask:UInt8;let decodedRemaining:Int
 let decodedSeed:UInt32;let decodedRange:UInt32;let decodedBits:Int;let decodedFraction:Int;let bytes:[UInt8]
}
@main struct Driver {
 /// Reads bounded offline development contexts and emits independent per-band coding states.
 /// Errors stop verification; no native codec, device, live endpoint or package graph is adopted.
 static func main() throws {
  while let line=readLine() {
   let x=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   let q=try CELTShapeCoding(frameSampleCount:120 << x.lm,bandIndex:x.band,channelCount:x.c,transient:x.transient,timeFrequencyChange:x.tf,spreading:CELTSpreading(rawValue:x.spread)!,intensityBand:x.intensity,disableInversion:x.disable,avoidSplitNoise:x.avoid,thetaRounding:x.round)
   var encoder=try OpusRangeEncoder(frameByteCount:x.bytes)
   let value=try q.encode(x.x,allocationEighthBits:x.b,remainingEighthBits:x.remaining,seed:x.seed,folding:x.low,fillMask:x.fill,bandEnergies:Array(x.energy.prefix(x.c)),into:&encoder)
   let range=encoder.finalRange,bits=encoder.bitsUsed,fraction=encoder.fractionalBitsUsed
   let data=try encoder.finalize()
   var decoder=try OpusRangeDecoder(frame:data)
   let decoded=try q.decode(allocationEighthBits:x.b,remainingEighthBits:x.remaining,seed:x.seed,folding:x.low,fillMask:x.fill,from:&decoder)
   print(String(decoding:try JSONEncoder().encode(Output(coefficients:value.coefficients,folding:value.folding,mask:value.collapseMask,remaining:value.remainingEighthBits,seed:value.seed,range:range,bits:bits,fraction:fraction,decoded:decoded.coefficients,decodedFolding:decoded.folding,decodedMask:decoded.collapseMask,decodedRemaining:decoded.remainingEighthBits,decodedSeed:decoded.seed,decodedRange:decoder.finalRange,decodedBits:decoder.bitsUsed,decodedFraction:decoder.fractionalBitsUsed,bytes:Array(data))),as:UTF8.self))
  }
 }
}
'''

BAND_EDGES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 34, 40, 48, 60, 78, 100]
NORMAL_TF = [[0, -1], [0, -1, -2], [0, -2, -3], [0, -2, -3]]
TRANSIENT_TF = [[0, -1], [1, 0, -1], [2, 0, 1, -1], [3, 0, 1, -1]]


def float32(value):
    """Round a context coefficient exactly once to the scalar float driver representation."""
    return struct.unpack("f", struct.pack("f", value))[0]


def context(band=20, lm=3, c=1, b=1024, transient=False, tf=0, spread=2,
            intensity=21, disable=False, avoid=False, rounding=0, byte_count=128,
            seed=0xdeadbeef, fill=None, low=None, energy=None):
    """Build a bounded ordinary per-band shape context with deterministic unit channel norms."""
    n = (BAND_EDGES[band + 1] - BAND_EDGES[band]) << lm
    coefficients = []
    for channel in range(c):
        raw = [math.sin(i * .419 + channel * .837 + .5) for i in range(n)]
        scale = .999999 / math.sqrt(sum(x*x for x in raw))
        coefficients += [float32(x * scale) for x in raw]
    return dict(band=band, lm=lm, c=c, transient=transient, tf=tf, spread=spread,
                intensity=intensity, disable=disable, avoid=avoid, round=rounding,
                bytes=byte_count, b=b, remaining=max(0, byte_count * 64 - 8), seed=seed,
                fill=fill if fill is not None else (1 << ((1 << lm) if transient else 1)) - 1,
                energy=energy or [1, 1], x=coefficients, low=low)


def systematic_cases():
    """Cover every ordinary band/duration/channel across zero, sparse and recursive budgets."""
    return [context(band, lm, c, b) for lm in range(4) for band in range(21)
            for c in (1, 2) for b in (0, 64, 128, 256, 512, 1024)]


def fixed_cases():
    """Literal fixtures cover recursive/stereo branches and every valid TF mapping."""
    result = [context(band, lm, c, 512) for lm in range(4) for band in (0, 20) for c in (1, 2)]
    for lm in range(4):
        for transient, changes in ((False, NORMAL_TF[lm]), (True, TRANSIENT_TF[lm])):
            for tf in changes:
                result.append(context(12, lm, 2, 256, transient=transient, tf=tf,
                                      spread=(tf + 4) % 4, avoid=transient))
    for c in (1, 2):
        for fill in (0, 1):
            result.append(context(8, 0, c, 0, low=[.5, -.25], fill=fill))
    for rounding in (-1, 1):
        result.append(context(20, 3, 2, 1024, rounding=rounding))
    for disable in (False, True):
        x = context(12, 1, 2, 64, intensity=0, disable=disable)
        n = len(x["x"]) // 2
        x["x"][n:] = [-v for v in x["x"][:n]]
        result.append(x)
    result.append(context(20, 3, 2, 1024, energy=[0, 1]))
    scarce = context(9, 3, 2, 1, transient=True, tf=-1, byte_count=0, fill=66,
                     low=[float32(math.sin(i * .7)) for i in range(16)])
    result.append(scarce)
    return result


def random_cases(count, seed):
    """Generate seeded valid contexts with scarce budgets, folding, zero/collinear channels and RDO angles."""
    rng = random.Random(seed)
    result = []
    for _ in range(count):
        band, lm, c = rng.randrange(21), rng.randrange(4), rng.randint(1, 2)
        transient = bool(rng.randrange(2))
        tf = rng.choice((TRANSIENT_TF if transient else NORMAL_TF)[lm])
        byte_count = rng.randint(0, 128)
        capacity = max(0, byte_count * 64 - 8)
        budget = rng.randint(0, min(16383, capacity + 1, 2048))
        x = context(band, lm, c, budget, transient=transient, tf=tf, spread=rng.randrange(4),
                    intensity=rng.randint(0, 21), disable=bool(rng.randrange(2)),
                    avoid=bool(rng.randrange(2)), rounding=rng.randint(-1, 1),
                    byte_count=byte_count, seed=rng.randrange(2**32))
        n = len(x["x"]) // c
        x["remaining"] = rng.randint(max(0, budget - 1), capacity)
        x["fill"] = rng.randrange(1 << ((1 << lm) if transient else 1))
        if rng.randrange(3) == 0:
            x["low"] = [float32(rng.uniform(-2, 2)) for _ in range(n)]
        kind = rng.randrange(10)
        if kind == 0:
            x["x"] = [0] * (n * c)
        elif kind in (1, 2) and c == 2:
            x["x"][n:] = [v * (-1 if kind == 2 else 1) for v in x["x"][:n]]
        else:
            x["x"] = []
            for _ in range(c):
                raw = [rng.uniform(-1, 1) for _ in range(n)]
                scale = .999999 / math.sqrt(sum(v*v for v in raw))
                x["x"] += [float32(v * scale) for v in raw]
        if rng.randrange(8) == 0:
            x["energy"][rng.randrange(2)] = 0
        result.append(x)
    return result


def commands(inputs):
    """Serialize validated generated contexts for the independent C source wrapper."""
    lines = []
    for x in inputs:
        fields = [x[k] for k in ("band", "lm", "c")]
        fields += [int(x["transient"]), x["tf"], x["spread"], x["intensity"], int(x["disable"]),
                   int(x["avoid"]), x["round"], x["bytes"], x["b"], x["remaining"], x["seed"],
                   x["fill"], int(x["low"] is not None)]
        fields += x["energy"] + x["x"] + (x["low"] or [])
        lines.append(" ".join(map(str, fields)))
    return "\n".join(lines).encode()


def compare_results(inputs, expected, actual):
    """Require exact entropy/control evidence and bounded scalar reconstruction error."""
    if len(inputs) != len(expected) or len(inputs) != len(actual):
        raise ValueError("case count mismatch")
    arrays = {"coefficients", "folding", "decoded", "decodedFolding"}
    exact = {"mask", "remaining", "seed", "range", "bits", "fraction", "decodedMask",
             "decodedRemaining", "decodedSeed", "decodedRange", "decodedBits", "decodedFraction", "bytes"}
    for index, (x, e, a) in enumerate(zip(inputs, expected, actual)):
        n = (BAND_EDGES[x["band"] + 1] - BAND_EDGES[x["band"]]) << x["lm"]
        blocks = (1 << x["lm"]) if x["transient"] else 1
        for result in (e, a):
            if set(result) != arrays | exact:
                raise ValueError(f"case {index}: output schema differs")
            for key in arrays:
                length = n * x["c"] if key in ("coefficients", "decoded") else n
                if len(result[key]) != length or any(not math.isfinite(v) for v in result[key]):
                    raise ValueError(f"case {index}: invalid {key} shape or finiteness")
            if len(result["bytes"]) != x["bytes"] or any(type(v) is not int or not 0 <= v <= 255 for v in result["bytes"]):
                raise ValueError(f"case {index}: invalid frame bytes")
            if not 0 <= result["mask"] < 1 << blocks or result["mask"] != result["decodedMask"]:
                raise ValueError(f"case {index}: invalid/mismatching occupancy")
            for first, second in (("range", "decodedRange"), ("bits", "decodedBits"),
                                  ("fraction", "decodedFraction"), ("remaining", "decodedRemaining"), ("seed", "decodedSeed")):
                if result[first] != result[second]:
                    raise ValueError(f"case {index}: encoder/decoder {first} disagreement")
            if not 0 < result["range"] <= 0xffffffff or not 0 <= result["seed"] <= 0xffffffff:
                raise ValueError(f"case {index}: invalid unsigned state")
            for first, second in (("coefficients", "decoded"), ("folding", "decodedFolding")):
                if any(abs(v - w) > 3e-5 for v, w in zip(result[first], result[second])):
                    raise ValueError(f"case {index}: encoder/decoder spectra disagreement")
        for key in e:
            if key in arrays:
                if any(abs(v - w) > 3e-5 for v, w in zip(e[key], a[key])):
                    raise ValueError(f"case {index} {key}: scalar tolerance exceeded; input={x}")
            elif e[key] != a[key]:
                raise ValueError(f"case {index} {key}: {a[key]} != {e[key]}; input={x}")


def main():
    """Compile only on explicit invocation, compare bounded cases and optionally refresh literal fixtures."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cases", type=int, default=5000)
    parser.add_argument("--seed", type=int, default=6716434)
    parser.add_argument("--write-fixtures", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error("--cases must be 1...10000 and seed must be nonnegative")
    repository = args.repository.resolve()
    fixed, systematic = fixed_cases(), systematic_cases()
    inputs = fixed + systematic + random_cases(args.cases, args.seed)
    with tempfile.TemporaryDirectory(prefix="discordkit-celt-shape-", dir="/private/tmp") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        c_driver, swift_driver = directory / "oracle.c", directory / "driver.swift"
        c_driver.write_text(C_DRIVER); swift_driver.write_text(SWIFT_DRIVER)
        reference, owned = directory / "oracle", directory / "owned"
        run(["cc", "-O2", "-ffp-contract=off", "-DOPUS_BUILD", "-DVAR_ARRAYS", "-Wl,-dead_strip",
             "-I" + str(upstream / "include"), "-I" + str(upstream / "celt"),
             "-I" + str(upstream / "silk"), str(c_driver), "-lm", "-o", str(reference)])
        run(["swiftc", "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated"]
            + [str(repository / p) for p in OWNED_PATHS] + [str(swift_driver), "-o", str(owned)])
        expected = parse_outputs(run([str(reference)], commands(inputs)), len(inputs), "Official shape driver")
        actual = parse_outputs(run([str(owned)], "\n".join(map(json.dumps, inputs)).encode()), len(inputs), "Owned shape driver")
        compare_results(inputs, expected, actual)
        records = [{"input": x, "output": e} for x, e in zip(fixed, expected)]
        fixture = repository / FIXTURE_PATH
        if args.write_fixtures:
            fixture.write_text('/// Independent libopus 1.6.1 recursive shape fixtures; refreshed only by the opt-in verifier.\n'
                               'enum CELTShapeOracleFixtures {\n    static let json = #"""\n'
                               + json.dumps(records, separators=(",", ":")) + '\n"""#\n}\n')
        if not fixture.exists() or json.loads(fixture.read_text().split('#"""', 1)[1].split('"""#', 1)[0]) != records:
            raise ValueError("fixture missing/different; review and explicitly --write-fixtures")
        report = {"verifiedAt": datetime.now(timezone.utc).isoformat(), "scope": "CELT recursive per-band shape component only",
                  "version": VERSION, "releaseURL": RELEASE_URL, "sourceURL": SOURCE_URL,
                  "archiveSHA256": ARCHIVE_SHA256, "seed": args.seed, "randomCases": args.cases,
                  "fixedCases": len(fixed), "systematicCases": len(systematic), "totalCases": len(inputs),
                  "floatTolerance": 3e-5, "exact": ["bytes", "range", "whole/fractional bit use", "masks", "seed", "remaining bits"],
                  "excluded": ["full Opus codec", "all-band orchestration", "anti-collapse", "PLC/FEC", "official decoded-PCM conformance", "device/realtime"],
                  "ownedSources": {p: digest(repository / p) for p in OWNED_PATHS},
                  "upstreamSources": {p: digest(upstream / p) for p in UPSTREAM_PATHS},
                  "fixture": {"path": FIXTURE_PATH, "sha256": digest(fixture)},
                  "verifierSHA256": digest(Path(__file__)),
                  "ccVersion": run(["cc", "--version"]).decode().splitlines()[0],
                  "swiftVersion": run(["swiftc", "--version"]).decode().splitlines()[0]}
        if args.report: args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

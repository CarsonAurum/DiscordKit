#!/usr/bin/env python3
"""Opt-in offline CELT bit-allocation verification against unmodified libopus 1.6.1.

The separately supplied archive is pinned, bounded and path-validated by the shared
entropy verifier. Consumer builds never fetch or compile it. This compares ordinary
caps, all allocation outputs, skip/stereo syntax, encoded bytes and exact entropy
state; arbitrary bytes also exercise the mandatory decoder independently of the
owned encoder. It supplies no full codec, PCM, PLC/FEC or realtime/device evidence.
"""
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

OWNED_PATHS = ("Sources/DiscordVoiceCodecs/OpusRangeCoding.swift",
               "Sources/DiscordVoiceCodecs/CELTAllocationTables.swift",
               "Sources/DiscordVoiceCodecs/CELTBitAllocation.swift")
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/CELTAllocationOracleFixtures.swift"
UPSTREAM_PATHS = ("celt/rate.c", "celt/modes.c", "celt/static_modes_float.h", "celt/celt.c",
                  "celt/entenc.c", "celt/entdec.c", "celt/entcode.c")
C_DRIVER = r'''
#define CELT_C
#include <stdio.h>
#include "entenc.c"
#include "entdec.c"
#include "entcode.c"
#include "modes.c"
#include "rate.c"
static void array(const int *x) { putchar('['); for(int i=0;i<21;i++) printf("%s%d",i?",":"",x[i]); putchar(']'); }
static void output(int *shape,int *fine,int *priority,int balance,int coded,int intensity,int dual,ec_ctx *ec) {
 printf("{\"shape\":");array(shape);printf(",\"fine\":");array(fine);printf(",\"priorities\":");array(priority);
 printf(",\"balance\":%d,\"coded\":%d,\"intensity\":%d,\"dual\":%s,\"bits\":%d,\"frac\":%u,\"range\":%u}",balance,coded,intensity,dual?"true":"false",ec_tell(ec),ec_tell_frac(ec),ec->rng);
}
int main(void) {
 int lm,c,start,end,trim,total,bytes,prefix,intensity,dual,prev,bandwidth;
 while(scanf("%d%d%d%d%d%d%d%d%d%d%d%d",&lm,&c,&start,&end,&trim,&total,&bytes,&prefix,&intensity,&dual,&prev,&bandwidth)==12) {
  if(lm<0||lm>3||c<1||c>2||start<0||end>21||start>=end||trim<0||trim>10||bytes<8||bytes>64) return 2;
  int offsets[21],caps[21],shape[21]={0},fine[21]={0},priority[21]={0},balance=0,coded;
  unsigned char data[64]={0},arbitrary[64]={0}; unsigned value;
  for(int i=0;i<21;i++) if(scanf("%d",&offsets[i])!=1) return 2;
  for(int i=0;i<bytes;i++){ if(scanf("%u",&value)!=1||value>255)return 2; arbitrary[i]=(unsigned char)value; }
  const CELTMode *m=&mode48000_960_120;
  for(int i=0;i<21;i++){int n=(m->eBands[i+1]-m->eBands[i])<<lm;caps[i]=(m->cache.caps[21*(2*lm+c-1)+i]+64)*c*n>>2;}
  ec_enc enc;ec_enc_init(&enc,data,bytes);if(prefix)ec_enc_bits(&enc,0,prefix);
  coded=clt_compute_allocation(m,start,end,offsets,caps,trim,&intensity,&dual,total,&balance,shape,fine,priority,c,lm,&enc,1,prev,bandwidth);
  printf("{\"caps\":");array(caps);printf(",\"encoded\":");output(shape,fine,priority,balance,coded,intensity,dual,&enc);
  ec_enc_done(&enc);if(enc.error)return 3;
  printf(",\"bytes\":[");for(int i=0;i<bytes;i++)printf("%s%u",i?",":"",data[i]);putchar(']');
  for(int kind=0;kind<2;kind++) {
   for(int i=0;i<21;i++)shape[i]=fine[i]=priority[i]=0;
   ec_dec dec;ec_dec_init(&dec,kind?arbitrary:data,bytes);if(prefix)ec_dec_bits(&dec,prefix);
   intensity=dual=0;
   coded=clt_compute_allocation(m,start,end,offsets,caps,trim,&intensity,&dual,total,&balance,shape,fine,priority,c,lm,&dec,0,0,0);
   if(dec.error)return 4;
   printf(kind?",\"arbitrary\":":",\"decoded\":");output(shape,fine,priority,balance,coded,intensity,dual,&dec);
  }
  puts("}");
 }
 return 0;
}
'''
SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable {
 let lm:Int;let c:Int;let start:Int;let end:Int;let trim:Int;let total:Int;let bytes:Int
 let prefix:Int;let intensity:Int;let dual:Bool;let offsets:[Int];let arbitrary:[UInt8];let limit:Int
}
struct Allocation: Encodable {
 let shape:[Int];let fine:[Int];let priorities:[Int];let balance:Int;let coded:Int;let intensity:Int;let dual:Bool
 let bits:Int;let frac:Int;let range:UInt32
 /// Projects an owned allocation and exact coder snapshot into the independent oracle schema.
 /// - Parameters:
 ///   - result: Completed allocation; its bounded arrays are copied by value.
 ///   - bits: Whole-bit usage after allocation.
 ///   - frac: Eighth-bit usage after allocation.
 ///   - range: Final arithmetic range before finalization.
 init(_ result:CELTBitAllocationResult,bits:Int,frac:Int,range:UInt32) {
  shape=result.shapeEighthBits;fine=result.fineEnergyBits;priorities=result.finePriorities
  balance=result.balanceEighthBits;coded=result.codedBandEnd;intensity=result.intensityBand;dual=result.dualStereo
  self.bits=bits;self.frac=frac;self.range=range
 }
}
struct Output: Encodable {let caps:[Int];let encoded:Allocation;let decoded:Allocation;let arbitrary:Allocation;let bytes:[UInt8]}
@main struct Driver {
 /// Processes bounded development-only JSON inputs; failures abort independent verification.
 static func main() throws {
  while let line=readLine() {
   let x=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   let q=try CELTBitAllocation(frameSampleCount:120 << x.lm,channelCount:x.c,startBand:x.start,endBand:x.end,allocationTrim:x.trim)
   var enc=try OpusRangeEncoder(frameByteCount:x.bytes)
   if x.prefix>0 {try enc.encodeRawBits(0,count:x.prefix)}
   let result=try q.encode(totalEighthBits:x.total,dynamicOffsets:x.offsets,codedBandLimit:x.limit,intensityBand:x.intensity,dualStereo:x.dual,into:&enc)
   let encoded=Allocation(result,bits:enc.bitsUsed,frac:enc.fractionalBitsUsed,range:enc.finalRange)
   let data=try enc.finalize()
   var dec=try OpusRangeDecoder(frame:data)
   if x.prefix>0 {_=try dec.decodeRawBits(count:x.prefix)}
   let decodedResult=try q.decode(totalEighthBits:x.total,dynamicOffsets:x.offsets,from:&dec)
   let decoded=Allocation(decodedResult,bits:dec.bitsUsed,frac:dec.fractionalBitsUsed,range:dec.finalRange)
   var arbitrary=try OpusRangeDecoder(frame:Data(x.arbitrary))
   if x.prefix>0 {_=try arbitrary.decodeRawBits(count:x.prefix)}
   let arbitraryResult=try q.decode(totalEighthBits:x.total,dynamicOffsets:x.offsets,from:&arbitrary)
   let arb=Allocation(arbitraryResult,bits:arbitrary.bitsUsed,frac:arbitrary.fractionalBitsUsed,range:arbitrary.finalRange)
   print(String(decoding:try JSONEncoder().encode(Output(caps:q.bandCaps,encoded:encoded,decoded:decoded,arbitrary:arb,bytes:Array(data))),as:UTF8.self))
  }
 }
}
'''


def context(lm=0, c=1, start=0, end=21, trim=5, total=2048, intensity=None,
            dual=False, bandwidth=None, prev=21, prefix=0):
    """Create bounded ordinary contexts independent of the owned allocator's tables/results."""
    return dict(lm=lm, c=c, start=start, end=end, trim=trim, total=total,
                intensity=end if intensity is None else intensity, dual=dual,
                bandwidth=end-1 if bandwidth is None else bandwidth, prev=prev,
                bytes=16, prefix=prefix, offsets=[0]*21,
                arbitrary=[(37*i+53*lm+17*c+11*trim) % 256 for i in range(16)])


def fixed_cases():
    """Cover all modes, trims, ranges, reservation boundaries, boosts, fine caps and explicit skips."""
    result = [context(lm=lm, c=c, dual=bool(lm % 2)) for lm in range(4) for c in (1, 2)]
    result += [context(lm=2, c=2, trim=trim) for trim in range(11)]
    budgets = (-1, 0, 1, 7, 8, 9, 15, 16, 17, 23, 24, 31, 32, 33, 39, 40, 41, 100, 500, 81600)
    result += [context(c=c, total=budget, intensity=0 if budget % 2 else 21, dual=True)
               for c in (1, 2) for budget in budgets]
    result += [context(lm=start % 4, c=1+start % 2, start=start, total=1024) for start in range(21)]
    result += [context(lm=lm, c=2, total=16000, bandwidth=0, prev=0, prefix=7, intensity=0)
               for lm in range(4)]
    for band in (0, 8, 17, 20):
        item = context(c=2, total=4096, bandwidth=0, intensity=17, dual=True)
        item['offsets'][band] = 384
        result.append(item)
    result += [context(lm=lm, c=c, start=17, end=19, total=81600, intensity=17, dual=True)
               for lm in range(4) for c in (1, 2)]
    result.append(context(lm=3, c=2, total=81600, intensity=21, dual=True))
    return result


def random_cases(count, seed):
    """Produce reproducible allocation contexts and unrelated decoder frames across every band range."""
    rng = random.Random(seed)
    result = []
    for index in range(count):
        start = rng.randrange(21)
        end = rng.randint(start+1, 21)
        item = context(lm=rng.randrange(4), c=rng.randint(1, 2), start=start, end=end,
                       trim=rng.randrange(11), total=rng.randint(0, 81600 if index % 5 == 0 else 4096),
                       intensity=rng.randint(start, end), dual=bool(rng.randrange(2)),
                       bandwidth=rng.randint(start, end-1), prev=rng.randint(start, end), prefix=rng.randrange(8))
        item['arbitrary'] = [rng.randrange(256) for _ in range(16)]
        if index % 3 == 0:
            for band in range(start, end):
                if rng.randrange(6) == 0:
                    item['offsets'][band] = rng.randint(0, 2048)
        result.append(item)
    return result


def commands(inputs):
    """Serialize bounded reference inputs; no shell interpolation or external access is involved."""
    lines = []
    for x in inputs:
        fields = [x[k] for k in ('lm', 'c', 'start', 'end', 'trim', 'total', 'bytes', 'prefix', 'intensity')]
        fields += [int(x['dual']), x['prev'], x['bandwidth']] + x['offsets'] + x['arbitrary']
        lines.append(' '.join(map(str, fields)))
    return '\n'.join(lines).encode()


def compare_results(inputs, expected, actual):
    """Require exact evidence and independent bounds even when both outputs are identically falsified."""
    if len(inputs) != len(expected) or len(inputs) != len(actual):
        raise ValueError('allocation case count mismatch')
    state_keys = {'shape', 'fine', 'priorities', 'balance', 'coded', 'intensity', 'dual', 'bits', 'frac', 'range'}
    for index, (x, e, a) in enumerate(zip(inputs, expected, actual)):
        if e != a:
            differing = [key for key in e if e.get(key) != a.get(key)]
            raise ValueError(json.dumps({'case': index, 'input': x, 'keys': differing, 'expected': e, 'actual': a}))
        if (set(e) != {'caps', 'bytes', 'encoded', 'decoded', 'arbitrary'}
                or len(e['caps']) != 21 or any(type(v) is not int or v <= 0 for v in e['caps'])
                or len(e['bytes']) != x['bytes']
                or any(type(v) is not int or not 0 <= v <= 255 for v in e['bytes'])):
            raise ValueError(f'case {index}: invalid independent output schema/caps/bytes')
        if e['encoded'] != e['decoded']:
            raise ValueError(f'case {index}: reference encoder/decoder disagree')
        for key in ('encoded', 'decoded', 'arbitrary'):
            r = e[key]
            if (set(r) != state_keys or type(r['dual']) is not bool
                    or any(type(r[k]) is not int for k in ('balance', 'coded', 'intensity', 'bits', 'frac', 'range'))
                    or not x['start'] < r['coded'] <= x['end'] or len(r['shape']) != 21
                    or len(r['fine']) != 21 or len(r['priorities']) != 21
                    or any(type(v) is not int or v < 0 or v > cap for v, cap in zip(r['shape'], e['caps']))
                    or any(type(v) is not int or not 0 <= v <= 8 for v in r['fine'])
                    or any(type(v) is not int or v not in (0, 1) for v in r['priorities']) or r['balance'] < 0
                    or not (r['intensity'] == 0 or x['start'] <= r['intensity'] <= r['coded'])
                    or r['dual'] and (x['c'] != 2 or r['intensity'] <= x['start'])
                    or not 1 <= r['bits'] <= x['bytes']*8 or not (r['bits']-1)*8 < r['frac'] <= r['bits']*8
                    or not 0x00800000 <= r['range'] <= 0xffffffff
                    or sum(r['shape']) + x['c']*8*sum(r['fine']) + r['balance'] > max(0, x['total'])
                    or any(r[k][band] != 0 for band in range(21)
                           if not x['start'] <= band < x['end'] for k in ('shape', 'fine', 'priorities'))
                    or any(r['shape'][band] != 0 for band in range(r['coded'], x['end']))):
                raise ValueError(f'case {index}: invalid independent allocation bounds')


def main():
    """Compile isolated drivers from a verified archive; optionally refresh fixtures and write evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-archive', required=True, type=Path)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--cases', type=int, default=2000)
    parser.add_argument('--seed', type=int, default=6716433)
    parser.add_argument('--write-fixtures', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error('--cases must be 1...10000 and seed must be nonnegative')
    repository = args.repository.resolve()
    fixed = fixed_cases()
    inputs = fixed + random_cases(args.cases, args.seed)
    with tempfile.TemporaryDirectory(prefix='discordkit-celt-allocation-', dir='/private/tmp') as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        c_driver, swift_driver = directory/'oracle.c', directory/'driver.swift'
        c_driver.write_text(C_DRIVER)
        swift_driver.write_text(SWIFT_DRIVER)
        reference, owned = directory/'oracle', directory/'owned'
        run(['cc', '-O2', '-DOPUS_BUILD', '-DVAR_ARRAYS', '-Wl,-dead_strip',
             '-I'+str(upstream/'include'), '-I'+str(upstream/'celt'), '-I'+str(upstream/'silk'),
             str(c_driver), '-lm', '-o', str(reference)])
        run(['swiftc', '-O', '-module-cache-path', str(directory/'module-cache'),
             '-enable-upcoming-feature', 'ApproachableConcurrency', '-default-isolation', 'nonisolated']
            + [str(repository/path) for path in OWNED_PATHS] + [str(swift_driver), '-o', str(owned)])
        expected = parse_outputs(run([str(reference)], commands(inputs)), len(inputs), 'Official allocation driver')
        owned_inputs = [{**x, 'limit': e['encoded']['coded']} for x, e in zip(inputs, expected)]
        actual = parse_outputs(run([str(owned)], '\n'.join(map(json.dumps, owned_inputs)).encode()), len(inputs), 'Owned allocation driver')
        compare_results(inputs, expected, actual)
        records = [{'input': x, 'output': e} for x, e in zip(fixed, expected)]
        fixture = repository/FIXTURE_PATH
        if args.write_fixtures:
            fixture.write_text('/// Independent unmodified libopus 1.6.1 ordinary allocation fixtures.\n'
                               'enum CELTAllocationOracleFixtures {\n    static let json = #"""\n'
                               + json.dumps(records, separators=(',', ':')) + '\n"""#\n}\n')
        if not fixture.exists() or json.loads(fixture.read_text().split('#"""', 1)[1].split('"""#', 1)[0]) != records:
            raise ValueError('committed fixtures differ or missing; review and use --write-fixtures')
        report = {'verifiedAt': datetime.now(timezone.utc).isoformat(), 'scope': 'CELT ordinary allocation component only',
                  'version': VERSION, 'releaseURL': RELEASE_URL, 'sourceURL': SOURCE_URL,
                  'archiveSHA256': ARCHIVE_SHA256, 'seed': args.seed, 'randomCases': args.cases,
                  'fixedCases': len(fixed), 'totalCases': len(inputs), 'arbitraryDecodeCases': len(inputs),
                  'exact': ['caps', 'shape eighth-bits', 'fine precision/priorities', 'balance',
                            'coded/intensity boundaries', 'dual stereo', 'encoded bytes', 'range', 'whole/eighth-bit accounting'],
                  'excluded': ['custom modes/extensions', 'full Opus codec', 'PLC/FEC', 'decoded-PCM conformance', 'devices', 'realtime'],
                  'ownedSources': {p: digest(repository/p) for p in OWNED_PATHS},
                  'upstreamSources': {p: digest(upstream/p) for p in UPSTREAM_PATHS},
                  'fixture': {'path': FIXTURE_PATH, 'sha256': digest(fixture)},
                  'verifierSHA256': digest(Path(__file__)),
                  'ccVersion': run(['cc', '--version']).decode().splitlines()[0],
                  'swiftVersion': run(['swiftc', '--version']).decode().splitlines()[0]}
        if args.report:
            args.report.write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

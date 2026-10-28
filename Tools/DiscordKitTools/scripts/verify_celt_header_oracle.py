#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/verify_celt_header_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Opt-in exact CELT frame-side-information verification against pinned libopus 1.6.1.

Verbatim tf_encode/tf_decode functions and decoder postfilter/dynamic-allocation
statement regions are extracted from the independently supplied verified archive.
A tiny wrapper supplies their normal local variables. Explicit encoder choices
replace perceptual analysis. Synthetic raw bits stand in for coarse energy between
the segmented APIs; this is syntax evidence, not a complete-codec/PCM claim.
"""
from publication import swift_header

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import random
import tempfile
from verify_opus_range_oracle import ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION, digest, extract_verified_archive, run
from verify_celt_pulse_oracle import parse_outputs

OWNED_PATHS = ('Sources/DiscordVoiceCodecs/OpusRangeCoding.swift',
               'Sources/DiscordVoiceCodecs/CELTAllocationTables.swift',
               'Sources/DiscordVoiceCodecs/CELTBitAllocation.swift',
               'Sources/DiscordVoiceCodecs/CELTPulseCodebook.swift',
               'Sources/DiscordVoiceCodecs/CELTBandQuantizer.swift',
               'Sources/DiscordVoiceCodecs/CELTFrameHeader.swift')
FIXTURE_PATH = 'Tests/DiscordVoiceCodecsTests/CELTHeaderOracleFixtures.swift'
UPSTREAM_PATHS = ('celt/celt_decoder.c', 'celt/celt_encoder.c', 'celt/celt.c', 'celt/celt.h',
                  'celt/modes.c', 'celt/static_modes_float.h', 'celt/entenc.c', 'celt/entdec.c', 'celt/entcode.c')
C_DRIVER = r"""
#define CELT_C
#include <stdio.h>
#include "entenc.c"
#include "entdec.c"
#include "entcode.c"
#include "modes.c"
#include "verbatim.h"
static void array(int *v){putchar('[');for(int i=0;i<21;i++)printf("%s%d",i?",":"",v[i]);putchar(']');}
static void prefix(int silence,int pitch,int qg,int tapset,int transient,ec_ctx *ec){
 printf("{\"silence\":%s,\"period\":%d,\"gainIndex\":%d,\"tapset\":%d,\"transient\":%s,\"bits\":%d,\"frac\":%u,\"range\":%u}",silence?"true":"false",pitch,pitch?qg:-1,tapset,transient?"true":"false",ec_tell(ec),ec_tell_frac(ec),ec->rng);
}
static void suffix(int *tf,int spread,int *offsets,int trim,int bits,int anti,ec_ctx *ec){
 printf("{\"tf\":");array(tf);printf(",\"spread\":%d,\"offsets\":",spread);array(offsets);
 printf(",\"trim\":%d,\"allocation\":%d,\"anti\":%s,\"bits\":%d,\"frac\":%u,\"range\":%u}",trim,bits,anti?"true":"false",ec_tell(ec),ec_tell_frac(ec),ec->rng);
}
static void decode(unsigned char *data,int len,int start,int end,int C,int LM,int preceding,int coarse){
 ec_dec state,*dec=&state;ec_dec_init(dec,data,len);if(preceding)ec_dec_bits(dec,preceding);
 int total_bits=len*8,tell=ec_tell(dec),silence=0,postfilter_pitch=0,postfilter_tapset=0,isTransient=0;
 float postfilter_gain=0;
 if(tell>=total_bits)silence=1;else if(tell==1)silence=ec_dec_bit_logp(dec,15);
 printf("{\"prefix\":");
 if(silence){prefix(1,0,-1,0,0,dec);printf(",\"suffix\":null}");return;}
 /* The original prefix statements retain exact budget checks and whole-bit snapshots. */
 VERBATIM_PREFIX
 prefix(0,postfilter_pitch,postfilter_pitch?(int)(postfilter_gain/.09375f)-1:-1,postfilter_tapset,isTransient,dec);
 if(coarse)ec_dec_bits(dec,coarse);
 const CELTMode *mode=&mode48000_960_120;const opus_int16 *eBands=mode->eBands;int nbEBands=21;
 int tf_res[21]={0},cap[21],offsets[21]={0},dynalloc_logp,alloc_trim,bits,anti_collapse_rsv,i;
 for(i=0;i<21;i++)cap[i]=(mode->cache.caps[21*(2*LM+C-1)+i]+64)*C*((eBands[i+1]-eBands[i])<<LM)>>2;
 tf_decode(start,end,isTransient,tf_res,LM,dec);
 tell=ec_tell(dec);int spread_decision=2;
 if(tell+4<=total_bits)spread_decision=ec_dec_icdf(dec,spread_icdf,5);
 VERBATIM_DYNAMIC
 printf(",\"suffix\":");suffix(tf_res,spread_decision,offsets,alloc_trim,bits,anti_collapse_rsv,dec);putchar('}');
}
int main(void){
 int LM,C,start,end,len,preceding,coarse,silence,pitch,qg,tapset,transient,select,spread,trim;
 while(scanf("%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d",&LM,&C,&start,&end,&len,&preceding,&coarse,&silence,&pitch,&qg,&tapset,&transient,&select,&spread,&trim)==15){
  if(len<0||len>128||LM<0||LM>3||C<1||C>2||start<0||end>21||start>=end)return 2;
  int tf[21],offsets[21],caps[21];unsigned value;unsigned char bytes[128]={0},arbitrary[128]={0};
  for(int i=0;i<21;i++)if(scanf("%d",tf+i)!=1)return 2;
  for(int i=0;i<21;i++)if(scanf("%d",offsets+i)!=1)return 2;
  for(int i=0;i<len;i++){if(scanf("%u",&value)!=1||value>255)return 2;arbitrary[i]=(unsigned char)value;}
  ec_enc state,*enc=&state;ec_enc_init(enc,bytes,len);if(preceding)ec_enc_bits(enc,0,preceding);
  int total_bits=len*8,tell=ec_tell(enc),admitted=tell>=total_bits;
  if(!admitted&&tell==1){ec_enc_bit_logp(enc,silence,15);admitted=silence;}
  printf("{\"encoded\":{\"prefix\":");
  if(admitted){prefix(1,0,-1,0,0,enc);printf(",\"suffix\":null}");}
  else{
   if(start==0&&tell+16<=total_bits){
    ec_enc_bit_logp(enc,pitch!=0,1);
    if(pitch){int octave=0;while(octave<5&&pitch+1>=(32<<octave))octave++;
     ec_enc_uint(enc,octave,6);ec_enc_bits(enc,pitch+1-(16<<octave),4+octave);ec_enc_bits(enc,qg,3);
     if(ec_tell(enc)+2<=total_bits)ec_enc_icdf(enc,tapset,tapset_icdf,2);else tapset=0;
    }tell=ec_tell(enc);
   }else pitch=0;
   if(LM>0&&tell+3<=total_bits)ec_enc_bit_logp(enc,transient,3);else transient=0;
   prefix(0,pitch,qg,pitch?tapset:0,transient,enc);
   if(coarse)ec_enc_bits(enc,0,coarse);
   tf_encode(start,end,transient,tf,LM,select,enc);
   int actualSpread=2;if(ec_tell(enc)+4<=total_bits){actualSpread=spread;ec_enc_icdf(enc,spread,spread_icdf,5);}
   const CELTMode *mode=&mode48000_960_120;const opus_int16 *eBands=mode->eBands;int cap[21],nbEBands=21,i,dynalloc_logp,total_boost;
   for(i=0;i<21;i++)cap[i]=(mode->cache.caps[21*(2*LM+C-1)+i]+64)*C*((eBands[i+1]-eBands[i])<<LM)>>2;
   VERBATIM_ENCODER_DYNAMIC
   int actualTrim=5;if(tell+(6<<BITRES)<=total_bits-total_boost){actualTrim=trim;ec_enc_icdf(enc,trim,trim_icdf,7);}
   int bits=(len*64)-(int)ec_tell_frac(enc)-1;int anti=transient&&LM>=2&&bits>=((LM+2)<<BITRES)?8:0;bits-=anti;
   for(int i=0;i<21;i++)if(i<start||i>=end)tf[i]=offsets[i]=0;
   printf(",\"suffix\":");suffix(tf,actualSpread,offsets,actualTrim,bits,anti,enc);putchar('}');
  }
  ec_enc_done(enc);if(enc->error)return 3;
  printf(",\"bytes\":[");for(int i=0;i<len;i++)printf("%s%u",i?",":"",bytes[i]);putchar(']');
  printf(",\"decoded\":");decode(bytes,len,start,end,C,LM,preceding,coarse);
  printf(",\"arbitrary\":");decode(arbitrary,len,start,end,C,LM,preceding,coarse);puts("}");
 }
 return 0;
}
"""
SWIFT_DRIVER = r"""
import Foundation
struct Input:Decodable {let lm:Int;let c:Int;let start:Int;let end:Int;let bytes:Int;let preceding:Int;let coarse:Int
 let silence:Bool;let period:Int;let gainIndex:Int;let tapset:Int;let transient:Bool;let select:Bool;let spread:Int;let trim:Int
 let tf:[Bool];let boosts:[Int];let arbitrary:[UInt8]}
struct Prefix:Encodable {let silence:Bool;let period:Int;let gainIndex:Int;let tapset:Int;let transient:Bool;let bits:Int;let frac:Int;let range:UInt32
 /// Snapshots admitted prefix and coder entropy in the independent reference schema.
 init(_ x:CELTFramePrefix,_ b:Int,_ f:Int,_ r:UInt32){silence=x.silence;period=x.postfilter?.period ?? 0;gainIndex=x.postfilter?.gainIndex ?? -1;tapset=x.postfilter?.tapset ?? 0;transient=x.isTransient;bits=b;frac=f;range=r}}
struct Suffix:Encodable {let tf:[Int];let spread:Int;let offsets:[Int];let trim:Int;let allocation:Int;let anti:Bool;let bits:Int;let frac:Int;let range:UInt32
 /// Snapshots bounded allocation metadata and exact arithmetic state.
 init(_ x:CELTFrameAllocationHeader,_ b:Int,_ f:Int,_ r:UInt32){tf=x.timeFrequencyChanges;spread=x.spreading.rawValue;offsets=x.dynamicOffsets;trim=x.allocationTrim;allocation=x.allocationEighthBits;anti=x.antiCollapseReserved;bits=b;frac=f;range=r}}
struct State:Encodable {let prefix:Prefix;let suffix:Suffix?}
struct Output:Encodable {let encoded:State;let decoded:State;let arbitrary:State;let bytes:[UInt8]}
@main struct Driver{
 /// Decodes arbitrary or encoded syntax through the segmented mandatory decoder API.
 static func decode(_ wire:Data,_ x:Input,_ h:CELTFrameHeader)throws->State{
  var d=try OpusRangeDecoder(frame:wire);if x.preceding>0{_=try d.decodeRawBits(count:x.preceding)}
  let p=try h.decodePrefix(from:&d);let prefix=Prefix(p,d.bitsUsed,d.fractionalBitsUsed,d.finalRange)
  if p.silence{return State(prefix:prefix,suffix:nil)}
  if x.coarse>0{_=try d.decodeRawBits(count:x.coarse)}
  let s=try h.decodeAfterCoarse(isTransient:p.isTransient,from:&d)
  return State(prefix:prefix,suffix:Suffix(s,d.bitsUsed,d.fractionalBitsUsed,d.finalRange))
 }
 /// Runs isolated development-only JSON cases; any thrown error aborts verification.
 static func main()throws{
  while let line=readLine(){let x=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   let h=try CELTFrameHeader(frameSampleCount:120<<x.lm,channelCount:x.c,startBand:x.start,endBand:x.end)
   let filter=x.period==0 ? nil:try CELTPostfilterParameters(period:x.period,gainIndex:x.gainIndex,tapset:x.tapset)
   var e=try OpusRangeEncoder(frameByteCount:x.bytes);if x.preceding>0{try e.encodeRawBits(0,count:x.preceding)}
   let p=try h.encodePrefix(silence:x.silence,postfilter:filter,isTransient:x.transient,into:&e)
   let prefix=Prefix(p,e.bitsUsed,e.fractionalBitsUsed,e.finalRange);var suffix:Suffix?
   if !p.silence{if x.coarse>0{try e.encodeRawBits(0,count:x.coarse)}
    let s=try h.encodeAfterCoarse(isTransient:p.isTransient,timeFrequencyFlags:x.tf,timeFrequencySelect:x.select,
      spreading:CELTSpreading(rawValue:x.spread)!,dynamicBoostCounts:x.boosts,allocationTrim:x.trim,into:&e)
    suffix=Suffix(s,e.bitsUsed,e.fractionalBitsUsed,e.finalRange)}
   let encoded=State(prefix:prefix,suffix:suffix);let wire=try e.finalize()
   print(String(decoding:try JSONEncoder().encode(Output(encoded:encoded,decoded:try decode(wire,x,h),arbitrary:try decode(Data(x.arbitrary),x,h),bytes:Array(wire))),as:UTF8.self))
  }
 }
}
"""


def region(source, start, end):
    """Extract a unique verbatim statement/function region, rejecting source drift instead of patching."""
    if source.count(start) != 1:
        raise ValueError('upstream start marker changed or ambiguous')
    suffix = source.split(start, 1)[1]
    if end not in suffix:
        raise ValueError('upstream end marker changed')
    return start + suffix.split(end, 1)[0]


def upstream_driver(upstream):
    """Assemble exact source fragments in wrappers retaining all original expressions and statements."""
    decoder = (upstream/'celt/celt_decoder.c').read_text()
    encoder = (upstream/'celt/celt_encoder.c').read_text()
    common = (upstream/'celt/celt.c').read_text()
    table = region(common, 'const signed char tf_select_table[4][8]', '\n\n')
    functions = table + '\n' + region(decoder, 'static void tf_decode(', '\nstatic int celt_plc_pitch_search(')
    functions += '\n' + region(encoder, 'static void tf_encode(', '\n\nstatic int alloc_trim_analysis(')
    (upstream/'celt/verbatim.h').write_text(functions)
    prefix = region(decoder, '   postfilter_gain = 0;', '   if (isTransient)\n')
    dynamic = region(decoder, '   dynalloc_logp = 6;', '\n   ALLOC(pulses, nbEBands, int);')
    enc_dynamic = region(encoder, '   dynalloc_logp = 6;', '\n   if (C==2)\n')
    return C_DRIVER.replace('VERBATIM_PREFIX', prefix).replace('VERBATIM_DYNAMIC', dynamic).replace('VERBATIM_ENCODER_DYNAMIC', enc_dynamic)


def context(lm=0, c=1, start=0, end=21, size=32, preceding=0, coarse=0, silence=False,
            period=0, gain=0, tapset=0, transient=False, select=False, spread=2, trim=5):
    """Create bounded explicit syntax inputs with independent unrelated decoder bytes."""
    return dict(lm=lm,c=c,start=start,end=end,bytes=size,preceding=preceding,coarse=coarse,
                silence=silence,period=period,gainIndex=gain,tapset=tapset,transient=transient,
                select=select,spread=spread,trim=trim,tf=[False]*21,boosts=[0]*21,
                arbitrary=[(53*i+17*lm+37*c+11*trim)%256 for i in range(size)])


def fixed_cases():
    """Cover all LM/channel modes, prefix choices, TF select, boost caps and tiny-frame defaults."""
    cases=[context(lm=lm,c=c,transient=lm>0) for lm in range(4) for c in (1,2)]
    cases += [context(lm=2,size=n,transient=True) for n in range(9)]
    cases += [context(lm=3,size=8,silence=True),context(size=0,silence=True)]
    cases += [context(lm=1,period=p,gain=g,tapset=t) for p in (15,30,31,62,63,126,254,510,1022)
              for g,t in ((0,0),(7,2))]
    cases += [context(lm=3,trim=trim,spread=trim%4,coarse=trim) for trim in range(11)]
    cases += [context(lm=lm,c=2,start=start,end=min(21,start+3),preceding=3,transient=lm>0,select=True)
              for lm in range(4) for start in (0,1,17,20)]
    for lm in range(4):
        for selected in (False,True):
            for transient in ((False,True) if lm else (False,)):
                x=context(lm=lm,c=2,select=selected,transient=transient,spread=3,trim=0)
                x['tf']=[i%3==0 for i in range(21)]
                x['boosts']=[10200 if i in (0,8,17,20) else 0 for i in range(21)]
                cases.append(x)
    return cases


def random_cases(count,seed):
    """Produce reproducible valid explicit choices and unrelated mandatory-decoder frames."""
    rng=random.Random(seed);cases=[]
    for _ in range(count):
        lm=rng.randrange(4);start=rng.randrange(21);size=rng.randrange(8,129)
        x=context(lm=lm,c=rng.randint(1,2),start=start,end=rng.randint(start+1,21),size=size,
                  preceding=rng.randrange(8),coarse=rng.randrange(25),period=rng.choice((0,rng.randint(15,1022))),
                  gain=rng.randrange(8),tapset=rng.randrange(3),transient=lm>0 and bool(rng.randrange(2)),
                  select=bool(rng.randrange(2)),spread=rng.randrange(4),trim=rng.randrange(11))
        x['tf']=[bool(rng.randrange(2)) for _ in range(21)]
        x['boosts']=[rng.randrange(24) if rng.randrange(4)==0 else 0 for _ in range(21)]
        x['arbitrary']=[rng.randrange(256) for _ in range(size)];cases.append(x)
    return cases


def commands(inputs):
    """Serialize exact C wrapper fields without shell interpolation."""
    order=('lm','c','start','end','bytes','preceding','coarse','silence','period','gainIndex','tapset','transient','select','spread','trim')
    return '\n'.join(' '.join(str(int(v)) for v in [x[k] for k in order]+x['tf']+x['boosts']+x['arbitrary']) for x in inputs).encode()


def compare_results(inputs,expected,actual):
    """Check exact bytes and entropy plus independent metadata schema, ranges and budget conservation."""
    if len(inputs)!=len(expected) or len(inputs)!=len(actual):raise ValueError('header case count mismatch')
    for index,(x,e,a) in enumerate(zip(inputs,expected,actual)):
        if e!=a:raise ValueError(json.dumps(dict(case=index,input=x,expected=e,actual=a)))
        if set(e)!={'encoded','decoded','arbitrary','bytes'} or len(e['bytes'])!=x['bytes'] or any(type(v)is not int or not 0<=v<=255 for v in e['bytes']):raise ValueError('invalid byte/schema evidence')
        if e['encoded']!=e['decoded']:raise ValueError('reference round-trip mismatch')
        for key in ('encoded','decoded','arbitrary'):
            state=e[key];p=state['prefix'];s=state['suffix']
            if set(state)!={'prefix','suffix'} or set(p)!={'silence','period','gainIndex','tapset','transient','bits','frac','range'}:raise ValueError('invalid prefix schema')
            if type(p['silence'])is not bool or type(p['transient'])is not bool or p['transient'] and x['lm']==0 or p['period']!=0 and not 15<=p['period']<=1022 or p['gainIndex'] not in (range(8) if p['period'] else (-1,)) or not 0<=p['tapset']<=2:raise ValueError('invalid prefix bounds')
            for snapshot in (p,s):
                if snapshot is None:continue
                if not 1<=snapshot['bits']<=max(1,x['bytes']*8) or not (snapshot['bits']-1)*8<snapshot['frac']<=snapshot['bits']*8 or not 0x00800000<=snapshot['range']<=0xffffffff:raise ValueError('invalid entropy bounds')
            if p['silence']!=(s is None):raise ValueError('silence must stop syntax')
            if s is None:continue
            if set(s)!={'tf','spread','offsets','trim','allocation','anti','bits','frac','range'} or len(s['tf'])!=21 or len(s['offsets'])!=21 or any(type(v)is not int or not -3<=v<=3 for v in s['tf']) or any(type(v)is not int or v<0 for v in s['offsets']) or not 0<=s['spread']<=3 or not 0<=s['trim']<=10 or type(s['anti'])is not bool:raise ValueError('invalid suffix bounds')
            if s['allocation']!=x['bytes']*64-s['frac']-1-(8 if s['anti'] else 0) or s['anti'] and not(p['transient'] and x['lm']>=2):raise ValueError('invalid allocation authority')
            if any(s[k][i]!=0 for i in range(21) if not x['start']<=i<x['end'] for k in ('tf','offsets')):raise ValueError('inactive bands modified')


def main():
    """Compile isolated reference and owned drivers; refresh fixtures only on explicit opt-in."""
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source-archive',required=True,type=Path)
    parser.add_argument('--repository',type=Path,default=Path(__file__).resolve().parents[3]);parser.add_argument('--cases',type=int,default=2000)
    parser.add_argument('--seed',type=int,default=7120443);parser.add_argument('--write-fixtures',action='store_true');parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    if not 1<=args.cases<=10000 or args.seed<0:parser.error('invalid case count or seed')
    repository=args.repository.resolve();fixed=fixed_cases();inputs=fixed+random_cases(args.cases,args.seed)
    with tempfile.TemporaryDirectory(prefix='discordkit-celt-header-',dir='/private/tmp') as temporary:
        directory=Path(temporary);upstream=extract_verified_archive(args.source_archive.resolve(),directory)
        c=directory/'oracle.c';s=directory/'driver.swift';c.write_text(upstream_driver(upstream));s.write_text(SWIFT_DRIVER)
        reference=directory/'oracle';owned=directory/'owned'
        run(['cc','-O2','-DOPUS_BUILD','-DVAR_ARRAYS','-Wl,-dead_strip','-I'+str(upstream/'include'),'-I'+str(upstream/'celt'),'-I'+str(upstream/'silk'),str(c),'-lm','-o',str(reference)])
        run(['swiftc','-O','-module-cache-path',str(directory/'module-cache'),'-enable-upcoming-feature','ApproachableConcurrency','-default-isolation','nonisolated']+[str(repository/p) for p in OWNED_PATHS]+[str(s),'-o',str(owned)])
        expected=parse_outputs(run([str(reference)],commands(inputs)),len(inputs),'Official header driver')
        actual=parse_outputs(run([str(owned)],'\n'.join(map(json.dumps,inputs)).encode()),len(inputs),'Owned header driver')
        for result in actual:
            for kind in ('encoded','decoded','arbitrary'):result[kind].setdefault('suffix',None)
        compare_results(inputs,expected,actual)
        records=[dict(input=x,output=e) for x,e in zip(fixed,expected)];fixture=repository/FIXTURE_PATH
        if args.write_fixtures:fixture.write_text(swift_header(FIXTURE_PATH) + '/// Independent unmodified libopus 1.6.1 segmented CELT header fixtures.\nenum CELTHeaderOracleFixtures {\n    static let json = #"""\n'+json.dumps(records,separators=(',',':'))+'\n"""#\n}\n')
        if not fixture.exists() or json.loads(fixture.read_text().split('#"""',1)[1].split('"""#',1)[0])!=records:raise ValueError('fixtures missing/different; review --write-fixtures')
        report=dict(verifiedAt=datetime.now(timezone.utc).isoformat(),scope='CELT segmented side information only',version=VERSION,releaseURL=RELEASE_URL,sourceURL=SOURCE_URL,archiveSHA256=ARCHIVE_SHA256,seed=args.seed,randomCases=args.cases,fixedCases=len(fixed),totalCases=len(inputs),arbitraryDecodeCases=len(inputs),exact=['prefix silence/postfilter/transient','TF resolution','spreading','dynamic offsets','trim','allocation and anti-collapse reserve','encoded bytes','whole/eighth-bit accounting','range'],excluded=['coarse energy (synthetic intervening raw bits)','full Opus codec','PCM/PLC/FEC','devices/realtime'],ownedSources={p:digest(repository/p) for p in OWNED_PATHS},upstreamSources={p:digest(upstream/p) for p in UPSTREAM_PATHS},fixture=dict(path=FIXTURE_PATH,sha256=digest(fixture)),verifierSHA256=digest(Path(__file__)),ccVersion=run(['cc','--version']).decode().splitlines()[0],swiftVersion=run(['swiftc','--version']).decode().splitlines()[0])
        if args.report:args.report.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))


if __name__=='__main__':main()

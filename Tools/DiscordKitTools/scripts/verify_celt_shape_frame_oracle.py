#!/usr/bin/env python3
"""Opt-in ordinary CELT quant_all_bands/anti_collapse comparison; no native runtime adoption."""
import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import random
import tempfile
from verify_celt_shape_oracle import (OWNED_PATHS, UPSTREAM_PATHS, BAND_EDGES, NORMAL_TF,
    TRANSIENT_TF, float32, C_DRIVER as BAND_DRIVER)
from verify_opus_range_oracle import (VERSION, RELEASE_URL, SOURCE_URL, ARCHIVE_SHA256,
    digest, extract_verified_archive, run)
from verify_celt_pulse_oracle import parse_outputs

FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/CELTShapeFrameOracleFixtures.swift"
C_DRIVER = '#define RESYNTH\n' + BAND_DRIVER.split('int main(void)')[0] + r'''
static void ints(const unsigned char *x,int n){putchar('[');for(int i=0;i<n;i++)printf("%s%u",i?",":"",x[i]);putchar(']');}
int main(void){
 int lm,c,start,end,transient,spread,disable,dual,intensity,coded,bytes,total,balance,prefix;unsigned seed;
 while(scanf("%d%d%d%d%d%d%d%d%d%d%d%d%d%d%u",&lm,&c,&start,&end,&transient,&spread,&disable,&dual,&intensity,&coded,&bytes,&total,&balance,&prefix,&seed)==15){
  if(lm<0||lm>3||c<1||c>2||start<0||end>21||start>=end||bytes<1||bytes>1275)return 2;
  const CELTMode *mode=opus_custom_mode_create(48000,960,NULL);int n=120<<lm;
  float x[1920]={0},dx[1920]={0},ae[1920],ad[1920],energy[42],loge[42],prev[42],prev2[42];
  int pulses[21],tf[21];unsigned char masks[42]={0},dmasks[42]={0},amasks[42],data[1275]={0};
  for(int i=0;i<21;i++)if(scanf("%d",&pulses[i])!=1)return 2;
  for(int i=0;i<21;i++)if(scanf("%d",&tf[i])!=1)return 2;
  for(int i=0;i<21*c;i++)if(scanf("%f",&energy[i])!=1)return 2;
  for(int i=0;i<n*c;i++)if(scanf("%f",&x[i])!=1)return 2;
  for(int i=0;i<21*c;i++){unsigned v;if(scanf("%u",&v)!=1)return 2;amasks[i]=v;}
  for(int i=0;i<21*c;i++)if(scanf("%f",&loge[i])!=1)return 2;
  for(int i=0;i<42;i++)if(scanf("%f",&prev[i])!=1)return 2;
  for(int i=0;i<42;i++)if(scanf("%f",&prev2[i])!=1)return 2;
  ec_enc enc;ec_enc_init(&enc,data,bytes);if(prefix)ec_enc_bits(&enc,12345&((1<<prefix)-1),prefix);
  unsigned es=seed;quant_all_bands(1,mode,start,end,x,c==2?x+n:NULL,masks,energy,pulses,transient,spread,dual,intensity,tf,total,balance,&enc,lm,coded,&es,0,0,disable);
  printf("{\"coefficients\":");array(x,n*c);printf(",\"masks\":");ints(masks,21*c);
  printf(",\"seed\":%u,\"range\":%u,\"bits\":%d,\"fraction\":%u",es,enc.rng,ec_tell(&enc),ec_tell_frac(&enc));
  ec_enc_done(&enc);if(enc.error)return 3;
  ec_dec dec;ec_dec_init(&dec,data,bytes);if(prefix)ec_dec_bits(&dec,prefix);
  unsigned ds=seed;quant_all_bands(0,mode,start,end,dx,c==2?dx+n:NULL,dmasks,NULL,pulses,transient,spread,dual,intensity,tf,total,balance,&dec,lm,coded,&ds,0,0,disable);
  /* The native decoder uses the inactive last band as scratch. Public owned output
     promises zero inactive bands, so discard this semantically unobservable workspace. */
  for(int ch=0;ch<c;ch++){OPUS_CLEAR(dx+ch*n,mode->eBands[start]<<lm);OPUS_CLEAR(dx+ch*n+(mode->eBands[end]<<lm),n-(mode->eBands[end]<<lm));}
  printf(",\"decoded\":");array(dx,n*c);printf(",\"decodedMasks\":");ints(dmasks,21*c);
  printf(",\"decodedSeed\":%u,\"decodedRange\":%u,\"decodedBits\":%d,\"decodedFraction\":%u",ds,dec.rng,ec_tell(&dec),ec_tell_frac(&dec));
  OPUS_COPY(ae,dx,n*c);OPUS_COPY(ad,dx,n*c);
  if(transient){anti_collapse(mode,ae,amasks,lm,c,n,start,end,loge,prev,prev2,pulses,ds,1,0);anti_collapse(mode,ad,amasks,lm,c,n,start,end,loge,prev,prev2,pulses,ds,0,0);}
  printf(",\"antiEncoder\":");array(ae,n*c);printf(",\"antiDecoder\":");array(ad,n*c);printf(",\"bytes\":[");
  for(int i=0;i<bytes;i++)printf("%s%u",i?",":"",data[i]);puts("]}");
 }
 return 0;
}
'''
SWIFT_DRIVER = r'''
import Foundation
struct Input:Decodable {
 let lm:Int;let c:Int;let start:Int;let end:Int;let transient:Bool;let spread:Int;let disable:Bool
 let dual:Bool;let intensity:Int;let coded:Int;let bytes:Int;let total:Int;let balance:Int;let prefix:Int;let seed:UInt32
 let pulses:[Int];let tf:[Int];let energy:[Float];let x:[Float];let masks:[UInt8]
 let loge:[Float];let prev:[Float];let prev2:[Float]
}
struct Output:Encodable {
 let coefficients:[Float];let masks:[UInt8];let seed:UInt32;let range:UInt32;let bits:Int;let fraction:Int
 let decoded:[Float];let decodedMasks:[UInt8];let decodedSeed:UInt32;let decodedRange:UInt32;let decodedBits:Int;let decodedFraction:Int
 let antiEncoder:[Float];let antiDecoder:[Float];let bytes:[UInt8]
}
@main struct Driver {
 /// Runs only explicit local comparison contexts; production imports no official codec.
 static func main() throws {
  while let line=readLine(){
   let x=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   let q=try CELTShapeFrameCoding(frameSampleCount:120 << x.lm,channelCount:x.c,startBand:x.start,endBand:x.end,transient:x.transient,timeFrequencyChanges:x.tf,spreading:CELTSpreading(rawValue:x.spread)!,disableInversion:x.disable)
   let a=CELTBitAllocationResult(shapeEighthBits:x.pulses,fineEnergyBits:Array(repeating:0,count:21),finePriorities:Array(repeating:0,count:21),balanceEighthBits:x.balance,codedBandEnd:x.coded,intensityBand:x.intensity,dualStereo:x.dual)
   var enc=try OpusRangeEncoder(frameByteCount:x.bytes)
   if x.prefix>0{try enc.encodeRawBits(UInt32(12345 & ((1 << x.prefix)-1)),count:x.prefix)}
   let v=try q.encode(x.x,allocation:a,totalEighthBits:x.total,seed:x.seed,bandEnergies:x.energy,into:&enc)
   let range=enc.finalRange,bits=enc.bitsUsed,fraction=enc.fractionalBitsUsed,data=try enc.finalize()
   var dec=try OpusRangeDecoder(frame:data);if x.prefix>0{_ = try dec.decodeRawBits(count:x.prefix)}
   let d=try q.decode(allocation:a,totalEighthBits:x.total,seed:x.seed,from:&dec)
   let ae=x.transient ? try q.applyAntiCollapse(d.coefficients,collapseMasks:x.masks,energies:x.loge,previous:x.prev,previous2:x.prev2,allocation:a,seed:d.seed,isEncoder:true):d.coefficients
   let ad=x.transient ? try q.applyAntiCollapse(d.coefficients,collapseMasks:x.masks,energies:x.loge,previous:x.prev,previous2:x.prev2,allocation:a,seed:d.seed):d.coefficients
   let o=Output(coefficients:v.coefficients,masks:v.collapseMasks,seed:v.seed,range:range,bits:bits,fraction:fraction,decoded:d.coefficients,decodedMasks:d.collapseMasks,decodedSeed:d.seed,decodedRange:dec.finalRange,decodedBits:dec.bitsUsed,decodedFraction:dec.fractionalBitsUsed,antiEncoder:ae,antiDecoder:ad,bytes:Array(data))
   print(String(decoding:try JSONEncoder().encode(o),as:UTF8.self))
  }
 }
}
'''

def context(lm=3,c=2,start=0,end=21,transient=False,dual=False,intensity=15,spread=2,
            byte_count=128,budget=128,seed=0xdeadbeef):
    """Build a deterministic unit-normalized spectrum and bounded all-band authority."""
    n=120<<lm
    x=[0.0]*(n*c)
    for ch in range(c):
        for band in range(start,end):
            lo,hi=BAND_EDGES[band]<<lm,BAND_EDGES[band+1]<<lm
            v=[math.sin(j*.419+band*.2+ch*.837+.5) for j in range(hi-lo)]
            scale=.999999/math.sqrt(sum(a*a for a in v))
            x[ch*n+lo:ch*n+hi]=[float32(a*scale) for a in v]
    blocks=(1<<lm) if transient else 1
    return dict(lm=lm,c=c,start=start,end=end,transient=transient,spread=spread,disable=False,
        dual=dual,intensity=min(end,intensity),coded=end,bytes=byte_count,total=byte_count*64-(8 if transient else 0),
        balance=0,prefix=7,seed=seed,pulses=[budget if start<=i<end else 0 for i in range(21)],
        tf=[0]*21,energy=[float32(1+.1*i) for i in range(21*c)],x=x,
        masks=[((1<<blocks)-1) if i%3==0 else (1 if i%3==1 else 0) for i in range(21*c)],
        loge=[float32(4+i*.04) for i in range(21*c)],
        prev=[float32(3.7+i*.02) for i in range(42)],prev2=[float32(3.6+i*.03) for i in range(42)])


def fixed_cases():
    """Cover every duration/channel/transient and low/high/hybrid folding/stereo case."""
    cases=[]
    for lm in range(4):
        for c in (1,2):
            for transient in (False,True):
                for start in (0,17):
                    for budget in (0,384):
                        cases.append(context(lm,c,start,transient=transient,dual=c==2,
                            intensity=19,budget=budget,byte_count=96))
    for spread in range(4):
        q=context(start=8,end=13,transient=True,spread=spread,budget=900)
        q['tf']=[-1]*21;q['intensity']=11;cases.append(q)
    # A nearly empty stereo channel can exceed unit norm after native approximate merge.
    q=context(3,2,13,21,transient=True,intensity=17,spread=1,byte_count=96)
    q.update(balance=35,prefix=5,seed=2985900412,disable=True,
        pulses=[0]*13+[209,1879,1577,49,1091,1561,837,1839],
        tf=[-1,3,-1,0,-1,-1,-1,0,1,3,1,3,0,0,-1,-1,-1,-1,1,1,-1])
    for ch,band in [(0,17),(0,19),(1,14),(1,17)]:
        q['x'][ch*960+(BAND_EDGES[band]<<3):ch*960+(BAND_EDGES[band+1]<<3)]=[0.0]*((BAND_EDGES[band+1]-BAND_EDGES[band])<<3)
    cases.append(q)
    # Mono decoder must use both previous channels while mono encoder uses its own.
    q=context(3,1,transient=True,budget=0)
    q.update(loge=[10.0]*21,prev=[0.0]*21+[20.0]*21,prev2=[0.0]*21+[20.0]*21,masks=[1]*21)
    cases.append(q)
    return cases


def random_cases(count,seed):
    """Vary finite spectra, scarce authority, stereo transition, TF and noise histories."""
    rng=random.Random(seed);cases=[]
    for _ in range(count):
        lm=rng.randrange(4);c=rng.randrange(1,3);start=rng.choice([0,0,0,8,13,17,20]);end=rng.randrange(start+1,22)
        q=context(lm,c,start,end,transient=bool(rng.randrange(2)),dual=c==2 and bool(rng.randrange(2)),
            intensity=rng.randrange(start,end+1),spread=rng.randrange(4),budget=0,
            byte_count=rng.choice([4,8,16,24,48,96,128,256]),seed=rng.getrandbits(32))
        q['disable']=bool(rng.randrange(2));q['coded']=rng.randrange(start+1,end+1)
        q['balance']=rng.randrange(-200,201);q['prefix']=rng.randrange(0,min(17,q['bytes']*8-2))
        q['pulses']=[rng.randrange(0,2001) if start<=i<end else 0 for i in range(21)]
        choices=(TRANSIENT_TF if q['transient'] else NORMAL_TF)[lm]
        q['tf']=[rng.choice(choices) for _ in range(21)]
        for ch in range(c):
            for band in range(start,end):
                lo,hi=BAND_EDGES[band]<<lm,BAND_EDGES[band+1]<<lm
                if rng.randrange(10)==0:q['x'][ch*(120<<lm)+lo:ch*(120<<lm)+hi]=[0.0]*(hi-lo)
        for key,length in [('loge',21*c),('prev',42),('prev2',42)]:
            q[key]=[float32(rng.uniform(-20,12)) for _ in range(length)]
        maskmax=1<<((1<<lm) if q['transient'] else 1)
        q['masks']=[rng.randrange(maskmax) for _ in range(21*c)]
        cases.append(q)
    return cases


def commands(inputs):
    """Serialize generated bounded contexts for the unmodified official C functions."""
    lines=[]
    for x in inputs:
        fields=[int(x[k]) for k in ('lm','c','start','end','transient','spread','disable','dual','intensity','coded','bytes','total','balance','prefix','seed')]
        for k in ('pulses','tf','energy','x','masks','loge','prev','prev2'):fields+=x[k]
        lines.append(' '.join(map(str,fields)))
    return '\n'.join(lines).encode()


def compare_results(inputs,expected,actual):
    """Check exact wire/control state and scalar spectra within 5e-5 absolute error."""
    if len(inputs)!=len(expected) or len(inputs)!=len(actual):raise ValueError('case count mismatch')
    arrays={'coefficients','decoded','antiEncoder','antiDecoder'}
    exact={'masks','seed','range','bits','fraction','decodedMasks','decodedSeed','decodedRange','decodedBits','decodedFraction','bytes'}
    for i,(x,e,a) in enumerate(zip(inputs,expected,actual)):
        for result in (e,a):
            if set(result)!=arrays|exact:raise ValueError(f'case {i}: output schema differs')
            for key in arrays:
                if len(result[key])!=(120<<x['lm'])*x['c'] or any(not math.isfinite(v) for v in result[key]):
                    raise ValueError(f'case {i}: invalid {key} shape/finiteness')
            for key in ('masks','decodedMasks'):
                if len(result[key])!=21*x['c'] or any(type(v)is not int or not 0<=v<1<<((1<<x['lm']) if x['transient'] else 1) for v in result[key]):
                    raise ValueError(f'case {i}: invalid occupancy')
            if len(result['bytes'])!=x['bytes'] or any(type(v)is not int or not 0<=v<=255 for v in result['bytes']):raise ValueError(f'case {i}: invalid bytes')
            for key in ('range','decodedRange'):
                if type(result[key]) is not int or not 0<result[key]<=0xffffffff:raise ValueError(f'case {i}: invalid range')
            for key in ('seed','decodedSeed'):
                if type(result[key]) is not int or not 0<=result[key]<=0xffffffff:raise ValueError(f'case {i}: invalid seed')
            for key in ('bits','decodedBits'):
                if type(result[key]) is not int or not 1<=result[key]<=x['bytes']*8:raise ValueError(f'case {i}: invalid bit use')
            for key in ('fraction','decodedFraction'):
                if type(result[key]) is not int or not 1<=result[key]<=x['bytes']*64:raise ValueError(f'case {i}: invalid fractional use')
            for k,d in [('masks' ,'decodedMasks'),('seed','decodedSeed'),('range','decodedRange'),('bits','decodedBits'),('fraction','decodedFraction')]:
                if result[k]!=result[d]:raise ValueError(f'case {i}: encoder/decoder {k} mismatch')
            if any(abs(v-w)>5e-5 for v,w in zip(result['coefficients'],result['decoded'])):raise ValueError(f'case {i}: {"official" if result is e else "owned"} encoder/decoder spectra mismatch: {max(abs(v-w) for v,w in zip(result["coefficients"],result["decoded"]))}')
        for key in exact:
            if e[key]!=a[key]:raise ValueError(f'case {i} {key}: owned {a[key]} != reference {e[key]}; input={x}')
        for key in arrays:
            delta=max(abs(v-w) for v,w in zip(e[key],a[key]))
            if delta>5e-5:raise ValueError(f'case {i} {key}: scalar delta {delta}; input={x}')


def main():
    """Compile explicit local drivers, compare bounded cases and optionally refresh fixtures/report."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-archive',type=Path,required=True)
    parser.add_argument('--repository',type=Path,default=Path(__file__).resolve().parents[3])
    parser.add_argument('--cases',type=int,default=1000);parser.add_argument('--seed',type=int,default=6716435)
    parser.add_argument('--write-fixtures',action='store_true');parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    if not 1<=args.cases<=10000 or args.seed<0:parser.error('--cases must be 1...10000 and seed nonnegative')
    repository=args.repository.resolve();fixed=fixed_cases();inputs=fixed+random_cases(args.cases,args.seed)
    with tempfile.TemporaryDirectory(prefix='discordkit-celt-shape-frame-',dir='/private/tmp') as tmp:
        directory=Path(tmp);upstream=extract_verified_archive(args.source_archive.resolve(),directory)
        c,swift=directory/'oracle.c',directory/'driver.swift';c.write_text(C_DRIVER);swift.write_text(SWIFT_DRIVER)
        reference,owned=directory/'oracle',directory/'owned'
        run(['cc','-O2','-ffp-contract=off','-DOPUS_BUILD','-DVAR_ARRAYS','-Wl,-dead_strip',
             '-I'+str(upstream/'include'),'-I'+str(upstream/'celt'),'-I'+str(upstream/'silk'),str(c),'-lm','-o',str(reference)])
        run(['swiftc','-O','-module-cache-path',str(directory/'module-cache'),'-enable-upcoming-feature','ApproachableConcurrency',
             '-default-isolation','nonisolated']+[str(repository/p) for p in OWNED_PATHS]+[str(swift),'-o',str(owned)])
        expected=parse_outputs(run([str(reference)],commands(inputs)),len(inputs),'Official all-band driver')
        actual=parse_outputs(run([str(owned)],'\n'.join(map(json.dumps,inputs)).encode()),len(inputs),'Owned all-band driver')
        compare_results(inputs,expected,actual)
        records=[{'input':x,'output':e} for x,e in zip(fixed,expected)];fixture=repository/FIXTURE_PATH
        if args.write_fixtures:fixture.write_text('/// Independent libopus 1.6.1 all-band shape/anti-collapse fixtures.\nenum CELTShapeFrameOracleFixtures {\n    static let json = #"""\n'+json.dumps(records,separators=(',',':'))+'\n"""#\n}\n')
        if not fixture.exists() or json.loads(fixture.read_text().split('#"""',1)[1].split('"""#',1)[0])!=records:raise ValueError('fixture differs; review and explicitly --write-fixtures')
        report={'verifiedAt':datetime.now(timezone.utc).isoformat(),'scope':'ordinary CELT quant_all_bands and anti_collapse components',
            'version':VERSION,'releaseURL':RELEASE_URL,'sourceURL':SOURCE_URL,'archiveSHA256':ARCHIVE_SHA256,
            'seed':args.seed,'randomCases':args.cases,'fixedCases':len(fixed),'totalCases':len(inputs),'floatTolerance':5e-5,
            'exact':['bytes','final ranges','whole/fractional bits','collapse masks','seed'],
            'excluded':['optional encoder stereo theta RDO','full Opus codec','PLC/FEC','decoded-PCM conformance','hardware/realtime'],
            'ownedSources':{p:digest(repository/p) for p in OWNED_PATHS},'upstreamSources':{p:digest(upstream/p) for p in UPSTREAM_PATHS},
            'fixture':{'path':FIXTURE_PATH,'sha256':digest(fixture)},'verifierSHA256':digest(Path(__file__)),
            'ccVersion':run(['cc','--version']).decode().splitlines()[0],'swiftVersion':run(['swiftc','--version']).decode().splitlines()[0]}
        if args.report:args.report.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))

if __name__=='__main__':main()

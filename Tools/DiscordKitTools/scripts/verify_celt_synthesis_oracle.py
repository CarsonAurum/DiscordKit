#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/verify_celt_synthesis_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Opt-in ordinary CELT floating synthesis against pinned unmodified libopus 1.6.1.

Verbatim synthesis/deemphasis functions are extracted; original denormalization,
MDCT, FFT and comb filters compile separately. Independent multi-frame sequences
cover duration/short-block/postfilter transitions, coded/output channel conversion
and exact signal-domain scaling with retained independent output histories.
No entropy, packet, PLC/FEC, resampler, device or full-codec evidence is implied.
"""
from publication import swift_header

import argparse
import base64
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import random
import struct
import tempfile
from verify_opus_range_oracle import ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION, digest, extract_verified_archive, run
from verify_celt_header_oracle import region
from verify_celt_pulse_oracle import parse_outputs

OWNED_PATHS=('Sources/DiscordVoiceCodecs/OpusRangeCoding.swift','Sources/DiscordVoiceCodecs/CELTAllocationTables.swift',
             'Sources/DiscordVoiceCodecs/CELTBitAllocation.swift','Sources/DiscordVoiceCodecs/CELTPulseCodebook.swift',
             'Sources/DiscordVoiceCodecs/CELTBandQuantizer.swift','Sources/DiscordVoiceCodecs/CELTFrameHeader.swift',
             'Sources/DiscordVoiceCodecs/CELTTransform.swift','Sources/DiscordVoiceCodecs/CELTSynthesis.swift',
             'Sources/DiscordVoiceCodecs/CELTPacketLossConcealment.swift')
UPSTREAM_PATHS=('celt/celt_decoder.c','celt/celt.c','celt/bands.c','celt/quant_bands.c','celt/mathops.h','celt/mdct.c','celt/kiss_fft.c','celt/modes.c','celt/static_modes_float.h')
FIXTURE_PATH='Tests/DiscordVoiceCodecsTests/CELTSynthesisOracleFixtures.swift'
ABSOLUTE_TOLERANCE=0.000003
RELATIVE_TOLERANCE=0.000008
C_DRIVER=r'''
#define CELT_C
#include <stdio.h>
#include <string.h>
#include "celt.h"
#include "bands.h"
#include "quant_bands.h"
#include "stack_alloc.h"
#include "modes.c"
#include "verbatim.h"
int main(void){int C,count;
 while(scanf("%d%d",&C,&count)==2){
  if(C<1||C>2||count<1||count>16)return 2;
  float buffer[2][2104]={{0}},mem[2]={0},X[1920],energies[42],pcm[1920];
  int oldPeriod=0,period=0,oldTapset=0,tapset=0;float oldGain=0,gain=0;
  printf("{\"frames\":[");
  for(int frame=0;frame<count;frame++){
   int LM,start,end,transient,pitch,qg,newTapset,silence,codedChannels;unsigned seed;
   if(scanf("%d%d%d%d%d%d%d%d%d",&LM,&start,&end,&transient,&pitch,&qg,&newTapset,&silence,&codedChannels)!=9)return 2;
   if(codedChannels<1||codedChannels>2)return 2;
   int N=120<<LM;
   for(int i=0;i<codedChannels*N;i++)if(scanf("%f",X+i)!=1)return 2;
   for(int i=0;i<codedChannels*21;i++)if(scanf("%f",energies+i)!=1)return 2;
   float *out[2]={buffer[0]+1024,buffer[1]+1024};
   celt_synthesis(&mode48000_960_120,X,out,energies,start,end,codedChannels,C,transient,LM,1,silence,0);
   float newGain=pitch?.09375f*(qg+1):0;
   for(int c=0;c<C;c++){
    comb_filter(out[c],out[c],oldPeriod,period,120,oldGain,gain,oldTapset,tapset,mode48000_960_120.window,120,0);
    if(LM)comb_filter(out[c]+120,out[c]+120,period,pitch,N-120,gain,newGain,tapset,newTapset,mode48000_960_120.window,120,0);
   }
   oldPeriod=period;oldGain=gain;oldTapset=tapset;period=pitch;gain=newGain;tapset=newTapset;
   if(LM){oldPeriod=period;oldGain=gain;oldTapset=tapset;}
   deemphasis(out,pcm,N,C,1,mode48000_960_120.preemph,mem,0);
   printf("%s[",frame?",":"");for(int i=0;i<N*C;i++)printf("%s%.9g",i?",":"",pcm[i]);putchar(']');
   for(int c=0;c<C;c++)memmove(buffer[c],buffer[c]+N,(1024+120)*sizeof(float));
  }puts("]}");
 }
 return 0;
}
'''
SWIFT_DRIVER=r'''
import Foundation
struct Frame:Decodable{let lm:Int;let start:Int;let end:Int;let transient:Bool;let period:Int;let gainIndex:Int;let tapset:Int;let silence:Bool;let coefficients:[Float];let energies:[Float];let codedChannelCount:Int?}
struct Input:Decodable{let channels:Int;let frames:[Frame]}
struct Output:Encodable{let frames:[[Float]]}
@main struct Driver{
 /// Runs independent bounded signal sequences through value-owned shared synthesis history.
 static func main()throws{while let line=readLine(){let x=try JSONDecoder().decode(Input.self,from:Data(line.utf8));var s=try CELTSynthesis(channelCount:x.channels);var frames=[[Float]]()
  for f in x.frames{let filter=f.period==0 ? nil:try CELTPostfilterParameters(period:f.period,gainIndex:f.gainIndex,tapset:f.tapset)
   frames.append(try s.synthesize(normalizedCoefficients:f.coefficients,bandLogEnergies:f.energies,frameSampleCount:120<<f.lm,startBand:f.start,endBand:f.end,isTransient:f.transient,postfilter:filter,silence:f.silence,codedChannelCount:f.codedChannelCount))}
  print(String(decoding:try JSONEncoder().encode(Output(frames:frames)),as:UTF8.self))}}
}
'''


def upstream_functions(upstream):
    """Extract complete original bodies with unique markers; no arithmetic is patched."""
    decoder=(upstream/'celt/celt_decoder.c').read_text()
    stereo=region(decoder,'static void deemphasis_stereo_simple(', '\n#endif')
    deemphasis=region(decoder,'void deemphasis(celt_sig *in[]', '\n#ifndef RESYNTH\nstatic\n#endif\nvoid celt_synthesis')
    synthesis=region(decoder,'void celt_synthesis(const CELTMode *mode,', '\nstatic void tf_decode(')
    return stereo+'\n'+deemphasis+'\n'+synthesis


def frame(lm=0,channels=1,start=0,end=21,transient=False,period=0,gain=0,tapset=0,silence=False,energy=4,phase=0):
    """Generate float32-exact synthetic normalized bands without depending on owned implementation."""
    n=120<<lm
    return dict(lm=lm,start=start,end=end,transient=transient,period=period,gainIndex=gain,tapset=tapset,silence=silence,
                coefficients=[(((i*37+phase*11)%101)-50)/512 for i in range(n*channels)],
                energies=[min(32768,max(-32768,energy+(i%5)/16)) for i in range(21*channels)])


def fixed_cases():
    """Cover all lengths/channels plus duration/transient/filter state changes and exponent clipping."""
    result=[]
    for channels in (1,2):
        for lm in range(4):
            result.append(dict(channels=channels,frames=[frame(lm,channels,transient=lm>0,phase=p) for p in range(3)]))
        result.append(dict(channels=channels,frames=[frame(lm,channels,transient=lm>0 and i%2==0,period=15 if i%3 else 1022,gain=i%8,tapset=i%3,phase=i) for i,lm in enumerate((0,1,2,3,2,1,0,3))]))
        result.append(dict(channels=channels,frames=[frame(3,channels,start=17,end=19,period=63,gain=7,tapset=2),frame(1,channels,silence=True),frame(0,channels,silence=True)]))
        for exponent in (-32768,-60,-50,-7,0,25,32768):
            result.append(dict(channels=channels,frames=[frame(1,channels,energy=exponent)]))
    for channels in (1,2):
        for lm in range(4):
            frames=[]
            for index,coded in enumerate((1,2,1,2,1,2)):
                f=frame(lm,coded,transient=lm>0 and index%2==0,period=63,gain=4,tapset=1,phase=index,silence=index==4)
                f['codedChannelCount']=coded
                # Distinct envelopes require averaging after independent denormalization.
                if coded==2:f['energies'][21:]=[v+3 for v in f['energies'][21:]]
                frames.append(f)
            result.append(dict(channels=channels,frames=frames))
    return result


def random_cases(count,seed):
    """Generate reproducible multiframe spectra, envelope and delayed postfilter changes."""
    rng=random.Random(seed);cases=[]
    for _ in range(count):
        channels=rng.randint(1,2);frames=[]
        for index in range(rng.randint(1,8)):
            lm=rng.randrange(4);start=rng.choice((0,0,0,17));end=rng.randint(max(start+1,19),21)
            coded=rng.randint(1,2)
            f=frame(lm,coded,start,end,transient=lm>0 and bool(rng.randrange(2)),period=rng.choice((0,rng.randint(15,1022))),gain=rng.randrange(8),tapset=rng.randrange(3),silence=rng.randrange(16)==0)
            f['codedChannelCount']=coded
            f['coefficients']=[rng.randint(-512,512)/512 for _ in f['coefficients']]
            f['energies']=[rng.randint(-320,320)/16 for _ in f['energies']]
            frames.append(f)
        cases.append(dict(channels=channels,frames=frames))
    return cases


def commands(inputs):
    """Serialize bounded multi-frame wrapper inputs with float32-exact numeric values."""
    lines=[]
    for x in inputs:
        fields=[x['channels'],len(x['frames'])]
        for f in x['frames']:
            fields += [int(f[k]) for k in ('lm','start','end','transient','period','gainIndex','tapset','silence')]+[f.get('codedChannelCount',x['channels'])]+f['coefficients']+f['energies']
        lines.append(' '.join(map(str,fields)))
    return '\n'.join(lines).encode()


def compare_results(inputs,expected,actual):
    """Require every finite PCM sample and dimension within tight absolute-plus-relative tolerance."""
    if len(inputs)!=len(expected) or len(inputs)!=len(actual):raise ValueError('synthesis case count mismatch')
    maximum=0.0;maximum_scaled=0.0;sample_count=0
    for index,(x,e,a) in enumerate(zip(inputs,expected,actual)):
        if set(e)!={'frames'} or set(a)!={'frames'} or len(e['frames'])!=len(x['frames']) or len(a['frames'])!=len(x['frames']):raise ValueError('invalid synthesis sequence shape')
        sequence_scale=max(1,max(abs(v) for frame in e['frames'] for v in frame))
        for fi,(f,reference,candidate) in enumerate(zip(x['frames'],e['frames'],a['frames'])):
            if len(reference)!=(120<<f['lm'])*x['channels'] or len(candidate)!=len(reference):raise ValueError('invalid synthesis PCM shape')
            # A sequence-scaled absolute allowance handles destructive MDCT cancellation.
            scale=sequence_scale
            for si,(v,w) in enumerate(zip(reference,candidate)):
                if type(v)not in(int,float) or type(w)not in(int,float) or not math.isfinite(v) or not math.isfinite(w) or abs(v-w)>ABSOLUTE_TOLERANCE*scale+RELATIVE_TOLERANCE*abs(v):raise ValueError(json.dumps(dict(case=index,frame=fi,sample=si,expected=v,actual=w,scale=scale)))
                maximum=max(maximum,abs(v-w));maximum_scaled=max(maximum_scaled,abs(v-w)/scale);sample_count+=1
    return dict(maximumAbsoluteError=maximum,maximumSequenceScaledAbsoluteError=maximum_scaled,comparedSamples=sample_count)


def encode_fixture(records):
    """Store complete independent PCM vectors as exact little-endian float32 base64, retaining inputs."""
    return [dict(input=x,output=[base64.b64encode(struct.pack('<'+'f'*len(f),*f)).decode() for f in y['frames']]) for x,y in records]


def main():
    """Compile verified archive in isolation, compare complete vectors and optionally refresh fixtures."""
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source-archive',required=True,type=Path)
    parser.add_argument('--repository',default=Path(__file__).resolve().parents[3],type=Path);parser.add_argument('--cases',type=int,default=200);parser.add_argument('--seed',type=int,default=7120491)
    parser.add_argument('--report',type=Path);parser.add_argument('--write-fixtures',action='store_true');args=parser.parse_args()
    if not 1<=args.cases<=2000 or args.seed<0:parser.error('invalid case count/seed')
    repository=args.repository.resolve();fixed=fixed_cases();inputs=fixed+random_cases(args.cases,args.seed)
    with tempfile.TemporaryDirectory(prefix='discordkit-celt-synthesis-',dir='/private/tmp') as temporary:
        directory=Path(temporary);upstream=extract_verified_archive(args.source_archive.resolve(),directory)
        (upstream/'celt/verbatim.h').write_text(upstream_functions(upstream));c=directory/'oracle.c';s=directory/'driver.swift';c.write_text(C_DRIVER);s.write_text(SWIFT_DRIVER)
        reference=directory/'reference';owned=directory/'owned'
        run(['cc','-O2','-DOPUS_BUILD','-DVAR_ARRAYS','-Wl,-dead_strip','-I'+str(upstream/'include'),'-I'+str(upstream/'celt'),'-I'+str(upstream/'silk'),str(c)] + [str(upstream/'celt'/p) for p in ('bands.c','quant_bands.c','celt.c','mdct.c','kiss_fft.c','entcode.c')] + ['-lm','-o',str(reference)])
        run(['swiftc','-O','-module-cache-path',str(directory/'module-cache'),'-enable-upcoming-feature','ApproachableConcurrency','-default-isolation','nonisolated']+[str(repository/p) for p in OWNED_PATHS]+[str(s),'-o',str(owned)])
        expected=parse_outputs(run([str(reference)],commands(inputs)),len(inputs),'Official synthesis driver')
        actual=parse_outputs(run([str(owned)],'\n'.join(map(json.dumps,inputs)).encode()),len(inputs),'Owned synthesis driver')
        statistics=compare_results(inputs,expected,actual);records=encode_fixture(zip(fixed,expected));fixture=repository/FIXTURE_PATH
        if args.write_fixtures:fixture.write_text(swift_header(FIXTURE_PATH) + '/// Complete independent libopus float32 synthesis sequences, including retained histories.\nenum CELTSynthesisOracleFixtures {\n    static let json = #"""\n'+json.dumps(records,separators=(',',':'))+'\n"""#\n}\n')
        if not fixture.exists() or json.loads(fixture.read_text().split('#"""',1)[1].split('"""#',1)[0])!=records:raise ValueError('fixtures missing or differ; review --write-fixtures')
        report=dict(verifiedAt=datetime.now(timezone.utc).isoformat(),scope='ordinary CELT floating-point multiframe synthesis',version=VERSION,releaseURL=RELEASE_URL,sourceURL=SOURCE_URL,archiveSHA256=ARCHIVE_SHA256,seed=args.seed,randomSequences=args.cases,fixedSequences=len(fixed),totalSequences=len(inputs),totalFrames=sum(len(x['frames']) for x in inputs),tolerance=dict(absoluteTimesSequenceMaximum=ABSOLUTE_TOLERANCE,relative=RELATIVE_TOLERANCE),**statistics,excluded=['entropy/packets','full Opus codec','PLC/FEC','resampling','devices/realtime'],ownedSources={p:digest(repository/p) for p in OWNED_PATHS},upstreamSources={p:digest(upstream/p) for p in UPSTREAM_PATHS},fixture=dict(path=FIXTURE_PATH,sha256=digest(fixture)),verifierSHA256=digest(Path(__file__)),ccVersion=run(['cc','--version']).decode().splitlines()[0],swiftVersion=run(['swiftc','--version']).decode().splitlines()[0])
        if args.report:args.report.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))


if __name__=='__main__':main()

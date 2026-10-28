#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/verify_celt_plc_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Opt-in bounded CELT periodic/noise loss synthesis against pinned scalar libopus.

The archive is supplied explicitly, checked by SHA256, and never downloaded.
Upstream PLC is included verbatim in a development-only C driver, with no native
codec dependency in a product. This does not claim full Opus conformance or FEC.
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
from verify_celt_frame_oracle import build, UPSTREAM_PATHS as FRAME_UPSTREAM
from verify_celt_synthesis_oracle import OWNED_PATHS as SYNTHESIS_PATHS, frame
from verify_opus_range_oracle import ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION, digest, extract_verified_archive, run
from verify_celt_pulse_oracle import parse_outputs

OWNED_PATHS=SYNTHESIS_PATHS
UPSTREAM_PATHS=tuple(dict.fromkeys(FRAME_UPSTREAM+('celt/pitch.c','celt/celt_lpc.c','celt/arch.h')))
FIXTURE_PATH='Tests/DiscordVoiceCodecsTests/CELTConcealmentOracleFixtures.swift'
# Independent MDCT float rounding can be amplified by the 24th-order predictor
# across repeated recovery/loss cycles. This explicit 0.2%-of-sequence-peak bound
# is a numerical interoperability check, not decoded-PCM conformance or quality.
ABSOLUTE_TOLERANCE=0.002
RELATIVE_TOLERANCE=0.0001
C_DRIVER=r'''
#include <stdio.h>
#include <stdlib.h>
#include "celt_decoder.c"
static void array(const float *x,int n){putchar('[');for(int i=0;i<n;i++)printf("%s%.9g",i?",":"",x[i]);putchar(']');}
int main(void){int C,count;
 while(scanf("%d%d",&C,&count)==2){
  int error;CELTDecoder *st=calloc(1,celt_decoder_get_size(C));error=celt_decoder_init(st,48000,C);if(error)return 2;
  float *energies=(float*)(st->_decode_mem+(2048+120)*C),*background=energies+6*21;
  printf("{\"frames\":[");
  for(int f=0;f<count;f++){
   int LM,start,end,transient,pitch,qg,tapset,silence,lost,force;unsigned seed;
   if(scanf("%d%d%d%d%d%d%d%d%d%d%u",&LM,&start,&end,&transient,&pitch,&qg,&tapset,&silence,&lost,&force,&seed)!=11)return 2;
   int N=120<<LM;float X[1920],e[42],pcm[1920];
   for(int i=0;i<C*N;i++)if(scanf("%f",X+i)!=1)return 2;
   for(int i=0;i<C*21;i++)if(scanf("%f",e+i)!=1)return 2;
   st->start=start;st->end=end;
   float *out[2]={st->_decode_mem+2048-N,st->_decode_mem+2168+2048-N};
   if(lost){
    for(int i=0;i<C*21;i++)background[i]=-28;
    if(force)st->skip_plc=1;
    celt_decode_lost(st,N,LM);
   }else{
    if(st->loss_duration==0)st->skip_plc=0;
    for(int c=0;c<C;c++)memmove(st->_decode_mem+c*2168,st->_decode_mem+c*2168+N,(2048-N+120)*sizeof(float));
    if(st->prefilter_and_fold)prefilter_and_fold(st,N);
    for(int i=0;i<C*21;i++)energies[i]=e[i];
    celt_synthesis(st->mode,X,out,energies,start,end,C,C,transient,LM,1,silence,0);
    float gain=pitch?.09375f*(qg+1):0;
    for(int c=0;c<C;c++){
     comb_filter(out[c],out[c],st->postfilter_period_old,st->postfilter_period,120,st->postfilter_gain_old,st->postfilter_gain,st->postfilter_tapset_old,st->postfilter_tapset,st->mode->window,120,0);
     if(LM)comb_filter(out[c]+120,out[c]+120,st->postfilter_period,pitch,N-120,st->postfilter_gain,gain,st->postfilter_tapset,tapset,st->mode->window,120,0);
    }
    st->postfilter_period_old=st->postfilter_period;st->postfilter_gain_old=st->postfilter_gain;st->postfilter_tapset_old=st->postfilter_tapset;
    st->postfilter_period=pitch;st->postfilter_gain=gain;st->postfilter_tapset=tapset;
    if(LM){st->postfilter_period_old=pitch;st->postfilter_gain_old=gain;st->postfilter_tapset_old=tapset;}
    st->loss_duration=0;st->plc_duration=0;st->last_frame_type=FRAME_NORMAL;st->prefilter_and_fold=0;st->rng=seed;
   }
   deemphasis(out,pcm,N,C,1,st->mode->preemph,st->preemph_memD,0);
   printf("%s{\"pcm\":",f?",":"");array(pcm,N*C);printf(",\"energies\":");array(energies,C*21);
   printf(",\"seed\":%u,\"duration\":%d,\"noise\":%s,\"pitch\":%d}",st->rng,st->loss_duration,lost&&st->last_frame_type==FRAME_PLC_NOISE?"true":"false",lost&&st->last_frame_type==FRAME_PLC_PERIODIC?st->last_pitch_index:0);
  }puts("]}");free(st);
 }return 0;
}
'''
SWIFT_DRIVER=r'''
import Foundation
struct Frame:Decodable{let lm:Int;let start:Int;let end:Int;let transient:Bool;let period:Int;let gainIndex:Int;let tapset:Int;let silence:Bool;let lost:Bool;let force:Bool;let seed:UInt32;let coefficients:[Float];let energies:[Float]}
struct Input:Decodable{let channels:Int;let frames:[Frame]}
struct OutputFrame:Encodable{let pcm:[Float];let energies:[Float];let seed:UInt32;let duration:Int;let noise:Bool;let pitch:Int}
struct Output:Encodable{let frames:[OutputFrame]}
@main struct Driver{
 /// Executes caller-owned explicit signal/loss frames without importing any reference codec.
 static func main()throws{while let line=readLine(){let x=try JSONDecoder().decode(Input.self,from:Data(line.utf8));var s=try CELTSynthesis(channelCount:x.channels);var frames=[OutputFrame]();var energies=Array(repeating:Float(0),count:21*x.channels);var seed:UInt32=0
  for f in x.frames{if f.lost{let p=try s.conceal(frameSampleCount:120<<f.lm,bandLogEnergies:energies,backgroundLogEnergies:Array(repeating:-28,count:21*x.channels),seed:seed,startBand:f.start,endBand:f.end,forceNoise:f.force);energies=p.bandLogEnergies;seed=p.seed;frames.append(OutputFrame(pcm:p.samples,energies:energies,seed:seed,duration:p.lossDuration,noise:p.usesNoise,pitch:p.pitchPeriod))}
   else{let filter=f.period==0 ? nil:try CELTPostfilterParameters(period:f.period,gainIndex:f.gainIndex,tapset:f.tapset);let samples=try s.synthesize(normalizedCoefficients:f.coefficients,bandLogEnergies:f.energies,frameSampleCount:120<<f.lm,startBand:f.start,endBand:f.end,isTransient:f.transient,postfilter:filter,silence:f.silence);energies=f.energies;seed=f.seed;frames.append(OutputFrame(pcm:samples,energies:energies,seed:seed,duration:0,noise:false,pitch:0))}}
  print(String(decoding:try JSONEncoder().encode(Output(frames:frames)),as:UTF8.self))}}
}
'''


def snapshot_sources(repository,directory,paths):
    """Copy each relative owned source exactly once and fingerprint the actual compiler inputs.

    The returned ordered paths live only in the caller-owned temporary directory.
    Source edits after a file is read cannot alter its compiled snapshot. Existing
    files are required; I/O errors abort verification rather than omitting inputs.
    """
    snapshots=[];fingerprints={}
    for name in paths:
        destination=directory/name
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes((repository/name).read_bytes())
        snapshots.append(destination);fingerprints[name]=digest(destination)
    return snapshots,fingerprints


def source_drift(repository,fingerprints):
    """Return current hashes only for sources changed after their compiled snapshots were read.

    An empty mapping confirms that every current source still matches its compiled
    input. A missing/unreadable source aborts verification with the underlying I/O
    error; concurrent development is recorded explicitly instead of mislabelled.
    """
    return {name:current for name,previous in fingerprints.items() if (current:=digest(repository/name))!=previous}


def step(lm,channels,index,lost=False,start=0,force=False,filtered=False):
    """Create finite float32-exact independent spectra and explicit packet-loss decisions."""
    result=frame(lm,channels,start=start,energy=4,phase=index,period=147 if filtered else 0,gain=3,tapset=index%3)
    result.update(lost=lost,force=force,seed=(67168251+index*6331)&0xffffffff)
    return result


def fixed_cases():
    """Cover cold noise, periodic loss, 100-ms noise transition, filter recovery and high bands."""
    cases=[]
    for channels in (1,2):
        for lm in range(4):
            frames=[step(lm,channels,i) for i in range(3)]
            frames += [step(lm,channels,i,lost=True) for i in range(3,3+42//(1<<lm))]
            frames += [step(lm,channels,80),step(lm,channels,81,lost=True),step(lm,channels,82),step(lm,channels,83),step(lm,channels,84,lost=True)]
            cases.append(dict(channels=channels,frames=frames))
        cases.append(dict(channels=channels,frames=[step(0,channels,0,lost=True),step(3,channels,1,lost=True),step(2,channels,2)]))
        cases.append(dict(channels=channels,frames=[step(3,channels,i,lost=i>=4 and i%3!=0,filtered=True) for i in range(16)]))
        cases.append(dict(channels=channels,frames=[step(2,channels,i,lost=i>1,start=17) for i in range(5)]))
    return cases


def random_cases(count,seed):
    """Generate seeded bounded loss/recovery bursts with changing duration and channel spectra."""
    rng=random.Random(seed);cases=[]
    for _ in range(count):
        channels=rng.randint(1,2);frames=[];filtered=bool(rng.randrange(2))
        for index in range(rng.randint(6,30)):
            f=step(rng.randrange(4),channels,index,lost=rng.randrange(3)!=0,filtered=filtered)
            f['coefficients']=[rng.randint(-512,512)/512 for _ in f['coefficients']]
            f['energies']=[rng.randint(-128,128)/16 for _ in f['energies']]
            frames.append(f)
        cases.append(dict(channels=channels,frames=frames))
    return cases


def commands(inputs):
    """Serialize explicit synthetic frames for the independently compiled C driver."""
    lines=[]
    for x in inputs:
        fields=[x['channels'],len(x['frames'])]
        for f in x['frames']:
            fields += [int(f[k]) for k in ('lm','start','end','transient','period','gainIndex','tapset','silence','lost','force','seed')]+f['coefficients']+f['energies']
        lines.append(' '.join(map(str,fields)))
    return '\n'.join(lines).encode()


def compare_results(inputs,expected,actual):
    """Require exact paths, pitch/envelope/seed/duration and every finite PCM sample within tolerance."""
    if len(inputs)!=len(expected) or len(inputs)!=len(actual):raise ValueError('PLC case count mismatch')
    samples=0;maximum=0.;maximum_scaled=0.;losses=0;noise=0
    for case,(x,e,a) in enumerate(zip(inputs,expected,actual)):
        if set(e)!={'frames'} or set(a)!={'frames'} or len(e['frames'])!=len(x['frames']) or len(a['frames'])!=len(x['frames']):raise ValueError('PLC sequence shape mismatch')
        scale=max(1,max(abs(v) for f in e['frames'] for v in f['pcm']))
        for index,(f,reference,candidate) in enumerate(zip(x['frames'],e['frames'],a['frames'])):
            if set(reference)!=set(candidate) or set(reference)!={'pcm','energies','seed','duration','noise','pitch'}:raise ValueError('PLC output fields mismatch')
            for key in ('energies','seed','duration','noise','pitch'):
                if reference[key]!=candidate[key]:raise ValueError(json.dumps(dict(case=case,frame=index,key=key,expected=reference[key],actual=candidate[key])))
            if len(reference['pcm'])!=(120<<f['lm'])*x['channels'] or len(candidate['pcm'])!=len(reference['pcm']):raise ValueError('PLC PCM dimensions mismatch')
            for position,(v,w) in enumerate(zip(reference['pcm'],candidate['pcm'])):
                if type(v)not in(int,float) or type(w)not in(int,float) or not math.isfinite(v) or not math.isfinite(w) or abs(v-w)>ABSOLUTE_TOLERANCE*scale+RELATIVE_TOLERANCE*abs(v):raise ValueError(json.dumps(dict(case=case,frame=index,sample=position,expected=v,actual=w,scale=scale)))
                maximum=max(maximum,abs(v-w));maximum_scaled=max(maximum_scaled,abs(v-w)/scale);samples+=1
            losses+=bool(f['lost']);noise+=bool(reference['noise'])
    return dict(comparedSamples=samples,maximumAbsoluteError=maximum,maximumSequenceScaledAbsoluteError=maximum_scaled,concealedFrames=losses,noiseFrames=noise,periodicFrames=losses-noise)


def fixture_records(inputs,outputs):
    """Store full independent PCM as float32 base64 and preserve every exact diagnostic field."""
    return [dict(input=x,output=[{**f,'pcm':base64.b64encode(struct.pack('<'+'f'*len(f['pcm']),*f['pcm'])).decode()} for f in y['frames']]) for x,y in zip(inputs,outputs)]


def main():
    """Build the pinned development oracle, compare bounded loss streams and optionally write evidence."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-archive',required=True,type=Path);parser.add_argument('--reference-build',type=Path)
    parser.add_argument('--repository',type=Path,default=Path(__file__).resolve().parents[3]);parser.add_argument('--cases',type=int,default=100)
    parser.add_argument('--seed',type=int,default=6716409);parser.add_argument('--write-fixtures',action='store_true');parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    if not 1<=args.cases<=1000 or args.seed<0:parser.error('cases must be 1...1000; seed nonnegative')
    repository=args.repository.resolve();fixed=fixed_cases();inputs=fixed+random_cases(args.cases,args.seed)
    with tempfile.TemporaryDirectory(prefix='discordkit-celt-plc-',dir='/private/tmp') as temporary:
        directory=Path(temporary);upstream=extract_verified_archive(args.source_archive.resolve(),directory)
        snapshots,compiled_hashes=snapshot_sources(repository,directory/'owned-sources',OWNED_PATHS)
        reference_source=args.reference_build.resolve() if args.reference_build else upstream
        if args.reference_build:
            for name in UPSTREAM_PATHS:
                if digest(upstream/name)!=digest(reference_source/name):raise ValueError('reference build source differs from verified archive')
        else:
            for helper in ('compile','config.guess','config.sub','depcomp','install-sh','missing','test-driver'):(upstream/helper).chmod(0o755)
            build(['sh',str(upstream/'configure'),'--disable-intrinsics','--disable-rtcd','--disable-shared','--disable-extra-programs','--disable-doc','--disable-dependency-tracking','CFLAGS=-O2 -ffp-contract=off'],upstream)
            build(['make','-j2'],upstream)
        c,s=directory/'oracle.c',directory/'driver.swift';c.write_text(C_DRIVER);s.write_text(SWIFT_DRIVER)
        reference,owned=directory/'reference',directory/'owned'
        run(['cc','-O2','-ffp-contract=off','-DHAVE_CONFIG_H','-I'+str(reference_source),'-I'+str(reference_source/'include'),'-I'+str(reference_source/'celt'),'-I'+str(reference_source/'silk'),str(c),str(reference_source/'.libs/libopus.a'),'-lm','-o',str(reference)])
        run(['swiftc','-O','-module-cache-path',str(directory/'module-cache'),'-enable-upcoming-feature','ApproachableConcurrency','-default-isolation','nonisolated']+[str(p) for p in snapshots]+[str(s),'-o',str(owned)])
        expected=parse_outputs(run([str(reference)],commands(inputs)),len(inputs),'Official PLC driver')
        actual=parse_outputs(run([str(owned)],'\n'.join(map(json.dumps,inputs)).encode()),len(inputs),'Owned PLC driver')
        statistics=compare_results(inputs,expected,actual);records=fixture_records(fixed,expected[:len(fixed)]);fixture=repository/FIXTURE_PATH
        if args.write_fixtures:fixture.write_text(swift_header(FIXTURE_PATH) + '/// Complete independent scalar libopus periodic/noise PLC and recovery sequences.\nenum CELTConcealmentOracleFixtures {\n    static let json = #"""\n'+json.dumps(records,separators=(',',':'))+'\n"""#\n}\n')
        if not fixture.exists() or json.loads(fixture.read_text().split('#"""',1)[1].split('"""#',1)[0])!=records:raise ValueError('PLC fixture differs; review --write-fixtures')
        report=dict(verifiedAt=datetime.now(timezone.utc).isoformat(),scope='ordinary CELT periodic/noise PLC, TDAC recovery and duration changes',version=VERSION,releaseURL=RELEASE_URL,sourceURL=SOURCE_URL,archiveSHA256=ARCHIVE_SHA256,seed=args.seed,fixedSequences=len(fixed),randomSequences=args.cases,totalSequences=len(inputs),totalFrames=sum(len(x['frames']) for x in inputs),**statistics,tolerance=dict(absoluteTimesSequenceMaximum=ABSOLUTE_TOLERANCE,relative=RELATIVE_TOLERANCE),exact=['pitch lag','loss path','loss duration','band envelopes','random seeds'],excluded=['SILK/hybrid','FEC','full Opus conformance','devices/realtime'],ownedSources=compiled_hashes,sourceDriftAtCompletion=source_drift(repository,compiled_hashes),upstreamSources={p:digest(upstream/p) for p in UPSTREAM_PATHS},fixture=dict(path=FIXTURE_PATH,sha256=digest(fixture)),verifierSHA256=digest(Path(__file__)),referenceBuild=dict(librarySHA256=digest(reference_source/'.libs/libopus.a'),configurationSHA256=digest(reference_source/'config.h')))
        if args.report:args.report.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))


if __name__=='__main__':main()

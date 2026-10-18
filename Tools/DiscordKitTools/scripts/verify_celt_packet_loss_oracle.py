#!/usr/bin/env python3
"""Opt-in actual compressed CELT loss/recovery interoperability with pinned scalar libopus.

Every missing packet is encoded but withheld from the reference and owned decoders,
so subsequent predictive frames exercise real loss recovery. No codec is linked by
products or ordinary tests. Official full Opus conformance, SILK/FEC and devices
remain outside this bounded local check.
"""
import argparse
import base64
from datetime import datetime,timezone
import json
import math
from pathlib import Path
import random
import struct
import tempfile
from verify_celt_frame_oracle import OWNED_PATHS as FRAME_PATHS, UPSTREAM_PATHS, build, pcm_frame
from verify_opus_range_oracle import ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION, digest, extract_verified_archive, run
from verify_celt_pulse_oracle import parse_outputs
from verify_celt_plc_oracle import snapshot_sources, source_drift

OWNED_PATHS=FRAME_PATHS+('Sources/DiscordVoiceCodecs/OpusPacket.swift','Sources/DiscordVoiceCodecs/CELTPacketCodec.swift')
FIXTURE_PATH='Tests/DiscordVoiceCodecsTests/CELTPacketLossOracleFixtures.swift'
MEDIA_PATH='Sources/DiscordMedia/PCM.swift'
# Repeated 24th-order prediction/recovery can amplify the independent MDCT's
# floating-point rounding. This 0.6%-of-sequence-peak stress-test allowance is
# explicitly broader than codec conformance and conveys no perceptual guarantee.
ABSOLUTE_TOLERANCE=0.006
RELATIVE_TOLERANCE=0.0001
C_DRIVER=r'''
#include <stdio.h>
#include <stdlib.h>
#include "opus.h"
static void array(const float *x,int n){putchar('[');for(int i=0;i<n;i++)printf("%s%.9g",i?",":"",x[i]);putchar(']');}
static int bandwidth(int end){return end==13?OPUS_BANDWIDTH_NARROWBAND:end==17?OPUS_BANDWIDTH_WIDEBAND:end==19?OPUS_BANDWIDTH_SUPERWIDEBAND:OPUS_BANDWIDTH_FULLBAND;}
int main(void){int C,count;
 while(scanf("%d%d",&C,&count)==2){
  int error;OpusEncoder *enc=opus_encoder_create(48000,C,OPUS_APPLICATION_RESTRICTED_LOWDELAY,&error);if(error)return 2;
  OpusDecoder *dec=opus_decoder_create(48000,C,&error);if(error)return 2;
  opus_encoder_ctl(enc,OPUS_SET_VBR(0));opus_encoder_ctl(enc,OPUS_SET_FORCE_CHANNELS(C));
  printf("{\"frames\":[");
  for(int f=0;f<count;f++){
   int n,end,bytes,intra,lost;float pcm[1920],out[1920];unsigned char data[1276];
   if(scanf("%d%d%d%d%d",&n,&end,&bytes,&intra,&lost)!=5)return 2;
   for(int i=0;i<n*C;i++)if(scanf("%f",pcm+i)!=1)return 2;
   opus_encoder_ctl(enc,OPUS_SET_BANDWIDTH(bandwidth(end)));opus_encoder_ctl(enc,OPUS_SET_BITRATE((bytes+1)*8*48000/n));opus_encoder_ctl(enc,OPUS_SET_PREDICTION_DISABLED(intra));
   int length=opus_encode_float(enc,pcm,n,data,bytes+1);
   if(length<3||length>1276||opus_packet_get_nb_frames(data,length)!=1||opus_packet_get_samples_per_frame(data,48000)!=n||opus_packet_get_bandwidth(data)!=bandwidth(end)||(data[0]&3)!=0||((data[0]>>2)&1)!=C-1)return 3;
   int decoded=opus_decode_float(dec,lost?NULL:data,lost?0:length,out,n,0);if(decoded!=n)return 4;
   opus_uint32 range;opus_decoder_ctl(dec,OPUS_GET_FINAL_RANGE(&range));
   printf("%s{\"packet\":[",f?",":"");for(int i=0;i<length;i++)printf("%s%u",i?",":"",data[i]);printf("],\"range\":%u,\"pcm\":",range);array(out,n*C);putchar('}');
  }puts("]}");opus_encoder_destroy(enc);opus_decoder_destroy(dec);
 }return 0;
}
'''
SWIFT_DRIVER=r'''
import Foundation
struct Frame:Decodable{let n:Int;let end:Int;let lost:Bool;let packet:[UInt8]}
struct Input:Decodable{let channels:Int;let frames:[Frame]}
struct FrameOutput:Encodable{let range:UInt32;let pcm:[Float]}
struct Output:Encodable{let frames:[FrameOutput]}
@main struct Driver{
 /// Decodes only received packets and advances exact missing intervals through the owned packet facade.
 static func main()throws{while let line=readLine(){let x=try JSONDecoder().decode(Input.self,from:Data(line.utf8));var decoder=try CELTPacketDecoder(channelCount:x.channels);var frames=[FrameOutput]();var end=21
  for f in x.frames{if f.lost{let p=try decoder.conceal(frameSampleCount:f.n,endBand:end);frames.append(FrameOutput(range:0,pcm:p.samples))}
   else{let d=try decoder.decode(Data(f.packet));end=f.end;frames.append(FrameOutput(range:d[0].finalRange,pcm:d.flatMap(\.samples)))}}
  print(String(decoding:try JSONEncoder().encode(Output(frames:frames)),as:UTF8.self))}}
}
'''


def stream(channels,size,end=21,variable=False):
    """Build real PCM streams with periodic/transient input, >100ms losses and multiple recoveries."""
    frames=[]
    count=3+42//(size//120)+5
    for index in range(count):
        lost=3<=index<count-5 or index==count-1
        n=(120,960,240,480)[index%4] if variable else size
        band=(13,17,19,21)[index%4] if variable else end
        frames.append(dict(n=n,end=band,bytes=100,intra=index%11==0,lost=lost,
            pcm=pcm_frame(n,channels,index,kind='transient' if index%7==0 else 'tone',frequency=220 if index<10 else 580)))
    return dict(channels=channels,frames=frames)


def fixed_cases():
    """Provide all channel extremes plus short/long loss bursts and duration/bandwidth changes."""
    return [stream(channels,size) for channels in (1,2) for size in (120,960)]+[stream(channels,480,variable=True) for channels in (1,2)]


def random_cases(count,seed):
    """Generate deterministic actually encoded packet streams without deriving inputs from owned output."""
    rng=random.Random(seed);cases=[]
    for case in range(count):
        channels=rng.randint(1,2);frames=[]
        for index in range(rng.randint(8,40)):
            n=rng.choice((120,240,480,960));end=rng.choice((13,17,19,21))
            frames.append(dict(n=n,end=end,bytes=rng.choice((40,80,120,160)),intra=rng.randrange(9)==0,
                lost=index>=2 and rng.randrange(3)!=0,
                pcm=pcm_frame(n,channels,case*40+index,kind=rng.choice(('tone','transient','noise','silence')),frequency=rng.choice((110,220,440,1000)))))
        cases.append(dict(channels=channels,frames=frames))
    return cases


def commands(inputs):
    """Serialize real PCM and explicit withholding decisions for the independent full codec driver."""
    lines=[]
    for x in inputs:
        fields=[x['channels'],len(x['frames'])]
        for f in x['frames']:fields += [int(f[k]) for k in ('n','end','bytes','intra','lost')]+f['pcm']
        lines.append(' '.join(map(str,fields)))
    return '\n'.join(lines).encode()


def compare_results(inputs,expected,actual):
    """Require every received final range and complete finite loss/recovery PCM within declared tolerance."""
    if len(inputs)!=len(expected) or len(inputs)!=len(actual):raise ValueError('packet-loss case count mismatch')
    samples=0;lost=0;maximum=0.;scaled=0.
    for case,(x,e,a) in enumerate(zip(inputs,expected,actual)):
        if set(e)!={'frames'} or set(a)!={'frames'} or len(e['frames'])!=len(x['frames']) or len(a['frames'])!=len(x['frames']):raise ValueError('packet-loss frame count mismatch')
        scale=max(1,max(abs(v) for f in e['frames'] for v in f['pcm']))
        for index,(f,reference,candidate) in enumerate(zip(x['frames'],e['frames'],a['frames'])):
            if set(candidate)!={'range','pcm'} or reference['range']!=candidate['range']:raise ValueError('packet-loss final range mismatch')
            if len(reference['pcm'])!=f['n']*x['channels'] or len(candidate['pcm'])!=len(reference['pcm']):raise ValueError('packet-loss PCM shape mismatch')
            for position,(v,w) in enumerate(zip(reference['pcm'],candidate['pcm'])):
                if type(v)not in(int,float) or type(w)not in(int,float) or not math.isfinite(v) or not math.isfinite(w) or abs(v-w)>ABSOLUTE_TOLERANCE*scale+RELATIVE_TOLERANCE*abs(v):raise ValueError(json.dumps(dict(case=case,frame=index,lost=f['lost'],sample=position,expected=v,actual=w,scale=scale)))
                maximum=max(maximum,abs(v-w));scaled=max(scaled,abs(v-w)/scale);samples+=1
            lost+=bool(f['lost'])
    return dict(comparedSamples=samples,concealedPackets=lost,maximumAbsoluteError=maximum,maximumSequenceScaledAbsoluteError=scaled)


def fixture_records(inputs,outputs):
    """Retain exact actual packets, withholding decisions, full independent PCM and final ranges."""
    return [dict(channels=x['channels'],frames=[dict(n=f['n'],end=f['end'],lost=f['lost'],packet=e['packet'],range=e['range'],pcm=base64.b64encode(struct.pack('<'+'f'*len(e['pcm']),*e['pcm'])).decode()) for f,e in zip(x['frames'],out['frames'])]) for x,out in zip(inputs,outputs)]


def main():
    """Build an explicit pinned oracle and compare received, missing and recovered compressed frames."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-archive',required=True,type=Path);parser.add_argument('--reference-build',type=Path)
    parser.add_argument('--repository',type=Path,default=Path(__file__).resolve().parents[3]);parser.add_argument('--cases',type=int,default=100)
    parser.add_argument('--seed',type=int,default=6716410);parser.add_argument('--write-fixtures',action='store_true');parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    if not 1<=args.cases<=1000 or args.seed<0:parser.error('cases must be 1...1000; seed nonnegative')
    repository=args.repository.resolve();fixed=fixed_cases();inputs=fixed+random_cases(args.cases,args.seed)
    with tempfile.TemporaryDirectory(prefix='discordkit-celt-packet-loss-',dir='/private/tmp') as temporary:
        directory=Path(temporary);upstream=extract_verified_archive(args.source_archive.resolve(),directory)
        snapshots,compiled_hashes=snapshot_sources(repository,directory/'owned-sources',OWNED_PATHS+(MEDIA_PATH,))
        source=args.reference_build.resolve() if args.reference_build else upstream
        if args.reference_build:
            for name in UPSTREAM_PATHS:
                if digest(upstream/name)!=digest(source/name):raise ValueError('reference build differs from verified archive')
        else:
            for helper in ('compile','config.guess','config.sub','depcomp','install-sh','missing','test-driver'):(upstream/helper).chmod(0o755)
            build(['sh',str(upstream/'configure'),'--disable-intrinsics','--disable-rtcd','--disable-shared','--disable-extra-programs','--disable-doc','--disable-dependency-tracking','CFLAGS=-O2 -ffp-contract=off'],upstream)
            build(['make','-j2'],upstream)
        c,s=directory/'oracle.c',directory/'driver.swift';c.write_text(C_DRIVER);s.write_text(SWIFT_DRIVER)
        reference,owned=directory/'reference',directory/'owned'
        run(['cc','-O2','-ffp-contract=off','-I'+str(source/'include'),str(c),str(source/'.libs/libopus.a'),'-lm','-o',str(reference)])
        run(['swiftc','-O','-emit-module','-emit-library','-module-name','DiscordMedia','-module-cache-path',str(directory/'module-cache'),'-enable-upcoming-feature','ApproachableConcurrency','-default-isolation','nonisolated',str(snapshots[-1]),'-emit-module-path',str(directory/'DiscordMedia.swiftmodule'),'-o',str(directory/'libDiscordMedia.dylib')])
        run(['swiftc','-O','-module-cache-path',str(directory/'module-cache'),'-enable-upcoming-feature','ApproachableConcurrency','-default-isolation','nonisolated','-I',str(directory),'-L',str(directory),'-lDiscordMedia','-Xlinker','-rpath','-Xlinker',str(directory)]+[str(p) for p in snapshots[:-1]]+[str(s),'-o',str(owned)])
        expected=parse_outputs(run([str(reference)],commands(inputs)),len(inputs),'Official compressed-loss driver')
        prepared=[dict(channels=x['channels'],frames=[dict(n=f['n'],end=f['end'],lost=f['lost'],packet=e['packet']) for f,e in zip(x['frames'],out['frames'])]) for x,out in zip(inputs,expected)]
        actual=parse_outputs(run([str(owned)],'\n'.join(map(json.dumps,prepared)).encode()),len(inputs),'Owned compressed-loss driver')
        statistics=compare_results(inputs,expected,actual);records=fixture_records(fixed,expected[:len(fixed)]);fixture=repository/FIXTURE_PATH
        if args.write_fixtures:fixture.write_text('/// Complete independent actual compressed CELT packet loss/recovery PCM vectors.\nenum CELTPacketLossOracleFixtures {\n    static let json = #"""\n'+json.dumps(records,separators=(',',':'))+'\n"""#\n}\n')
        if not fixture.exists() or json.loads(fixture.read_text().split('#"""',1)[1].split('"""#',1)[0])!=records:raise ValueError('packet-loss fixture differs; review --write-fixtures')
        report=dict(verifiedAt=datetime.now(timezone.utc).isoformat(),scope='actual compressed CELT packets withheld and recovered through full official Opus API',version=VERSION,releaseURL=RELEASE_URL,sourceURL=SOURCE_URL,archiveSHA256=ARCHIVE_SHA256,seed=args.seed,fixedSequences=len(fixed),randomSequences=args.cases,totalSequences=len(inputs),totalFrames=sum(len(x['frames']) for x in inputs),**statistics,tolerance=dict(absoluteTimesSequenceMaximum=ABSOLUTE_TOLERANCE,relative=RELATIVE_TOLERANCE),exact=['every received and lost packet final range'],excluded=['SILK/hybrid','FEC','full decoded-PCM conformance','devices/realtime'],ownedSources=compiled_hashes,sourceDriftAtCompletion=source_drift(repository,compiled_hashes),upstreamSources={p:digest(upstream/p) for p in UPSTREAM_PATHS},fixture=dict(path=FIXTURE_PATH,sha256=digest(fixture)),verifierSHA256=digest(Path(__file__)),referenceBuild=dict(librarySHA256=digest(source/'.libs/libopus.a'),configurationSHA256=digest(source/'config.h')))
        if args.report:args.report.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))


if __name__=='__main__':main()

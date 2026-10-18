#!/usr/bin/env python3
"""Opt-in bidirectional ordinary CELT interoperability with pinned scalar libopus; no runtime dependency."""
import argparse
import base64
from datetime import datetime,timezone
import json
import math
from pathlib import Path
import random
import struct
import subprocess
import tempfile
from verify_celt_shape_oracle import OWNED_PATHS as SHAPE_PATHS,float32
from verify_celt_synthesis_oracle import OWNED_PATHS as SYNTHESIS_PATHS
from verify_opus_range_oracle import VERSION,RELEASE_URL,SOURCE_URL,ARCHIVE_SHA256,digest,extract_verified_archive,run
from verify_celt_pulse_oracle import parse_outputs

OWNED_PATHS=tuple(dict.fromkeys(SHAPE_PATHS+SYNTHESIS_PATHS+(
    'Sources/DiscordVoiceCodecs/CELTEnergyQuantizer.swift','Sources/DiscordVoiceCodecs/CELTFrameEncoder.swift',
    'Sources/DiscordVoiceCodecs/CELTFrameDecoder.swift')))
UPSTREAM_PATHS=('src/opus_encoder.c','src/opus_decoder.c','src/opus.c','celt/celt_encoder.c','celt/celt_decoder.c',
    'celt/bands.c','celt/quant_bands.c','celt/rate.c','celt/vq.c','celt/mdct.c','celt/kiss_fft.c','celt/static_modes_float.h')
FIXTURE_PATH='Tests/DiscordVoiceCodecsTests/CELTFrameOracleFixtures.swift'
ABSOLUTE_TOLERANCE=3e-6
RELATIVE_TOLERANCE=8e-6
C_DRIVER=r'''
#include <stdio.h>
#include <stdlib.h>
#include "opus.h"
static void array(const float *x,int n){putchar('[');for(int i=0;i<n;i++)printf("%s%.9g",i?",":"",x[i]);putchar(']');}
static int bandwidth(int end){return end==13?OPUS_BANDWIDTH_NARROWBAND:end==17?OPUS_BANDWIDTH_WIDEBAND:end==19?OPUS_BANDWIDTH_SUPERWIDEBAND:OPUS_BANDWIDTH_FULLBAND;}
static int lm(int n){return n==120?0:n==240?1:n==480?2:3;}
int main(void){int mode,c,count;
 while(scanf("%d%d%d",&mode,&c,&count)==3){
  int error;OpusEncoder *enc=opus_encoder_create(48000,c,OPUS_APPLICATION_RESTRICTED_LOWDELAY,&error);if(error)return 2;
  OpusDecoder *dec=opus_decoder_create(48000,c,&error);if(error)return 2;
  opus_encoder_ctl(enc,OPUS_SET_VBR(0));opus_encoder_ctl(enc,OPUS_SET_FORCE_CHANNELS(c));opus_encoder_ctl(enc,OPUS_SET_COMPLEXITY(10));
  int prior_n=0,prior_end=0;
  printf("{\"frames\":[");
  for(int f=0;f<count;f++){
   int n,end,bytes,intra,length;float pcm[1920],out[1920];unsigned char data[1276];
   if(scanf("%d%d%d%d",&n,&end,&bytes,&intra)!=4)return 2;
   if(mode==0){
    for(int j=0;j<n*c;j++)if(scanf("%f",&pcm[j])!=1)return 2;
    opus_encoder_ctl(enc,OPUS_SET_BANDWIDTH(bandwidth(end)));opus_encoder_ctl(enc,OPUS_SET_BITRATE((bytes+1)*8*48000/n));
    opus_encoder_ctl(enc,OPUS_SET_PREDICTION_DISABLED(intra));
    length=opus_encode_float(enc,pcm,n,data,bytes+1);
    if(length<3||length>1276||opus_packet_get_nb_frames(data,length)!=1||opus_packet_get_samples_per_frame(data,48000)!=n||opus_packet_get_bandwidth(data)!=bandwidth(end)||(data[0]&3)!=0||((data[0]>>2)&1)!=c-1){fprintf(stderr,"packet invalid f%d n%d c%d end%d length%d toc%d\n",f,n,c,end,length,data[0]);return 3;}
   }else{
    if(f>0&&(n!=prior_n||end!=prior_end))opus_decoder_ctl(dec,OPUS_RESET_STATE);
    int group=end==13?0:end==17?1:end==19?2:3;
    data[0]=((16+4*group+lm(n))<<3)|((c-1)<<2);length=bytes+1;
    for(int j=1;j<length;j++){unsigned v;if(scanf("%u",&v)!=1)return 2;data[j]=v;}
   }
   prior_n=n;prior_end=end;
   int samples=opus_decode_float(dec,data,length,out,n,0);if(samples!=n){fprintf(stderr,"decode failure %d\n",samples);return 3;}
   opus_uint32 range;opus_decoder_ctl(dec,OPUS_GET_FINAL_RANGE(&range));
   printf("%s{\"raw\":[",f?",":"");for(int j=1;j<length;j++)printf("%s%u",j>1?",":"",data[j]);
   printf("],\"toc\":%u,\"range\":%u,\"pcm\":",data[0],range);array(out,n*c);putchar('}');
  }
  puts("]}");opus_encoder_destroy(enc);opus_decoder_destroy(dec);
 }
 return 0;
}
'''
SWIFT_DRIVER=r'''
import Foundation
struct Frame:Decodable{let n:Int;let end:Int;let bytes:Int;let intra:Bool;let pcm:[Float];let raw:[UInt8]}
struct Input:Decodable{let c:Int;let frames:[Frame]}
struct Decoded:Encodable{let pcm:[Float];let range:UInt32;let bits:Int;let transient:Bool;let silence:Bool;let postfilter:Bool}
struct Encoded:Encodable{let raw:[UInt8];let range:UInt32;let pcm:[Float];let bits:Int}
struct Output:Encodable{let decoded:[Decoded];let encoded:[Encoded]}
@main struct Driver{
 /// Consumes explicit local scalar contexts; no official codec is imported by owned code.
 static func main()throws{
  while let line=readLine(){
   let x=try JSONDecoder().decode(Input.self,from:Data(line.utf8));var decoder=try CELTFrameDecoder(channelCount:x.c)
   var ownDecoder=try CELTFrameDecoder(channelCount:x.c);var encoder:CELTFrameEncoder?;var format:[Int]=[]
   var decoded:[Decoded]=[],encoded:[Encoded]=[]
   for f in x.frames{
    let d=try decoder.decode(Data(f.raw),frameSampleCount:f.n,endBand:f.end)
    var prefixDecoder=try OpusRangeDecoder(frame:Data(f.raw))
    let prefix=try CELTFrameHeader(frameSampleCount:f.n,channelCount:x.c,endBand:f.end).decodePrefix(from:&prefixDecoder)
    decoded.append(Decoded(pcm:d.samples,range:d.finalRange,bits:d.bitsUsed,transient:d.isTransient,silence:d.isSilence,postfilter:prefix.postfilter != nil))
    if format != [f.n,f.end]{encoder=try CELTFrameEncoder(frameSampleCount:f.n,channelCount:x.c,endBand:f.end);ownDecoder=try CELTFrameDecoder(channelCount:x.c);format=[f.n,f.end]}
    let e=try encoder!.encode(f.pcm,frameByteCount:f.bytes,intra:f.intra)
    let r=try ownDecoder.decode(e.bytes,frameSampleCount:f.n,endBand:f.end)
    encoded.append(Encoded(raw:Array(e.bytes),range:e.finalRange,pcm:r.samples,bits:e.bitsUsed))
   }
   print(String(decoding:try JSONEncoder().encode(Output(decoded:decoded,encoded:encoded)),as:UTF8.self))
  }
 }
}
'''


def pcm_frame(n,c,index,kind='tone',frequency=440.0):
    """Build normalized scalar-float PCM with deterministic pitch, silence and transient branches."""
    result=[];noise=random.Random(6716400+index)
    for j in range(n):
        for ch in range(c):
            t=(index*n+j)/48000
            if kind=='silence':v=0.0
            elif kind=='noise':v=noise.uniform(-.5,.5)
            elif kind=='impulse':v=(.85 if j in (n//2,n//2+1) else 0.0)*(1 if ch==0 else -.8)
            elif kind=='transient':v=noise.uniform(-.8,.8) if n//2<=j<n//2+48 else 0.0
            else:v=.2*math.sin(2*math.pi*frequency*t+ch*.7)+.04*math.sin(2*math.pi*frequency*3.1*t)
            result.append(float32(v))
    return result


def sequence(n=960,c=2,end=21,kinds=('tone','tone','transient','silence','silence'),byte_count=None):
    """Build a fixed format sequence, preserving real predictor/overlap/postfilter state."""
    b=byte_count or max(24,n*c//8)
    return dict(c=c,frames=[dict(n=n,end=end,bytes=b,intra=i==0,pcm=pcm_frame(n,c,i,kind)) for i,kind in enumerate(kinds)])


def fixed_cases():
    """Cover every ordinary duration, channel count and bandwidth with multiframe signal changes."""
    result=[sequence(n,c,end,kinds=('tone','transient','silence')) for n in (120,240,480,960) for c in (1,2) for end in (13,17,19,21)]
    for c in (1,2):
        result.append(sequence(960,c,21,kinds=('silence','silence','tone','tone','tone','tone','tone','impulse','noise','silence')))
    for c in (1,2):
        x=sequence(c=c,kinds=())
        x['frames']=[dict(n=n,end=end,bytes=max(32,n*c//8),intra=i==0,
            pcm=pcm_frame(n,c,i,kind)) for i,(n,end,kind) in enumerate([
                (960,21,'tone'),(120,13,'transient'),(480,19,'noise'),(240,17,'tone'),
                (960,21,'silence'),(480,13,'impulse'),(120,21,'tone'),(960,17,'tone')])]
        result.append(x)
    return result


def random_cases(count,seed):
    """Generate repeatable ordinary fixed-format sequences with varied rate and signal structure."""
    rng=random.Random(seed);result=[]
    for _ in range(count):
        n=rng.choice([120,240,480,960]);c=rng.randrange(1,3);end=rng.choice([13,17,19,21])
        b=rng.choice([12,24,32,48,64,96,128,240])
        x=sequence(n,c,end,kinds=[rng.choice(['tone','tone','noise','impulse','transient','silence']) for _ in range(rng.randrange(2,7))],byte_count=b)
        for f in x['frames']:f['intra']=rng.randrange(8)==0
        result.append(x)
    return result


def commands(inputs,encoded=None):
    """Serialize bounded PCM or owned bytes to independent full official Opus entry points."""
    lines=[]
    for i,x in enumerate(inputs):
        fields=[int(encoded is not None),x['c'],len(x['frames'])]
        for j,f in enumerate(x['frames']):
            b=f['bytes'] if encoded is None else len(encoded[i]['encoded'][j]['raw'])
            fields += [f['n'],f['end'],b,int(f['intra'])]
            fields += f['pcm'] if encoded is None else encoded[i]['encoded'][j]['raw']
        lines.append(' '.join(map(str,fields)))
    return '\n'.join(lines).encode()


def compare_results(inputs,native,owned,reverse):
    """Require exact native entropy ranges and sequence-scaled full PCM reconstruction both ways."""
    if not len(inputs)==len(native)==len(owned)==len(reverse):raise ValueError('sequence count mismatch')
    maximum=0.0;samples=0;transients=0;silences=0;postfilters=0
    for si,(x,n,o,r) in enumerate(zip(inputs,native,owned,reverse)):
        if len(n['frames'])!=len(x['frames']) or len(o['decoded'])!=len(x['frames']) or len(o['encoded'])!=len(x['frames']) or len(r['frames'])!=len(x['frames']):raise ValueError('frame count mismatch')
        for fi,(f,nf,rf,od,oe) in enumerate(zip(x['frames'],n['frames'],r['frames'],o['decoded'],o['encoded'])):
            for result in (nf,rf):
                if set(result)!={'raw','toc','range','pcm'}:raise ValueError('native schema mismatch')
                if not 2<=len(result['raw'])<=1275 or any(type(v)is not int or not 0<=v<=255 for v in result['raw']):raise ValueError('invalid native raw frame')
                group={13:0,17:1,19:2,21:3}[f['end']];lm={120:0,240:1,480:2,960:3}[f['n']]
                if result['toc']!=((16+4*group+lm)<<3)|((x['c']-1)<<2):raise ValueError('native TOC differs from supplied mode')
                if type(result['range'])is not int or not 0<result['range']<=0xffffffff:raise ValueError('invalid native range')
            if set(od)!={'pcm','range','bits','transient','silence','postfilter'} or set(oe)!={'raw','range','pcm','bits'}:raise ValueError('owned schema mismatch')
            if any(type(od[key])is not bool for key in ('transient','silence','postfilter')):raise ValueError('invalid flag type')
            if oe['raw']!=rf['raw']:raise ValueError('official decoder did not receive owned bytes')
            for value,raw in ((od,nf['raw']),(oe,oe['raw'])):
                if type(value['bits'])is not int or not 1<=value['bits']<=len(raw)*8:raise ValueError('invalid owned bit authority')
                if type(value['range'])is not int or not 0<value['range']<=0xffffffff:raise ValueError('invalid owned range')
        for direction,expected,actual in [('native-to-owned',n['frames'],o['decoded']),('owned-to-native',r['frames'],o['encoded'])]:
            scale=max(1,max(abs(v) for f in expected for v in f['pcm']))
            for fi,(f,e,a) in enumerate(zip(x['frames'],expected,actual)):
                if e['range']!=a['range']:raise ValueError(f'{direction} seq{si} frame{fi}: range {a["range"]} != {e["range"]}; context={ {k:v for k,v in f.items() if k!="pcm"} }')
                if len(e['pcm'])!=f['n']*x['c'] or len(a['pcm'])!=len(e['pcm']):raise ValueError('PCM length mismatch')
                for j,(v,w) in enumerate(zip(e['pcm'],a['pcm'])):
                    if not math.isfinite(v) or not math.isfinite(w) or abs(v-w)>ABSOLUTE_TOLERANCE*scale+RELATIVE_TOLERANCE*abs(v):
                        raise ValueError(f'{direction} seq{si} frame{fi} sample{j}: {w} != {v}; delta={abs(v-w)} scale={scale}; frame={ {k:v for k,v in f.items() if k!="pcm"} }')
                    maximum=max(maximum,abs(v-w));samples+=1
        transients+=sum(f['transient'] for f in o['decoded']);silences+=sum(f['silence'] for f in o['decoded']);postfilters+=sum(f['postfilter'] for f in o['decoded'])
    return dict(maximumAbsoluteError=maximum,comparedSamples=samples,transientFrames=transients,silenceFrames=silences,postfilterFrames=postfilters)


def packed(values):
    """Preserve complete scalar-float PCM compactly as explicit little-endian base64 bytes."""
    return base64.b64encode(struct.pack('<'+'f'*len(values),*values)).decode()


def fixture_records(inputs,native,reverse):
    """Retain independent raw frames/ranges and compact full PCM vectors without a native runtime."""
    result=[]
    for x,n,r in zip(inputs,native,reverse):
        source=dict(c=x['c'],frames=[{**f,'pcm':packed(f['pcm'])} for f in x['frames']])
        output=[{**f,'pcm':packed(f['pcm'])} for f in n['frames']]
        # Reverse vectors retain independently decoded owned bytes; tests decode them directly.
        encoded=[{**f,'pcm':packed(f['pcm'])} for f in r['frames']]
        result.append(dict(input=source,output=output,encodedOutput=encoded))
    return result



def build(command,directory):
    """Run one explicit official development build with bounded captured failure diagnostics."""
    completed=subprocess.run(command,cwd=directory,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    if completed.returncode:raise RuntimeError('official build failed: '+completed.stdout.decode(errors='replace')[-8000:])


def main():
    """Build the pinned official library only on explicit invocation and compare full entry points."""
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source-archive',required=True,type=Path)
    p.add_argument('--reference-build',type=Path);p.add_argument('--repository',type=Path,default=Path(__file__).resolve().parents[3])
    p.add_argument('--cases',type=int,default=100);p.add_argument('--seed',type=int,default=6716436)
    p.add_argument('--write-fixtures',action='store_true');p.add_argument('--report',type=Path);args=p.parse_args()
    if not 1<=args.cases<=1000 or args.seed<0:p.error('cases must be1...1000; seed nonnegative')
    repository=args.repository.resolve();fixed=fixed_cases();inputs=fixed+random_cases(args.cases,args.seed)
    with tempfile.TemporaryDirectory(prefix='discordkit-celt-frame-',dir='/private/tmp') as tmp:
        directory=Path(tmp);upstream=extract_verified_archive(args.source_archive.resolve(),directory)
        if args.reference_build:
            reference_source=args.reference_build.resolve()
            for name in UPSTREAM_PATHS:
                if digest(upstream/name)!=digest(reference_source/name):raise ValueError('reference build source differs from verified archive')
        else:
            reference_source=upstream
            # The safe archive reader copies regular contents without executable modes.
            # Restore only the pinned upstream shell helpers required by autoconf/make.
            for helper in ('compile','config.guess','config.sub','depcomp','install-sh','missing','test-driver'):
                (upstream/helper).chmod(0o755)
            build(['sh',str(upstream/'configure'),'--disable-intrinsics','--disable-rtcd',
                   '--disable-shared','--disable-extra-programs','--disable-doc','--disable-dependency-tracking',
                   'CFLAGS=-O2 -ffp-contract=off'],upstream)
            build(['make','-j2'],upstream)
        c,s=directory/'oracle.c',directory/'driver.swift';c.write_text(C_DRIVER);s.write_text(SWIFT_DRIVER)
        reference,owned=directory/'reference',directory/'owned'
        run(['cc','-O2','-I'+str(reference_source/'include'),str(c),str(reference_source/'.libs/libopus.a'),'-lm','-o',str(reference)])
        run(['swiftc','-O','-module-cache-path',str(directory/'module-cache'),'-enable-upcoming-feature','ApproachableConcurrency','-default-isolation','nonisolated']+[str(repository/f) for f in OWNED_PATHS]+[str(s),'-o',str(owned)])
        native=parse_outputs(run([str(reference)],commands(inputs)),len(inputs),'Full official encoder/decoder')
        prepared=[dict(c=x['c'],frames=[{**f,'raw':n['raw']} for f,n in zip(x['frames'],out['frames'])]) for x,out in zip(inputs,native)]
        actual=parse_outputs(run([str(owned)],'\n'.join(map(json.dumps,prepared)).encode()),len(inputs),'Owned raw frame codec')
        reverse=parse_outputs(run([str(reference)],commands(inputs,actual)),len(inputs),'Official decoder on owned frames')
        statistics=compare_results(inputs,native,actual,reverse)
        records=fixture_records(fixed,native[:len(fixed)],reverse[:len(fixed)]);fixture=repository/FIXTURE_PATH
        if args.write_fixtures:fixture.write_text('/// Complete independently decoded scalar PCM stored as little-endian float32 base64.\nenum CELTFrameOracleFixtures {\n    static let json = #"""\n'+json.dumps(records,separators=(',',':'))+'\n"""#\n}\n')
        if not fixture.exists() or json.loads(fixture.read_text().split('#"""',1)[1].split('"""#',1)[0])!=records:raise ValueError('fixture differs; review and explicitly --write-fixtures')
        report=dict(verifiedAt=datetime.now(timezone.utc).isoformat(),scope='bidirectional ordinary CELT raw frame interoperability with full official Opus entry points',version=VERSION,releaseURL=RELEASE_URL,sourceURL=SOURCE_URL,archiveSHA256=ARCHIVE_SHA256,
            seed=args.seed,randomSequences=args.cases,fixedSequences=len(fixed),totalSequences=len(inputs),totalFrames=sum(len(x['frames']) for x in inputs),**statistics,
            exact=['full-decoder final range both directions'],tolerance=dict(absoluteTimesSequenceMaximum=ABSOLUTE_TOLERANCE,relative=RELATIVE_TOLERANCE),
            excluded=['SILK/hybrid','loss/PLC/FEC','channel transitions','resampling','reference encoder byte identity','devices/realtime'],
            ownedSources={f:digest(repository/f) for f in OWNED_PATHS},upstreamSources={f:digest(upstream/f) for f in UPSTREAM_PATHS},fixture=dict(path=FIXTURE_PATH,sha256=digest(fixture)),verifierSHA256=digest(Path(__file__)),
            referenceBuild=dict(reused=args.reference_build is not None,scalar=True,configureArguments=run(['sh',str(reference_source/'config.status'),'--config']).decode().strip(),librarySHA256=digest(reference_source/'.libs/libopus.a'),configurationSHA256=digest(reference_source/'config.h')),
            ccVersion=run(['cc','--version']).decode().splitlines()[0],swiftVersion=run(['swiftc','--version']).decode().splitlines()[0])
        if args.report:args.report.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))

if __name__=='__main__':main()

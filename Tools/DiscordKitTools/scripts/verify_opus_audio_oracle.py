#!/usr/bin/env python3
"""Compare owned ordinary Opus mode/loss/FEC orchestration with pinned scalar libopus.

The independently supplied source archive is verified and built in temporary
storage. Synthetic streams switch all coding modes, coded/output channels,
bandwidths and durations with transition redundancy, explicit losses and FEC.
This opt-in check is not the separate RFC 8251 conformance-vector qualification.
"""
import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import platform
import tempfile
from verify_opus_range_oracle import VERSION, RELEASE_URL, SOURCE_URL, ARCHIVE_SHA256, digest, extract_verified_archive, run
from verify_silk_mono_oracle import run_at
from verify_opus_hybrid_oracle import snapshot_sources

TOLERANCE = 3e-6
LOSS_ABSOLUTE_TOLERANCE = 0.006
LOSS_RELATIVE_TOLERANCE = 0.0001
FIXTURE_PATH = 'Tests/DiscordVoiceCodecsTests/OpusAudioOracleFixtures.swift'
C_DRIVER = r'''
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "opus.h"
#include "opus_private.h"
static int emit(OpusDecoder *dec,int channels,int *operations,const char *action,unsigned char *bytes,int len,int n,int fec){
 float pcm[11520];int ret=opus_decode_float(dec,bytes,len,pcm,n,fec);if(ret<0){fprintf(stderr,"decode %s %d\n",action,ret);return 1;}
 opus_uint32 range;opus_decoder_ctl(dec,OPUS_GET_FINAL_RANGE(&range));
 printf("%s{\"action\":\"%s\",\"count\":%d,\"bytes\":[",(*operations)++?",":"",action,n);
 for(int i=0;i<len;i++)printf("%s%u",i?",":"",bytes[i]);printf("],\"range\":%u,\"pcm\":[",range);
 for(int i=0;i<ret*channels;i++)printf("%s%.9g",i?",":"",pcm[i]);printf("]}");return 0;
}
int main(void){int channels,variant;
 while(scanf("%d%d",&channels,&variant)==2){
 int error;OpusEncoder *enc=opus_encoder_create(48000,2,OPUS_APPLICATION_VOIP,&error);
 OpusDecoder *dec=opus_decoder_create(48000,channels,&error);if(!enc||!dec||error)return 2;
 opus_encoder_ctl(enc,OPUS_SET_BITRATE(48000));opus_encoder_ctl(enc,OPUS_SET_VBR(0));
 opus_encoder_ctl(enc,OPUS_SET_DTX(0));opus_encoder_ctl(enc,OPUS_SET_COMPLEXITY(10));
 opus_encoder_ctl(enc,OPUS_SET_INBAND_FEC(1));opus_encoder_ctl(enc,OPUS_SET_PACKET_LOSS_PERC(30));
 int modes[]={MODE_SILK_ONLY,MODE_SILK_ONLY,MODE_SILK_ONLY,MODE_SILK_ONLY,MODE_HYBRID,MODE_HYBRID,MODE_CELT_ONLY,MODE_CELT_ONLY,MODE_CELT_ONLY,MODE_CELT_ONLY,MODE_HYBRID,MODE_SILK_ONLY};
 int bands[]={1103,1101,1102,1103,1104,1105,1105,1103,1101,1104,1105,1103};
 int sizes[]={480,960,1920,2880,960,480,960,480,240,120,960,960};
 int losses[]={120,240,360,480,600,720,960,1080,1920,2880,5760};
 int operations=0,position=0,missing=0;unsigned random=variant+1;
 unsigned char saved[48][1276];int saved_len[48];
 printf("{\"channels\":%d,\"variant\":%d,\"operations\":[",channels,variant);
 if(variant==1&&emit(dec,channels,&operations,"loss",NULL,0,360,0))return 3;
 for(int frame=0;frame<48;frame++){
  int f=frame%12,n=sizes[f];opus_int16 pcm[5760];unsigned char bytes[1276];
  opus_encoder_ctl(enc,OPUS_SET_FORCE_MODE(modes[f]));opus_encoder_ctl(enc,OPUS_SET_FORCE_CHANNELS((frame/2)%2+1));
  opus_encoder_ctl(enc,OPUS_SET_BANDWIDTH(bands[f]));opus_encoder_ctl(enc,OPUS_SET_MAX_BANDWIDTH(bands[f]));
  for(int i=0;i<n;i++,position++)for(int c=0;c<2;c++){
   random=1664525*random+1013904223;double t=position/48000.;double v=10000*sin(6.283185307179586*(170+c*117)*t)+3000*sin(6.283185307179586*(5000+c*1700)*t);
   if(frame%9==3)v=((int)(random>>16)-32768)*.2;if(frame%9==4)v=0;pcm[i*2+c]=(opus_int16)v;
  }
  int len=opus_encode(enc,pcm,n,bytes,1276);if(len<1){fprintf(stderr,"encode%d\n",len);return 4;}
  if(variant==3){saved_len[frame]=len;for(int i=0;i<len;i++)saved[frame][i]=bytes[i];continue;}
  if(variant==2&&frame%5==1){missing=n;continue;}
  if(missing){if(emit(dec,channels,&operations,"fec",bytes,len,missing,1))return 5;missing=0;}
  if(emit(dec,channels,&operations,"packet",bytes,len,5760,0))return 6;
  if(variant==1&&frame%3==2&&emit(dec,channels,&operations,"loss",NULL,0,losses[(frame/3)%11],0))return 7;
 }
 if(variant==3){
  int order[]={0,7,1,9,2,4,8,10,3,5,7,11,9,0,10,8,4,11,7,2,9,1,10,3};
  for(unsigned i=0;i<sizeof(order)/sizeof(order[0]);i++){int f=order[i];if(emit(dec,channels,&operations,"packet",saved[f],saved_len[f],5760,0))return 8;}
 }
 puts("]}");opus_encoder_destroy(enc);opus_decoder_destroy(dec);
 }
 return 0;
}
'''
SWIFT_DRIVER = r'''
import Foundation
struct Operation: Decodable { let action:String; let count:Int; let bytes:[UInt8] }
struct Input: Decodable { let channels:Int; let operations:[Operation] }
struct Output: Encodable { let range:UInt32; let pcm:[Float]; let redundancy:Int; let celtToSilk:Bool }
@main struct Driver {
 /// Executes only owned decoding; independent expected PCM is not read by this input schema.
 static func main() throws {
  while let line=readLine() {
   let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8));var decoder=try OpusAudioDecoder(channelCount:input.channels)
   var output:[Output]=[]
   for operation in input.operations {
    let pcm:[Float];var redundancy=0;var celtToSilk=false
    switch operation.action {
    case "packet": let frames=try decoder.decode(Data(operation.bytes));pcm=frames.flatMap(\.samples);redundancy=frames.map(\.redundancyByteCount).reduce(0,+);celtToSilk=frames.contains { $0.redundancyByteCount > 0 && $0.celtToSilkRedundancy }
    case "loss": pcm=try decoder.conceal(frameSampleCount:operation.count).samples
    case "fec": pcm=try decoder.recover(Data(operation.bytes),frameSampleCount:operation.count).samples
    default: fatalError("unknown local oracle action")
    }
    output.append(Output(range:decoder.finalRange,pcm:pcm,redundancy:redundancy,celtToSilk:celtToSilk))
   }
   print(String(decoding:try JSONEncoder().encode(output),as:UTF8.self))
  }
 }
}
'''


def requests():
    """Return both output layouts crossed with ordinary, loss, FEC and direct-mode splice policies."""
    return [(channels, variant) for channels in (1, 2) for variant in range(4)]


def compare(streams, actual):
    """Require exact interval shape/range and finite PCM within the declared absolute tolerance."""
    if len(streams) != len(actual):
        raise ValueError('stream count mismatch')
    maximum = 0.0
    for stream_index, (stream, results) in enumerate(zip(streams, actual)):
        if len(stream['operations']) != len(results):
            raise ValueError(f'operation count mismatch {stream_index}')
        scale = max(1.0, max((abs(v) for operation in stream['operations'] for v in operation['pcm']), default=0.0))
        lossy = stream.get('variant', 0) != 0
        for operation_index, (operation, result) in enumerate(zip(stream['operations'], results)):
            where = f'{stream_index}:{operation_index}:{operation["action"]}'
            if operation['range'] != result.get('range'):
                raise ValueError(f'final range mismatch {where}: {operation["range"]} != {result.get("range")}')
            if len(operation['pcm']) != len(result['pcm']):
                raise ValueError(f'PCM shape mismatch {where}')
            for index, (expected, observed) in enumerate(zip(operation['pcm'], result['pcm'])):
                if not math.isfinite(expected) or not math.isfinite(observed):
                    raise ValueError(f'nonfinite PCM {where}:{index}')
                error = abs(expected - observed)
                maximum = max(maximum, error)
                tolerance = LOSS_ABSOLUTE_TOLERANCE * scale + LOSS_RELATIVE_TOLERANCE * abs(expected) if lossy else TOLERANCE
                if error > tolerance:
                    raise ValueError(f'PCM mismatch {where}:{index}: {expected} != {observed}, error {error}')
    return maximum


def fixture_text(streams):
    """Produce literal native operation fixtures without embedding reference implementation code."""
    import base64
    encoded = [base64.b64encode(json.dumps(stream, separators=(',', ':')).encode()).decode() for stream in streams]
    return ('/// Independently generated scalar libopus 1.6.1 mode/loss/FEC streams.\n'
            '/// Generated by verify_opus_audio_oracle.py; tests call no native codec.\n'
            'let opusAudioOracleFixtures: [String] = [\n'
            + ''.join('    "' + value + '",\n' for value in encoded) + ']\n')


def main():
    """Compile independently pinned peers from an immutable owned snapshot and record observed agreement."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-archive', type=Path, required=True)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--report', type=Path)
    parser.add_argument('--write-fixtures', action='store_true')
    parser.add_argument('--diagnostics-directory', type=Path, help='Optional local reference/owned JSON for mismatch investigation')
    args = parser.parse_args()
    repository = args.repository.resolve()
    with tempfile.TemporaryDirectory(prefix='discordkit-opus-audio-') as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        for name in ('configure', 'install-sh', 'missing', 'depcomp', 'compile', 'config.guess', 'config.sub'):
            (upstream / name).chmod(0o755)
        build = directory / 'reference-build'
        build.mkdir()
        configuration = ['--disable-shared', '--enable-static', '--disable-intrinsics', '--disable-asm', '--disable-rtcd',
                         '--disable-dependency-tracking', '--disable-extra-programs', '--disable-doc', '--disable-deep-plc', '--disable-osce']
        run_at(['sh', str(upstream / 'configure')] + configuration, build)
        run_at(['make', '-j4'], build)
        source = directory / 'oracle.c'
        source.write_text(C_DRIVER)
        oracle = directory / 'oracle'
        run(['cc', '-std=c99', '-O2', '-DHAVE_CONFIG_H', '-I' + str(build)]
            + ['-I' + str(upstream / path) for path in ('include', 'celt', 'silk', 'src')]
            + [str(source), str(build / '.libs/libopus.a'), '-lm', '-o', str(oracle)])
        streams = [json.loads(line) for line in run([str(oracle)],
            ('\n'.join(' '.join(map(str, case)) for case in requests()) + '\n').encode()).splitlines()]
        snapshot = snapshot_sources(repository, directory)
        run(['swiftc', '-O', '-emit-module', '-emit-library', '-module-name', 'DiscordMedia',
             '-module-cache-path', str(directory / 'module-cache'),
             *[str(path) for path in sorted((snapshot / 'Sources/DiscordMedia').glob('*.swift'))],
             '-emit-module-path', str(directory / 'DiscordMedia.swiftmodule'), '-o', str(directory / 'libDiscordMedia.dylib')])
        swift = directory / 'driver.swift'
        swift.write_text(SWIFT_DRIVER)
        owned = directory / 'owned'
        paths = sorted((snapshot / 'Sources/DiscordVoiceCodecs').glob('*.swift'))
        run(['swiftc', '-O', '-module-cache-path', str(directory / 'module-cache'),
             '-enable-upcoming-feature', 'ApproachableConcurrency', '-default-isolation', 'nonisolated',
             '-I', str(directory), '-L', str(directory), '-lDiscordMedia', '-Xlinker', '-rpath', '-Xlinker', str(directory)]
            + [str(path) for path in paths] + [str(swift), '-o', str(owned)])
        actual = [json.loads(line) for line in run([str(owned)],
            ('\n'.join(json.dumps(stream) for stream in streams) + '\n').encode()).splitlines()]
        if args.diagnostics_directory:
            args.diagnostics_directory.mkdir(parents=True, exist_ok=True)
            (args.diagnostics_directory / 'reference.json').write_text(json.dumps(streams))
            (args.diagnostics_directory / 'owned.json').write_text(json.dumps(actual))
            (args.diagnostics_directory / 'snapshot-hashes.json').write_text(json.dumps({str(p.relative_to(snapshot)):digest(p) for p in sorted(snapshot.rglob('*.swift'))}, indent=2))
        maximum = compare(streams, actual)
        fixture = repository / FIXTURE_PATH
        rendered = fixture_text(streams)
        if args.write_fixtures:
            fixture.write_text(rendered)
        if fixture.exists() and fixture.read_text() != rendered:
            raise ValueError('committed native fixtures differ; regenerate explicitly')
        hashes = {str(path.relative_to(snapshot)): digest(path) for target in ('DiscordMedia', 'DiscordVoiceCodecs')
                  for path in sorted((snapshot / 'Sources' / target).glob('*.swift'))}
        report = dict(schemaVersion=1, status='pass', upstreamVersion=VERSION,
            releaseURL=RELEASE_URL, sourceURL=SOURCE_URL, archiveSHA256=ARCHIVE_SHA256,
            verifiedAt=datetime.now(timezone.utc).isoformat(), host=platform.platform(),
            swiftCompiler=run(['swiftc', '--version']).decode().splitlines()[0], referenceConfiguration=configuration,
            streamPolicies=['ordinary encoder stream', 'explicit loss', 'in-band FEC', 'direct mode splices'],
            streamCount=len(streams), operationCount=sum(len(s['operations']) for s in streams),
            packetCount=sum(o['action'] == 'packet' for s in streams for o in s['operations']),
            lossCount=sum(o['action'] == 'loss' for s in streams for o in s['operations']),
            fecCount=sum(o['action'] == 'fec' for s in streams for o in s['operations']),
            pcmValueCount=sum(len(o['pcm']) for s in streams for o in s['operations']),
            ordinaryAbsoluteTolerance=TOLERANCE,
            lossTolerance=dict(absoluteTimesSequenceMaximum=LOSS_ABSOLUTE_TOLERANCE, relative=LOSS_RELATIVE_TOLERANCE),
            maximumAbsoluteError=maximum,
            ordinaryMaximumAbsoluteError=compare([s for s in streams if s['variant'] == 0],
                [a for s, a in zip(streams, actual) if s['variant'] == 0]),
            directTransitionMaximumAbsoluteError=compare([s for s in streams if s['variant'] == 3],
                [a for s, a in zip(streams, actual) if s['variant'] == 3]),
            redundancyPayloadCount=sum(o['redundancy'] > 0 for s in actual for o in s),
            celtToSilkPayloadCount=sum(o['redundancy'] > 0 and o['celtToSilk'] for s in actual for o in s),
            silkToCeltPayloadCount=sum(o['redundancy'] > 0 and not o['celtToSilk'] for s in actual for o in s),
            exactFinalRanges=True, ownedSwiftSHA256=hashes, verifierSHA256=digest(Path(__file__)),
            fixture=dict(path=FIXTURE_PATH, sha256=digest(fixture)) if fixture.exists() else None,
            upstreamSources={p:digest(upstream / p) for p in ('src/opus_decoder.c', 'src/opus_encoder.c', 'celt/celt_decoder.c', 'silk/dec_API.c')},
            referenceBuild=dict(librarySHA256=digest(build / '.libs/libopus.a'), configurationSHA256=digest(build / 'config.h')),
            workingTreeChangedSinceSnapshot=[path for path, sha in hashes.items() if digest(repository / path) != sha],
            limitations=['Synthetic ordinary streams; separate RFC 8251 vectors qualify normative conformance.',
                          'Direct-mode splices, loss and FEC invoke scalar CELT PLC and use its separately declared existing tolerance.',
                          'No enhancement extensions, multistream, integer soft clipping or non-48kHz output.'])
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

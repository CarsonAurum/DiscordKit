#!/usr/bin/env python3
"""Opt-in bidirectional ordinary hybrid Opus PCM/range comparison with pinned libopus.

Builds only an independently supplied verified archive in temporary storage. Owned
mono/stereo hybrid encoders and decoders cover both bandwidths and 10/20ms frames;
this is syntax/interoperability evidence, not perceptual-quality, complete Opus
mode/loss/FEC conformance, device or realtime qualification. No download occurs.
"""
import argparse
import base64
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
from verify_opus_range_oracle import VERSION, RELEASE_URL, SOURCE_URL, ARCHIVE_SHA256, digest, extract_verified_archive, run
from verify_silk_mono_oracle import run_at

FIXTURE_PATH = 'Tests/DiscordVoiceCodecsTests/OpusHybridOracleFixtures.swift'
OWNED_FEC_FIXTURE_PATH = 'Tests/DiscordVoiceCodecsTests/OpusHybridFECOracleFixtures.swift'
TOLERANCE = 3e-6
C_DRIVER = r'''
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include "opus.h"
#include "opus_private.h"
int main(void){int channels,bandwidth,count,variant;
 while(scanf("%d%d%d%d",&channels,&bandwidth,&count,&variant)==4){
  int error;OpusEncoder *enc=opus_encoder_create(48000,channels,OPUS_APPLICATION_VOIP,&error);
  OpusDecoder *dec=opus_decoder_create(48000,channels,&error);if(!enc||!dec||error)return 2;
  opus_encoder_ctl(enc,OPUS_SET_FORCE_MODE(MODE_HYBRID));opus_encoder_ctl(enc,OPUS_SET_FORCE_CHANNELS(channels));
  opus_encoder_ctl(enc,OPUS_SET_BANDWIDTH(bandwidth));opus_encoder_ctl(enc,OPUS_SET_MAX_BANDWIDTH(bandwidth));
  opus_encoder_ctl(enc,OPUS_SET_BITRATE(32000*channels));opus_encoder_ctl(enc,OPUS_SET_VBR(0));
  opus_encoder_ctl(enc,OPUS_SET_DTX(0));opus_encoder_ctl(enc,OPUS_SET_INBAND_FEC(variant%2));
  opus_encoder_ctl(enc,OPUS_SET_PACKET_LOSS_PERC(variant%2?25:0));opus_encoder_ctl(enc,OPUS_SET_COMPLEXITY(10));
  printf("{\"channels\":%d,\"packets\":[",channels);int position=0;unsigned random=variant+1;
  for(int frame=0;frame<count;frame++){
   int n=frame%2==0?480:960;opus_int16 pcm[1920];float out[1920];unsigned char bytes[1276];
   for(int i=0;i<n;i++,position++)for(int c=0;c<channels;c++){
    random=1664525*random+1013904223;double t=position/48000.;double value=11000*sin(6.283185307179586*(130+variant*17+c*77)*t)+4000*sin(6.283185307179586*(5000+c*3900)*t);
    if(frame%7==3)value=((int)(random>>16)-32768)*.4;if(frame%7==4||variant==3)value=0;
    pcm[i*channels+c]=(opus_int16)value;
   }
   int len=opus_encode(enc,pcm,n,bytes,1276);
   if(len<3||(bytes[0]>>3)<12||(bytes[0]>>3)>15){fprintf(stderr,"not hybrid:len%d toc%d\n",len,bytes[0]);return 3;}
   int decoded=opus_decode_float(dec,bytes,len,out,960,0);if(decoded!=n)return 4;
   opus_uint32 range;opus_decoder_ctl(dec,OPUS_GET_FINAL_RANGE(&range));
   printf("%s{\"bytes\":[",frame?",":"");for(int i=0;i<len;i++)printf("%s%u",i?",":"",bytes[i]);
   printf("],\"range\":%u,\"pcm\":[",range);for(int i=0;i<n*channels;i++)printf("%s%.9g",i?",":"",out[i]);printf("]}");
  }
  puts("]}");opus_encoder_destroy(enc);opus_decoder_destroy(dec);
 }
 return 0;
}
'''
SWIFT_DRIVER = r'''
import Foundation
struct Packet:Decodable { let bytes:[UInt8] }
struct Input:Decodable { let channels:Int; let packets:[Packet] }
struct Output:Encodable { let pcm:[Float]; let range:UInt32; let redundancy:Int }
@main struct Driver {
 /// Decodes supplied local reference packets with owned Swift only; no native runtime is linked.
 static func main() throws {
  while let line=readLine() {
   let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8));var decoder=try OpusHybridDecoder(channelCount:input.channels)
   var output:[Output]=[]
   for packet in input.packets {
    let frames=try decoder.decode(Data(packet.bytes));output.append(Output(pcm:frames.flatMap(\.samples),range:frames.last!.finalRange,redundancy:frames.map(\.redundancyByteCount).reduce(0,+)))
   }
   print(String(decoding:try JSONEncoder().encode(output),as:UTF8.self))
  }
 }
}
'''


DECODER_DRIVER = r'''
#include <stdio.h>
#include <stdlib.h>
#include "opus.h"
int main(void){int channels,count,size,value;
 while(scanf("%d%d",&channels,&count)==2){
  if((channels!=1&&channels!=2)||count<1||count>64)return 2;
  int error;OpusDecoder *dec=opus_decoder_create(48000,channels,&error);if(!dec||error)return 3;
  printf("[");
  for(int packet=0;packet<count;packet++){
   unsigned char bytes[1276];float pcm[1920];
   if(scanf("%d",&size)!=1||size<2||size>1276)return 4;
   for(int i=0;i<size;i++){if(scanf("%d",&value)!=1||value<0||value>255)return 4;bytes[i]=value;}
   if((bytes[0]>>3)<12||(bytes[0]>>3)>15||opus_packet_get_nb_channels(bytes)!=channels)return 5;
   int n=opus_decode_float(dec,bytes,size,pcm,960,0);if(n<1)return 6;
   opus_uint32 range;opus_decoder_ctl(dec,OPUS_GET_FINAL_RANGE(&range));
   printf("%s{\"range\":%u,\"pcm\":[",packet?",":"",range);
   for(int i=0;i<n*channels;i++)printf("%s%.9g",i?",":"",pcm[i]);printf("]}");
  }
  puts("]");opus_decoder_destroy(dec);
 }
 return 0;
}
'''
RECOVERY_DRIVER = r'''
#include <stdio.h>
#include <stdlib.h>
#include "opus.h"
int main(void){int channels,count,size,value,n,fec;
 while(scanf("%d%d",&channels,&count)==2){
  if((channels!=1&&channels!=2)||count<1||count>64)return 2;
  int error;OpusDecoder *dec=opus_decoder_create(48000,channels,&error);if(!dec||error)return 3;
  printf("[");
  for(int packet=0;packet<count;packet++){
   unsigned char bytes[1276];float pcm[1920];
   if(scanf("%d%d%d",&n,&fec,&size)!=3||size<2||size>1276||(n!=480&&n!=960)||(fec!=0&&fec!=1))return 4;
   for(int i=0;i<size;i++){if(scanf("%d",&value)!=1||value<0||value>255)return 4;bytes[i]=value;}
   int decoded=opus_decode_float(dec,bytes,size,pcm,n,fec);if(decoded!=n)return 5;
   opus_uint32 range;opus_decoder_ctl(dec,OPUS_GET_FINAL_RANGE(&range));
   printf("%s{\"range\":%u,\"pcm\":[",packet?",":"",range);
   for(int i=0;i<n*channels;i++)printf("%s%.9g",i?",":"",pcm[i]);printf("]}");
  }
  puts("]");opus_decoder_destroy(dec);
 }
 return 0;
}
'''
ENCODER_DRIVER = r'''
import Foundation
struct Input:Decodable { let channels:Int; let bandwidth:Int; let samples:Int; let bytes:Int; let fec:Bool; let frames:[[Float]] }
struct Packet:Encodable { let bytes:[UInt8]; let pcm:[Float]; let range:UInt32; let lbrr:Bool }
struct Recovery:Encodable { let bytes:[UInt8]; let samples:Int; let fec:Bool; let pcm:[Float]; let range:UInt32; let selectedLBRR:Bool }
struct Output:Encodable { let channels:Int; let packets:[Packet]; let recoveries:[Recovery]; let budgetRejections:Int }
@main struct Driver {
 /// Encodes finite offline PCM, inspects LBRR, and independently exercises normal and recovered owned synthesis.
 static func main() throws {
  while let line=readLine() {
   let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   var encoder=try OpusHybridEncoder(frameSampleCount:input.samples,channelCount:input.channels,
       bandwidth:input.bandwidth==1105 ? .fullband : .superwideband,enableInBandFEC:input.fec)
   var decoder=try OpusHybridDecoder(channelCount:input.channels)
   var low=try SILKStereoDecoder(sampleRate:16000,outputChannelCount:input.channels)
   var packets:[Packet]=[];var rejections=0
   for pcm in input.frames {
    let bytes:Data
    do { bytes=try encoder.encode(pcm,packetByteCount:input.bytes) }
    catch SILKMonoEncoderError.payloadBudgetExceeded { rejections += 1;continue }
    let parsed=try OpusPacket(bytes)
    let flags=try low.decodePayload(Data(parsed.data[parsed.frameRanges[0]]),
        durationMilliseconds:input.samples/48,codedChannelCount:input.channels).redundancy
    let output=try decoder.decode(bytes)
    packets.append(Packet(bytes:[UInt8](bytes),pcm:output.flatMap(\.samples),range:output.last!.finalRange,
        lbrr:flags.flatMap { $0 }.contains(true)))
   }
   var recovery=try OpusAudioDecoder(channelCount:input.channels);var recoveries:[Recovery]=[]
   for (index,packet) in packets.enumerated() {
    if [1,4].contains(index) && index+1 < packets.count { continue }
    if [2,5].contains(index) {
     let output=try recovery.recover(Data(packet.bytes),frameSampleCount:input.samples)
     recoveries.append(Recovery(bytes:packet.bytes,samples:input.samples,fec:true,pcm:output.samples,
         range:output.finalRange,selectedLBRR:packet.lbrr))
    }
    let output=try recovery.decode(Data(packet.bytes))
    recoveries.append(Recovery(bytes:packet.bytes,samples:input.samples,fec:false,pcm:output.flatMap(\.samples),
        range:output.last!.finalRange,selectedLBRR:false))
   }
   print(String(decoding:try JSONEncoder().encode(Output(channels:input.channels,packets:packets,
       recoveries:recoveries,budgetRejections:rejections)),as:UTF8.self))
  }
 }
}
'''


def requests(variants):
    """Exercise both hybrid bandwidths/channel layouts with alternating 10/20ms and LBRR headers."""
    if not 4 <= variants <= 20:
        raise ValueError('variants must be 4...20')
    return [(channels, bandwidth, 8, variant)
            for channels in (1, 2) for bandwidth in (1104, 1105) for variant in range(variants)]


def encoder_requests():
    """Cover both FEC policies, startup/continuous resampling and independent low/high/stereo content at two budgets each."""
    import math
    import random
    result = []
    for channels in (1, 2):
        for bandwidth in (1104, 1105):
            for samples in (480, 960):
                for fec, byte_count in ((False, 256), (False, 512), (True, 640), (True, 1024)):
                    rng = random.Random(channels * samples + bandwidth)
                    frames = []
                    for frame in range(8):
                        pcm = []
                        for sample in range(samples):
                            time = (frame * samples + sample) / 48000
                            for channel in range(channels):
                                low = 0.26 * math.sin(2 * math.pi * (211 + channel * 179) * time)
                                high = 0.15 * math.sin(2 * math.pi * (6100 + channel * 3211) * time)
                                value = low + high
                                if frame == 2:
                                    value = high
                                elif frame == 3:
                                    value = low
                                elif frame == 4:
                                    value = rng.uniform(-0.4, 0.4)
                                elif frame == 5:
                                    value = 0
                                elif frame == 6:
                                    value = 0.12 if channel == 0 else -0.12
                                pcm.append(value)
                        frames.append(pcm)
                    result.append(dict(channels=channels, bandwidth=bandwidth, samples=samples,
                                       bytes=byte_count, fec=fec, frames=frames))
    return result


def decoder_commands(streams):
    """Serialize owned ordinary hybrid packets for independent native decoding without shell parsing."""
    lines = []
    for stream in streams:
        lines.append(f"{stream['channels']} {len(stream['packets'])}")
        for packet in stream['packets']:
            lines.append(str(len(packet['bytes'])) + ' ' + ' '.join(map(str, packet['bytes'])))
    return ('\n'.join(lines) + '\n').encode()


def recovery_commands(streams):
    """Serialize selected recovery/ordinary calls for a fresh independent full Opus decoder per stream."""
    lines = []
    for stream in streams:
        lines.append(f"{stream['channels']} {len(stream['recoveries'])}")
        for operation in stream['recoveries']:
            lines.append(f"{operation['samples']} {int(operation['fec'])} {len(operation['bytes'])} "
                         + ' '.join(map(str, operation['bytes'])))
    return ('\n'.join(lines) + '\n').encode()


def validate_encoded(requests, streams):
    """Require exact fixed framing, budgets and dimensions before native interoperability comparison."""
    if len(requests) != len(streams):
        raise RuntimeError('owned hybrid encoder stream count mismatch')
    for request, stream in zip(requests, streams):
        if stream['channels'] != request['channels'] or len(stream['packets']) + stream.get('budgetRejections', 0) != len(request['frames']):
            raise RuntimeError('owned hybrid encoder packet count/channel mismatch')
        configuration = (14 if request['bandwidth'] == 1105 else 12) + (request['samples'] == 960)
        toc = configuration * 8 + (4 if request['channels'] == 2 else 0)
        for packet in stream['packets']:
            if len(packet['bytes']) != request['bytes'] or packet['bytes'][0] != toc:
                raise RuntimeError('owned hybrid encoder framing/budget mismatch')
            if len(packet['pcm']) != request['samples'] * request['channels']:
                raise RuntimeError('owned hybrid encoder output dimensions mismatch')
            if not request.get('fec', False) and packet.get('lbrr', False):
                raise RuntimeError('unexpected owned hybrid LBRR without FEC policy')
        if request.get('fec', False) and not any(packet.get('lbrr', False) for packet in stream['packets']):
            raise RuntimeError('owned hybrid FEC stream carried no selected LBRR')


def compare(inputs, actual, absolute_tolerance=TOLERANCE, relative_tolerance=0):
    """Reject missing results, nonfinite PCM, wrong exact ranges, dimensions or excess float error."""
    import math
    if len(inputs) != len(actual):
        raise RuntimeError('hybrid stream count mismatch')
    maximum = 0.0
    for stream, decoded in zip(inputs, actual):
        if len(stream['packets']) != len(decoded):
            raise RuntimeError('hybrid packet count mismatch')
        scale = max(1.0, max((abs(v) for packet in stream['packets'] for v in packet['pcm']), default=0.0))
        for expected, result in zip(stream['packets'], decoded):
            if expected['range'] != result['range'] or len(expected['pcm']) != len(result['pcm']):
                raise RuntimeError('hybrid range/sample count mismatch')
            for reference, sample in zip(expected['pcm'], result['pcm']):
                error = abs(reference - sample)
                if not math.isfinite(reference) or not math.isfinite(sample) or error > absolute_tolerance * (scale if relative_tolerance else 1) + relative_tolerance * abs(reference):
                    raise RuntimeError(f'hybrid PCM mismatch {reference} != {sample}, error={error}')
                maximum = max(maximum, error)
    return maximum


def owned_fec_fixture_text(cases, encoded, references):
    """Preserve native full-PCM/range results for owned FEC packets at every format using the lower FEC budget."""
    fixtures = []
    for case, stream, reference in zip(cases, encoded, references):
        if not case['fec'] or case['bytes'] != 640:
            continue
        operations = [dict(bytes=operation['bytes'], fec=operation['fec'], samples=operation['samples'],
                           selectedLBRR=operation['selectedLBRR'], pcm=expected['pcm'], range=expected['range'])
                      for operation, expected in zip(stream['recoveries'], reference)]
        fixtures.append(dict(channels=case['channels'], bandwidth=case['bandwidth'], samples=case['samples'], operations=operations))
    return ('/// Owned hybrid FEC packets with independently decoded libopus 1.6.1 full PCM and ranges.\n'
            '/// Generated offline; normal tests call no native codec.\n'
            'let opusHybridFECOracleFixtures: [String] = [\n'
            + ''.join('    "' + base64.b64encode(json.dumps(stream, separators=(',', ':')).encode()).decode() + '",\n'
                      for stream in fixtures) + ']\n')


def snapshot_sources(repository, directory):
    """Copy only owned media/codec Swift bytes so concurrent edits cannot invalidate a compiler input."""
    snapshot = directory / 'owned-source'
    for target in ('DiscordMedia', 'DiscordVoiceCodecs'):
        destination = snapshot / 'Sources' / target
        destination.mkdir(parents=True)
        for source in sorted((repository / 'Sources' / target).glob('*.swift')):
            shutil.copyfile(source, destination / source.name)
    return snapshot


def main():
    """Build temporary pinned reference/Swift peers and record bounded ordinary-path evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-archive', type=Path, required=True)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--variants', type=int, default=4)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--write-fixtures', action='store_true')
    args = parser.parse_args()
    cases = requests(args.variants)
    repository = args.repository.resolve()
    with tempfile.TemporaryDirectory(prefix='discordkit-hybrid-') as temporary:
        directory = Path(temporary).resolve()
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
        streams = [json.loads(line) for line in run([str(oracle)], ('\n'.join(' '.join(map(str, case)) for case in cases) + '\n').encode()).splitlines()]
        snapshot = snapshot_sources(repository, directory)
        media = directory / 'libDiscordMedia.dylib'
        run(['swiftc', '-O', '-emit-module', '-emit-library', '-module-name', 'DiscordMedia',
             '-module-cache-path', str(directory / 'module-cache'), *[str(p) for p in sorted((snapshot / 'Sources/DiscordMedia').glob('*.swift'))],
             '-emit-module-path', str(directory / 'DiscordMedia.swiftmodule'), '-o', str(media)])
        swift = directory / 'driver.swift'
        swift.write_text(SWIFT_DRIVER)
        owned = directory / 'owned'
        paths = sorted((snapshot / 'Sources/DiscordVoiceCodecs').glob('*.swift'))
        run(['swiftc', '-O', '-module-cache-path', str(directory / 'module-cache'),
             '-enable-upcoming-feature', 'ApproachableConcurrency', '-default-isolation', 'nonisolated',
             '-I', str(directory), '-L', str(directory), '-lDiscordMedia', '-Xlinker', '-rpath', '-Xlinker', str(directory)]
            + [str(path) for path in paths] + [str(swift), '-o', str(owned)])
        actual = [json.loads(line) for line in run([str(owned)], ('\n'.join(json.dumps(stream) for stream in streams) + '\n').encode()).splitlines()]
        error = compare(streams, actual)
        decoder_source = directory / 'decoder.c'
        decoder_source.write_text(DECODER_DRIVER)
        native_decoder = directory / 'native-decoder'
        run(['cc', '-std=c99', '-O2', '-DHAVE_CONFIG_H', '-I' + str(build)]
            + ['-I' + str(upstream / path) for path in ('include', 'celt', 'silk', 'src')]
            + [str(decoder_source), str(build / '.libs/libopus.a'), '-lm', '-o', str(native_decoder)])
        encoder_source = directory / 'encoder.swift'
        encoder_source.write_text(ENCODER_DRIVER)
        owned_encoder = directory / 'owned-encoder'
        run(['swiftc', '-O', '-module-cache-path', str(directory / 'module-cache'),
             '-enable-upcoming-feature', 'ApproachableConcurrency', '-default-isolation', 'nonisolated',
             '-I', str(directory), '-L', str(directory), '-lDiscordMedia', '-Xlinker', '-rpath', '-Xlinker', str(directory)]
            + [str(path) for path in paths] + [str(encoder_source), '-o', str(owned_encoder)])
        encoding_cases = encoder_requests()
        encoded = [json.loads(line) for line in run([str(owned_encoder)],
            ('\n'.join(json.dumps(item) for item in encoding_cases) + '\n').encode()).splitlines()]
        validate_encoded(encoding_cases, encoded)
        independently_decoded = [json.loads(line) for line in run([str(native_decoder)], decoder_commands(encoded)).splitlines()]
        encoder_error = compare([dict(packets=stream) for stream in independently_decoded],
                                [stream['packets'] for stream in encoded])
        recovery_source = directory / 'recovery.c'
        recovery_source.write_text(RECOVERY_DRIVER)
        native_recovery = directory / 'native-recovery'
        run(['cc', '-std=c99', '-O2', '-I' + str(upstream / 'include'), str(recovery_source),
             str(build / '.libs/libopus.a'), '-lm', '-o', str(native_recovery)])
        recovered = [json.loads(line) for line in run([str(native_recovery)], recovery_commands(encoded)).splitlines()]
        recovery_error = compare([dict(packets=stream) for stream in recovered],
            [stream['recoveries'] for stream in encoded])
        selected = sum(operation['fec'] and operation['selectedLBRR'] for stream in encoded for operation in stream['recoveries'])
        if selected < 1:
            raise RuntimeError('no owned hybrid LBRR was independently selected for missing audio')
        fec_fixture = repository / OWNED_FEC_FIXTURE_PATH
        rendered_fec = owned_fec_fixture_text(encoding_cases, encoded, recovered)
        if args.write_fixtures:
            fec_fixture.write_text(rendered_fec)
        elif not fec_fixture.exists() or fec_fixture.read_text() != rendered_fec:
            raise RuntimeError('owned hybrid native FEC fixtures differ; regenerate explicitly')
        fixtures = [streams[index] for index in (0, args.variants, 2 * args.variants, 3 * args.variants)]
        fixture = repository / FIXTURE_PATH
        if args.write_fixtures:
            fixture.write_text('/// Pinned libopus 1.6.1 authentic hybrid packets, full 48kHz float PCM and final ranges.\n'
                '/// Generated offline; normal tests never fetch or link the reference codec.\n'
                'let opusHybridOracleFixtures: [String] = [\n' + ''.join('    "' + base64.b64encode(json.dumps(stream, separators=(',', ':')).encode()).decode() + '",\n' for stream in fixtures) + ']\n')
        else:
            import re
            committed = [json.loads(base64.b64decode(value)) for value in re.findall(r'"([A-Za-z0-9+/=]+)"', fixture.read_text())]
            if committed != fixtures:
                raise RuntimeError('committed hybrid fixtures differ from reference reproduction')
        report = dict(verifiedOn=datetime.now(timezone.utc).date().isoformat(), result='passed',
            scope='Bidirectional ordinary hybrid encode/decode with shared SILK/CELT entropy, both channels/bandwidths and 10/20ms; conservative voiced/unvoiced encoding with optional independently selected SILK LBRR recovery, without perceptual delay compensation/noise shaping/DTX. Excludes full Opus conformance, reference encoder quality, devices and realtime qualification',
            officialVersion=VERSION, officialReleaseURL=RELEASE_URL, sourceArchiveURL=SOURCE_URL,
            sourceArchiveSHA256=ARCHIVE_SHA256, referenceConfiguration=configuration,
            ownedSwiftSHA256={str(path.relative_to(snapshot)):digest(path) for path in paths},
            ownedMediaSHA256={str(path.relative_to(snapshot)):digest(path) for path in sorted((snapshot / 'Sources/DiscordMedia').glob('*.swift'))},
            fixtureSHA256={FIXTURE_PATH:digest(fixture)}, verifierSHA256=digest(Path(__file__)),
            officialSourceSHA256={path:digest(upstream/path) for path in ('src/opus_decoder.c','silk/dec_API.c','celt/celt_decoder.c')},
            streams=len(streams), packets=sum(len(stream['packets']) for stream in streams),
            decodedSamples=sum(len(packet['pcm']) for stream in streams for packet in stream['packets']),
            transitionRedundancyFrames=sum(result['redundancy']>0 for stream in actual for result in stream),
            ownedEncodedStreams=len(encoded), ownedEncodedPackets=sum(len(stream['packets']) for stream in encoded),
            ownedEncodedSamples=sum(len(packet['pcm']) for stream in encoded for packet in stream['packets']),
            ownedEncoderBudgetRejections=sum(stream['budgetRejections'] for stream in encoded),
            ownedEncoderFECPolicies=[False, True],
            ownedRecoveredOperations=sum(len(stream['recoveries']) for stream in encoded),
            ownedFECOperations=sum(operation['fec'] for stream in encoded for operation in stream['recoveries']),
            ownedSelectedLBRRRecoveries=selected,
            ownedRecoveredSamples=sum(len(operation['pcm']) for stream in encoded for operation in stream['recoveries']),
            maximumOwnedRecoveryAbsolutePCMError=recovery_error,
            recoveryAbsoluteTolerance=TOLERANCE,
            ownedFECFixtureSHA256={OWNED_FEC_FIXTURE_PATH:digest(fec_fixture)},
            workingTreeChangedSinceSnapshot=[str(path.relative_to(snapshot)) for path in paths + sorted((snapshot / 'Sources/DiscordMedia').glob('*.swift'))
                if digest(path) != digest(repository / path.relative_to(snapshot))],
            maximumOwnedEncoderAbsolutePCMError=encoder_error,
            maximumAbsolutePCMError=error, absoluteTolerance=TOLERANCE,
            host=platform.platform(), swiftCompiler=run(['swiftc','--version']).decode().splitlines()[0])
        if args.report:
            args.report.write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

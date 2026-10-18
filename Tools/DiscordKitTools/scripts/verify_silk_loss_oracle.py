#!/usr/bin/env python3
"""Offline scalar SILK PLC/CNG, post-loss recovery and in-band FEC verification.

Builds unmodified pinned libopus 1.6.1 from a separately supplied verified archive
in temporary storage. Actual encoder streams exercise all SILK rates, durations,
mid-only/channel/rate transitions, initial/consecutive losses and present/absent
LBRR selection. Compares every output PCM16 sample and all compressed entropy
boundaries; no native codec is included in consumer runtime dependencies.
"""
import argparse
import ast
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import re
import subprocess
import tempfile

from verify_opus_range_oracle import (
    ARCHIVE_BYTE_COUNT, ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION,
    digest, extract_verified_archive, run,
)
from verify_silk_frame_oracle import OWNED_PATHS as CHANNEL_PATHS, OFFICIAL_PATHS as CHANNEL_OFFICIAL_PATHS, parse_outputs
from verify_silk_pulse_oracle import compare_results

OWNED_PATHS = CHANNEL_PATHS + ("Sources/DiscordVoiceCodecs/SILKMonoDecoder.swift", "Sources/DiscordVoiceCodecs/SILKMonoPacketDecoder.swift", "Sources/DiscordVoiceCodecs/SILKStereoDecoder.swift", "Sources/DiscordVoiceCodecs/OpusPacket.swift")
MEDIA_PATH = "Sources/DiscordMedia/PCM.swift"
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/SILKLossOracleFixtures.swift"
OFFICIAL_PATHS = CHANNEL_OFFICIAL_PATHS + tuple("silk/" + name for name in (
    "dec_API.c", "decoder_set_fs.c", "init_decoder.c", "decode_frame.c", "CNG.c", "PLC.c",
    "resampler.c", "resampler_private_IIR_FIR.c", "resampler_private_up2_HQ.c", "resampler_rom.c", "resampler_rom.h")) + ("silk/stereo_decode_pred.c", "silk/stereo_MS_to_LR.c", "src/opus_encoder.c", "src/opus.c", "configure")

C_DRIVER = r'''
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "opus.h"
#include "main.h"
#include "API.h"
#include "entdec.h"
typedef struct {silk_decoder_state channel[2];stereo_dec_state stereo;int api;int internal;int only;} State;
int main(void){int rate,channels,operations;
 while(scanf("%d %d %d",&rate,&channels,&operations)==3){int stateSize;silk_Get_Decoder_Size(&stateSize);void *state=calloc(1,stateSize);silk_InitDecoder(state);silk_DecControlStruct ctrl={0};ctrl.nChannelsAPI=channels;ctrl.nChannelsInternal=channels;ctrl.API_sampleRate=48000;ctrl.internalSampleRate=rate;printf("[");
 for(int operation=0;operation<operations;operation++){int mode,ms,size,value;if(scanf("%d %d %d",&mode,&ms,&size)!=3||size<0||size>65536)return 2;unsigned char bytes[65536];for(int i=0;i<size;i++){if(scanf("%d",&value)!=1)return 2;bytes[i]=value;}
 printf("%s{\"pcm\":[",operation?",":"");int printed=0;
 const unsigned char *frames[48];opus_int16 sizes[48];int offset;int count=1;unsigned ranges[48];int bits[48],nf[48],flags[48][2][3];
 if(size){count=opus_packet_parse(bytes,size,NULL,frames,sizes,&offset);if(count<1)return 3;ctrl.nChannelsInternal=opus_packet_get_nb_channels(bytes);ctrl.internalSampleRate=(int[]){8000,12000,16000}[bytes[0]>>5];ms=opus_packet_get_samples_per_frame(bytes,48000)/48;}
 for(int payload=0;payload<count;payload++){ec_dec dec;ec_dec_init(&dec,size?(unsigned char*)frames[payload]:bytes,size?sizes[payload]:0);ctrl.payloadSize_ms=ms;int internalCount=ms==10?1:ms/20;
 nf[payload]=internalCount;for(int f=0;f<internalCount;f++){opus_res pcm[1920];opus_int32 samples;if(silk_Decode(state,&ctrl,mode,f==0,&dec,pcm,&samples,0))return 4;for(int i=0;i<samples*channels;i++){printf("%s%d",printed?",":"",(int)lrintf(pcm[i]*32768.f));printed=1;}}
 ranges[payload]=dec.rng;bits[payload]=ec_tell(&dec);State *ss=state;for(int c=0;c<ctrl.nChannelsInternal;c++)for(int f=0;f<internalCount;f++)flags[payload][c][f]=ss->channel[c].LBRR_flags[f];
 }printf("],\"ranges\":[");if(size)for(int j=0;j<count;j++)printf("%s%u",j?",":"",ranges[j]);printf("],\"bits\":[");if(size)for(int j=0;j<count;j++)printf("%s%d",j?",":"",bits[j]);printf("],\"redundancy\":[");if(size)for(int j=0;j<count;j++){printf("%s[",j?",":"");for(int c=0;c<ctrl.nChannelsInternal;c++){printf("%s[",c?",":"");for(int f=0;f<nf[j];f++)printf("%s%s",f?",":"",flags[j][c][f]?"true":"false");printf("]");}printf("]");}printf("]}");
 }puts("]");free(state);
 }return 0;}
'''

GENERATOR_DRIVER = r'''
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include "opus.h"
#include "opus_private.h"
int main(void){int rate,fec,count,variant,pattern;
 while(scanf("%d %d %d %d %d",&rate,&fec,&count,&variant,&pattern)==5){
 int err;OpusEncoder *enc=opus_encoder_create(48000,2,OPUS_APPLICATION_VOIP,&err);if(!enc||err)return 2;
 int bw=rate==8000?OPUS_BANDWIDTH_NARROWBAND:rate==12000?OPUS_BANDWIDTH_MEDIUMBAND:OPUS_BANDWIDTH_WIDEBAND;
 opus_encoder_ctl(enc,OPUS_SET_FORCE_MODE(MODE_SILK_ONLY));opus_encoder_ctl(enc,OPUS_SET_BANDWIDTH(bw));opus_encoder_ctl(enc,OPUS_SET_MAX_BANDWIDTH(bw));
 opus_encoder_ctl(enc,OPUS_SET_BITRATE(rate==8000?26000:rate==12000?34000:64000));opus_encoder_ctl(enc,OPUS_SET_VBR(0));opus_encoder_ctl(enc,OPUS_SET_DTX(0));
 opus_encoder_ctl(enc,OPUS_SET_INBAND_FEC(fec));opus_encoder_ctl(enc,OPUS_SET_PACKET_LOSS_PERC(fec?25:0));opus_encoder_ctl(enc,OPUS_SET_COMPLEXITY(10));
 printf("{\"rate\":%d,\"packets\":[",rate);int position=0;unsigned random=variant+1;
 for(int f=0;f<count;f++){const int durations[8]={10,10,20,20,40,40,60,60};int ms=pattern==0||pattern==5?durations[f%8]:(int[]){10,20,40,60}[pattern-1];if(pattern==5){int rr=(int[]){8000,8000,12000,12000,16000,16000,12000,8000}[f%8];int bb=rr==8000?OPUS_BANDWIDTH_NARROWBAND:rr==12000?OPUS_BANDWIDTH_MEDIUMBAND:OPUS_BANDWIDTH_WIDEBAND;opus_encoder_ctl(enc,OPUS_SET_BANDWIDTH(bb));opus_encoder_ctl(enc,OPUS_SET_MAX_BANDWIDTH(bb));opus_encoder_ctl(enc,OPUS_SET_FORCE_CHANNELS(f%4<2?2:1));}if(pattern==0&&variant==3){opus_encoder_ctl(enc,OPUS_SET_FORCE_CHANNELS(2));opus_encoder_ctl(enc,OPUS_SET_BITRATE(10000));}opus_int16 pcm[5760];unsigned char bytes[1275];
 for(int i=0;i<ms*48;i++,position++){random=1664525*random+1013904223; double t=position/48000.;double s=11000*sin(2*3.141592653589793*(110+variant*7)*t)+4500*sin(2*3.141592653589793*327*t);if(variant%3==1&&f%5==4)s=0;if(variant%3==2&&f%5==3)s=((int)(random>>16)-32768)*0.4;if(variant==3)s=0;pcm[2*i]=(opus_int16)s;pcm[2*i+1]=(opus_int16)(variant==3?s:variant==2&&f%4==2?s:0.65*s+4000*sin(2*3.141592653589793*631*t));}
 int n=opus_encode(enc,pcm,ms*48,bytes,1275);if(n<1||bytes[0]>>3>11){fprintf(stderr,"badpacket:%d toc%d\n",n,bytes[0]);return 3;}
 printf("%s[",f?",":"");for(int i=0;i<n;i++)printf("%s%d",i?",":"",bytes[i]);printf("]");
 }puts("]}");opus_encoder_destroy(enc);
 }return 0;}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Operation: Codable { let mode: Int; let ms: Int; let packet: [UInt8] }
struct Input: Codable { let rate: Int; let channels: Int; let generalized: Bool?; let operations: [Operation] }
struct Output: Encodable { let pcm: [Int16]; let ranges: [UInt32]; let bits: [Int]; let redundancy: [[[Bool]]] }
@main struct Driver {
    static func main() throws {
        while let line = readLine() {
            let input = try JSONDecoder().decode(Input.self, from: Data(line.utf8))
            var mono = try SILKMonoDecoder(sampleRate: input.rate)
            var stereo = try SILKStereoDecoder(sampleRate: input.rate, outputChannelCount: input.channels)
            var results: [Output] = []
            for op in input.operations {
                var pcm: [Int16] = []
                var ranges: [UInt32] = []
                var bits: [Int] = []
                var redundancy: [[[Bool]]] = []
                if op.mode == 1 {
                    pcm = input.channels == 1 && input.generalized != true ? try mono.conceal(durationMilliseconds: op.ms).pcm48k : try stereo.conceal(durationMilliseconds: op.ms).pcm48k
                } else {
                    let packet = try OpusPacket(Data(op.packet))
                    let rate = [8_000, 12_000, 16_000][packet.configuration / 4]
                    if input.channels == 1 && input.generalized != true { try mono.updateSampleRate(rate) }
                    else { try stereo.updateSampleRate(rate) }
                    if op.mode == 2 {
                        for range in packet.frameRanges {
                            let payload = packet.data.subdata(in: range)
                            let recovered = input.channels == 1 && input.generalized != true
                                ? try mono.recoverPayload(payload, durationMilliseconds: packet.frameSampleCount / 48)
                                : try stereo.recoverPayload(payload, durationMilliseconds: packet.frameSampleCount / 48, codedChannelCount: packet.channelCount)
                            pcm += recovered.pcm48k
                            ranges.append(recovered.finalRange)
                            bits.append(recovered.bitsUsed)
                            redundancy.append(recovered.redundancy)
                        }
                    } else if input.channels == 1 && input.generalized != true {
                        let decoded = try mono.decode(packet)
                        pcm = decoded.pcm48k
                        ranges = decoded.payloads.map(\.finalRange)
                        bits = decoded.payloads.map(\.bitsUsed)
                        redundancy = decoded.payloads.map { [$0.redundancy] }
                    } else {
                        let decoded = try stereo.decode(packet)
                        pcm = decoded.pcm48k
                        ranges = decoded.payloads.map(\.finalRange)
                        bits = decoded.payloads.map(\.bitsUsed)
                        redundancy = decoded.payloads.map(\.redundancy)
                    }
                }
                results.append(Output(pcm: pcm, ranges: ranges, bits: bits, redundancy: redundancy))
            }
            print(String(decoding: try JSONEncoder().encode(results), as: UTF8.self))
        }
    }
}
'''


def committed_fixtures(repository):
    """Read independent literal compressed streams and complete PCM/header evidence."""
    result = []
    for line in (repository / FIXTURE_PATH).read_text().splitlines():
        match = re.fullmatch(r"\s*SILKLossOracleFixture\(input: (.*), expected: (.*)\),", line)
        if match:
            result.append((json.loads(ast.literal_eval(match.group(1))), json.loads(ast.literal_eval(match.group(2)))))
    if not result:
        raise RuntimeError("No stereo SILK packet fixtures found")
    return result


def generator_requests(variants):
    """Cover five duration policies, three rates and both encoder FEC policies deterministically."""
    return [(rate, fec, (24 if pattern == 5 else 8), variant, pattern) for pattern in range(6) for variant in range(variants)
            for rate in (8000, 12000, 16000) for fec in (0, 1)]


def commands(inputs):
    """Serialize ordered normal/loss/FEC operations with explicit API output channels."""
    lines = []
    for item in inputs:
        lines.append(f"{item['rate']} {item['channels']} {len(item['operations'])}")
        for op in item['operations']:
            lines.append(f"{op['mode']} {op['ms']} {len(op['packet'])} " + " ".join(map(str, op['packet'])))
    return ("\n".join(lines) + "\n").encode()



def operation_inputs(generated, repository):
    """Inject deterministic consecutive losses, FEC selection and ordinary recovery.

    Mono convenience and generalized mono/stereo outputs run independently.
    Missing LBRR is deliberately included, so recovery must match actual scalar
    PLC/CNG instead of silently returning empty data. Initial loss runs before
    any successful packet as a separate zero-state boundary.
    """
    from verify_silk_mono_oracle import committed_fixtures as mono_fixtures
    sources = [(i, 1, False) for i, _ in mono_fixtures(repository)]
    sources += [(i, channels, True) for i in generated for channels in (1, 2)]
    result = []
    for item, channels, generalized in sources:
        operations = []
        for index, packet in enumerate(item['packets']):
            if index % 3 == 1:
                operations.append(dict(mode=2, ms=0, packet=packet))
            operations.append(dict(mode=0, ms=0, packet=packet))
            if index % 3 == 0:
                operations.extend(dict(mode=1, ms=ms, packet=[]) for ms in (10, 20, 40, 60))
        result.append(dict(rate=item['rate'], channels=channels, generalized=generalized, operations=operations))
    for rate in (8000, 12000, 16000):
        for channels in (1, 2):
            result.append(dict(rate=rate, channels=channels, generalized=True,
                               operations=[dict(mode=1, ms=ms, packet=[]) for ms in (10, 20, 40, 60)]))
    return result


def run_at(command, directory):
    """Run an isolated configure/make step with captured diagnostics and no shell expansion."""
    result = subprocess.run(command, cwd=directory, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f"Reference build failed: {command!r}\n" + result.stderr.decode(errors="replace")[-8000:]
                           + result.stdout.decode(errors="replace")[-8000:])
    return result.stdout


def main():
    """Build only temporary references and compare every complete packet output exactly."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--variants", type=int, default=4)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 4 <= args.variants <= 20:
        parser.error("--variants must be 4...20 so every committed fixture is reproduced")
    repository = args.repository.resolve()
    fixtures = committed_fixtures(repository)
    with tempfile.TemporaryDirectory(prefix="discordkit-silk-stereo-") as temporary:
        directory = Path(temporary).resolve()
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        # The safe shared extractor copies bytes without archive mode bits. Restore
        # execution only for these audited upstream build helpers; content is unchanged.
        for name in ("configure", "install-sh", "missing", "depcomp", "compile", "config.guess", "config.sub"):
            (upstream / name).chmod(0o755)
        build = directory / "reference-build"
        build.mkdir()
        configuration = ["--disable-shared", "--enable-static", "--disable-intrinsics", "--disable-asm",
                         "--disable-rtcd", "--disable-dependency-tracking", "--disable-extra-programs", "--disable-doc", "--disable-deep-plc", "--disable-osce"]
        run_at(["sh", str(upstream / "configure")] + configuration + ["CC=" + args.cc], build)
        run_at(["make", "-j4"], build)
        binaries = []
        for name, source in (("oracle", C_DRIVER), ("generator", GENERATOR_DRIVER)):
            driver = directory / (name + ".c")
            driver.write_text(source)
            binary = directory / name
            run([args.cc, "-std=c99", "-O2", "-DHAVE_CONFIG_H", "-I" + str(build)]
                + ["-I" + str(upstream / path) for path in ("include", "celt", "silk", "src")]
                + [str(driver), str(build / ".libs/libopus.a"), "-lm", "-o", str(binary)])
            binaries.append(binary)
        requests = generator_requests(args.variants)
        generated = parse_outputs(run([str(binaries[1])], ("\n".join(" ".join(map(str, i)) for i in requests) + "\n").encode()), len(requests), arrays=False)
        operations = operation_inputs(generated, repository)
        for item, _ in fixtures:
            if item not in operations:
                raise RuntimeError("Committed operation stream differs from authentic packet reproduction")
        inputs = [i for i, _ in fixtures] + operations
        swift_driver = directory / "driver.swift"
        swift_driver.write_text(SWIFT_DRIVER)
        media = directory / "libDiscordMedia.dylib"
        run([args.swiftc, "-O", "-emit-module", "-emit-library", "-module-name", "DiscordMedia",
             "-module-cache-path", str(directory / "module-cache"), str(repository / MEDIA_PATH),
             "-emit-module-path", str(directory / "DiscordMedia.swiftmodule"), "-o", str(media)])
        owned = directory / "owned-driver"
        run([args.swiftc, "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated",
             "-I", str(directory), "-L", str(directory), "-lDiscordMedia", "-Xlinker", "-rpath", "-Xlinker", str(directory)]
            + [str(repository / path) for path in OWNED_PATHS] + [str(swift_driver), "-o", str(owned)])
        expected = parse_outputs(run([str(binaries[0])], commands(inputs)), len(inputs))
        actual = parse_outputs(run([str(owned)], ("\n".join(json.dumps(i) for i in inputs) + "\n").encode()), len(inputs))
        compare_results(inputs, expected, actual, args.variants)
        compare_results([i for i, _ in fixtures], [e for _, e in fixtures], expected[:len(fixtures)], args.variants)
        report = dict(
            verifiedOn=datetime.now(timezone.utc).date().isoformat(),
            scope="Scalar SILK PLC/CNG, normal post-loss recovery and in-band LBRR/FEC selection at 48kHz for mono convenience and generalized one/two API channels; excludes neural enhancements, complete Opus mode transitions, device and realtime qualification",
            officialVersion=VERSION, officialReleaseURL=RELEASE_URL, sourceArchiveURL=SOURCE_URL,
            sourceArchiveSHA256=ARCHIVE_SHA256, sourceArchiveByteCount=ARCHIVE_BYTE_COUNT,
            sourceLicense="Unmodified upstream COPYING retained in temporary reference build; owned scalar adaptations retain source notices",
            sourceLicenseSHA256=digest(upstream / "COPYING"), referenceConfiguration=configuration,
            officialSourceSHA256={path: digest(upstream / path) for path in OFFICIAL_PATHS},
            ownedSwiftSHA256={path: digest(repository / path) for path in OWNED_PATHS + (MEDIA_PATH,)},
            fixtureSHA256={FIXTURE_PATH: digest(repository / FIXTURE_PATH)}, verifierSHA256=digest(Path(__file__)),
            pythonVersion=platform.python_version(), compiler=run([args.cc, "--version"]).decode().splitlines()[0],
            swiftCompiler=run([args.swiftc, "--version"]).decode().splitlines()[0], host=platform.platform(),
            fixtureStreams=len(fixtures), authenticEncoderStreams=len(generated), operationStreams=len(operations),
            totalStreams=len(inputs), decodedOperations=sum(len(i["operations"]) for i in inputs),
            concealedOperations=sum(o["mode"] == 1 for i in inputs for o in i["operations"]),
            fecOperations=sum(o["mode"] == 2 for i in inputs for o in i["operations"]),
            decodedPCM16Samples=sum(len(packet["pcm"]) for stream in expected for packet in stream),
            redundantHeaderFrames=sum(sum(sum(sum(flags) for flags in payload) for payload in packet["redundancy"]) for stream in expected for packet in stream),
            comparison="Exact every 48kHz PCM16 sample after every normal/loss/FEC operation, and exact range/bit/redundancy evidence for compressed normal/FEC payloads",
            result="passed")
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

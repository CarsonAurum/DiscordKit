#!/usr/bin/env python3
"""Offline complete ordinary mono SILK packets -> 48kHz PCM against libopus 1.6.1.

A separately supplied pinned archive is verified and built only in temporary
storage. No download, native runtime dependency, credential or device is used.
Authentic encoder streams exercise all NB/MB/WB rates, 10/20/40/60ms payloads,
ordinary LBRR skipping, duration switches and all ordinary Opus packing codes.
This is no-loss mono SILK decode evidence, not a complete Opus codec, encoding
implementation, PLC/FEC recovery, stereo, hybrid, device or realtime qualification.
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

OWNED_PATHS = CHANNEL_PATHS + ("Sources/DiscordVoiceCodecs/SILKMonoDecoder.swift", "Sources/DiscordVoiceCodecs/SILKMonoPacketDecoder.swift", "Sources/DiscordVoiceCodecs/OpusPacket.swift")
MEDIA_PATH = "Sources/DiscordMedia/PCM.swift"
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/SILKMonoOracleFixtures.swift"
OFFICIAL_PATHS = CHANNEL_OFFICIAL_PATHS + tuple("silk/" + name for name in (
    "dec_API.c", "decoder_set_fs.c", "init_decoder.c", "decode_frame.c", "CNG.c", "PLC.c",
    "resampler.c", "resampler_private_IIR_FIR.c", "resampler_private_up2_HQ.c", "resampler_rom.c", "resampler_rom.h")) + ("src/opus_encoder.c", "src/opus.c", "configure")

C_DRIVER = r'''
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "opus.h"
#include "main.h"
#include "API.h"
#include "entdec.h"
int main(void){int rate,packets,size,value;
 while(scanf("%d %d",&rate,&packets)==2){int stateSize;silk_Get_Decoder_Size(&stateSize);void *state=calloc(1,stateSize);silk_InitDecoder(state);silk_DecControlStruct ctrl={0};ctrl.nChannelsAPI=ctrl.nChannelsInternal=1;ctrl.API_sampleRate=48000;ctrl.internalSampleRate=rate;printf("[");
 for(int packet=0;packet<packets;packet++){unsigned char bytes[65536];if(scanf("%d",&size)!=1||size<1||size>65536)return 2;for(int i=0;i<size;i++){if(scanf("%d",&value)!=1)return 2;bytes[i]=value;}
 const unsigned char *frames[48];opus_int16 sizes[48];int offset;int count=opus_packet_parse(bytes,size,NULL,frames,sizes,&offset);if(count<1)return 2;int ms=opus_packet_get_samples_per_frame(bytes,48000)/48;printf("%s{\"pcm\":[",packet?",":"");int printed=0;unsigned ranges[48];int bits[48],vads[48][3],lbrrs[48][3],nf[48];
 for(int payload=0;payload<count;payload++){ec_dec dec;ec_dec_init(&dec,(unsigned char*)frames[payload],sizes[payload]);ctrl.payloadSize_ms=ms;int internalCount=ms==10?1:ms/20;nf[payload]=internalCount;
 for(int f=0;f<internalCount;f++){opus_res pcm[960];opus_int32 samples;if(silk_Decode(state,&ctrl,0,f==0,&dec,pcm,&samples,0))return 3;for(int i=0;i<samples;i++){printf("%s%d",printed?",":"",(int)lrintf(pcm[i]*32768.f));printed=1;}}
 ranges[payload]=dec.rng;bits[payload]=ec_tell(&dec);silk_decoder_state *s=state;for(int f=0;f<internalCount;f++){vads[payload][f]=s->VAD_flags[f];lbrrs[payload][f]=s->LBRR_flags[f];}
 }
 printf("],\"ranges\":[");for(int i=0;i<count;i++)printf("%s%u",i?",":"",ranges[i]);printf("],\"bits\":[");for(int i=0;i<count;i++)printf("%s%d",i?",":"",bits[i]);
 printf("],\"activity\":[");for(int i=0;i<count;i++){printf("%s[",i?",":"");for(int f=0;f<nf[i];f++)printf("%s%s",f?",":"",vads[i][f]?"true":"false");printf("]");}
 printf("],\"redundancy\":[");for(int i=0;i<count;i++){printf("%s[",i?",":"");for(int f=0;f<nf[i];f++)printf("%s%s",f?",":"",lbrrs[i][f]?"true":"false");printf("]");}printf("]}");
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
 int err;OpusEncoder *enc=opus_encoder_create(48000,1,OPUS_APPLICATION_VOIP,&err);if(!enc||err)return 2;
 int bw=rate==8000?OPUS_BANDWIDTH_NARROWBAND:rate==12000?OPUS_BANDWIDTH_MEDIUMBAND:OPUS_BANDWIDTH_WIDEBAND;
 opus_encoder_ctl(enc,OPUS_SET_FORCE_MODE(MODE_SILK_ONLY));opus_encoder_ctl(enc,OPUS_SET_BANDWIDTH(bw));opus_encoder_ctl(enc,OPUS_SET_MAX_BANDWIDTH(bw));
 opus_encoder_ctl(enc,OPUS_SET_BITRATE(rate==8000?16000:rate==12000?24000:40000));opus_encoder_ctl(enc,OPUS_SET_VBR(0));opus_encoder_ctl(enc,OPUS_SET_DTX(0));
 opus_encoder_ctl(enc,OPUS_SET_INBAND_FEC(fec));opus_encoder_ctl(enc,OPUS_SET_PACKET_LOSS_PERC(fec?25:0));opus_encoder_ctl(enc,OPUS_SET_COMPLEXITY(10));
 printf("{\"rate\":%d,\"packets\":[",rate);int position=0;unsigned random=variant+1;
 for(int f=0;f<count;f++){const int durations[8]={10,10,20,20,40,40,60,60};int ms=pattern==0?durations[f%8]:(int[]){10,20,40,60}[pattern-1];opus_int16 pcm[2880];unsigned char bytes[1275];
 for(int i=0;i<ms*48;i++,position++){random=1664525*random+1013904223; double t=position/48000.;double s=11000*sin(2*3.141592653589793*(110+variant*7)*t)+4500*sin(2*3.141592653589793*327*t);if(variant%3==1&&f%5==4)s=0;if(variant%3==2&&f%5==3)s=((int)(random>>16)-32768)*0.4;if(variant==3)s=0;pcm[i]=(opus_int16)s;}
 int n=opus_encode(enc,pcm,ms*48,bytes,1275);if(n<1||bytes[0]>>3>11||bytes[0]&4){fprintf(stderr,"badpacket:%d toc%d\n",n,bytes[0]);return 3;}
 printf("%s[",f?",":"");for(int i=0;i<n;i++)printf("%s%d",i?",":"",bytes[i]);printf("]");
 }puts("]}");opus_encoder_destroy(enc);
 }return 0;}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable { let rate:Int; let packets:[[UInt8]] }
struct Output: Encodable { let pcm:[Int16]; let ranges:[UInt32]; let bits:[Int]; let activity:[[Bool]]; let redundancy:[[Bool]] }
@main struct Driver {
 static func main() throws {
  while let line=readLine() {
   let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   var decoder=try SILKMonoDecoder(sampleRate:input.rate)
   var outputs:[Output]=[]
   for bytes in input.packets {
    let output=try decoder.decode(OpusPacket(Data(bytes)))
    outputs.append(Output(pcm:output.pcm48k,ranges:output.payloads.map(\.finalRange),bits:output.payloads.map(\.bitsUsed),activity:output.payloads.map(\.voiceActivity),redundancy:output.payloads.map(\.redundancy)))
   }
   print(String(decoding:try JSONEncoder().encode(outputs),as:UTF8.self))
  }
 }
}
'''

def committed_fixtures(repository):
    """Read independent literal compressed streams and complete PCM/header evidence."""
    result = []
    for line in (repository / FIXTURE_PATH).read_text().splitlines():
        match = re.fullmatch(r"\s*SILKMonoOracleFixture\(input: (.*), expected: (.*)\),", line)
        if match:
            result.append((json.loads(ast.literal_eval(match.group(1))), json.loads(ast.literal_eval(match.group(2)))))
    if not result:
        raise RuntimeError("No mono SILK packet fixtures found")
    return result


def generator_requests(variants):
    """Cover five duration policies, three rates and both encoder FEC policies deterministically."""
    return [(rate, fec, 8, variant, pattern) for pattern in range(5) for variant in range(variants)
            for rate in (8000, 12000, 16000) for fec in (0, 1)]


def commands(inputs):
    """Serialize complete Opus packets while preserving per-stream decoder ownership."""
    lines = []
    for item in inputs:
        lines.append(f"{item['rate']} {len(item['packets'])}")
        for packet in item["packets"]:
            lines.append(str(len(packet)) + " " + " ".join(map(str, packet)))
    return ("\n".join(lines) + "\n").encode()


def single_payload(packet):
    """Remove generated code-zero or one-frame code-three CBR headers and padding.

    This generator-specific extraction is checked independently by upstream
    opus_packet_parse and the real owned OpusPacket when repackings are decoded.
    It deliberately rejects framing outside the authentic generator's output.
    """
    if not packet or packet[0] >> 3 > 11 or packet[0] & 4:
        raise RuntimeError("Generator produced unsupported mode/channel configuration")
    code = packet[0] & 3
    offset = 1
    padding = 0
    if code == 3:
        if len(packet) < 2 or packet[1] & 63 != 1:
            raise RuntimeError("Generator produced more than one packed frame")
        header = packet[1]
        offset = 2
        if header & 64:
            while True:
                if offset >= len(packet):
                    raise RuntimeError("Truncated generator padding")
                value = packet[offset]
                offset += 1
                padding += 254 if value == 255 else value
                if value != 255:
                    break
    elif code != 0:
        raise RuntimeError("Unexpected authentic generator packing code")
    if padding > len(packet) - offset:
        raise RuntimeError("Invalid generator padding")
    return packet[0] & 248, packet[offset:len(packet) - padding]


def length_bytes(count):
    """Produce the normative one/two-byte length field for a bounded payload size."""
    if not 0 <= count <= 1275:
        raise ValueError("Invalid payload count")
    if count < 252:
        return [count]
    first = 252 + (count & 3)
    return [first, (count - first) // 4]


def repacked_inputs(generated):
    """Exercise all four packing codes, VBR, padding and 120ms duration boundaries."""
    result = []
    for rate in (8000, 12000, 16000):
        item = next(i for i in generated if i["rate"] == rate)
        for index in (0, 6):
            toc, payload = single_payload(item["packets"][index])
            length = length_bytes(len(payload))
            packets = [[toc] + payload, [toc | 1] + payload * 2,
                       [toc | 2] + length + payload * 2,
                       [toc | 3, 2] + payload * 2,
                       [toc | 3, 0x82] + length + payload * 2,
                       [toc | 3, 0xc2, 3] + length + payload * 2 + [255, 0, 127]]
            if index == 0:
                packets.append([toc | 3, 12] + payload * 12)
            result.append(dict(rate=rate, packets=packets))
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
    with tempfile.TemporaryDirectory(prefix="discordkit-silk-mono-") as temporary:
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
        for item, _ in fixtures:
            if item not in generated:
                raise RuntimeError("Committed packet stream differs from authentic encoder reproduction")
        repacked = repacked_inputs(generated)
        inputs = [i for i, _ in fixtures] + generated + repacked
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
            scope="Ordinary no-loss mono SILK Opus packet decode to 48kHz PCM, VAD/LBRR skipping and packing only; excludes PLC/CNG after loss, FEC recovery, stereo, rate/mode transitions, full Opus codec/encoding, CELT/hybrid, device or realtime qualification",
            officialVersion=VERSION, officialReleaseURL=RELEASE_URL, sourceArchiveURL=SOURCE_URL,
            sourceArchiveSHA256=ARCHIVE_SHA256, sourceArchiveByteCount=ARCHIVE_BYTE_COUNT,
            sourceLicense="Unmodified upstream COPYING retained in temporary reference build; owned scalar adaptations retain source notices",
            sourceLicenseSHA256=digest(upstream / "COPYING"), referenceConfiguration=configuration,
            officialSourceSHA256={path: digest(upstream / path) for path in OFFICIAL_PATHS},
            ownedSwiftSHA256={path: digest(repository / path) for path in OWNED_PATHS + (MEDIA_PATH,)},
            fixtureSHA256={FIXTURE_PATH: digest(repository / FIXTURE_PATH)}, verifierSHA256=digest(Path(__file__)),
            pythonVersion=platform.python_version(), compiler=run([args.cc, "--version"]).decode().splitlines()[0],
            swiftCompiler=run([args.swiftc, "--version"]).decode().splitlines()[0], host=platform.platform(),
            fixtureStreams=len(fixtures), authenticStreams=len(generated), repackedStreams=len(repacked),
            totalStreams=len(inputs), decodedPackets=sum(len(i["packets"]) for i in inputs),
            decodedPCM16Samples=sum(len(packet["pcm"]) for stream in expected for packet in stream),
            skippedRedundantFrames=sum(sum(sum(flags) for flags in packet["redundancy"]) for stream in expected for packet in stream),
            comparison="Exact every 48kHz PCM16 sample, per-payload final range/bit accounting and VAD/LBRR flags after each packet",
            result="passed")
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

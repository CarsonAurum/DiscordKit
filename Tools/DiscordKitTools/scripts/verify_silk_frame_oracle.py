#!/usr/bin/env python3
"""Offline ordinary SILK compressed-channel PCM comparison against libopus 1.6.1.

Requires a separately supplied pinned archive; nothing is downloaded. Complete
unmodified upstream routines compile only in temporary storage. Scope is internal
8/12/16kHz channel PCM/state, excluding packet/stereo/resampling, PLC/CNG/FEC policy,
full codec conformance, encoding analysis, CELT/hybrid and native devices/realtime.
"""
import argparse
import ast
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import random
import re
import tempfile

from verify_opus_range_oracle import (
    ARCHIVE_BYTE_COUNT, ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION,
    digest, extract_verified_archive, run,
)
from verify_silk_parameter_oracle import OWNED_PATHS as PARAMETER_PATHS, OFFICIAL_PATHS as PARAMETER_OFFICIAL_PATHS, GENERATOR_DRIVER, generator_commands
from verify_silk_pulse_oracle import compare_results

OWNED_PATHS = PARAMETER_PATHS + ("Sources/DiscordVoiceCodecs/SILKNLSF.swift", "Sources/DiscordVoiceCodecs/SILKFrameDecoder.swift", "Sources/DiscordVoiceCodecs/SILKPacketLossConcealment.swift")
OFFICIAL_PATHS = PARAMETER_OFFICIAL_PATHS + tuple("silk/" + name + ".c" for name in (
    "decode_parameters", "decode_core", "NLSF2A", "LPC_fit", "LPC_inv_pred_gain",
    "bwexpander_32", "bwexpander", "LPC_analysis_filter", "table_LSF_cos"))
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/SILKFrameOracleFixtures.swift"

C_DRIVER = r'''
#include <stdio.h>
#include <string.h>
#include "main.h"
#include "entdec.h"
int main(void) {
 int rate,ms,frames,vad,lbrr,coding,count,value;
 while(scanf("%d %d %d",&rate,&ms,&frames)==3){
  if(!(rate==8000||rate==12000||rate==16000)||!(ms==10||ms==20)||frames<1||frames>20)return 2;
  silk_decoder_state state={0};
  state.fs_kHz=rate/1000;state.nb_subfr=ms/5;state.LPC_order=rate==16000?16:10;
  state.subfr_length=rate/200;state.frame_length=rate*ms/1000;state.ltp_mem_length=rate/50;
  state.prev_gain_Q16=65536;state.first_frame_after_reset=1;
  state.psNLSF_CB=rate==16000?&silk_NLSF_CB_WB:&silk_NLSF_CB_NB_MB;
  state.pitch_lag_low_bits_iCDF=rate==8000?silk_uniform4_iCDF:(rate==12000?silk_uniform6_iCDF:silk_uniform8_iCDF);
  state.pitch_contour_iCDF=rate==8000?(ms==10?silk_pitch_contour_10_ms_NB_iCDF:silk_pitch_contour_NB_iCDF):(ms==10?silk_pitch_contour_10_ms_iCDF:silk_pitch_contour_iCDF);
  printf("[");
  for(int frame=0;frame<frames;frame++){
   unsigned char bytes[1275]={0};opus_int16 pulses[336]={0},pcm[320]={0};ec_dec dec;silk_decoder_control control={0};
   if(scanf("%d %d %d %d",&vad,&lbrr,&coding,&count)!=4||count<0||count>1275)return 2;
   for(int i=0;i<count;i++){if(scanf("%d",&value)!=1||value<0||value>255)return 2;bytes[i]=value;}
   state.VAD_flags[0]=vad;ec_dec_init(&dec,bytes,count);
   silk_decode_indices(&state,&dec,0,lbrr,coding);silk_decode_pulses(&dec,pulses,state.indices.signalType,state.indices.quantOffsetType,state.frame_length);
   silk_decode_parameters(&state,&control,coding);silk_decode_core(&state,&control,pcm,pulses,0);
   int movement=state.ltp_mem_length-state.frame_length;memmove(state.outBuf,state.outBuf+state.frame_length,movement*sizeof(opus_int16));memcpy(state.outBuf+movement,pcm,state.frame_length*sizeof(opus_int16));state.first_frame_after_reset=0;
   printf("%s{\"pcm\":[",frame?",":"");for(int i=0;i<state.frame_length;i++)printf("%s%d",i?",":"",pcm[i]);
   printf("],\"lpcState\":[");for(int i=0;i<16;i++)printf("%s%d",i?",":"",state.sLPC_Q14_buf[i]);
   printf("],\"outputHistory\":[");for(int i=0;i<state.ltp_mem_length;i++)printf("%s%d",i?",":"",state.outBuf[i]);
   printf("],\"nlsfs\":[");for(int i=0;i<state.LPC_order;i++)printf("%s%d",i?",":"",state.prevNLSF_Q15[i]);
   printf("],\"gain\":%d,\"range\":%u,\"bits\":%d,\"fractional\":%u}",state.prev_gain_Q16,dec.rng,ec_tell(&dec),ec_tell_frac(&dec));
  }
  puts("]");
 }
 return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Frame: Decodable { let vad:Bool; let lbrr:Bool; let coding:Int; let bytes:[UInt8] }
struct Input: Decodable { let rate:Int; let milliseconds:Int; let frames:[Frame] }
struct Output: Encodable { let pcm:[Int16]; let lpcState:[Int32]; let outputHistory:[Int16]; let nlsfs:[Int16]; let gain:Int32; let range:UInt32; let bits:Int; let fractional:Int }
@main struct Driver {
 static func main() throws {
  while let line=readLine() {
   let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   var channel=try SILKFrameDecoder(sampleRate:input.rate,frameDurationMilliseconds:input.milliseconds)
   var outputs:[Output]=[]
   for frame in input.frames {
    var entropy=try OpusRangeDecoder(frame:Data(frame.bytes))
    let output=try channel.decode(from:&entropy,voiceActivity:frame.vad,lowBitrateRedundancy:frame.lbrr,coding:SILKParameterCoding(rawValue:frame.coding)!)
    outputs.append(Output(pcm:output.pcm,lpcState:channel.shortTermHistoryQ14,outputHistory:channel.outputHistory,nlsfs:channel.previousNormalizedLSFsQ15,gain:channel.previousGainQ16,range:entropy.finalRange,bits:entropy.bitsUsed,fractional:entropy.fractionalBitsUsed))
   }
   print(String(decoding:try JSONEncoder().encode(outputs),as:UTF8.self))
  }
 }
}
'''


def committed_fixtures(repository):
    """Read bounded compressed streams and independent literal PCM/state arrays."""
    result = []
    for line in (repository / FIXTURE_PATH).read_text().splitlines():
        match = re.fullmatch(r"\s*SILKFrameOracleFixture\(input: (.*), expected: (.*)\),", line)
        if match:
            result.append((json.loads(ast.literal_eval(match.group(1))), json.loads(ast.literal_eval(match.group(2)))))
    if not result:
        raise RuntimeError("No ordinary SILK PCM fixtures found")
    return result


def sequence_inputs(generated, count, seed):
    """Create reproducible two-through-twelve-frame streams with persistent channel state."""
    rng = random.Random(seed)
    result = []
    for index in range(count):
        rate = (8000, 12000, 16000)[index % 3]
        ms = (10, 20)[index % 2]
        available = [i for i in generated if i["rate"] == rate and i["milliseconds"] == ms]
        result.append(dict(rate=rate, milliseconds=ms, frames=[rng.choice(available) for _ in range(rng.randint(2, 12))]))
    return result


def commands(inputs):
    """Serialize configured streams while preserving per-frame entropy boundaries."""
    lines = []
    for item in inputs:
        lines.append(f"{item['rate']} {item['milliseconds']} {len(item['frames'])}")
        for frame in item["frames"]:
            lines.append(f"{int(frame['vad'])} {int(frame['lbrr'])} {frame['coding']} {len(frame['bytes'])} "
                         + " ".join(map(str, frame["bytes"])))
    return ("\n".join(lines) + "\n").encode()


def parse_outputs(data, count, arrays=True):
    """Reject missing/non-JSON results and wrong scalar-stream or generator shapes."""
    try:
        values = [json.loads(line) for line in data.decode().splitlines()]
    except (ValueError, UnicodeError) as error:
        raise RuntimeError("Invalid SILK frame oracle output") from error
    expected_type = list if arrays else dict
    if len(values) != count or any(not isinstance(value, expected_type) for value in values):
        raise RuntimeError("SILK frame oracle result count or shape mismatch")
    return values


def main():
    """Compile temporary authentic sources and compare every PCM sample/state exactly."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--cases", type=int, default=180)
    parser.add_argument("--seed", type=int, default=67164279)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 2000 or args.seed < 0:
        parser.error("--cases must be 1...2000 and --seed nonnegative")
    repository = args.repository.resolve()
    fixtures = committed_fixtures(repository)
    with tempfile.TemporaryDirectory(prefix="discordkit-silk-frames-") as temporary:
        directory = Path(temporary)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        binaries = []
        for name, source in (("oracle", C_DRIVER), ("generator", GENERATOR_DRIVER)):
            driver = directory / (name + ".c")
            driver.write_text(source)
            binary = directory / name
            run([args.cc, "-std=c99", "-O0", "-DOPUS_BUILD", "-DVAR_ARRAYS"]
                + ["-I" + str(upstream / path) for path in ("include", "celt", "silk")]
                + [str(driver)] + [str(upstream / path) for path in OFFICIAL_PATHS]
                + ["-lm", "-o", str(binary)])
            binaries.append(binary)
        generated = parse_outputs(run([str(binaries[1])], generator_commands()), 108, arrays=False)
        for item, _ in fixtures:
            if any(frame not in generated for frame in item["frames"]):
                raise RuntimeError("Compressed PCM fixture input differs from official reproduction")
        singles = [dict(rate=i["rate"], milliseconds=i["milliseconds"], frames=[i]) for i in generated]
        inputs = [i for i, _ in fixtures] + singles + sequence_inputs(generated, args.cases, args.seed)
        swift_driver = directory / "driver.swift"
        swift_driver.write_text(SWIFT_DRIVER)
        owned = directory / "owned-driver"
        run([args.swiftc, "-O", "-module-cache-path", str(directory / "module-cache"),
             "-enable-upcoming-feature", "ApproachableConcurrency", "-default-isolation", "nonisolated"]
            + [str(repository / path) for path in OWNED_PATHS] + [str(swift_driver), "-o", str(owned)])
        expected = parse_outputs(run([str(binaries[0])], commands(inputs)), len(inputs))
        actual = parse_outputs(run([str(owned)], ("\n".join(json.dumps(i) for i in inputs) + "\n").encode()), len(inputs))
        compare_results(inputs, expected, actual, args.seed)
        compare_results([i for i, _ in fixtures], [e for _, e in fixtures], expected[:len(fixtures)], args.seed)
        report = dict(
            verifiedOn=datetime.now(timezone.utc).date().isoformat(),
            scope="Ordinary no-loss internal-rate SILK compressed channel PCM/state only; no full packet/stereo/resampling, PLC/CNG/FEC policy, official full-codec conformance, encoder analysis, CELT/hybrid, device or realtime qualification",
            officialVersion=VERSION, officialReleaseURL=RELEASE_URL, sourceArchiveURL=SOURCE_URL,
            sourceArchiveSHA256=ARCHIVE_SHA256, sourceArchiveByteCount=ARCHIVE_BYTE_COUNT,
            sourceLicense="Unmodified upstream COPYING retained during temporary compilation; adapted scalar methods/tables retain source notices",
            sourceLicenseSHA256=digest(upstream / "COPYING"),
            officialSourceSHA256={path: digest(upstream / path) for path in OFFICIAL_PATHS},
            ownedSwiftSHA256={path: digest(repository / path) for path in OWNED_PATHS},
            fixtureSHA256={FIXTURE_PATH: digest(repository / FIXTURE_PATH)}, verifierSHA256=digest(Path(__file__)),
            pythonVersion=platform.python_version(), compiler=run([args.cc, "--version"]).decode().splitlines()[0],
            swiftCompiler=run([args.swiftc, "--version"]).decode().splitlines()[0], host=platform.platform(),
            seed=args.seed, fixtureStreams=len(fixtures), authenticSingleFrameCases=len(singles),
            continuedStreams=args.cases, totalStreams=len(inputs), decodedFrames=sum(len(i["frames"]) for i in inputs),
            comparison="Exact PCM16, persistent Q14 LPC/PCM history, previous LSF/gain, range and whole/eighth-bit accounting at every frame",
            result="passed")
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

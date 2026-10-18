#!/usr/bin/env python3
"""Offline complete SILK channel syntax/parameter verification against libopus 1.6.1.

The separately supplied pinned archive is never downloaded. C sources compile only
in temporary storage. Scope excludes decoded PCM, whole packet/stereo orchestration,
full codec conformance, encoding analysis/quantization, hybrid, PLC/FEC and devices.
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
from verify_silk_pulse_oracle import parse_outputs, compare_results

OWNED_PATHS = ("Sources/DiscordVoiceCodecs/OpusRangeCoding.swift",
               "Sources/DiscordVoiceCodecs/SILKExcitation.swift",
               "Sources/DiscordVoiceCodecs/SILKPulseTables.swift",
               "Sources/DiscordVoiceCodecs/SILKPulseCoding.swift",
               "Sources/DiscordVoiceCodecs/SILKParameterTables.swift",
               "Sources/DiscordVoiceCodecs/SILKFrameParameters.swift")
FIXTURE_PATH = "Tests/DiscordVoiceCodecsTests/SILKParameterOracleFixtures.swift"
OFFICIAL_PATHS = tuple("silk/" + name + ".c" for name in (
    "decode_indices", "NLSF_decode", "NLSF_unpack", "NLSF_stabilize", "sort", "gain_quant",
    "log2lin", "lin2log", "decode_pitch", "tables_NLSF_CB_NB_MB", "tables_NLSF_CB_WB",
    "tables_gain", "tables_pitch_lag", "tables_LTP", "tables_other", "pitch_est_tables",
    "decode_pulses", "shell_coder", "code_signs", "tables_pulses_per_block", "encode_indices", "encode_pulses"
)) + ("celt/entdec.c", "celt/entcode.c", "celt/entenc.c")

C_DRIVER = r'''
#include <stdio.h>
#include <string.h>
#include "main.h"
#include "entdec.h"
int main(void) {
 int rate,ms,vad,lbrr,coding,prevGain,prevType,prevLag,count,value;
 while(scanf("%d %d %d %d %d %d %d %d %d",&rate,&ms,&vad,&lbrr,&coding,&prevGain,&prevType,&prevLag,&count)==9) {
  if(!(rate==8000||rate==12000||rate==16000)||!(ms==10||ms==20)||count<0||count>1275)return 2;
  unsigned char bytes[1275]={0};
  for(int i=0;i<count;i++){if(scanf("%d",&value)!=1||value<0||value>255)return 2;bytes[i]=value;}
  silk_decoder_state state={0}; ec_dec dec;
  state.fs_kHz=rate/1000;state.nb_subfr=ms/5;state.LPC_order=rate==16000?16:10;
  state.psNLSF_CB=rate==16000?&silk_NLSF_CB_WB:&silk_NLSF_CB_NB_MB;
  state.pitch_lag_low_bits_iCDF=rate==8000?silk_uniform4_iCDF:(rate==12000?silk_uniform6_iCDF:silk_uniform8_iCDF);
  state.pitch_contour_iCDF=rate==8000?(ms==10?silk_pitch_contour_10_ms_NB_iCDF:silk_pitch_contour_NB_iCDF):(ms==10?silk_pitch_contour_10_ms_iCDF:silk_pitch_contour_iCDF);
  state.VAD_flags[0]=vad;state.ec_prevSignalType=prevType;state.ec_prevLagIndex=prevLag;
  ec_dec_init(&dec,bytes,count);silk_decode_indices(&state,&dec,0,lbrr,coding);
  SideInfoIndices *p=&state.indices;opus_int8 lastGain=prevGain;opus_int32 gains[4]={0};opus_int16 nlsfs[16]={0};int pitches[4]={0};
  silk_gains_dequant(gains,p->GainsIndices,&lastGain,coding==2,state.nb_subfr);
  silk_NLSF_decode(nlsfs,p->NLSFIndices,state.psNLSF_CB);
  if(p->signalType==2)silk_decode_pitch(p->lagIndex,p->contourIndex,pitches,state.fs_kHz,state.nb_subfr);
  printf("{\"signal\":%d,\"offset\":%d,\"seed\":%d,\"interpolation\":%d,\"stage1\":%d,\"gainIndices\":[",p->signalType,p->quantOffsetType,p->Seed,p->NLSFInterpCoef_Q2,p->NLSFIndices[0]);
  for(int i=0;i<state.nb_subfr;i++)printf("%s%d",i?",":"",p->GainsIndices[i]);
  printf("],\"residualIndices\":[");for(int i=0;i<state.LPC_order;i++)printf("%s%d",i?",":"",p->NLSFIndices[i+1]);
  printf("],\"gains\":[");for(int i=0;i<state.nb_subfr;i++)printf("%s%d",i?",":"",gains[i]);
  printf("],\"nlsfs\":[");for(int i=0;i<state.LPC_order;i++)printf("%s%d",i?",":"",nlsfs[i]);
  printf("],\"pitches\":[");for(int i=0;i<state.nb_subfr;i++)printf("%s%d",i?",":"",pitches[i]);
  printf("],\"ltpIndices\":[");if(p->signalType==2)for(int i=0;i<state.nb_subfr;i++)printf("%s%d",i?",":"",p->LTPIndex[i]);
  printf("],\"coefficients\":[");for(int i=0;i<state.nb_subfr;i++){printf("%s[",i?",":"");for(int j=0;j<5;j++)printf("%s%d",j?",":"",p->signalType==2?silk_LTP_vq_ptrs_Q7[p->PERIndex][p->LTPIndex[i]*5+j]:0);printf("]");}
  printf("],\"ltpScale\":%d,\"previousGain\":%d,\"previousType\":%d,\"previousLag\":%d,\"range\":%u,\"bits\":%d,\"fractional\":%u",p->signalType==2?silk_LTPScales_table_Q14[p->LTP_scaleIndex]:0,lastGain,state.ec_prevSignalType,state.ec_prevLagIndex,dec.rng,ec_tell(&dec),ec_tell_frac(&dec));
  if(p->signalType==2)printf(",\"lagIndex\":%d,\"contour\":%d,\"periodicity\":%d,\"scaleIndex\":%d",p->lagIndex,p->contourIndex,p->PERIndex,p->LTP_scaleIndex);
  opus_int16 pulses[336]={0};silk_decode_pulses(&dec,pulses,p->signalType,p->quantOffsetType,rate*ms/1000);
  printf(",\"pulses\":[");for(int i=0;i<(rate*ms/1000+15)/16*16;i++)printf("%s%d",i?",":"",pulses[i]);
  printf("],\"completeRange\":%u,\"completeBits\":%d,\"completeFractional\":%u}",dec.rng,ec_tell(&dec),ec_tell_frac(&dec));puts("");
 }
 return 0;
}
'''

GENERATOR_DRIVER = r'''
#include <stdio.h>
#include <string.h>
#include "main.h"
#include "entenc.h"
int main(void) {
 int rate,ms,signal,offset,coding,seed;
 while(scanf("%d %d %d %d %d %d",&rate,&ms,&signal,&offset,&coding,&seed)==6){
  silk_encoder_state state={0};unsigned char bytes[1275]={0};opus_int8 pulses[336]={0};ec_enc enc;
  state.fs_kHz=rate/1000;state.nb_subfr=ms/5;state.predictLPCOrder=rate==16000?16:10;
  state.psNLSF_CB=rate==16000?&silk_NLSF_CB_WB:&silk_NLSF_CB_NB_MB;
  state.pitch_lag_low_bits_iCDF=rate==8000?silk_uniform4_iCDF:(rate==12000?silk_uniform6_iCDF:silk_uniform8_iCDF);
  state.pitch_contour_iCDF=rate==8000?(ms==10?silk_pitch_contour_10_ms_NB_iCDF:silk_pitch_contour_NB_iCDF):(ms==10?silk_pitch_contour_10_ms_iCDF:silk_pitch_contour_iCDF);
  state.ec_prevSignalType=2;state.ec_prevLagIndex=40;
  SideInfoIndices *p=&state.indices;
  p->signalType=signal;p->quantOffsetType=offset;
  for(int i=0;i<state.nb_subfr;i++)p->GainsIndices[i]=i==0?(coding==2?5:32):(i*7)%41;
  p->NLSFIndices[0]=seed*7%32;for(int i=0;i<state.predictLPCOrder;i++)p->NLSFIndices[i+1]=(i+seed)%11-5;
  p->NLSFInterpCoef_Q2=ms==10?4:seed%5;
  p->lagIndex=40+seed;p->contourIndex=seed%(rate==8000?(ms==10?3:11):(ms==10?12:34));
  p->PERIndex=seed%3;for(int i=0;i<state.nb_subfr;i++)p->LTPIndex[i]=(i+seed)%(8<<p->PERIndex);
  p->LTP_scaleIndex=coding==0?seed%3:0;p->Seed=seed%4;
  int count=rate*ms/1000;for(int i=0;i<count;i++)pulses[i]=((i+seed)%13==0)?(i%2?-4:3):0;
  ec_enc_init(&enc,bytes,1275);silk_encode_indices(&state,&enc,0,0,coding);silk_encode_pulses(&enc,signal,offset,pulses,count);
  int storage=(ec_tell(&enc)+7)/8;ec_enc_shrink(&enc,storage);ec_enc_done(&enc);if(enc.error)return 3;
  printf("{\"rate\":%d,\"milliseconds\":%d,\"vad\":%s,\"lbrr\":false,\"coding\":%d,\"previousGain\":32,\"previousType\":2,\"previousLag\":40,\"bytes\":[",rate,ms,signal==0?"false":"true",coding);
  for(int i=0;i<storage;i++)printf("%s%d",i?",":"",bytes[i]);puts("]}");
 }
 return 0;
}
'''

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable { let rate:Int; let milliseconds:Int; let vad:Bool; let lbrr:Bool; let coding:Int; let previousGain:Int; let previousType:Int; let previousLag:Int16; let bytes:[UInt8] }
@main struct Driver {
 static func main() throws {
  while let line=readLine() {
   let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   var channel=try SILKFrameParameterDecoder(sampleRate:input.rate,frameDurationMilliseconds:input.milliseconds,previousGainIndex:input.previousGain,previousSignalType:SILKSignalType(rawValue:input.previousType)!,previousPitchLagIndex:input.previousLag)
   var entropy=try OpusRangeDecoder(frame:Data(input.bytes))
   let p=try channel.decode(from:&entropy,voiceActivity:input.vad,lowBitrateRedundancy:input.lbrr,coding:SILKParameterCoding(rawValue:input.coding)!)
   var output:[String:Any] = ["signal":p.signalType.rawValue,"offset":p.quantizationOffset.rawValue,"seed":Int(p.seed),"interpolation":p.interpolationQ2,"stage1":p.normalizedLSFCodebookIndex,"gainIndices":p.gainIndices,"residualIndices":p.normalizedLSFResidualIndices,"gains":p.gainsQ16.map{Int($0)},"nlsfs":p.normalizedLSFsQ15.map{Int($0)},"pitches":p.pitchLags,"ltpIndices":p.longTermGainIndices,"coefficients":p.longTermCoefficientsQ7.map{$0.map{Int($0)}},"ltpScale":Int(p.longTermScaleQ14),"previousGain":channel.previousGainIndex,"previousType":channel.previousSignalType.rawValue,"previousLag":Int(channel.previousPitchLagIndex),"range":entropy.finalRange,"bits":entropy.bitsUsed,"fractional":entropy.fractionalBitsUsed]
   if let lag=p.pitchLagIndex {output["lagIndex"]=Int(lag);output["contour"]=p.pitchContourIndex!;output["periodicity"]=p.periodicityIndex!;output["scaleIndex"]=p.longTermScaleIndex!}
   let pulseFrame=try SILKPulseCoding.decode(from:&entropy,sampleCount:channel.sampleCount,signalType:p.signalType,quantizationOffset:p.quantizationOffset)
   output["pulses"]=(pulseFrame.signedPulses+pulseFrame.discardedPadding).map{Int($0)};output["completeRange"]=entropy.finalRange;output["completeBits"]=entropy.bitsUsed;output["completeFractional"]=entropy.fractionalBitsUsed
   print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:.sortedKeys),as:UTF8.self))
  }
 }
}
'''


def committed_fixtures(repository):
    """Read exact literal fixture inputs/outputs without executing Swift code."""
    result = []
    for line in (repository / FIXTURE_PATH).read_text().splitlines():
        match = re.fullmatch(r"\s*SILKParameterOracleFixture\(input: (.*), expected: (.*)\),", line)
        if match:
            result.append((json.loads(ast.literal_eval(match.group(1))), json.loads(ast.literal_eval(match.group(2)))))
    if not result:
        raise RuntimeError("No SILK parameter fixtures found")
    return result


def generator_commands():
    """Cover all six rate/duration, six type/offset and three coding-mode contexts."""
    return "".join(f"{rate} {ms} {signal} {offset} {coding} {signal + coding + offset}\n"
                   for rate in (8000, 12000, 16000) for ms in (10, 20)
                   for signal in range(3) for offset in range(2) for coding in range(3)).encode()


def boundary_inputs():
    """Exercise zero-extension and deterministic arbitrary bytes across packet contexts."""
    return [dict(rate=rate, milliseconds=ms, vad=vad, lbrr=lbrr, coding=coding,
                 previousGain=0, previousType=0, previousLag=0, bytes=list(data))
            for rate in (8000, 12000, 16000) for ms in (10, 20) for vad in (False, True)
            for lbrr in (False, True) for coding in range(3)
            for data in ((), (0,), (255,), tuple(range(64)))]


def mixed_inputs(count, seed):
    """Generate reproducible arbitrary syntax with bounded extreme previous lag history."""
    rng = random.Random(seed)
    return [dict(rate=rng.choice((8000, 12000, 16000)), milliseconds=rng.choice((10, 20)),
                 vad=bool(rng.randrange(2)), lbrr=bool(rng.randrange(2)), coding=rng.randrange(3),
                 previousGain=rng.randrange(64), previousType=rng.randrange(3), previousLag=rng.randint(-32768, 32767),
                 bytes=[rng.randrange(256) for _ in range(rng.randrange(128))]) for _ in range(count)]


def commands(inputs):
    """Serialize explicit bounded channel/state/context inputs for the reference decoder."""
    return ("\n".join(f"{i['rate']} {i['milliseconds']} {int(i['vad'])} {int(i['lbrr'])} {i['coding']} "
                      f"{i['previousGain']} {i['previousType']} {i['previousLag']} {len(i['bytes'])} "
                      + " ".join(map(str, i["bytes"])) for i in inputs) + "\n").encode()


def main():
    """Reproduce encoded fixtures and compare exact parameters plus pulse-frame state."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=67164277)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 10000 or args.seed < 0:
        parser.error("--cases must be 1...10000 and --seed nonnegative")
    repository = args.repository.resolve()
    fixtures = committed_fixtures(repository)
    boundaries = boundary_inputs()
    with tempfile.TemporaryDirectory(prefix="discordkit-silk-parameters-") as temporary:
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
        generated = parse_outputs(run([str(binaries[1])], generator_commands()), 108)
        if any(item not in generated for item, _ in fixtures):
            raise RuntimeError("Encoded SILK channel fixture bytes differ from official reproduction")
        inputs = [item for item, _ in fixtures] + generated + boundaries + mixed_inputs(args.cases, args.seed)
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
            scope="Complete SILK channel parameter/pulse syntax only; no gain/LPC/LTP PCM orchestration, packet/stereo decoding, full codec conformance, hybrid, PLC/FEC or devices",
            officialVersion=VERSION, officialReleaseURL=RELEASE_URL, sourceArchiveURL=SOURCE_URL,
            sourceArchiveSHA256=ARCHIVE_SHA256, sourceArchiveByteCount=ARCHIVE_BYTE_COUNT,
            sourceLicense="Unmodified upstream COPYING retained during temporary compilation; adapted normative tables retain source notices",
            sourceLicenseSHA256=digest(upstream / "COPYING"),
            officialSourceSHA256={path: digest(upstream / path) for path in OFFICIAL_PATHS},
            ownedSwiftSHA256={path: digest(repository / path) for path in OWNED_PATHS},
            fixtureSHA256={FIXTURE_PATH: digest(repository / FIXTURE_PATH)},
            verifierSHA256=digest(Path(__file__)), pythonVersion=platform.python_version(),
            compiler=run([args.cc, "--version"]).decode().splitlines()[0],
            swiftCompiler=run([args.swiftc, "--version"]).decode().splitlines()[0], host=platform.platform(),
            seed=args.seed, fixtureCases=len(fixtures), validEncodedChannelCases=len(generated),
            boundaryCases=len(boundaries), randomCases=args.cases, totalCases=len(inputs),
            comparison="Exact entropy indices, Q15 stabilized LSFs, Q16 gains, pitch contours/Q7 LTP/scale, previous state, signed pulses/padding, intermediate/final range and whole/eighth-bit accounting",
            result="passed")
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

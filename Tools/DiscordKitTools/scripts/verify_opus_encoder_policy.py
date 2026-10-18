#!/usr/bin/env python3
"""Opt-in owned encoder policy, objective signal quality and frame-time measurements.

Uses pinned separately supplied libopus only as an independent decoder. Generated
vowel-like speech and chord/percussion signals are synthetic regression material,
not a natural-speech/music listening corpus or perceptual MOS qualification.
No devices, network, credentials or native product dependency are used.
"""
import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import platform
import random
import subprocess
import struct
import tempfile
import wave

from verify_opus_range_oracle import ARCHIVE_SHA256, digest, extract_verified_archive, run
from verify_silk_mono_oracle import run_at
from verify_opus_hybrid_oracle import snapshot_sources

SWIFT_DRIVER = r'''
import Foundation
struct Input: Decodable { let mode:String; let channels:Int; let rate:Int; let dtx:Bool; let kind:String; let frames:[[Float]]; let fec:Bool?; let recovery:Bool? }
struct Packet: Encodable { let bytes:[UInt8]; let pcm:[Float]; let range:UInt32; let transmit:Bool; let dtx:Bool; let budget:Int; let encodeNS:UInt64; let decodeNS:UInt64; let sourceIndex:Int; let packetIndex:Int; let recovering:Bool; let selectedLBRR:Bool }
@main struct Driver {
 /// Reads only the VAD/LBRR header of one fixed 20ms SILK/hybrid payload.
 /// - Parameters:
 ///   - data: Complete single-frame packet, including external SILK padding.
 ///   - channels: Validated one/two coded channels in the fixed stream.
 /// - Returns: Whether either coded channel advertises selected LBRR; empty DTX is false.
 /// - Throws: Framing/range errors. No decoder, predictor or PCM history is changed.
 static func hasLBRR(_ data:Data, channels:Int) throws -> Bool {
  let packet=try OpusPacket(data)
  let payload=Data(packet.data[packet.frameRanges[0]])
  guard payload.count > 1 else {return false}
  var entropy=try OpusRangeDecoder(frame:payload);var selected=false
  for _ in 0..<channels {
   _=try entropy.decodeBit(logProbability:1)
   let present=try entropy.decodeBit(logProbability:1)
   selected=selected || present
  }
  return selected
 }
 /// Measures caller-serialized owned encoding/decoding after ten untimed warmup frames.
 /// Each JSON line defines one finite fixed-format stream. Optional recovery replay
 /// omits frames 2/10/52 and invokes FEC from their following packets before normal decode.
 /// - Throws: Invalid local input, codec or JSON errors; partial streams never pass.
 static func main() throws {
  while let line=readLine() {
   let input=try JSONDecoder().decode(Input.self,from:Data(line.utf8))
   let mode:OpusMode=input.mode=="silk" ? .silk : input.mode=="hybrid" ? .hybrid : .celt
   let bandwidth:OpusBandwidth=mode == .silk ? .wideband : .fullband
   var encoder=try OpusAudioEncoder(mode:mode,bandwidth:bandwidth,channelCount:input.channels,
       targetBitrate:input.rate,dtx:input.dtx ? try OpusDTXPolicy(hangoverMilliseconds:40) : nil,
       enableInBandFEC:input.fec ?? false)
   var decoder=try OpusAudioDecoder(channelCount:input.channels)
   for _ in 0..<10 {let output=try encoder.encode(input.frames[0]);_=try decoder.decode(output.data)}
   encoder.reset();decoder.reset()
   var packets:[Packet]=[]
   for (index,frame) in input.frames.enumerated() {
    let start=DispatchTime.now().uptimeNanoseconds
    let output:OpusAudioEncodedPacket
    do {output=try encoder.encode(frame)} catch {
     throw NSError(domain:"\(input.mode)/\(input.channels)ch/\(input.rate)bps/\(input.kind)/frame\(index): \(error)",code:1)
    }
    let encoded=DispatchTime.now().uptimeNanoseconds
    if input.recovery == true && [2,10,52].contains(index) {continue}
    if input.recovery == true && [3,11,53].contains(index) {
     let recovered=try decoder.recover(output.data,frameSampleCount:960)
     packets.append(Packet(bytes:[UInt8](output.data),pcm:recovered.samples,range:recovered.finalRange,
         transmit:output.shouldTransmit,dtx:output.isDTX,budget:output.packetByteBudget,encodeNS:0,decodeNS:0,
         sourceIndex:index-1,packetIndex:index,recovering:true,
         selectedLBRR:try hasLBRR(output.data,channels:input.channels)))
    }
    let pcm=try decoder.decode(output.data).flatMap(\.samples)
    let decoded=DispatchTime.now().uptimeNanoseconds
    guard output.finalRange == decoder.finalRange else {
     throw NSError(domain:"encoder/decoder final range mismatch",code:1)
    }
    packets.append(Packet(bytes:[UInt8](output.data),pcm:pcm,range:decoder.finalRange,
        transmit:output.shouldTransmit,dtx:output.isDTX,budget:output.packetByteBudget,encodeNS:encoded-start,decodeNS:decoded-encoded,
        sourceIndex:index,packetIndex:index,recovering:false,selectedLBRR:false))
   }
   print(String(decoding:try JSONEncoder().encode(packets),as:UTF8.self))
  }
 }
}
'''

C_DRIVER = r'''
#include <stdio.h>
#include "opus.h"
int main(void) {
int channels,count;
 while(scanf("%d%d",&channels,&count)==2) {
  if(channels<1||channels>2||count<1||count>300)return 2;
  int error;OpusDecoder *decoder=opus_decoder_create(48000,channels,&error);
  if(!decoder||error)return 3;
  printf("[");
  for(int p=0;p<count;p++) {
   unsigned char bytes[1276];float pcm[1920];int fec,size,value;
   if(scanf("%d%d",&fec,&size)!=2||(fec!=0&&fec!=1)||size<1||size>1276)return 4;
   for(int i=0;i<size;i++){if(scanf("%d",&value)!=1||value<0||value>255)return 4;bytes[i]=value;}
   int lbrr=opus_packet_has_lbrr(bytes,size);if(lbrr<0||lbrr>1)return 6;
   int n=opus_decode_float(decoder,bytes,size,pcm,960,fec);if(n!=960)return 5;
   opus_uint32 range;opus_decoder_ctl(decoder,OPUS_GET_FINAL_RANGE(&range));
   printf("%s{\"range\":%u,\"lbrr\":%s,\"pcm\":[",p?",":"",range,lbrr?"true":"false");
   for(int i=0;i<n*channels;i++)printf("%s%.9g",i?",":"",pcm[i]);printf("]}");
  }
  puts("]");opus_decoder_destroy(decoder);
 }
 return 0;
}
'''


def signal(kind, channels, frames=60):
    """Generate reproducible normalized voiced/unvoiced or tonal/percussive PCM.

    Includes a silent tail to flush algorithmic delay; each frame is exactly 20ms.
    This models selected signal features and makes no human-corpus accuracy claim.
    """
    if kind not in ('speech', 'music', 'dtx') or channels not in (1, 2) or not 12 <= frames <= 300:
        raise ValueError('invalid signal format')
    rng = random.Random(67168251)
    output = []
    for frame in range(frames):
        pcm = []
        for i in range(960):
            t = (frame * 960 + i) / 48000
            for channel in range(channels):
                if kind == 'speech':
                    f0 = 143 + channel * 29
                    envelope = max(0, math.sin(math.pi * (t % 0.24) / 0.24)) ** 2
                    value = sum(math.sin(2 * math.pi * f0 * h * t) / h for h in range(1, 13)) * 0.14 * envelope
                    if frame % 12 in (8, 9):
                        value = rng.uniform(-0.09, 0.09) * envelope
                else:
                    value = sum(math.sin(2 * math.pi * f * (1 + channel * 0.003) * t)
                                for f in (220, 277.1826, 329.6276, 659.255)) * 0.09
                    pulse = math.exp(-(t % 0.2) * 90)
                    value += rng.uniform(-0.18, 0.18) * pulse
                if frame >= frames - 3 or kind == 'dtx' and 8 <= frame < frames - 8:
                    value = 0
                pcm.append(value)
        output.append(pcm)
    return output


def fec_dtx_cases():
    """Add four fixed-format FEC/DTX streams without changing ordinary baseline inputs.

    The 60-frame signal has initial activity, a long suppressed interval and a
    resumed talkspurt. Generous finite rates admit preceding-frame LBRR; they are
    selected interoperability cases, not low-bitrate or complete loss qualification.
    """
    return [dict(mode=mode, channels=channels, rate=256_000 if channels == 1 else 384_000,
                 dtx=True, fec=True, kind='fec-dtx', frames=signal('dtx', channels))
            for mode in ('silk', 'hybrid') for channels in (1, 2)]


def percentile(values, quantile):
    """Return the conservative nearest-rank quantile of nonempty finite measurements."""
    if not values or not 0 < quantile <= 1 or any(not math.isfinite(v) or v < 0 for v in values):
        raise ValueError('invalid timing measurements')
    return sorted(values)[max(0, math.ceil(len(values) * quantile) - 1)]


def wav_signal(path):
    """Read at most five seconds of supplied 48kHz PCM16 mono/stereo plus a 60ms tail.

    Files stay external; the report retains content fingerprints and numerical
    diagnostics only. Bounded input validation precedes sample allocation.
    """
    if not 44 <= path.stat().st_size <= 64 * 1024 * 1024:
        raise ValueError('WAV size out of bounds')
    with wave.open(str(path), 'rb') as audio:
        channels = audio.getnchannels()
        if channels not in (1, 2) or audio.getframerate() != 48000 or audio.getsampwidth() != 2 or audio.getcomptype() != 'NONE':
            raise ValueError('expected 48kHz mono/stereo uncompressed PCM16 WAV')
        frames = min(audio.getnframes() // 960, 250)
        if frames < 12:
            raise ValueError('WAV has insufficient complete frames')
        raw = audio.readframes(frames * 960)
        if len(raw) != frames * 960 * channels * 2:
            raise ValueError('truncated WAV')
    values = [value / 32768 for value in struct.unpack('<' + 'h' * (len(raw) // 2), raw)]
    count = 960 * channels
    blocks = [values[offset:offset + count] for offset in range(0, len(values), count)]
    return channels, blocks + [[0.0] * count for _ in range(3)]


def quality(source, decoded, channels):
    """Measure unscaled delay-aligned waveform SNR and peak over complete output.

    Search only a bounded 0...20ms algorithmic delay. Coarse alignment uses a
    decimated channel, followed by sample-accurate refinement; all channels then
    contribute to unscaled SNR. This is a diagnostic, not perceptual acceptance.
    """
    if channels not in (1, 2) or len(source) != len(decoded) or len(source) < 3840 * channels:
        raise ValueError('invalid quality dimensions')
    if any(not math.isfinite(v) for v in source + decoded):
        raise ValueError('nonfinite quality samples')
    stop = len(source) // channels - 960
    def error(delay, stride):
        return sum((source[i * channels] - decoded[(i + delay) * channels]) ** 2
                   for i in range(0, stop, stride))
    coarse = min(range(0, 961, 8), key=lambda delay: error(delay, 16))
    delay = min(range(max(0, coarse - 8), min(960, coarse + 8) + 1), key=lambda lag: error(lag, 1))
    expected = source[:stop * channels]
    actual = decoded[delay * channels:(delay + stop) * channels]
    power = sum(v * v for v in expected)
    noise = sum((v - w) ** 2 for v, w in zip(expected, actual))
    return dict(delaySamples=delay, snrDB=10 * math.log10(max(power, 1e-30) / max(noise, 1e-30)),
                decodedPeak=max(map(abs, decoded)), clippedSampleCount=sum(abs(v) > 1 for v in decoded))


def native_commands(cases, streams):
    """Serialize ordinary or explicit FEC operations, including legal DTX placeholders."""
    if len(cases) != len(streams):
        raise ValueError('missing streams')
    lines = []
    for case, packets in zip(cases, streams):
        lines.append(f"{case['channels']} {len(packets)}")
        lines.extend(f"{int(p.get('recovering', False))} {len(p['bytes'])} " + ' '.join(map(str, p['bytes']))
                     for p in packets)
    return ('\n'.join(lines) + '\n').encode()


def validate_owned(cases, streams):
    """Require complete bounded allocations and observable DTX silence suppression/refresh.

    These selected rates have integral 20ms allocations. The production tests cover
    fractional targets separately. Failure never converts a rejected frame to success.
    """
    if len(cases) != len(streams):
        raise ValueError('missing owned streams')
    for case, packets in zip(cases, streams):
        if len(case['frames']) != len(packets):
            raise ValueError('missing owned frames')
        silent_gap = 0
        for packet in packets:
            data = packet['bytes']
            if packet['budget'] != case['rate'] // 400 or not data or len(data) > packet['budget']:
                raise ValueError('invalid owned framing/allocation')
            if packet['dtx']:
                if not case['dtx'] or packet['transmit'] or len(data) != 1 or data[0] & 3:
                    raise ValueError('invalid DTX interval')
                silent_gap += 960
                if silent_gap >= 19200:
                    raise ValueError('DTX refresh interval exceeded')
            else:
                if not packet['transmit'] or len(data) != packet['budget']:
                    raise ValueError('invalid active/refresh packet')
                silent_gap = 0
        if case['dtx'] and not any(packet['dtx'] for packet in packets):
            raise ValueError('silence never suppressed')


def validate_fec_recovery(case, ordinary, recovered):
    """Require selected LBRR before/after DTX and explicit PLC inside suppression.

    Missing source frames 2, 10 and 52 are replaced by recovery from the following
    packet, which must then also be decoded normally. Header evidence establishes
    selected LBRR, not recovery waveform identity to the omitted ordinary decode.
    This validates operation provenance before independent native PCM/range checks.
    """
    if case.get('fec') is not True or case.get('dtx') is not True or case.get('mode') not in ('silk', 'hybrid'):
        raise ValueError('invalid FEC/DTX case')
    if len(case['frames']) != 60 or len(ordinary) != 60 or len(recovered) != 60:
        raise ValueError('missing FEC/DTX operations')
    selected = 0
    for index, packet in enumerate(recovered):
        recovering = index in (2, 10, 52)
        source_packet = index + 1 if recovering else index
        if packet.get('sourceIndex') != index or packet.get('packetIndex') != source_packet:
            raise ValueError('incorrect FEC source/packet order')
        if packet.get('recovering') is not recovering or packet.get('selectedLBRR') is not (index in (2, 52)):
            raise ValueError('missing selected LBRR or unexpected recovery')
        if packet['bytes'] != ordinary[source_packet]['bytes'] or packet.get('dtx') is not ordinary[source_packet]['dtx']:
            raise ValueError('recovery used different encoded bytes')
        selected += packet['selectedLBRR']
    if not ordinary[10]['dtx'] or not ordinary[11]['dtx'] or not ordinary[51]['dtx']:
        raise ValueError('recovery did not cross a suppressed interval')
    if any(ordinary[index]['dtx'] or not ordinary[index]['transmit'] for index in (2, 3, 52, 53)):
        raise ValueError('missing pre/post-suppression active packets')
    return dict(mode=case['mode'], channels=case['channels'], frames=60,
                selectedLBRRRecoveries=selected, suppressedPLCRecoveries=1,
                missingSourceFrames=[2, 10, 52])


def compare_native(cases, owned, native):
    """Reject missing frames, dimensions, nonfinite PCM and unequal compressed final ranges.

    Ordinary PCM uses a tight floating tolerance. DTX PLC may amplify transform
    roundoff; its explicit sequence-scaled bound is numerical, not perceptual.
    """
    if len(cases) != len(owned) or len(owned) != len(native):
        raise ValueError('missing independent streams')
    maximum = 0.0
    for case, stream, reference in zip(cases, owned, native):
        if len(stream) != len(case['frames']) or len(stream) != len(reference):
            raise ValueError('missing independent frames')
        scale = max(1, *(abs(v) for packet in reference for v in packet['pcm']))
        after_suppression = False
        for packet, expected in zip(stream, reference):
            after_suppression = after_suppression or packet.get('dtx', False)
            if packet.get('recovering', False) and expected.get('lbrr') is not packet.get('selectedLBRR'):
                raise ValueError('independent selected LBRR mismatch')
            if packet['range'] != expected['range'] or len(packet['pcm']) != 960 * case['channels'] or len(packet['pcm']) != len(expected['pcm']):
                raise ValueError('independent range/dimension mismatch')
            for a, b in zip(packet['pcm'], expected['pcm']):
                delta = abs(a - b)
                if not math.isfinite(a) or not math.isfinite(b) or delta > (0.002 * scale if after_suppression else 3e-6) + 3e-6 * abs(b):
                    raise ValueError(f'independent PCM mismatch: {delta}')
                maximum = max(maximum, delta)
    return maximum


def main():
    """Compile immutable owned snapshots and a pinned scalar oracle, then record measured limits."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-archive', type=Path, required=True)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--speech-wav', type=Path)
    parser.add_argument('--music-wav', type=Path)
    args = parser.parse_args()
    repository = args.repository.resolve()
    cases = [dict(mode=mode, channels=channels, rate=rate * channels, dtx=kind == 'dtx', kind=kind,
                  frames=signal(kind, channels))
             for mode, rate in (('silk', 32000), ('hybrid', 64000), ('celt', 64000))
             for channels in (1, 2) for kind in ('speech', 'music', 'dtx')]
    external = []
    for kind, path in [('speech', args.speech_wav), ('music', args.music_wav)]:
        if path:
            channels, frames = wav_signal(path)
            external.append(dict(kind=kind, sha256=digest(path), bytes=path.stat().st_size,
                                 measuredSeconds=(len(frames) - 3) * .02))
            cases.extend(dict(mode=mode, channels=channels, rate=rate * channels, dtx=False,
                              kind='external-' + kind, frames=frames)
                         for mode, rate in (('silk', 32000), ('hybrid', 64000), ('celt', 64000)))
    cases.extend(fec_dtx_cases())
    with tempfile.TemporaryDirectory(prefix='discordkit-encoder-policy-') as temporary:
        directory = Path(temporary).resolve()
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        for name in ('configure', 'install-sh', 'missing', 'depcomp', 'compile', 'config.guess', 'config.sub'):
            (upstream / name).chmod(0o755)
        build = directory / 'reference-build'
        build.mkdir()
        run_at(['sh', str(upstream / 'configure'), '--disable-shared', '--enable-static', '--disable-intrinsics',
                '--disable-asm', '--disable-rtcd', '--disable-dependency-tracking', '--disable-extra-programs',
                '--disable-doc', '--disable-deep-plc', '--disable-osce'], build)
        run_at(['make', '-j4'], build)
        source = directory / 'decoder.c'
        source.write_text(C_DRIVER)
        oracle = directory / 'oracle'
        run(['cc', '-O2', '-I' + str(upstream / 'include'), str(source), str(build / '.libs/libopus.a'), '-lm', '-o', str(oracle)])
        snapshot = snapshot_sources(repository, directory)
        settings = ['-O', '-module-cache-path', str(directory / 'module-cache'),
                    '-enable-upcoming-feature', 'ApproachableConcurrency', '-default-isolation', 'nonisolated']
        media = sorted((snapshot / 'Sources/DiscordMedia').glob('*.swift'))
        run(['swiftc', *settings, '-emit-module', '-emit-library', '-module-name', 'DiscordMedia', *map(str, media),
             '-emit-module-path', str(directory / 'DiscordMedia.swiftmodule'), '-o', str(directory / 'libDiscordMedia.dylib')])
        driver = directory / 'driver.swift'
        driver.write_text(SWIFT_DRIVER)
        executable = directory / 'owned'
        codecs = sorted((snapshot / 'Sources/DiscordVoiceCodecs').glob('*.swift'))
        run(['swiftc', *settings, '-I', str(directory), '-L', str(directory), '-lDiscordMedia',
             '-Xlinker', '-rpath', '-Xlinker', str(directory), *map(str, codecs), str(driver), '-o', str(executable)])
        accepted, owned, failures = [], [], []
        for case in cases:
            completed = subprocess.run([str(executable)], input=(json.dumps(case) + '\n').encode(),
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
            if completed.returncode:
                failures.append(dict(mode=case['mode'], channels=case['channels'], kind=case['kind'],
                                     bitrate=case['rate'], failure=completed.stderr.decode(errors='replace')[-2000:]))
            else:
                lines = completed.stdout.splitlines()
                if len(lines) != 1:
                    raise RuntimeError('Expected exactly one complete owned output stream')
                accepted.append(case)
                owned.append(json.loads(lines[0]))
        cases = accepted
        validate_owned(cases, owned)
        native = [json.loads(line) for line in run([str(oracle)], native_commands(cases, owned)).splitlines()]
        maximum = compare_native(cases, owned, native)
        recovery_records = []
        recovery_maximum = 0.0
        for case, packets in zip(cases, owned):
            if not case.get('fec', False):
                continue
            recovery_case = dict(case, recovery=True)
            completed = subprocess.run([str(executable)], input=(json.dumps(recovery_case) + '\n').encode(),
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
            if completed.returncode:
                failures.append(dict(mode=case['mode'], channels=case['channels'], kind='fec-dtx-recovery',
                                     bitrate=case['rate'], failure=completed.stderr.decode(errors='replace')[-2000:]))
                continue
            lines = completed.stdout.splitlines()
            if len(lines) != 1:
                raise RuntimeError('Expected exactly one complete FEC recovery stream')
            recovered = json.loads(lines[0])
            summary = validate_fec_recovery(case, packets, recovered)
            reference = [json.loads(line) for line in run([str(oracle)], native_commands([case], [recovered])).splitlines()]
            error = compare_native([case], [recovered], reference)
            recovery_maximum = max(recovery_maximum, error)
            recovery_records.append(dict(**summary, maximumIndependentPCMError=error))
        records = []
        for case, packets in zip(cases, owned):
            samples = sum(case['frames'], [])
            pcm = [value for p in packets for value in p['pcm']]
            encode = [p['encodeNS'] / 1e6 for p in packets]
            decode = [p['decodeNS'] / 1e6 for p in packets]
            total = [a + b for a, b in zip(encode, decode)]
            records.append(dict(mode=case['mode'], channels=case['channels'], kind=case['kind'],
                enableInBandFEC=case.get('fec', False),
                bitrate=case['rate'], frames=len(packets), inputSHA256=__import__('hashlib').sha256(json.dumps(case['frames']).encode()).hexdigest(),
                **quality(samples, pcm, case['channels']),
                encodeP50MS=percentile(encode, .5), encodeP99MS=percentile(encode, .99),
                decodeP99MS=percentile(decode, .99), roundTripP99MS=percentile(total, .99),
                below20MS=percentile(total, .99) < 20,
                dtxFrames=sum(p['dtx'] for p in packets), suppressedFrames=sum(not p['transmit'] for p in packets),
                transmittedBytes=sum(len(p['bytes']) for p in packets if p['transmit'])))
        paths = sorted((snapshot / 'Sources').rglob('*.swift'))
        hardware = subprocess.run(['sysctl', '-n', 'machdep.cpu.brand_string'], capture_output=True, check=False) if platform.system() == 'Darwin' else None
        hardware_name = hardware.stdout.decode().strip() if hardware and hardware.returncode == 0 else platform.machine() + ' (model query unavailable)'
        report = dict(verifiedAt=datetime.now(timezone.utc).isoformat(), scope='signal quality diagnostics, independent decoding and local optimized frame benchmarks',
            archiveSHA256=ARCHIVE_SHA256, maximumIndependentPCMError=maximum, results=records,
            fecDTXRecovery=dict(scope='Selected WB SILK/FB hybrid 20ms mono/stereo LBRR before and after suppression, independently confirmed by opus_packet_has_lbrr; suppressed empty payload uses PLC; following packet decoded normally',
                                streams=recovery_records, maximumIndependentPCMError=recovery_maximum,
                                selectedLBRRRecoveries=sum(record['selectedLBRRRecoveries'] for record in recovery_records),
                                suppressedPLCRecoveries=sum(record['suppressedPLCRecoveries'] for record in recovery_records)),
            result='failed' if failures else 'passed', failedCases=failures,
            hardware=hardware_name, externalInputs=external,
            os=platform.platform(), swiftVersion=run(['swiftc', '--version']).decode().splitlines()[0],
            timing='Swift -O, sequential encode/decode, ten warmup frames then reset; nearest-rank sample p99, no deadline or hardware scheduling guarantee',
            quality='Unscaled waveform SNR after bounded delay alignment; generated signals and optional separately supplied WAV excerpts; no perceptual pass threshold or listening claim',
            excluded=['broad natural speech/music corpus qualification', 'perceptual MOS/listening qualification', 'device duplex', 'permission/route/interruption/unplug', 'live Discord'],
            ownedSources={str(path.relative_to(snapshot)): digest(path) for path in paths}, verifierSHA256=digest(Path(__file__)))
        args.report.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({k:v for k,v in report.items() if k != 'ownedSources'}, indent=2))
        if failures:
            raise SystemExit(1)


if __name__ == '__main__':
    main()

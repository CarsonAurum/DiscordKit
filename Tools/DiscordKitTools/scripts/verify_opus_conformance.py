#!/usr/bin/env python3
"""Opt-in RFC8251 full-vector decoded-PCM/range verification; never part of consumer builds."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import struct
import subprocess
import tarfile
import tempfile
from verify_opus_range_oracle import digest, extract_verified_archive, run, VERSION

VECTOR_URL = 'https://www.opus-codec.org/docs/opus_testvectors-rfc8251.tar.gz'
VECTOR_SHA256 = '6b26a22f9ba87b2b836906a9bb7afec5f8e54d49553b1200382520ee6fedfa55'
VECTOR_BYTES = 74624664
SWIFT_DRIVER = r'''
import Foundation
struct Result: Encodable {
 let packets:Int;let samples:Int;let rangeMismatches:Int;let firstRangeMismatch:Int?;let error:String?
}
@main struct Driver {
 /// Reads one local bounded conformance bitstream and emits complete PCM16 plus exact-range evidence.
 /// Arguments are the admitted bitstream path, one/two output channels and PCM destination.
 /// Calls are synchronous; no device, task, network or native decoder is selected.
 /// - Throws: Local file/JSON errors. Codec failures are retained in the JSON result
 ///   with the successfully consumed prefix, preventing a partial stream from passing.
 static func main() throws {
  let args=CommandLine.arguments;let bytes=Array(try Data(contentsOf:URL(fileURLWithPath:args[1])))
  let channels=Int(args[2])!;var decoder=try OpusAudioDecoder(channelCount:channels)
  var position=0;var packets=0;var samples=0;var mismatches=0;var first:Int?;var failure:String?
  var pcm=Data()
  do {
   while position<bytes.count {
    guard position+8<=bytes.count else {throw NSError(domain:"vectorHeader",code:1)}
    var length=0;var expected:UInt32=0
    for i in 0..<4 {length=(length<<8)|Int(bytes[position+i]);expected=(expected<<8)|UInt32(bytes[position+4+i])}
    position+=8
    guard length>0 && length<=65536 && length<=bytes.count-position else {throw NSError(domain:"vectorLength",code:1)}
    let frames=try decoder.decode(Data(bytes[position..<(position+length)]));position+=length
    if expected != 0 && decoder.finalRange != expected {mismatches+=1;if first == nil {first=packets}}
    for value in frames.flatMap(\.samples) {
     guard value.isFinite else {throw NSError(domain:"nonfinitePCM",code:1)}
     let clipped=max(-32768.0,min(32767.0,Double(value)*32768))
     let bits=UInt16(bitPattern:Int16(clipped.rounded(.toNearestOrEven)))
     pcm.append(UInt8(truncatingIfNeeded:bits));pcm.append(UInt8(truncatingIfNeeded:bits>>8));samples+=1
    }
    packets+=1
   }
  } catch {failure=String(describing:error)}
  try pcm.write(to:URL(fileURLWithPath:args[3]))
  let result=Result(packets:packets,samples:samples,rangeMismatches:mismatches,firstRangeMismatch:first,error:failure)
  print(String(decoding:try JSONEncoder().encode(result),as:UTF8.self))
 }
}
'''


def parse_bitstream(data):
    """Validate each bounded big-endian length/range header and reject truncated/empty packets."""
    if len(data) > 32 * 1024 * 1024:
        raise ValueError('vector exceeds bounded file size')
    packets = []
    position = 0
    while position < len(data):
        if position + 8 > len(data):
            raise ValueError('truncated vector header')
        length, final_range = struct.unpack_from('>II', data, position)
        position += 8
        if not 1 <= length <= 65536 or length > len(data) - position:
            raise ValueError('invalid vector packet size')
        packets.append((data[position:position + length], final_range))
        position += length
    if not packets:
        raise ValueError('empty vector')
    return packets


def extract_vectors(archive_path, destination):
    """Admit only the exact official archive and regular bounded relative entries."""
    if archive_path.stat().st_size != VECTOR_BYTES or digest(archive_path) != VECTOR_SHA256:
        raise ValueError('official conformance archive fingerprint mismatch')
    with tarfile.open(archive_path, 'r:gz') as archive:
        members = archive.getmembers()
        if len(members) > 64 or sum(member.size for member in members) > 256 * 1024 * 1024:
            raise ValueError('vector archive exceeds storage limits')
        for member in members:
            path = Path(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isdir() or member.isfile()):
                raise ValueError('unsafe vector archive member')
            target = destination / path
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source:
                    target.write_bytes(source.read())
    return destination / 'opus_newvectors'


def compare_references(comparator, references, output, channels):
    """Use upstream run_vectors.sh's either-reference acceptance for both layouts.

    The corpus contains two stereo reference variants, not one mono file and one
    stereo file. opus_compare performs its own stereo-to-mono reference conversion.
    Both official comparisons remain in the report, including rejected variants.
    """
    results = []
    for reference in references:
        compared = subprocess.run([str(comparator)] + (['-s'] if channels == 2 else [])
            + [str(reference), str(output)], capture_output=True)
        results.append(dict(reference=reference.name, referencePCMBytes=reference.stat().st_size,
            exitCode=compared.returncode, comparison=compared.stderr.decode(errors='replace').strip()))
    return results, any(item['exitCode'] == 0 for item in results)


def main():
    """Run all selected official streams, retain failures and report full-corpus status honestly."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vector-archive', type=Path, required=True)
    parser.add_argument('--source-archive', type=Path, required=True)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--vectors', type=int, nargs='+', default=list(range(1, 13)))
    parser.add_argument('--channels', type=int, nargs='+', default=[1, 2])
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if not args.vectors or any(index not in range(1, 13) for index in args.vectors) or any(count not in (1, 2) for count in args.channels):
        parser.error('vectors must be 1...12 and channels one or two')
    repository = args.repository.resolve()
    verifier_hash = digest(Path(__file__))
    with tempfile.TemporaryDirectory(prefix='discordkit-opus-conformance-') as temporary:
        directory = Path(temporary).resolve()
        vectors = extract_vectors(args.vector_archive.resolve(), directory)
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        comparator = directory / 'opus_compare'
        run(['cc', '-std=c99', '-O2', str(upstream / 'src/opus_compare.c'), '-lm', '-o', str(comparator)])
        snapshot = directory / 'snapshot'
        snapshot.mkdir()
        paths = sorted((repository/'Sources/DiscordMedia').glob('*.swift')) + sorted((repository/'Sources/DiscordVoiceCodecs').glob('*.swift'))
        hashes = {}
        for path in paths:
            data = path.read_bytes()
            (snapshot / path.name).write_bytes(data)
            hashes[str(path.relative_to(repository))] = hashlib.sha256(data).hexdigest()
        media_paths = [snapshot/path.name for path in paths if path.parent.name == 'DiscordMedia']
        codec_paths = [snapshot/path.name for path in paths if path.parent.name == 'DiscordVoiceCodecs']
        cache = str(directory/'module-cache')
        run(['swiftc','-O','-emit-module','-emit-library','-module-name','DiscordMedia','-module-cache-path',cache]
            + [str(path) for path in media_paths]
            + ['-emit-module-path',str(directory/'DiscordMedia.swiftmodule'),'-o',str(directory/'libDiscordMedia.dylib')])
        source = directory/'driver.swift'
        source.write_text(SWIFT_DRIVER)
        binary = directory/'owned'
        run(['swiftc','-O','-module-cache-path',cache,'-enable-upcoming-feature','ApproachableConcurrency',
             '-default-isolation','nonisolated','-I',str(directory),'-L',str(directory),'-lDiscordMedia',
             '-Xlinker','-rpath','-Xlinker',str(directory)] + [str(path) for path in codec_paths] + [str(source),'-o',str(binary)])
        results = []
        for index in args.vectors:
            bitstream = vectors/f'testvector{index:02d}.bit'
            expected_packets = len(parse_bitstream(bitstream.read_bytes()))
            for channels in args.channels:
                output = directory/f'output-{index}-{channels}.pcm'
                actual = json.loads(run([str(binary),str(bitstream),str(channels),str(output)]))
                references = [vectors/f'testvector{index:02d}{suffix}.dec' for suffix in ('', 'm')]
                comparisons, matched = compare_references(comparator, references, output, channels)
                passed = actual.get('error') is None and actual['packets'] == expected_packets and actual['rangeMismatches'] == 0 and matched
                item = dict(vector=index,channels=channels,expectedPackets=expected_packets,**actual,
                    actualPCMBytes=output.stat().st_size, comparisons=comparisons,
                    result='passed' if passed else 'failed')
                results.append(item)
                print(json.dumps(item),flush=True)
        report = dict(verifiedOn=datetime.now(timezone.utc).date().isoformat(),
            scope='Official RFC8251 full decoded-PCM vectors at 48kHz with exact nonzero final ranges and official opus_compare; no device/network/perceptual/realtime qualification',
            vectorURL=VECTOR_URL,vectorSHA256=VECTOR_SHA256,vectorArchiveByteCount=VECTOR_BYTES,
            officialVersion=VERSION,sourceArchiveSHA256=digest(args.source_archive.resolve()),
            sourceArchiveByteCount=args.source_archive.stat().st_size,
            comparatorSHA256=digest(upstream/'src/opus_compare.c'),
            ownedSwiftSHA256=hashes,sourceDrift=[path for path,value in hashes.items() if digest(repository/path) != value],
            verifierSHA256=verifier_hash,verifierDrift=digest(Path(__file__)) != verifier_hash,host=platform.platform(),
            swiftCompiler=run(['swiftc','--version']).decode().splitlines()[0],
            fullCorpus=set(args.vectors)==set(range(1,13)) and set(args.channels)=={1,2},
            results=results,result='passed' if all(item['result']=='passed' for item in results) else 'failed')
        args.report.write_text(json.dumps(report,indent=2)+'\n')
        if report['result'] != 'passed':
            raise SystemExit(1)


if __name__ == '__main__':
    main()

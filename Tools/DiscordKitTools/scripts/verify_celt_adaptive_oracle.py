#!/usr/bin/env python3
"""Opt-in adaptive CELT interoperability and independently decoded fixture regeneration.

Builds a separately supplied, SHA256-verified official libopus archive in temporary
storage. No download, native product dependency or normal-test compilation occurs.
Checks exact ranges and tolerance-qualified PCM in both directions, including owned
short-block packets. These checks do not establish perceptual or device quality.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import tempfile

import verify_celt_frame_oracle as frame
from verify_opus_range_oracle import ARCHIVE_SHA256, RELEASE_URL, SOURCE_URL, VERSION, digest, extract_verified_archive, run

FIXTURE_PATH = 'Tests/DiscordVoiceCodecsTests/CELTAdaptiveOracleFixtures.swift'
CONFIGURE_ARGUMENTS = (
    '--disable-shared', '--disable-extra-programs', '--disable-doc',
    '--disable-intrinsics', '--disable-rtcd',
)
HELPER_NAMES = (
    'verify_celt_frame_oracle.py', 'verify_celt_shape_oracle.py',
    'verify_celt_synthesis_oracle.py', 'verify_celt_header_oracle.py',
    'verify_celt_pulse_oracle.py', 'verify_opus_range_oracle.py',
)


def adaptive_driver():
    """Adapt the shared complete-frame driver, rejecting missing or ambiguous anchors.

    Fixed frame evidence keeps its original policy. This opt-in driver selects
    adaptive analysis explicitly and counts the actually decoded owned transients.
    Every replacement requires exactly one original occurrence so upstream helper
    drift cannot silently leave some or all frames on the fixed policy.
    """
    result = frame.SWIFT_DRIVER
    replacements = (
        ('endBand:f.end);ownDecoder=', 'endBand:f.end,analysisPolicy:.adaptive);ownDecoder='),
        ('struct Output:Encodable{let decoded:[Decoded];let encoded:[Encoded]}',
         'struct Output:Encodable{let decoded:[Decoded];let encoded:[Encoded];let ownTransientFrames:Int}'),
        ('var decoded:[Decoded]=[],encoded:[Encoded]=[]',
         'var decoded:[Decoded]=[],encoded:[Encoded]=[];var ownTransientFrames=0'),
        ('let r=try ownDecoder.decode(e.bytes,frameSampleCount:f.n,endBand:f.end)',
         'let r=try ownDecoder.decode(e.bytes,frameSampleCount:f.n,endBand:f.end);if r.isTransient{ownTransientFrames += 1}'),
        ('Output(decoded:decoded,encoded:encoded)',
         'Output(decoded:decoded,encoded:encoded,ownTransientFrames:ownTransientFrames)'),
    )
    for original, replacement in replacements:
        if result.count(original) != 1:
            raise ValueError('complete-frame driver changed; review adaptive driver anchors')
        result = result.replace(original, replacement, 1)
    return result


def fixture_inputs():
    """Generate six bounded long/short-transition sequences at every transient duration/layout."""
    return [frame.sequence(size, channels, 21,
                           kinds=('silence', 'impulse', 'tone', 'tone', 'transient'), byte_count=160)
            for size in (240, 480, 960) for channels in (1, 2)]


def snapshot_owned(repository, directory):
    """Copy exact compiled source files and reject changes during the snapshot.

    Returns an isolated source root and original file fingerprints. The compiler
    reads only that root, so a concurrent workspace edit cannot mix Swift files
    from different revisions. `require_unchanged_sources` runs again before any
    fixture/report is written, refusing evidence for a newer uncompiled tree.
    """
    fingerprints = {name: digest(repository / name) for name in frame.OWNED_PATHS}
    snapshot = directory / 'owned-snapshot'
    for name, fingerprint in fingerprints.items():
        target = snapshot / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(repository / name, target)
        if digest(target) != fingerprint:
            raise ValueError('owned source changed while creating snapshot: ' + name)
    require_unchanged_sources(repository, fingerprints)
    return snapshot, fingerprints


def require_unchanged_sources(repository, fingerprints):
    """Fail closed when any fingerprinted source disappeared or changed since compilation."""
    for name, fingerprint in fingerprints.items():
        path = repository / name
        if not path.is_file() or digest(path) != fingerprint:
            raise ValueError('owned source changed after snapshot: ' + name)


def owned_transient_count(inputs, outputs):
    """Validate bounded per-sequence transient telemetry before including it in evidence."""
    if len(inputs) != len(outputs):
        raise ValueError('missing owned transient sequences')
    total = 0
    for source, output in zip(inputs, outputs):
        count = output.get('ownTransientFrames')
        if type(count) is not int or not 0 <= count <= len(source['frames']):
            raise ValueError('invalid owned transient count')
        total += count
    return total


def fixture_text(records):
    """Render compact independent PCM fixtures deterministically, without a codec runtime."""
    return ('/// Official libopus 1.6.1 scalar decoded PCM for owned adaptive packets; little-endian float32 base64.\n'
            'enum CELTAdaptiveOracleFixtures {\n    static let json = #"""\n'
            + json.dumps(records, separators=(',', ':')) + '\n"""#\n}\n')


def check_fixture(path, records, write=False):
    """Require byte-identical fixture generation; mutate only with explicit `write=True`."""
    expected = fixture_text(records)
    if write:
        path.write_text(expected)
    if not path.is_file() or path.read_text() != expected:
        raise ValueError('adaptive fixture differs; review and explicitly --write-fixtures')


def compare_sequences(inputs, reference, owned):
    """Run both complete official entry-point directions and require full range/PCM agreement."""
    native = frame.parse_outputs(run([str(reference)], frame.commands(inputs)), len(inputs), 'Official CELT codec')
    prepared = [dict(c=source['c'], frames=[{**value, 'raw': expected['raw']}
                    for value, expected in zip(source['frames'], decoded['frames'])])
                for source, decoded in zip(inputs, native)]
    actual = frame.parse_outputs(run([str(owned)], '\n'.join(map(json.dumps, prepared)).encode()),
                                 len(inputs), 'Owned adaptive CELT codec')
    reverse = frame.parse_outputs(run([str(reference)], frame.commands(inputs, actual)),
                                  len(inputs), 'Official decoder on owned adaptive CELT')
    statistics = frame.compare_results(inputs, native, actual, reverse)
    statistics['nativeTransientFrames'] = statistics.pop('transientFrames')
    statistics['ownedTransientFrames'] = owned_transient_count(inputs, actual)
    return native, actual, reverse, statistics


def main():
    """Build verified scalar code only on explicit invocation and record reproducible local evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-archive', type=Path, required=True)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--cases', type=int, default=256)
    parser.add_argument('--seed', type=int, default=67161219)
    parser.add_argument('--write-fixtures', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if not 1 <= args.cases <= 1000 or args.seed < 0:
        parser.error('cases must be 1...1000 and seed must be nonnegative')
    repository = args.repository.resolve()
    fixed = frame.fixed_cases()
    inputs = fixed + frame.random_cases(args.cases, args.seed)
    with tempfile.TemporaryDirectory(prefix='discordkit-celt-adaptive-') as temporary:
        directory = Path(temporary).resolve()
        snapshot, source_fingerprints = snapshot_owned(repository, directory)
        helper_fingerprints = {'Tools/DiscordKitTools/scripts/' + name:
                               digest(Path(__file__).resolve().parent / name) for name in HELPER_NAMES}
        upstream = extract_verified_archive(args.source_archive.resolve(), directory)
        for name in ('compile', 'config.guess', 'config.sub', 'depcomp', 'install-sh', 'missing', 'test-driver'):
            (upstream / name).chmod(0o755)
        frame.build(['sh', str(upstream / 'configure'), *CONFIGURE_ARGUMENTS], upstream)
        frame.build(['make', '-j2'], upstream)
        c_source = directory / 'reference.c'
        swift_source = directory / 'owned.swift'
        c_source.write_text(frame.C_DRIVER)
        swift_source.write_text(adaptive_driver())
        reference, owned = directory / 'reference', directory / 'owned'
        run(['cc', '-O2', '-I' + str(upstream / 'include'), str(c_source),
             str(upstream / '.libs/libopus.a'), '-lm', '-o', str(reference)])
        run(['swiftc', '-O', '-module-cache-path', str(directory / 'module-cache'),
             '-enable-upcoming-feature', 'ApproachableConcurrency', '-default-isolation', 'nonisolated',
             *[str(snapshot / name) for name in frame.OWNED_PATHS], str(swift_source), '-o', str(owned)])
        _, _, _, statistics = compare_sequences(inputs, reference, owned)
        fixture_cases = fixture_inputs()
        native, _, reverse, fixture_statistics = compare_sequences(fixture_cases, reference, owned)
        records = frame.fixture_records(fixture_cases, native, reverse)
        for record in records:
            record.pop('output')
        require_unchanged_sources(repository, {**source_fingerprints, **helper_fingerprints})
        fixture = repository / FIXTURE_PATH
        check_fixture(fixture, records, args.write_fixtures)
        report = dict(verifiedAt=datetime.now(timezone.utc).isoformat(),
            scope='adaptive CELT masked onset short-block and spectral/rate trim interoperability',
            version=VERSION, releaseURL=RELEASE_URL, sourceURL=SOURCE_URL, archiveSHA256=ARCHIVE_SHA256,
            seed=args.seed, randomSequences=args.cases, fixedSequences=len(fixed), sequences=len(inputs),
            frames=sum(len(source['frames']) for source in inputs), **statistics,
            exact=['full-decoder final ranges both directions', 'physical byte counts', 'fixture byte identity'],
            tolerance=dict(absoluteTimesStreamMaximum=frame.ABSOLUTE_TOLERANCE, relative=frame.RELATIVE_TOLERANCE),
            excluded=['reference encoder byte identity', 'perceptual listening qualification', 'devices', 'real time'],
            ownedSources=source_fingerprints, helperSources=helper_fingerprints,
            upstreamSources={name: digest(upstream / name) for name in frame.UPSTREAM_PATHS},
            fixture=dict(path=FIXTURE_PATH, sha256=digest(fixture), streams=len(records),
                         frames=sum(len(record['input']['frames']) for record in records),
                         **fixture_statistics),
            referenceBuild=dict(configureArguments=list(CONFIGURE_ARGUMENTS), scalar=True,
                                librarySHA256=digest(upstream / '.libs/libopus.a'),
                                configurationSHA256=digest(upstream / 'config.h')),
            driverSHA256=digest(swift_source), referenceDriverSHA256=digest(c_source),
            verifierSHA256=digest(Path(__file__)),
            swiftVersion=run(['swiftc', '--version']).decode().splitlines()[0],
            ccVersion=run(['cc', '--version']).decode().splitlines()[0])
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

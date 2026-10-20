#!/usr/bin/env python3
"""Inspect IPA metadata and all Mach-O images without extracting or executing code."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import zipfile

MACH_MAGICS = {bytes.fromhex(h) for h in ('cefaedfe', 'cffaedfe', 'feedface', 'feedfacf')}
FAT_MAGICS = {bytes.fromhex(h) for h in ('cafebabe', 'cafebabf', 'bebafeca', 'bfbafeca')}


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def version(value):
    return '.'.join(map(str, (value >> 16, value >> 8 & 255, value & 255)))


def parse_macho(data):
    """Decode thin/fat headers and bounded load commands; never interpret instructions."""
    if len(data) < 4:
        raise ValueError('Truncated Mach-O magic')
    magic = bytes(data[:4])
    if magic in FAT_MAGICS:
        endian = '>' if magic in {bytes.fromhex('cafebabe'), bytes.fromhex('cafebabf')} else '<'
        wide = magic in {bytes.fromhex('cafebabf'), bytes.fromhex('bfbafeca')}
        count, = struct.unpack_from(endian + 'I', data, 4)
        if not 0 < count <= 64:
            raise ValueError('Invalid fat slice count')
        spans = []
        for index in range(count):
            values = struct.unpack_from(endian + ('IIQQII' if wide else 'IIIII'), data, 8 + index * (32 if wide else 20))
            spans.append((values[2], values[3], values[0]))
    else:
        spans = [(0, len(data), None)]
    result = []
    for offset, size, fat_cpu in spans:
        if size < 28 or offset + size > len(data):
            raise ValueError('Mach-O slice outside executable')
        magic = bytes(data[offset:offset + 4])
        if magic not in MACH_MAGICS:
            raise ValueError('Unrecognized Mach-O header')
        endian = '<' if magic in {bytes.fromhex('cefaedfe'), bytes.fromhex('cffaedfe')} else '>'
        wide = magic in {bytes.fromhex('cffaedfe'), bytes.fromhex('feedfacf')}
        _, cpu, subtype, filetype, count, command_size, flags = struct.unpack_from(endian + '7I', data, offset)
        if fat_cpu is not None and fat_cpu != cpu:
            raise ValueError('Fat and slice CPU types disagree')
        position = offset + (32 if wide else 28)
        end = position + command_size
        if end > offset + size or count > command_size // 8:
            raise ValueError('Load commands outside slice')
        architecture = {12: {6: 'armv6', 9: 'armv7', 11: 'armv7s'}.get(subtype & 0xffffff, 'arm32'),
                        0x100000c: 'arm64e' if subtype & 0xffffff == 2 else 'arm64',
                        0x200000c: 'arm64_32', 7: 'i386', 0x1000007: 'x86_64'}.get(cpu, hex(cpu))
        item = dict(architecture=architecture, cpu_type=cpu, cpu_subtype=subtype,
                    bits=64 if wide else 32, filetype=filetype, flags=flags,
                    offset=offset, size=size, encryption_commands=[], libraries=[])
        for _ in range(count):
            command, length = struct.unpack_from(endian + 'II', data, position)
            if length < 8 or position + length > end:
                raise ValueError('Invalid load command length')
            if command in (0x21, 0x2c):
                if length < (24 if command == 0x2c else 20):
                    raise ValueError('Truncated encryption command')
                crypt_offset, crypt_size, crypt_id = struct.unpack_from(endian + 'III', data, position + 8)
                if crypt_id and crypt_offset + crypt_size > size:
                    raise ValueError('Encrypted range outside slice')
                item['encryption_commands'].append(dict(offset=crypt_offset, size=crypt_size, cryptid=crypt_id))
            if command in (0xc, 0x80000018, 0x8000001f, 0x20):
                if length < 24:
                    raise ValueError('Truncated library command')
                string_offset, = struct.unpack_from(endian + 'I', data, position + 8)
                if not 0 <= string_offset < length:
                    raise ValueError('Invalid library name offset')
                raw = data[position + string_offset:position + length]
                item['libraries'].append(dict(path=raw.split(b'\0', 1)[0].decode('utf-8', 'replace'), weak=command == 0x80000018))
            if command in (0x24, 0x25, 0x2f, 0x30):
                if length < 16:
                    raise ValueError('Truncated version command')
                minimum, sdk = struct.unpack_from(endian + 'II', data, position + 8)
                item.update(minimum_os=version(minimum), sdk=version(sdk), platform={0x24: 1, 0x25: 2, 0x2f: 3, 0x30: 4}[command])
            if command == 0x32:
                if length < 24:
                    raise ValueError('Truncated build-version command')
                platform, minimum, sdk = struct.unpack_from(endian + 'III', data, position + 8)
                item.update(platform=platform, minimum_os=version(minimum), sdk=version(sdk))
            position += length
        if position != end:
            raise ValueError('Load command size mismatch')
        item['encryption_status'] = ('encrypted' if any(c['cryptid'] for c in item['encryption_commands'])
                                     else 'reports_unencrypted' if item['encryption_commands'] else 'no_encryption_command')
        result.append(item)
    return result


def inspect(path):
    path = Path(path).resolve()
    report = dict(path=str(path), sha256=sha256_file(path), size=path.stat().st_size,
                  file_present=True, successfully_downloaded=None, acquisition='local_file; download origin not established by inspector',
                  runtime_tested=False, installs_and_runs='unverified', ui_match='unverified',
                  target={'device': 'iPhone 16', 'ios': '27.0.1'}, components=[], binaries=[], resource_inventory=[])
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP member names')
        for name in names:
            parts = PurePosixPath(name)
            if parts.is_absolute() or '..' in parts.parts:
                raise ValueError('Unsafe ZIP member name')
        roots = [n for n in names if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        if len(roots) != 1:
            raise ValueError('Expected one top-level iOS application')
        main_plist = roots[0]
        for name in names:
            if not name.startswith('Payload/') or not name.endswith('/Info.plist'):
                continue
            parent = name.rsplit('/', 1)[0]
            if not parent.endswith(('.app', '.appex', '.framework', '.bundle')):
                continue
            data = plistlib.loads(archive.read(name))
            executable = data.get('CFBundleExecutable')
            component = dict(path=parent, bundle_identifier=data.get('CFBundleIdentifier'),
                             version=data.get('CFBundleShortVersionString'), build=data.get('CFBundleVersion'),
                             minimum_ios=data.get('MinimumOSVersion'), sdk=data.get('DTSDKName'),
                             executable=parent + '/' + executable if executable else None,
                             kind='main_app' if name == main_plist else parent.rsplit('.', 1)[-1])
            report['components'].append(component)
            if name == main_plist:
                report.update({k: component[k] for k in ('bundle_identifier', 'version', 'build', 'minimum_ios', 'sdk')})
                main_executable = component['executable']
        if not main_executable or main_executable not in names:
            raise ValueError('Main executable missing')
        for info in archive.infolist():
            if info.is_dir() or not info.filename.startswith('Payload/'):
                continue
            if info.filename.lower().endswith(('.png', '.jpg', '.jpeg', '.nib', '.storyboardc', '.car')):
                report['resource_inventory'].append(info.filename)
            with archive.open(info) as stream:
                head = stream.read(4)
            if head not in MACH_MAGICS | FAT_MAGICS:
                continue
            if info.file_size > 512 * 1024 * 1024:
                raise ValueError('Mach-O member exceeds inspection memory limit')
            payload = archive.read(info)
            slices = parse_macho(payload)
            report['binaries'].append(dict(path=info.filename, sha256=hashlib.sha256(payload).hexdigest(),
                size=len(payload), slices=slices, contains_arm64=any(s['architecture'] in ('arm64', 'arm64e') for s in slices)))
        if archive.testzip() is not None:
            raise ValueError('ZIP CRC validation failed')
        report['zip_integrity'] = True
        report['drm_resource_count'] = sum('/SC_Info/' in name for name in names)
    main = next(b for b in report['binaries'] if b['path'] == main_executable)
    report['contains_arm64'] = main['contains_arm64']
    report['main_architectures'] = [s['architecture'] for s in main['slices']]
    report['main_encryption_status'] = {s['architecture']: s['encryption_status'] for s in main['slices']}
    report['components_requiring_architecture_review'] = [b['path'] for b in report['binaries'] if not b['contains_arm64'] and b['path'] != main_executable]
    report['static_architecture_result'] = 'arm64_present; runtime_unverified' if report['contains_arm64'] else 'blocked_on_iOS_11_and_later'
    report['patchability'] = ('Encrypted executable: resources/metadata inspection only; signing does not decrypt code.'
        if any(s['encryption_status'] == 'encrypted' for s in main['slices']) else
        'Executable reports no encryption. Binary modification still requires architecture/API work and testing; source code is not included.')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', nargs='+', type=Path)
    parser.add_argument('--output-dir', type=Path, default=Path(__file__).resolve().parents[1] / '.ios-work/inspection')
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    for path in args.ipa:
        result = inspect(path)
        output = args.output_dir / (result['sha256'][:16] + '.json')
        output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({k: result[k] for k in ('path', 'version', 'build', 'bundle_identifier', 'main_architectures', 'main_encryption_status', 'contains_arm64')}))
        print('Inspection:', output)


if __name__ == '__main__':
    main()

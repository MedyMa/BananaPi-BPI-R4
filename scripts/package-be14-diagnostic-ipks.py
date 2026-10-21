#!/usr/bin/env python3
"""Preserve BE14 diagnostic IPKs before the firmware artifact cleanup."""
import gzip
import hashlib
import io
import json
import lzma
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

NAMES = {
    'be14-whnat-diag', 'kmod-mediatek_hnat', 'kmod-mt_wifi7',
    'kmod-mt_hwifi', 'kmod-mtk_pci', 'kmod-mt_wifi_cmn',
    'kmod-mtk_wed', 'kmod-connac_if', 'kmod-mt7990', 'kmod-mt7991', 'kmod-warp',
}
REQUIRED = {'be14-whnat-diag', 'kmod-mediatek_hnat', 'kmod-mt_wifi7',
            'kmod-mt_hwifi', 'kmod-mtk_pci', 'kmod-mt_wifi_cmn'}
MARKERS = {
    'kmod-mediatek_hnat': ('mtkhnat.ko', (b'hnat_diag_enable', b'hnat_account_lock_diag_enable')),
    'kmod-mt_wifi7': ('mt_wifi.ko', (b'whnat_force_rx_diag_enable',)),
    'kmod-mtk_pci': ('mtk_pci.ko', (b'whnat_rx_diag_enable',)),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def ipk_members(path):
    data = path.read_bytes()
    if data.startswith(b'!<arch>\n'):
        offset = 8
        result = {}
        while offset + 60 <= len(data):
            header = data[offset:offset + 60]
            if header[58:60] != b'`\n':
                raise ValueError('Invalid IPK ar header: ' + path.name)
            name = header[:16].decode('ascii').strip().rstrip('/')
            size = int(header[48:58])
            offset += 60
            result[name] = data[offset:offset + size]
            offset += size + size % 2
        return result
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as archive:
        return {Path(m.name).name: archive.extractfile(m).read()
                for m in archive.getmembers() if m.isfile()}


def nested(members, prefix):
    matches = [value for name, value in members.items() if name.startswith(prefix)]
    if len(matches) != 1:
        raise ValueError('Missing or ambiguous IPK member: ' + prefix)
    return tarfile.open(fileobj=io.BytesIO(matches[0]), mode='r:*')


def metadata(members):
    with nested(members, 'control.tar') as archive:
        controls = [m for m in archive.getmembers() if Path(m.name).name == 'control']
        if len(controls) != 1:
            raise ValueError('Missing or ambiguous package control')
        text = archive.extractfile(controls[0]).read().decode('utf-8')
    return dict(line.split(': ', 1) for line in text.splitlines() if ': ' in line and not line.startswith(' '))


def verify_markers(package, members):
    if package not in MARKERS:
        return
    module, markers = MARKERS[package]
    with nested(members, 'data.tar') as archive:
        matches = [m for m in archive.getmembers()
                   if m.isfile() and Path(m.name).name in (module, module + '.gz', module + '.xz')]
        if len(matches) != 1:
            raise ValueError('Expected diagnostic module missing: ' + module)
        entry = matches[0]
        data = archive.extractfile(entry).read()
        if entry.name.endswith('.gz'):
            data = gzip.decompress(data)
        elif entry.name.endswith('.xz'):
            data = lzma.decompress(data)
        if any(marker not in data for marker in markers):
            raise ValueError('Diagnostic parameters missing from ' + module)


def main():
    root = Path(sys.argv[1]).resolve()
    output = root / 'bin/targets/mediatek/filogic_a73'
    output.mkdir(parents=True, exist_ok=True)
    records = {}
    files = {}
    for path in sorted((root / 'bin').rglob('*.ipk')):
        if not any(path.name.startswith(name + '_') for name in NAMES):
            continue
        members = ipk_members(path)
        control = metadata(members)
        package = control.get('Package')
        if package not in NAMES:
            continue
        data = path.read_bytes()
        if package in records:
            if records[package]['sha256'] != sha(data):
                raise ValueError('Conflicting package artifacts: ' + package)
            continue
        verify_markers(package, members)
        records[package] = {'file': path.name, 'sha256': sha(data), 'bytes': len(data),
                            'version': control.get('Version'), 'architecture': control.get('Architecture'),
                            'depends': control.get('Depends')}
        files[path.name] = data
    missing = REQUIRED - records.keys()
    if missing:
        raise ValueError('Diagnostic IPKs missing: ' + ', '.join(sorted(missing)))
    source_sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    manifest = {'source_commit': source_sha, 'config_sha256': sha((root / '.config').read_bytes()),
                'coverage': ['hnat', 'pci_rx', 'wifi_swpath', 'accounting'],
                'omitted': ['ethernet_builtin_diagnostics', 'dtb'],
                'device_abi_confirmed': False, 'packages': records}
    destination = output / 'be14-diagnostic-ipks.tar.gz'
    with tempfile.TemporaryDirectory(prefix='.be14-ipks-', dir=output) as tmp:
        staging = Path(tmp) / 'be14-diagnostic-ipks'
        staging.mkdir()
        for name, data in files.items():
            (staging / name).write_bytes(data)
        (staging / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        (staging / 'README.txt').write_text(
            'Diagnostic candidate IPKs. Verify exact kernel ABI against opkg status kernel before installation.\n'
            'Do not force dependencies or unload Wi-Fi modules over a Wi-Fi connection.\n'
            'Installation does not start diagnostics. Use collect-be14-whnat-window explicitly after matching modules are active.\n'
            'Ethernet built-in diagnostics and DTB changes are not included in this IPK suite.\n', encoding='utf-8')
        hashes = ''.join(sha(p.read_bytes()) + '  ' + p.name + '\n'
                         for p in sorted(staging.iterdir()) if p.is_file())
        (staging / 'SHA256SUMS').write_text(hashes, encoding='ascii')
        with tarfile.open(destination, 'w:gz') as archive:
            archive.add(staging, arcname=staging.name)
    digest = sha(destination.read_bytes())
    destination.with_name(destination.name + '.sha256').write_text(digest + '  ' + destination.name + '\n', encoding='ascii')
    print(json.dumps({'archive': str(destination), 'sha256': digest, 'packages': sorted(records)}, indent=2))


if __name__ == '__main__':
    main()

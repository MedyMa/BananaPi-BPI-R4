#!/usr/bin/env python3
"""Replay HNAT kernel patches, then compile real driver fragments on the host.

Usage: python3 scripts/test-hnat-secondary-wan.py OPENWRT_ROOT [--cc gcc]
       [--with-patch patches/filogic/25.12/1013-mtk-hnat-secondary-wan.patch]
Requires GNU patch and a C99 compiler. No kernel or router state is modified.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

DRIVER = Path('drivers/net/ethernet/mediatek/mtk_hnat')


def prepare(source, dest, extra_patch=None):
    target = source / 'target/linux/mediatek'
    shutil.copytree(target / 'files-6.12' / DRIVER, dest / DRIVER)
    applied = []
    for patch in sorted((target / 'patches-6.12').glob('*.patch')):
        text = patch.read_text(encoding='utf-8')
        blocks = re.split(r'(?=^--- (?:a/|/dev/null))', text, flags=re.M)
        selected = []
        for block in blocks:
            match = re.search(r'^\+\+\+ b/(\S+)', block, re.M)
            if match and match[1].startswith(DRIVER.as_posix() + '/'):
                # Strip mail footer / following git header, retain unified hunks.
                block = re.split(r'^diff --git |^-- $', block, flags=re.M)[0]
                selected.append(block)
        if selected:
            result = subprocess.run(
                ['patch', '-f', '-p1'], cwd=dest,
                input=''.join(selected).encode('utf-8'), capture_output=True)
            if result.returncode:
                raise RuntimeError(f'{patch.name}:\n' +
                                   (result.stdout + result.stderr).decode('utf-8', 'replace'))
            applied.append(patch.name)
    print(f'Replayed {len(applied)} HNAT patches', flush=True)
    if extra_patch:
        result = subprocess.run(['patch', '-f', '-p1', '--fuzz=0'], cwd=dest,
                                input=extra_patch.read_bytes(), capture_output=True)
        if result.returncode:
            raise RuntimeError('Secondary WAN patch failed:\n' +
                               (result.stdout + result.stderr).decode('utf-8', 'replace'))
        print('Applied secondary WAN patch without fuzz', flush=True)
    return dest / DRIVER


def function(text, name):
    match = re.search(r'^(?:static )?(?:inline )?[\w *]+\b' +
                      re.escape(name) + r'\([^;]*?\)\s*\{', text, re.M)
    if not match:
        raise ValueError(f'missing function {name}')
    start = match.start()
    opening = text.index('{', match.start())
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def build_harness(driver):
    header = (driver / 'hnat.h').read_text(encoding='utf-8')
    core = (driver / 'hnat.c').read_text(encoding='utf-8')
    hook = (driver / 'hnat_nf_hook.c').read_text(encoding='utf-8')
    startup = function(core, 'hnat_hw_init').split('hnat_hw_set_prot_3t(ppe_id);', 1)[1]
    startup = startup.split('dev_info(', 1)[0]
    events = function(hook, 'nf_hnat_netdevice_event')
    unregister = events.split('case NETDEV_UNREGISTER:', 1)[1].split('break;', 1)[0]
    register = events.split('case NETDEV_REGISTER:', 1)[1].split('break;', 1)[0]
    optional = re.search(r'\terr = of_property_read_string\(np, "mtketh-wan2".*?'
                         r'(?=\terr = of_property_read_string\(np, "mtketh-lan")',
                         core, re.S)
    parts = {
        'CLASSIFY': function(header, 'is_hnat_wan_dev'),
        'LOOKUP': function(hook, 'get_wandev_from_index'),
        'START': startup,
        'RELEASE': function(core, 'hnat_release_netdev'),
        'REGISTER': register,
        'UNREGISTER': unregister,
        'PARSE': optional[0] if optional else 'err = -EINVAL; goto err_out2;',
    }
    harness = Path(__file__).with_name('tests').joinpath('hnat-secondary-wan.c').read_text(encoding='utf-8')
    for name, code in parts.items():
        harness = harness.replace(f'/* @{name}@ */', code)
    return harness


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--cc', default=os.environ.get('CC', 'cc'))
    parser.add_argument('--with-patch', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='hnat-wan-test-') as directory:
        root = Path(directory)
        driver = prepare(args.source.resolve(), root, args.with_patch)
        test = root / 'test.c'
        test.write_text(build_harness(driver), encoding='utf-8')
        binary = root / ('test.exe' if os.name == 'nt' else 'test')
        subprocess.run([args.cc, '-std=c99', '-Wall', '-Werror', str(test),
                        '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    main()

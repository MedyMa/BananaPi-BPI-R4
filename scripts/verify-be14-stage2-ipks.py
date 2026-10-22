#!/usr/bin/env python3
"""Check the new parameters in real packaged modules; no device actions."""
import importlib.util
import json
import os
from pathlib import Path
import tarfile
import tempfile
import sys

spec=importlib.util.spec_from_file_location('ipks',Path(__file__).with_name('package-be14-diagnostic-ipks.py'))
ipks=importlib.util.module_from_spec(spec)
spec.loader.exec_module(ipks)

def main():
    archive=Path(sys.argv[1]).resolve()
    with tarfile.open(archive) as t:
        files={Path(m.name).name:t.extractfile(m).read() for m in t.getmembers() if m.isfile()}
    manifest=json.loads(files['manifest.json'])
    assert manifest['source_commit']==os.environ['SOURCE_COMMIT']
    with tempfile.TemporaryDirectory(prefix='be14-stage2-ipks-') as tmp:
        for package,names in {
            'kmod-mediatek_hnat': ['hnat_diag_cpu_wifi_'+n for n in ['no_device_drop','vlan_drop','headroom_drop','xmit_calls','xmit_ok','xmit_cn','xmit_drop','xmit_other']],
            'kmod-mt_wifi7': ['whnat_tx_diag_'+n for n in ['fw_reports','fw_total','fw_fail','txs_reports','txs_me','txs_re','txs_le','txs_be','txs_txop','txs_baf']]
        }.items():
            record=manifest['packages'][package]
            payload=files[record['file']]
            assert ipks.sha(payload)==record['sha256']
            p=Path(tmp)/record['file'];p.write_bytes(payload)
            members=ipks.ipk_members(p)
            module,old=ipks.MARKERS[package]
            ipks.MARKERS[package]=(module,old+tuple(n.encode() for n in names))
            ipks.verify_markers(package,members)
            assert 'kernel (' in record['depends'], record
            print(json.dumps({'package':package,'sha256':record['sha256'],'depends':record['depends'],'stage2_parameters':names}))
    assert manifest['device_abi_confirmed'] is False
    print('PASS stage2 markers in actual IPK modules; device ABI/loading/throughput not verified')

if __name__=='__main__': main()

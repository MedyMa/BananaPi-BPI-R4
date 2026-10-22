#!/usr/bin/env python3
"""Exercise collector failure/normal/signal restoration using temporary files only."""
import io
import os
from pathlib import Path
import signal
import subprocess
import sys
import tarfile
import tempfile
import time

HNAT = '''rx_hook_calls rx_no_headroom rx_not_from_wed rx_wed0 rx_wed1 rx_wed2
rx_no_hnat_private rx_bad_entry rx_bad_ppe cpu_wifi_attempts cpu_wifi_gso
cpu_wifi_gso_errors cpu_wifi_segments_queued cpu_wifi_no_device_drop
cpu_wifi_vlan_drop cpu_wifi_headroom_drop cpu_wifi_xmit_calls cpu_wifi_xmit_ok
cpu_wifi_xmit_cn cpu_wifi_xmit_drop cpu_wifi_xmit_other'''.split()
PCI = '''desc_total desc_ppe_valid desc_no_ppe_valid desc_hw_path desc_cannot_reorder
desc_csrn_zero desc_csrn_nonzero desc_pn_fail desc_repeat desc_oldpkt queue_rro
queue_msdu_pg skb_built skb_hw_path skb_no_hw_path bus_handoff fifo_enqueued fifo_drop'''.split()
WIFI = '''whnat_force_rx_sw_packets whnat_tx_diag_fw_reports whnat_tx_diag_fw_total
whnat_tx_diag_fw_fail whnat_tx_diag_txs_reports whnat_tx_diag_txs_me whnat_tx_diag_txs_re
whnat_tx_diag_txs_le whnat_tx_diag_txs_be whnat_tx_diag_txs_txop whnat_tx_diag_txs_baf'''.split()
SWITCHES = [('mtkhnat','hnat_diag_enable'),('mtk_pci','whnat_rx_diag_enable'),
            ('mt_wifi','whnat_force_rx_diag_enable'),('mtkhnat','hnat_account_lock_diag_enable')]

def run_case(script, mode):
    with tempfile.TemporaryDirectory(prefix='be14-collector-test-') as tmp:
        root = Path(tmp)
        sysroot, proc, out = root/'sys', root/'proc', root/'out'
        proc.mkdir(); out.mkdir()
        for module, names in [('mtkhnat',['hnat_diag_'+n for n in HNAT]),
                              ('mtk_pci',['whnat_rx_diag_'+n for n in PCI]),('mt_wifi',WIFI)]:
            p = sysroot/'module'/module/'parameters'; p.mkdir(parents=True)
            for n in names:
                (p/n).write_text('0\n')
        originals = ['N','Y','0','1']
        for (module, name), old in zip(SWITCHES, originals):
            (sysroot/'module'/module/'parameters'/name).write_text(old+'\n')
        accounting = sysroot/'kernel/debug/hnat/accounting'
        accounting.parent.mkdir(parents=True)
        accounting.write_text('diag_lock_enabled=0 lock_samples=0\n')
        (proc/'uptime').write_text('100.00 90.00\n')
        (proc/'net').mkdir()
        (proc/'net/snmp').write_text('Tcp: RetransSegs\nTcp: 0\n')
        sleeper = root/'sleep-test'
        sleeper.write_text('#!/bin/sh\n'+ ('sleep 2\n' if mode == 'signal' else 'exit 0\n'))
        sleeper.chmod(0o755)
        if mode == 'missing':
            (sysroot/'module/mt_wifi/parameters/whnat_tx_diag_fw_total').unlink()
        env = dict(os.environ, SYSROOT=str(sysroot), PROCROOT=str(proc), OUTROOT=str(out),
                   SLEEP_BIN=str(sleeper), WINDOW_SECONDS='1', SS_BIN='be14-no-such-ss')
        p = subprocess.Popen(['sh',str(script)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if mode == 'signal':
            deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                if all((sysroot/'module'/m/'parameters'/n).read_text().strip() in ('Y','1') for m,n in SWITCHES):
                    p.send_signal(signal.SIGTERM)
                    break
                if p.poll() is not None:
                    raise AssertionError('collector exited before signal')
                time.sleep(.01)
            else:
                p.kill(); raise AssertionError('collector did not enter enabled sample window')
        stdout, stderr=p.communicate(timeout=10)
        assert (p.returncode==0) == (mode=='normal'), (mode,p.returncode,stdout,stderr)
        for (module,name),old in zip(SWITCHES,originals):
            assert (sysroot/'module'/module/'parameters'/name).read_text().strip()==old, (mode,name)
        archives=list(out.glob('*.tar.gz'))
        assert len(archives)==1, (mode,stdout,stderr)
        with tarfile.open(archives[0]) as t:
            data={Path(m.name).name:t.extractfile(m).read().decode() for m in t.getmembers() if m.isfile()}
        assert 'diagnostic_revision=2' in data['run.txt']
        if mode=='normal':
            assert 'sample_complete=1' in data['run.txt']
            assert 'mt_wifi.whnat_tx_diag_fw_total=0' in data['after.module-counters']
            assert 'mtkhnat.hnat_diag_cpu_wifi_xmit_calls=0' in data['after.module-counters']
            assert not data['errors.txt'], data['errors.txt']
        elif mode=='missing':
            assert not data['switches-touched.tsv'], 'preflight failure changed switches'
            assert 'whnat_tx_diag_fw_total' in data['errors.txt']
        print('PASS',mode,'restore original four switch values')

if __name__=='__main__':
    for mode in ['normal','missing','signal']:
        run_case(Path(sys.argv[1]).resolve(),mode)

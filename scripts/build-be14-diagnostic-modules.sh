#!/usr/bin/env bash
# The source tree, config and patch queue are prepared by BE14-Diagnostic.yml.
set -euo pipefail
cd "$GITHUB_WORKSPACE/openwrt"
evidence="$GITHUB_WORKSPACE/be14-evidence"
mkdir -p "$evidence"
run_make() {
    local label=$1
    shift
    printf '%s\t' "$(date -u +%FT%TZ)" >> "$evidence/commands.tsv"
    printf '%q ' make -j2 V=s 'PATCH=patch --batch --fuzz=2' "$@" >> "$evidence/commands.tsv"
    printf '\n' >> "$evidence/commands.tsv"
    set +e
    make -j2 V=s 'PATCH=patch --batch --fuzz=2' "$@" 2>&1 | tee "$evidence/$label.log"
    local result=${PIPESTATUS[0]}
    set -e
    printf '%s\t%s\n' "$label" "$result" >> "$evidence/exits.tsv"
    if [ "$result" -ne 0 ]; then return "$result"; fi
    df -h > "$evidence/space-$label.txt"
}

# Do not run world/download or remove selected features. Package targets below
# build their own dependency closures with the complete MT7988 configuration.
run_make tools tools/install
run_make toolchain toolchain/install
run_make kernel target/linux/compile
run_make kernel-packages package/kernel/linux/compile
run_make wifi-common package/mtk/drivers/mt_wifi_cmn/compile
run_make wifi package/mtk/drivers/mt_wifi7/compile
run_make hwifi package/mtk/drivers/mt_hwifi/compile
run_make warp package/mtk/drivers/warp/compile
run_make collector package/utils/be14-whnat-diag/compile

# New diagnostics must reverse-apply without fuzz against actual prepared trees.
# This does not claim that the legacy complete patch queue applied without fuzz.
python3 - "$PWD" "$evidence" <<'PY'
from pathlib import Path
import hashlib, shutil, subprocess, sys
root, evidence = map(Path, sys.argv[1:])
kernel = list((root/'build_dir').glob('target-*/linux-*/linux-6.6*'))
kernel = [p for p in kernel if (p/'drivers/net/ethernet/mediatek/mtk_hnat/hnat_nf_hook.c').is_file()]
wifi = list((root/'build_dir').glob('target-*/linux-*/mt_wifi7'))
if len(kernel)!=1 or len(wifi)!=1:
    raise SystemExit('Expected one actual prepared kernel and mt_wifi7 build tree')
with (evidence/'strict-new-patches.log').open('w') as log:
    for cwd, patch in [(kernel[0],root/'target/linux/mediatek/patches-6.6/99999-zz-be14-whnat-diag.patch'),
                       (wifi[0],root/'package/mtk/drivers/mt_wifi7/patches/974-be14-whnat-swpath-diag.patch')]:
        command=['patch','--batch','--dry-run','--reverse','--fuzz=0','-p1','-i',str(patch)]
        log.write('cwd='+str(cwd)+'\ncommand='+repr(command)+'\n');log.flush()
        subprocess.run(command,cwd=cwd,stdout=log,stderr=subprocess.STDOUT,check=True)
for name in ['.config','Module.symvers']:
    p=kernel[0]/name
    if not p.is_file(): raise SystemExit('Missing kernel evidence: '+name)
    shutil.copy2(p,evidence/('kernel'+name))
with (evidence/'module-sha256.txt').open('w') as out:
    for p in sorted((root/'build_dir').rglob('*.ko')):
        out.write(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(root))+'\n')
PY
grep -hE 'MODPOST|fuzz|offset' "$evidence"/*.log > "$evidence/modpost-patch-summary.txt" || true

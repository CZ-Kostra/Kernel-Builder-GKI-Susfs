#!/bin/bash
# scripts/custom_patches.sh

set -euo pipefail

if [[ "${SU_VARIANT}" == "SukiSU-Ultra" ]]; then
    echo ">>> Target is SukiSU-Ultra. Applying Universal SuSFS 2.20 Patch..."
    
    # Navigate into the staged manager directory
    cd kernel_workspace/KernelSU
    
    # Attempt to apply the patch. We use || true so a rejection doesn't instantly crash the CI runner.
    # --no-backup-if-mismatch prevents patch from leaving messy .orig files around
    patch -p1 --no-backup-if-mismatch < ../../patches/2.20_universal_susfs.patch || true
    
    # Catch and display any rejected hunks for our fixup script
    if find . -name "*.rej" | grep -q "."; then
        echo "[-] Patch resulted in rejections! Locating .rej files:"
        find . -name "*.rej"
    else
        echo ">>> Patch applied cleanly!"
    fi
    
    cd ../..
fi

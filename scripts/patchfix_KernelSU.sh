#!/bin/bash
# scripts/patchfix_KernelSU.sh

set -euo pipefail
MANAGER_DIR="KernelSU"

cd "kernel_workspace/${MANAGER_DIR}"

echo ">>> Applying Universal SuSFS 2.20 Patch to Mainline KernelSU..."
patch -p1 --no-backup-if-mismatch < ../../patches/ksu_susfs.patch || true

if find . -name "*.rej" | grep -q "."; then
    echo "[-] Patch rejections detected for KernelSU!"
    echo ""
    echo "========================================"
    echo ">>> LIST OF REJECTED FILES:"
    echo "========================================"
    find . -name "*.rej" | sort
    echo ""
    
    echo ">>> PRINTING REJECTION CONTENTS:"
    for rej_file in $(find . -name "*.rej" | sort); do
        echo "========================================"
        echo "FILE: $rej_file"
        echo "========================================"
        cat "$rej_file"
        echo ""
    done
    
    # Clean up the .rej files so the workspace is ready for the next run
    find . -name "*.rej" -type f -delete
else
    echo ">>> Patch applied cleanly to KernelSU with zero rejections!"
fi

cd ../..

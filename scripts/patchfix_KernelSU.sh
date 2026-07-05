#!/bin/bash
# scripts/patchfix_kernelsu.sh

set -euo pipefail
MANAGER_DIR="KernelSU"

cd "kernel_workspace/${MANAGER_DIR}"

echo ">>> Applying Universal SuSFS 2.20 Patch to Mainline KernelSU..."
patch -p1 --no-backup-if-mismatch < ../../patches/2.20_universal_susfs.patch || true

if find . -name "*.rej" | grep -q "."; then
    echo "[-] Patch rejections detected for KernelSU!"
    for rej_file in $(find . -name "*.rej"); do
        echo "========================================"
        echo "FILE: $rej_file"
        echo "========================================"
        cat "$rej_file"
        echo ""
    done
    find . -name "*.rej" -type f -delete
else
    echo ">>> Patch applied cleanly to KernelSU with zero rejections!"
fi
cd ../..
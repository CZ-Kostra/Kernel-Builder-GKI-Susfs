#!/bin/bash
# scripts/patchfix_KernelSU-Next.sh

set -euo pipefail
MANAGER_DIR="KernelSU-Next"

cd "kernel_workspace/${MANAGER_DIR}"


echo ">>> Applying Universal SuSFS 2.20 Patch to KernelSU-Next..."
patch -p1 --no-backup-if-mismatch < ../../patches/12.20_universal_susfs.patch || true

# Future-proofing: Catch any rejections from upstream merges
if find . -name "*.rej" | grep -q "."; then
    echo "[-] WARNING: Unexpected patch rejections detected in KernelSU-Next!"
    for rej_file in $(find . -name "*.rej"); do
        echo "========================================"
        echo "FILE: $rej_file"
        echo "========================================"
        cat "$rej_file"
        echo ""
    done
else
    echo ">>> Patch applied cleanly to KernelSU-Next!"
fi

cd ../..

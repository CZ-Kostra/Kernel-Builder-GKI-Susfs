#!/bin/bash
# scripts/patchfix_resukisu.sh

set -euo pipefail
MANAGER_DIR="KernelSU"

cd "kernel_workspace/${MANAGER_DIR}"

echo ">>> Applying Universal SuSFS 2.20 Patch to ReSukiSU..."
patch -p1 --no-backup-if-mismatch < ../../patches/2.20_universal_susfs.patch || true

if find . -name "*.rej" | grep -q "."; then
    echo "[-] Patch rejections detected for ReSukiSU!"
    for rej_file in $(find . -name "*.rej"); do
        echo "========================================"
        echo "FILE: $rej_file"
        echo "========================================"
        cat "$rej_file"
        echo ""
    done
    # We clean up the files so Bazel attempts to compile (and fail) so we get the full picture
    find . -name "*.rej" -type f -delete
else
    echo ">>> Patch applied cleanly to ReSukiSU with zero rejections!"
fi
cd ../..
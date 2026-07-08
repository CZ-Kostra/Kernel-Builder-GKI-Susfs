#!/bin/bash
set -euo pipefail

cd kernel_workspace/KernelSU-Next

echo ">>> SuSFS natively detected via Pershoot's dev-susfs branch."
echo ">>> Detecting Kernel Version for Dynamic Adaptation..."

# Extract version numbers directly from the GKI common Makefile
K_MAJ=$(grep -m 1 "^VERSION =" ../common/Makefile | awk '{print $3}')
K_MIN=$(grep -m 1 "^PATCHLEVEL =" ../common/Makefile | awk '{print $3}')

echo ">>> Target Kernel: $K_MAJ.$K_MIN"

# ---------------------------------------------------------
# 6.6 AND HIGHER ADAPTATIONS (Android 15+)
# ---------------------------------------------------------
if [ "$K_MAJ" -eq 6 ] && [ "$K_MIN" -ge 6 ]; then
    echo ">>> Manually exposing 6.6 SELinux functions for SuSFS linking..."
    
    # Strip 'static' scope from functions required by selinuxfs.c
    sed -i 's/static int security_context_to_sid_with_policy/int security_context_to_sid_with_policy/g' kernel/feature/selinux_hide.c
    sed -i 's/static int security_sid_to_context_with_policy/int security_sid_to_context_with_policy/g' kernel/feature/selinux_hide.c
    sed -i 's/static void security_compute_av_user_with_policy/void security_compute_av_user_with_policy/g' kernel/feature/selinux_hide.c
fi

# ---------------------------------------------------------
# 6.12 AND HIGHER ADAPTATIONS (Future-Proofing)
# ---------------------------------------------------------
if [ "$K_MAJ" -eq 6 ] && [ "$K_MIN" -ge 12 ]; then
    echo ">>> Applying 6.12+ specific API shifts..."
    # Future sed fixes go here
fi

cd ../..
echo ">>> Universal compiler adaptation complete."

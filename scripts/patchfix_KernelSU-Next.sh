#!/bin/bash
# scripts/patchfix_KernelSU-Next.sh

set -euo pipefail
MANAGER_DIR="KernelSU-Next"

cd "kernel_workspace/${MANAGER_DIR}"

echo ">>> Target is KernelSU-Next. Native 2.20 support detected, skipping main patch."

# Future-proofing: Catch any rejections from upstream merges or earlier pipeline steps
if find . -name "*.rej" | grep -q "."; then
    echo "[-] WARNING: Unexpected patch rejections detected in KernelSU-Next!"
    for rej_file in $(find . -name "*.rej"); do
        echo "========================================"
        echo "FILE: $rej_file"
        echo "========================================"
        cat "$rej_file"
        echo ""
    done
    # We deliberately do not delete the .rej files here. 
    # If they exist in Next, something is critically wrong upstream and the build should fail.
fi

echo ">>> Applying linkage and compatibility fixes..."

if [ -f kernel/feature/selinux_hide.c ]; then
    # 1. Fix drop_backup_if_unused linkage
    sed -i 's/static void ksu_selinux_hide_drop_backup_if_unused/void ksu_selinux_hide_drop_backup_if_unused/g' kernel/feature/selinux_hide.c
    
    # 2. Fix the three security_*_with_policy functions for Android 15 / 6.6 compatibility
    sed -i 's/static int security_context_to_sid_with_policy/int security_context_to_sid_with_policy/g' kernel/feature/selinux_hide.c
    sed -i 's/static int security_sid_to_context_with_policy/int security_sid_to_context_with_policy/g' kernel/feature/selinux_hide.c
    sed -i 's/static void security_compute_av_user_with_policy/void security_compute_av_user_with_policy/g' kernel/feature/selinux_hide.c
    
    echo ">>> SELinux linkage fixes applied!"
fi

if [ -f kernel/kpm/super_access.c ]; then
    # 3. Fix Android 16 / 6.12 cb_mutex removal in KPM
    sed -i 's/DEFINE_MEMBER(netlink_kernel_cfg, cb_mutex)/#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 12, 0)\n    DEFINE_MEMBER(netlink_kernel_cfg, cb_mutex)\n#endif/g' kernel/kpm/super_access.c
    echo ">>> KPM 6.12 cb_mutex fix applied!"
fi

cd ../..

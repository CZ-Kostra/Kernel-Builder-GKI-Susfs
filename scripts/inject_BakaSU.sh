#!/usr/bin/env bash
# scripts/inject_BakaSU.sh

echo ">>> Executing Integration Module for BakaSU..."

# 1. Universally clone the target branch handed down by the YAML
echo ">>> 1. Cloning target branch (${KSU_VARIANT_REF}) from ${KSU_VARIANT_REPO_URL}..."
git clone -b "${KSU_VARIANT_REF}" "${KSU_VARIANT_REPO_URL}" "${MANAGER_DIR}"

ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
cd common
bash "${MANAGER_DIR}/kernel/setup.sh" "${KSU_VARIANT_REF}"
cd ..

cd "${MANAGER_DIR}"

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> [DYNAMIC] Executing Automated Dynamic Transplant for BakaSU..."
    
    # In dynamic, HEAD is already pristine upstream. Grab the hash!
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -i --grep="ci skip" --grep="skip ci" --grep="clippy" --invert-grep -- manager/ kernel/ userspace/ .github/workflows/ ":!*Cargo.lock" ":!*Cargo.toml")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
    
    UPSTREAM_BRANCH="${TARGET_BRANCH}"

    echo ">>> 2. Applying dynamic Kleaf bypass & Kconfig overrides..."
    sed -i 's/default KSU_TRACEPOINT_HOOK/default KSU_SUSFS/g' kernel/Kconfig
    sed -i 's/bool "Tracepoint Syscall Redirect"/bool "Tracepoint Syscall Redirect"\n\t\tdepends on n/g' kernel/Kconfig
    sed -i 's/depends on KSU != m/depends on n/g' kernel/Kconfig
    sed -i 's/ifeq ($(shell test -e $(srctree)\/fs\/susfs.c.*/ifeq (0,0)/g' kernel/Kbuild
    sed -i 's/cat $(srctree)\/include\/linux\/susfs.h |/cat $(srctree)\/include\/linux\/susfs.h 2>\/dev\/null |/g' kernel/Kbuild

else
    echo ">>> [STABLE] Safe fallback channel detected. Bypassing dynamic overrides..."
    
    UPSTREAM_BRANCH="${KSU_VARIANT_REF}"
    
    echo ">>> Locating official upstream sync point for ${UPSTREAM_REPO}..."
    # Guarantee safe tag math with --tags --force
    git fetch --quiet --tags --force "https://github.com/${UPSTREAM_REPO}.git" "${TARGET_BRANCH}"
    RAW_BASE=$(git merge-base HEAD FETCH_HEAD)
    
    set +o pipefail
    UPSTREAM_HASH=$(git log -n 1 --first-parent "${RAW_BASE}" --format="%H" -i --grep="ci skip" --grep="skip ci" --grep="clippy" --invert-grep -- manager/ kernel/ userspace/ .github/workflows/ ":!*Cargo.lock" ":!*Cargo.toml")
    set -o pipefail

    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v0.0.0")
fi

# Exit the MANAGER_DIR universally
cd ..

# ---------------------------------------------------------
# BakaSU Hotfixes
# ---------------------------------------------------------

# We strip the $(error ...) directive to force compilation of our custom port.
SUSFS_COMPAT_MK="${MANAGER_DIR}/kernel/tools/susfs_compat.mk"
if [ -f "$SUSFS_COMPAT_MK" ]; then
    echo ">>> [HOTFIX] Neutering BakaSU strict SuSFS version gatekeeper..."
    sed -i '/Please wait susfs update/d' "$SUSFS_COMPAT_MK"
else
    echo ">>> [NOTICE] BakaSU gatekeeper file not found at $SUSFS_COMPAT_MK"
fi

# Injecting 'return 0;' for BakaSU non-void legacy kernel compat
SELINUX_HIDE_FILE="${MANAGER_DIR}/kernel/feature/selinux_hide.c"
if [ -f "$SELINUX_HIDE_FILE" ]; then
    K_VER=$(grep "^VERSION =" common/Makefile | tr -d ' ' | cut -d'=' -f2 || echo "0")
    K_PATCH=$(grep "^PATCHLEVEL =" common/Makefile | tr -d ' ' | cut -d'=' -f2 || echo "0")
    
    # Only kernels < 6.6 require the int return fix
    if ! { [ "$K_VER" = "6" ] && [ "$K_PATCH" -ge "6" ]; }; then
        if grep -q "void security_compute_av_user_with_policy" "$SELINUX_HIDE_FILE"; then
            echo ">>> [HOTFIX] Patching BakaSU non-void return error for legacy kernels..."
            
            # Line 1: Fix the signature from void to int
            sed -i 's/__maybe_static void security_compute_av_user_with_policy/__maybe_static int security_compute_av_user_with_policy/g' "$SELINUX_HIDE_FILE"
            
            # Line 2: Inject the return 0;
            sed -i 's/ksu_security_compute_av_user(policydb, sidtab, ssid, tsid, tclass, avd);/ksu_security_compute_av_user(policydb, sidtab, ssid, tsid, tclass, avd);\n\treturn 0;/g' "$SELINUX_HIDE_FILE"
        fi
    fi
fi

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: $UPSTREAM_HASH"
echo "  -> Target Count: $CALCULATED_COUNT"
echo ">>> BakaSU integration complete."

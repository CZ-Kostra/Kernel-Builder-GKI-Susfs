#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace
[ -d common ] || { echo "[-] common/ not found in kernel_workspace" >&2; exit 1; }

VARIANT=$1
# Export these so the sourced scripts can use them natively
export KSU_VARIANT_REF=$(echo "${KSU_VARIANT_REF:-}" | xargs)
export USE_DYNAMIC_TRANSPLANT=$(echo "${USE_DYNAMIC_TRANSPLANT:-false}" | tr '[:upper:]' '[:lower:]')

# 1. Map the expected directory name based on the variant's internal setup.sh hardcoding
case "${VARIANT}" in
    "KernelSU-Next")
        export MANAGER_DIR="KernelSU-Next"
        ;;
    "SukiSU-Ultra" | "ReSukiSU" | "KernelSU")
        export MANAGER_DIR="KernelSU"
        ;;
    *)
        echo "[-] Error: Unsupported Variant '${VARIANT}'. Selected variant not supported" >&2
        exit 1
        ;;
esac

rm -rf "${MANAGER_DIR}"
echo "=== Integrating ${VARIANT} ==="

# ========================================================================
# MODULAR DELEGATION
# ========================================================================
# Note the '../' because we are currently inside the 'kernel_workspace' directory
INJECTOR_SCRIPT="../scripts/inject_${VARIANT}.sh"

if [ -f "$INJECTOR_SCRIPT" ]; then
    echo ">>> Delegating integration to modular script: $INJECTOR_SCRIPT"
    
    # We use 'source' so the child script runs in THIS environment.
    # This allows it to set UPSTREAM_HASH, UPSTREAM_BRANCH, CALCULATED_COUNT, and CALCULATED_TAG 
    # so we can use them in the Gatekeeper below.
    source "$INJECTOR_SCRIPT"
else
    echo "[-] CRITICAL: Modular script $INJECTOR_SCRIPT not found!" >&2
    exit 1
fi

# ========================================================================
# KERNEL 6.6/6.12 UPSTREAM COMPATIBILITY FIXES
# ========================================================================
echo ">>> Checking for upstream 6.6+ SELinux static declaration conflicts..."
SELINUX_HIDE="${MANAGER_DIR}/kernel/feature/selinux_hide.c"

# Apply fixes ONLY if the file exists AND the variant is NOT ReSukiSU
if [ -f "$SELINUX_HIDE" ] && [[ "$VARIANT" != "ReSukiSU" ]]; then
    # 1. security_compute_av_user_with_policy (void/int, catching optional __nocfi)
    sed -i -E 's/static\s+(void|int)\s+(__nocfi\s+)?security_compute_av_user_with_policy/\1 \2security_compute_av_user_with_policy/g' "$SELINUX_HIDE"
    
    # 2. security_context_to_sid_with_policy (int, catching optional __nocfi)
    sed -i -E 's/static\s+(int)\s+(__nocfi\s+)?security_context_to_sid_with_policy/\1 \2security_context_to_sid_with_policy/g' "$SELINUX_HIDE"
    
    # 3. security_sid_to_context_with_policy (int, catching optional __nocfi)
    sed -i -E 's/static\s+(int)\s+(__nocfi\s+)?security_sid_to_context_with_policy/\1 \2security_sid_to_context_with_policy/g' "$SELINUX_HIDE"

    echo "  -> Applied targeted SELinux scope fixes to ${VARIANT}."
else
    echo "  -> Bypassing SELinux scope fixes (Native compatibility detected for ${VARIANT})."
fi

# ========================================================================
# KLEAF SANDBOX IMMUTABLE GATEKEEPER
# ========================================================================
# (These variables were populated by the sourced variant script)
SHORT_HASH=${UPSTREAM_HASH:0:7}
echo "UPSTREAM_HASH=${UPSTREAM_HASH}" >> $GITHUB_ENV

echo ">>> Injecting Sandbox Variables into Kbuild..."
TARGET_KBUILD="${MANAGER_DIR}/kernel/Kbuild"

if [ -f "$TARGET_KBUILD" ]; then
    {
        # --- Official & Next Namespaces ---
        echo "override KSU_GIT_VERSION_VALID := false" 
        echo "override KSU_GIT_VERSION := ${CALCULATED_COUNT}"
        echo "override KSU_GIT_TAG := ${CALCULATED_TAG}"
        echo "override KSU_COMMIT_SHA := ${SHORT_HASH}"
        echo "override KSU_GIT_BRANCH := ${UPSTREAM_BRANCH}"
        
        # --- ReSukiSU Namespaces ---
        echo "override LOCAL_GIT_EXISTS := 1"
        echo "override KSU_LOCAL_VERSION := ${CALCULATED_COUNT}"
        echo "override KSU_TAG_NAME := ${CALCULATED_TAG}"
        echo "override KSU_BRANCH_NAME := ${UPSTREAM_BRANCH}"
        echo "override KSU_COMMIT_SHA := ${SHORT_HASH}" 

        # --- SukiSU-Ultra Specific Namespaces ---
        echo "override LOCAL_COUNT := ${CALCULATED_COUNT}"
        echo "override git_commit_count := ${CALCULATED_COUNT}"
        echo "override git_short_sha := ${SHORT_HASH}"
        echo "override git_branch := ${UPSTREAM_BRANCH}"
        echo "override git_latest_tag := ${CALCULATED_TAG}"

        cat "$TARGET_KBUILD"
    } > "${TARGET_KBUILD}.tmp" && mv "${TARGET_KBUILD}.tmp" "$TARGET_KBUILD"

    echo "  -> Prepend Immutable Count: ${CALCULATED_COUNT}"
    echo "  -> Prepend Immutable Tag: ${CALCULATED_TAG}"
    echo "  -> Prepend Immutable SHA: ${SHORT_HASH}"
    echo "  -> Prepend Immutable Branch: ${UPSTREAM_BRANCH}"
else
    echo "[-] Warning: $TARGET_KBUILD not found. Sandbox variables not injected."
fi

# ========================================================================
# KERNEL DRIVER SYMLINK
# ========================================================================
echo ">>> Injecting Bazel symlink..."
DRIVER_ROOT="common/drivers"
rm -rf "${DRIVER_ROOT}/kernelsu"
ln -sfn "../../${MANAGER_DIR}/kernel" "${DRIVER_ROOT}/kernelsu"
[ -L "${DRIVER_ROOT}/kernelsu" ] || { echo "[-] Symlink failed" >&2; exit 1; }

echo ">>> ${MANAGER_DIR} architecture locked, sanitized and integrated!"

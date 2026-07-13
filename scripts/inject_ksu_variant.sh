#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace
[ -d common ] || { echo "[-] common/ not found in kernel_workspace" >&2; exit 1; }

VARIANT=$1
KSU_VARIANT_REF=$(echo "${KSU_VARIANT_REF:-}" | xargs)
USE_DYNAMIC_TRANSPLANT=$(echo "${USE_DYNAMIC_TRANSPLANT:-false}" | tr '[:upper:]' '[:lower:]')

# 1. Map the expected directory name based on the variant's internal setup.sh hardcoding
case "${VARIANT}" in
    "KernelSU-Next")
        MANAGER_DIR="KernelSU-Next"
        ;;
    "SukiSU-Ultra" | "ReSukiSU")
        MANAGER_DIR="KernelSU"
        ;;
    *)
        echo "[-] Error: Unsupported Variant '${VARIANT}'. Vanilla KernelSU is deprecated." >&2
        exit 1
        ;;
esac

rm -rf "${MANAGER_DIR}"
echo "=== Integrating ${VARIANT} ==="

# ========================================================================
# KERNELSU-NEXT: CANARY DYNAMIC TRANSPLANT
# ========================================================================
if [[ "${VARIANT}" == "KernelSU-Next" ]] && [[ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]]; then
    echo ">>> [CANARY] Executing Automated Dynamic Transplant for KernelSU-Next..."
    
    echo ">>> 1. Cloning pristine official KernelSU-Next..."
    git clone https://github.com/KernelSU-Next/KernelSU-Next.git "${MANAGER_DIR}"
    cd "${MANAGER_DIR}"

    # CAPTURE THIS IMMEDIATELY BEFORE ANY CHERRY-PICKS!
    UPSTREAM_HASH=$(git log -n 1 --format="%H")

    echo ">>> 2. Scraping the latest official tag for the Bazel Sandbox..."
    CALCULATED_TAG=$(git describe --tags --abbrev=0)
    echo "  -> Target Tag: $CALCULATED_TAG"

    echo ">>> 3. Fetching Pershoot's live laboratory..."
    git remote add pershoot https://github.com/pershoot/KernelSU-Next.git
    git fetch pershoot dev-susfs

    echo ">>> 4. Calculating the architectural split..."
    MERGE_BASE=$(git merge-base HEAD pershoot/dev-susfs)

    echo ">>> 5. Generating dynamic commit list (Filtering out CI hacks)..."
    VALID_COMMITS=$(git log --reverse --format="%H %s" ${MERGE_BASE}..pershoot/dev-susfs | grep -v -i -E "setup:|manager" | awk '{print $1}')

    echo ">>> Configuring dummy Git identity for transplant operations..."
    git config --global user.email "runner@github.actions"
    git config --global user.name "GitHub Actions Canary"

    echo ">>> 6. Transplanting pure SuSFS commits onto upstream tree..."
    for commit in $VALID_COMMITS; do
        COMMIT_TITLE=$(git log --format="%s" -n 1 "$commit")
        echo "  -> Transplanting: $COMMIT_TITLE"
        git cherry-pick "$commit"
    done

    echo ">>> Dynamic SuSFS integration complete!"

    # Step back out to the main workspace
    cd .. 

    # Prevent setup.sh from performing a redundant clone by spoofing its presence in common/
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"

    echo ">>> Executing native setup.sh..."
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" dev
    cd ..

    # Lock in variables for the Kbuild Gatekeeper
    UPSTREAM_REPO="KernelSU-Next/KernelSU-Next"
    UPSTREAM_BRANCH="dev"
    CALCULATED_COUNT=$(git -C "${MANAGER_DIR}" rev-list --count "${UPSTREAM_HASH}")
    
# ========================================================================
# STABLE / LEGACY VARIANTS
# ========================================================================
else
    echo ">>> [STABLE] Cloning custom pipeline branch: ${KSU_VARIANT_REF} from ${KSU_VARIANT_REPO_URL}..."
    git clone "${KSU_VARIANT_REPO_URL}" -b "${KSU_VARIANT_REF}" "${MANAGER_DIR}"

    # Prevent setup.sh from performing a redundant clone by spoofing its presence in common/
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"

    echo ">>> Executing native setup.sh..."
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" "${KSU_VARIANT_REF}"
    cd ..

    # Route the URL and default branch based on the variant for sync calculation
    if [[ "${VARIANT}" == "KernelSU-Next" ]]; then
        UPSTREAM_REPO="KernelSU-Next/KernelSU-Next"
        UPSTREAM_BRANCH="dev"
    elif [[ "${VARIANT}" == "SukiSU-Ultra" ]]; then
        UPSTREAM_REPO="SukiSU-Ultra/SukiSU-Ultra"
        UPSTREAM_BRANCH="main"
    elif [[ "${VARIANT}" == "ReSukiSU" ]]; then
        UPSTREAM_REPO="ReSukiSU/ReSukiSU"
        UPSTREAM_BRANCH="main"
    fi

    echo ">>> Locating official upstream sync point for ${UPSTREAM_REPO}..."
    git -C "${MANAGER_DIR}" fetch --quiet "https://github.com/${UPSTREAM_REPO}.git" "${UPSTREAM_BRANCH}"
    RAW_BASE=$(git -C "${MANAGER_DIR}" merge-base HEAD FETCH_HEAD)

    # Walk backward down the official mainline branch, ignoring bots
    set +o pipefail
    UPSTREAM_HASH=$(git -C "${MANAGER_DIR}" log --first-parent "${RAW_BASE}" --format="%H %an" | grep -m 1 -iv "dependabot" | awk '{print $1}')
    set -o pipefail
    
    # Calculate exact versions for the Sandbox Gatekeeper
    CALCULATED_COUNT=$(git -C "${MANAGER_DIR}" rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
    CALCULATED_TAG=$(git -C "${MANAGER_DIR}" describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v3.2.0")
fi

# ========================================================================
# KLEAF SANDBOX IMMUTABLE GATEKEEPER
# ========================================================================
SHORT_HASH=${UPSTREAM_HASH:0:7}
echo "UPSTREAM_HASH=${UPSTREAM_HASH}" >> $GITHUB_ENV

echo ">>> Injecting Sandbox Variables into Kbuild..."
TARGET_KBUILD="${MANAGER_DIR}/kernel/Kbuild"

if [ -f "$TARGET_KBUILD" ]; then

    # Inject everything immutably
    {
        # --- Official & Next Namespaces ---
        echo "override KSU_GIT_VERSION_VALID := false" 
        echo "override KSU_GIT_VERSION := ${CALCULATED_COUNT}"
        echo "override KSU_GIT_TAG := ${CALCULATED_TAG}"
        echo "override KSU_COMMIT_SHA := ${SHORT_HASH}"
        echo "override KSU_GIT_BRANCH := ${UPSTREAM_BRANCH}"
        
        # --- ReSukiSU & Ultra Namespaces ---
        echo "override KSU_LOCAL_VERSION := ${CALCULATED_COUNT}"
        echo "override KSU_TAG_NAME := ${CALCULATED_TAG}"
        echo "override KSU_BRANCH_NAME := ${UPSTREAM_BRANCH}"
        echo "override KSU_BRANCH := ${UPSTREAM_BRANCH}"
        
        cat "$TARGET_KBUILD"
    } > "${TARGET_KBUILD}.tmp" && mv "${TARGET_KBUILD}.tmp" "$TARGET_KBUILD"

    echo "  -> Prepend Immutable Count: ${CALCULATED_COUNT}"
    echo "  -> Prepend Immutable Tag: ${CALCULATED_TAG}"
    echo "  -> Prepend Immutable SHA: ${SHORT_HASH}"
    echo "  -> Prepend Immutable Branch: ${UPSTREAM_BRANCH}"
fi

echo ">>> Injecting Bazel symlink..."
DRIVER_ROOT="common/drivers"
rm -rf "${DRIVER_ROOT}/kernelsu"
ln -sfn "../../${MANAGER_DIR}/kernel" "${DRIVER_ROOT}/kernelsu"
[ -L "${DRIVER_ROOT}/kernelsu" ] || { echo "[-] Symlink failed" >&2; exit 1; }

echo ">>> ${MANAGER_DIR} architecture locked, sanitized and integrated!"

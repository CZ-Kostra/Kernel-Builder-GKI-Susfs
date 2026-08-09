#!/usr/bin/env bash
# scripts/inject_KernelSU-Next.sh
# Dynamic SuSFS integration module for KernelSU-Next

echo ">>> Executing Integration Module for KernelSU-Next..."

if [[ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]]; then
    echo ">>> [CANARY] Executing Automated Dynamic Transplant for KernelSU-Next..."
    
    echo ">>> 1. Cloning pristine official KernelSU-Next..."
    git clone https://github.com/KernelSU-Next/KernelSU-Next.git "${MANAGER_DIR}"
    
    # Prevent setup.sh from performing a redundant clone
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    
    echo ">>> Executing native setup.sh to initialize branch..."
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" dev
    cd ..
    
    cd "${MANAGER_DIR}"

    # CAPTURE THIS IMMEDIATELY BEFORE ANY CHERRY-PICKS!
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    echo "  -> Target Tag: $CALCULATED_TAG"

    echo ">>> 2. Fetching Pershoot's live laboratory..."
    git remote add pershoot https://github.com/pershoot/KernelSU-Next.git
    git fetch pershoot dev-susfs

    echo ">>> 3. Calculating the merge-base for SuSFS commits..."
    MERGE_BASE=$(git merge-base HEAD pershoot/dev-susfs)

    echo ">>> 4. Generating dynamic commit list (Filtering out CI hacks)..."
    VALID_COMMITS=$(git log --reverse --format="%H %s" ${MERGE_BASE}..pershoot/dev-susfs | grep -v -i -E "setup:|manager" | awk '{print $1}')

    echo ">>> Configuring dummy Git identity for transplant operations..."
    git config --global user.email "runner@github.actions"
    git config --global user.name "GitHub Actions Canary"

    echo ">>> 5. Transplanting pure SuSFS commits onto upstream tree..."
    for commit in $VALID_COMMITS; do
        COMMIT_TITLE=$(git log --format="%s" -n 1 "$commit")
        echo "  -> Transplanting: $COMMIT_TITLE"
        if ! git cherry-pick "$commit"; then
            echo "[-] CRITICAL: Merge conflict detected on commit: $commit"
            git --no-pager diff --diff-filter=U
            git cherry-pick --abort
            exit 1
        fi
    done

    # Lock in variables for the Kbuild Gatekeeper
    UPSTREAM_BRANCH="dev"
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
    
else
    echo ">>> [STABLE/TEST] Cloning custom pipeline branch: ${KSU_VARIANT_REF} from ${KSU_VARIANT_REPO_URL}..."
    git clone "${KSU_VARIANT_REPO_URL}" -b "${KSU_VARIANT_REF}" "${MANAGER_DIR}"

    # Prevent setup.sh from performing a redundant clone
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"

    echo ">>> Executing native setup.sh..."
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" "${KSU_VARIANT_REF}"
    cd ..

    cd "${MANAGER_DIR}"
    UPSTREAM_REPO="KernelSU-Next/KernelSU-Next"
    UPSTREAM_BRANCH="dev"

    # If building custom manager on test channel, use HEAD so kernel and APK versions match perfectly.
    if [[ "${BUILD_CHANNEL:-}" == "test" ]]; then
        echo ">>> [TEST CHANNEL] Bypassing upstream sync. Using custom HEAD for version match..."
        UPSTREAM_HASH=$(git rev-parse HEAD)
    else
        echo ">>> Locating official upstream sync point for ${UPSTREAM_REPO}..."
        git fetch --quiet "https://github.com/${UPSTREAM_REPO}.git" "${UPSTREAM_BRANCH}"
        RAW_BASE=$(git merge-base HEAD FETCH_HEAD)

        # Walk backward down the official mainline branch
        set +o pipefail
        UPSTREAM_HASH=$(git log --first-parent "${RAW_BASE}" --format="%H" -n 1 -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
        set -o pipefail
    fi
    
    # Calculate exact versions for the Sandbox Gatekeeper
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v3.2.0")
fi

# ========================================================================
# KERNEL VERSION ADAPTATION (6.6+ FIXES)
# ========================================================================
echo ">>> Detecting Kernel Version for Dynamic Adaptation..."
K_MAJ=$(grep -m 1 "^VERSION =" ../common/Makefile | awk '{print $3}')
K_MIN=$(grep -m 1 "^PATCHLEVEL =" ../common/Makefile | awk '{print $3}')

echo ">>> Target Kernel: $K_MAJ.$K_MIN"

if [ "$K_MAJ" -eq 6 ] && [ "$K_MIN" -ge 6 ]; then
    echo ">>> Manually exposing 6.6 SELinux functions for SuSFS linking..."
    
    # Strip 'static' scope from functions required by selinuxfs.c
    sed -i 's/static int security_context_to_sid_with_policy/int security_context_to_sid_with_policy/g' kernel/feature/selinux_hide.c
    sed -i 's/static int security_sid_to_context_with_policy/int security_sid_to_context_with_policy/g' kernel/feature/selinux_hide.c
    sed -i 's/static void security_compute_av_user_with_policy/void security_compute_av_user_with_policy/g' kernel/feature/selinux_hide.c
fi

# Step back out to kernel_workspace
cd .. 

echo ">>> KernelSU-Next integration complete."

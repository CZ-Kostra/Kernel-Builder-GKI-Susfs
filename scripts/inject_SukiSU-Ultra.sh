#!/usr/bin/env bash
# scripts/inject_ReSukiSU.sh
# Dynamic SuSFS integration module for ReSukiSU (and SukiSU-Ultra via symlink)

echo ">>> Executing Integration Module for ${VARIANT}..."

if [[ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]]; then
    echo ">>> [CANARY] Executing Automated Dynamic Transplant for ${VARIANT}..."

    echo ">>> 1. Cloning pristine official ${VARIANT}..."
    git clone "https://github.com/${VARIANT}/${VARIANT}.git" "${MANAGER_DIR}"

    # Prevent setup.sh from performing a redundant clone
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    
    echo ">>> Executing native setup.sh to initialize branch..."
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" main
    cd ..

    cd "${MANAGER_DIR}"

    # CAPTURE THIS IMMEDIATELY BEFORE ANY CHERRY-PICKS!
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    echo "  -> Target Tag: $CALCULATED_TAG"
    echo "  -> Target Hash: $UPSTREAM_HASH"

    echo ">>> Configuring dummy Git identity for transplant operations..."
    git config --global user.email "runner@github.actions"
    git config --global user.name "GitHub Actions Canary"

    echo ">>> 2. Fetching and cherry-picking SuSFS commit from shoey63's stable fork..."
    git fetch "https://github.com/shoey63/${VARIANT}.git" "${KSU_VARIANT_REF}"

    if ! git cherry-pick FETCH_HEAD; then
        echo "[-] CRITICAL: Merge conflict detected on ${VARIANT} patch!"
        echo ">>> Dumping conflict markers to console:"
        git --no-pager diff --diff-filter=U
        git cherry-pick --abort
        exit 1
    fi

    # Lock in variables for the Kbuild Gatekeeper
    UPSTREAM_BRANCH="main"
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
    
    UPSTREAM_REPO="${VARIANT}/${VARIANT}"
    UPSTREAM_BRANCH="main"

    echo ">>> Locating official upstream sync point for ${UPSTREAM_REPO}..."
    git fetch --quiet "https://github.com/${UPSTREAM_REPO}.git" "${UPSTREAM_BRANCH}"
    RAW_BASE=$(git merge-base HEAD FETCH_HEAD)

    # Walk backward down the official mainline branch
    set +o pipefail
    UPSTREAM_HASH=$(git log --first-parent "${RAW_BASE}" --format="%H" -n 1 -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
    set -o pipefail
    
    # Calculate exact versions for the Sandbox Gatekeeper
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v3.2.0")
fi

# Step back out to kernel_workspace
cd .. 

echo ">>> ${VARIANT} integration complete."

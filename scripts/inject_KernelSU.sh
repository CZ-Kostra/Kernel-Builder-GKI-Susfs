#!/usr/bin/env bash
# scripts/inject_KernelSU.sh

echo ">>> Executing Integration Module for standard KernelSU..."

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> 1. Cloning pristine official KernelSU upstream..."
    git clone https://github.com/tiann/KernelSU.git "${MANAGER_DIR}"
    
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" main
    cd ..
    
    cd "${MANAGER_DIR}"
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
    UPSTREAM_BRANCH="main"

    echo ">>> 2. Fetching Simonpunk's 6.6-dev 10_enable_susfs_for_ksu patch..."
    PATCH_URL="https://gitlab.com/simonpunk/susfs4ksu/-/raw/gki-android15-6.6-dev/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"

    if wget -qO 10_enable_susfs_for_ksu.patch "$PATCH_URL"; then
        echo ">>> 3. Applying SuSFS patch dynamically..."
        patch -p1 < 10_enable_susfs_for_ksu.patch || exit 1
        
        echo ">>> 4. Injecting SuSFS Macros & Compiler Overrides into Kbuild..."
        cat << 'EOF' >> kernel/Kbuild

# --- Force SuSFS Macros and Compiler Overrides ---
ccflags-y += -Wno-pointer-bool-conversion
ccflags-y += -DCONFIG_KSU_SUSFS=1
ccflags-y += -DCONFIG_KSU_SUSFS_SUS_PATH=1
ccflags-y += -DCONFIG_KSU_SUSFS_SUS_MOUNT=1
ccflags-y += -DCONFIG_KSU_SUSFS_SUS_KSTAT=1
ccflags-y += -DCONFIG_KSU_SUSFS_SPOOF_UNAME=1
ccflags-y += -DCONFIG_KSU_SUSFS_ENABLE_LOG=1
ccflags-y += -DCONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=1
ccflags-y += -DCONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=1
ccflags-y += -DCONFIG_KSU_SUSFS_OPEN_REDIRECT=1
ccflags-y += -DCONFIG_KSU_SUSFS_SUS_MAP=1
EOF
        rm 10_enable_susfs_for_ksu.patch
    else
        echo "[-] CRITICAL: Failed to download the SuSFS patch."
        exit 1
    fi
    cd ..
else
    echo ">>> Safe fallback channel detected. Cloning custom pipeline branch..."
    git clone -b "${KSU_VARIANT_REF}" "${KSU_VARIANT_REPO_URL}" "${MANAGER_DIR}"
    
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" main
    cd ..
    
    cd "${MANAGER_DIR}"
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
    UPSTREAM_BRANCH="main"
    cd ..
fi

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: $UPSTREAM_HASH"
echo "  -> Target Count: $CALCULATED_COUNT"
echo ">>> Standard KernelSU injection complete."

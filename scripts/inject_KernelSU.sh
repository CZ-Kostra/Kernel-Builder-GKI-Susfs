#!/usr/bin/env bash
# scripts/inject_KernelSU.sh
# Dynamic SuSFS integration module for Standard KernelSU

echo ">>> [CANARY] Executing Automated Dynamic Transplant for standard KernelSU..."

echo ">>> 1. Cloning pristine official KernelSU..."
git clone https://github.com/tiann/KernelSU.git "${MANAGER_DIR}"

# Prevent setup.sh from performing a redundant clone
ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"

echo ">>> Executing native setup.sh to initialize branch..."
cd common
bash "${MANAGER_DIR}/kernel/setup.sh" main
cd ..

cd "${MANAGER_DIR}"

# ========================================================================
# CAPTURE HASHES FOR SANDBOX GATEKEEPER
# ========================================================================
# Walk backward from HEAD, ignoring commits that ONLY touch website/docs
UPSTREAM_HASH=$(git log -n 1 --format="%H" -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
UPSTREAM_BRANCH="main"

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: $UPSTREAM_HASH"
echo "  -> Target Count: $CALCULATED_COUNT"

# ========================================================================
# DYNAMIC SuSFS INJECTION
# ========================================================================
echo ">>> 2. Fetching Simonpunk's 6.6-dev 10_enable_susfs_for_ksu patch..."

# Fetching from the gki-android15-6.6-dev branch for universal compatibility
PATCH_URL="https://gitlab.com/simonpunk/susfs4ksu/-/raw/gki-android15-6.6-dev/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"

if wget -qO 10_enable_susfs_for_ksu.patch "$PATCH_URL"; then
    echo "  -> Downloaded patch successfully!"
else
    echo "[-] CRITICAL: Failed to download the SuSFS patch (HTTP Error). URL may be invalid."
    exit 1
fi

echo ">>> 3. Applying SuSFS patch dynamically..."
patch -p1 < 10_enable_susfs_for_ksu.patch || {
    echo "[-] CRITICAL: Failed to apply Simonpunk's SuSFS patch!"
    echo ">>> Dumping downloaded file contents to verify it isn't an HTML error page:"
    head -n 20 10_enable_susfs_for_ksu.patch
    exit 1
}

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

# Clean up the patch file to keep the directory pristine
rm 10_enable_susfs_for_ksu.patch

# Step back out to kernel_workspace so the main router can finish
cd ..

echo ">>> Standard KernelSU injection complete."

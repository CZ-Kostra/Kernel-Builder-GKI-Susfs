#!/usr/bin/env bash
# scripts/inject_ReSukiSU.sh
# Dynamic SuSFS integration module for ReSukiSU (and SukiSU-Ultra)

echo ">>> Executing Integration Module for ${VARIANT}..."

echo ">>> 1. Cloning pristine official ${VARIANT} upstream..."
git clone "https://github.com/${VARIANT}/${VARIANT}.git" "${MANAGER_DIR}"

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
UPSTREAM_HASH=$(git log -n 1 --format="%H" -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
UPSTREAM_BRANCH="main"

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: $UPSTREAM_HASH"
echo "  -> Target Count: $CALCULATED_COUNT"

# ========================================================================
# KLEAF BYPASS & KCONFIG INJECTION (Robust sed strategy)
# ========================================================================
echo ">>> 2. Applying dynamic Kleaf bypass & Kconfig overrides..."

# 1. Modify Kconfig to force KSU_SUSFS as default and hide the other options
sed -i 's/default KSU_TRACEPOINT_HOOK/default KSU_SUSFS/g' kernel/Kconfig
sed -i 's/bool "Tracepoint Syscall Redirect"/bool "Tracepoint Syscall Redirect"\n\t\tdepends on n/g' kernel/Kconfig
sed -i 's/depends on KSU != m/depends on n/g' kernel/Kconfig

# 2. Modify Kbuild to bypass the strict sandbox test -e check
# We force the 'ifeq' to (0,0) so it always evaluates as true and extracts the SUSFS_VERSION
sed -i 's/ifeq ($(shell test -e $(srctree)\/fs\/susfs.c.*/ifeq (0,0)/g' kernel/Kbuild

# Silence the 'cat' error if the susfs.h file is temporarily hidden by the Kleaf sandbox
sed -i 's/cat $(srctree)\/include\/linux\/susfs.h |/cat $(srctree)\/include\/linux\/susfs.h 2>\/dev\/null |/g' kernel/Kbuild

echo ">>> 3. Kleaf bypass applied successfully."

# Step back out to kernel_workspace
cd .. 

echo ">>> ${VARIANT} integration complete."

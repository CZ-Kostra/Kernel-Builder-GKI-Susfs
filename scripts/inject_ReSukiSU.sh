#!/usr/bin/env bash
# scripts/inject_ReSukiSU.sh

echo ">>> Executing Integration Module for ReSukiSU..."

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> 1. Cloning pristine official ReSukiSU upstream..."
    git clone https://github.com/ReSukiSU/ReSukiSU.git "${MANAGER_DIR}"
    
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" main
    cd ..
    
    cd "${MANAGER_DIR}"
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
    UPSTREAM_BRANCH="main"

    echo ">>> 2. Applying dynamic Kleaf bypass & Kconfig overrides..."
    sed -i 's/default KSU_TRACEPOINT_HOOK/default KSU_SUSFS/g' kernel/Kconfig
    sed -i 's/bool "Tracepoint Syscall Redirect"/bool "Tracepoint Syscall Redirect"\n\t\tdepends on n/g' kernel/Kconfig
    sed -i 's/depends on KSU != m/depends on n/g' kernel/Kconfig
    sed -i 's/ifeq ($(shell test -e $(srctree)\/fs\/susfs.c.*/ifeq (0,0)/g' kernel/Kbuild
    sed -i 's/cat $(srctree)\/include\/linux\/susfs.h |/cat $(srctree)\/include\/linux\/susfs.h 2>\/dev\/null |/g' kernel/Kbuild
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
echo ">>> ReSukiSU integration complete."

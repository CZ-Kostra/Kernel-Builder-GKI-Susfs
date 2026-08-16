#!/usr/bin/env bash
# scripts/inject_SukiSU-Ultra.sh

echo ">>> Executing Integration Module for SukiSU-Ultra..."

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> 1. Cloning pristine official SukiSU-Ultra upstream..."
    git clone https://github.com/SukiSU-Ultra/SukiSU-Ultra.git "${MANAGER_DIR}"
    
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" main
    cd ..
    
    cd "${MANAGER_DIR}"
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -- . ":!website/" ":!docs/" ":!*.md" ":!.github/")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
    UPSTREAM_BRANCH="main"

    echo ">>> 2. Fetching 'builtin' branch for SuSFS code transplant..."
    git fetch origin builtin:builtin
    git checkout builtin

    rm -rf uapi
    mv kernel/include/uapi uapi 2>/dev/null || true
    cd kernel/include
    ln -s ../../uapi uapi
    cd ../..
    mv kernel/Makefile kernel/Kbuild 2>/dev/null || true

    git add uapi kernel/
    git config --global user.email "runner@github.actions"
    git config --global user.name "GitHub Actions Canary"
    git commit -m "chore: CI structural fixes (symlinks and Kbuild)"

    echo ">>> 3. Generating filtered SuSFS patch..."
    git checkout main
    git diff --diff-filter=AM main..builtin -- kernel/ uapi/ \
      ':!kernel/.clangd' \
      ':!kernel/.clang-format' \
      ':!kernel/.gitignore' \
      ':!.gitignore' > susfs_port_clean.patch

    echo ">>> 4. Applying surgical SuSFS port patch to main..."
    git apply susfs_port_clean.patch
    rm susfs_port_clean.patch
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
echo ">>> SukiSU-Ultra integration complete."

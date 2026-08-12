#!/usr/bin/env bash
# scripts/inject_SukiSU-Ultra.sh
# Dynamic SuSFS integration module for SukiSU-Ultra (Builtin -> Main Transplant)

echo ">>> Executing Integration Module for SukiSU-Ultra..."

echo ">>> 1. Cloning pristine official SukiSU-Ultra upstream..."
git clone "https://github.com/SukiSU-Ultra/SukiSU-Ultra.git" "${MANAGER_DIR}"

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
# DYNAMIC SuSFS TRANSPLANT (From cheat sheet)
# ========================================================================
if [ "${INTEGRATE_SUSFS}" == "true" ]; then
echo ">>> 2. Fetching 'builtin' branch for SuSFS code transplant..."
git fetch origin builtin:builtin

echo ">>> 3. Structuring 'builtin' branch for clean diffing..."
git checkout builtin

# Fix the symlink structure and Kbuild exactly as requested
rm -rf uapi
mv kernel/include/uapi uapi 2>/dev/null || true
cd kernel/include
ln -s ../../uapi uapi
cd ../..
mv kernel/Makefile kernel/Kbuild 2>/dev/null || true

# Stage and commit structural changes locally to create a clean diff
git add uapi kernel/
git config --global user.email "runner@github.actions"
git config --global user.name "GitHub Actions Canary"
git commit -m "chore: CI structural fixes (symlinks and Kbuild)"

echo ">>> 4. Generating filtered SuSFS patch..."
git checkout main
git diff --diff-filter=AM main..builtin -- kernel/ uapi/ \
  ':!kernel/.clangd' \
  ':!kernel/.clang-format' \
  ':!kernel/.gitignore' \
  ':!.gitignore' > susfs_port_clean.patch

echo ">>> 5. Applying surgical SuSFS port patch to main..."
git apply susfs_port_clean.patch
rm susfs_port_clean.patch
fi

# Step back out to kernel_workspace
cd .. 

echo ">>> SukiSU-Ultra integration complete."

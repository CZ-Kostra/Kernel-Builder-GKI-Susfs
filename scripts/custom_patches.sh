#!/usr/bin/env bash
# scripts/custom_patches.sh
# Source code modifications and C/Header tweaks
# (Note: Kconfig modifications belong in scripts/configure_kconfigs.sh via Bazel fragments)

set -euo pipefail

echo ">>> Applying custom source code patches..."

# cd kernel_workspace/common

# ========================================================================
# PLACEHOLDER: Add your raw source code modifications here
# ========================================================================

# Example 1: Suppressing a specific noisy driver warning in source
# sed -i 's/pr_warn("noisy driver warning/pr_debug("noisy driver warning/' drivers/misc/noisy_driver.c

# Example 2: Hardcoding an aggressive compiler flag into a specific subsystem
# echo "ccflags-y += -O3" >> fs/Makefile

echo ">>> Source code customizations complete."

#!/bin/bash
# scripts/custom_patches.sh
# Router script to delegate patching to variant-specific modular scripts.

set -euo pipefail

echo ">>> Evaluating target variant: ${SU_VARIANT}"

# Map directly to the exact variant name
SCRIPT_PATH="scripts/patchfix_${SU_VARIANT}.sh"

if [ -f "$SCRIPT_PATH" ]; then
    echo ">>> Delegating to modular patch script: $SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    exec bash "$SCRIPT_PATH"
else
    echo "[-] No modular script found at $SCRIPT_PATH! Proceeding without custom patches."
fi

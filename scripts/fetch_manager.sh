#!/bin/bash
# scripts/fetch_manager.sh

set -euo pipefail

VARIANT="${1}"
GH_TOKEN="${2}"
UPSTREAM_HASH="${3:-}" # Optional: Not needed for ZeroMount

# ==========================================
# ZEROMOUNT FETCH LOGIC (Releases API)
# ==========================================
if [[ "${VARIANT}" == "ZeroMount" ]]; then
  echo ">>> Fetching latest ZeroMount release from Enginex0/zeromount..."
  
  LATEST_JSON=$(curl -s -H "Authorization: token $GH_TOKEN" "https://api.github.com/repos/Enginex0/zeromount/releases/latest")
  DOWNLOAD_URL=$(echo "$LATEST_JSON" | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' | head -n 1)
  
  if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    echo "[-] Failed to find a ZeroMount module zip in the latest release."
    exit 1
  fi
  
  echo ">>> Downloading $DOWNLOAD_URL..."
  mkdir -p zeromount_module
  FILE_NAME=$(basename "$DOWNLOAD_URL")
  curl -s -L -H "Authorization: token $GH_TOKEN" -o "zeromount_module/$FILE_NAME" "$DOWNLOAD_URL"
  
  echo ">>> Extracting ZeroMount module to prevent double-zipping..."
  unzip -q -o "zeromount_module/$FILE_NAME" -d zeromount_module/
  rm "zeromount_module/$FILE_NAME"
  
  echo ">>> ZeroMount successfully staged for final upload!"
  exit 0
fi

# ==========================================
# ROOT MANAGER FETCH LOGIC (Artifacts API)
# ==========================================
echo ">>> Mapping selected variant to upstream repository..."
if [[ "${VARIANT}" == "KernelSU-Next" ]]; then
    REPO="KernelSU-Next/KernelSU-Next"
elif [[ "${VARIANT}" == "SukiSU-Ultra" ]]; then
    REPO="SukiSU-Ultra/SukiSU-Ultra"
elif [[ "${VARIANT}" == "ReSukiSU" ]]; then
    REPO="ReSukiSU/ReSukiSU"
elif [[ "${VARIANT}" == "KernelSU" ]]; then
    REPO="tiann/KernelSU"
else
    echo "[-] Error: Unsupported Variant '${VARIANT}'. Vanilla KernelSU is deprecated." >&2
    exit 1
fi

echo ">>> Searching $REPO for a Release Manager..."

DOWNLOAD_URLS=""

# ==========================================
# 1. EXACT MATCH (Immune to dependabot spam)
# ==========================================
echo ">>> Checking for exact upstream hash: ${UPSTREAM_HASH}"
EXACT_RUNS=$(curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/$REPO/actions/runs?head_sha=${UPSTREAM_HASH}&status=success&per_page=50")

RUN_IDS=$(echo "$EXACT_RUNS" | jq -r '.workflow_runs[]?.id // empty')

for ID in $RUN_IDS; do
    echo ">>> Checking exact-match Run ID: $ID for artifacts..."
    ARTIFACTS_JSON=$(curl -s -H "Authorization: token $GH_TOKEN" \
      "https://api.github.com/repos/$REPO/actions/runs/$ID/artifacts")
    
    # Action Artifacts are always ZIPs. Prepends 'ARTIFACT|' for the download loop.
    DOWNLOAD_URLS=$(echo "$ARTIFACTS_JSON" | jq -r '
      .artifacts[]? 
      | select(.name | test("(?i)manager"))
      | select(.name | test("(?i)(debug|mappings|gradle)") | not)
      | select(.name | test("(?i)(armeabi-v7a|universal|x86_64)") | not)
      | select(.expired == false)
      | "ARTIFACT|\(.archive_download_url)" // empty')

    if [ -n "$DOWNLOAD_URLS" ]; then
        echo ">>> Success! Found unexpired exact Manager artifacts in Run ID: $ID"
        break
    fi
done

# ==========================================
# 2. THE LATEST RELEASE FALLBACK 
# ==========================================
if [ -z "$DOWNLOAD_URLS" ]; then
    echo "[-] Exact match missing or expired. Fetching the latest release tag as fallback..."
    
    LATEST_RELEASE=$(curl -s -H "Authorization: token $GH_TOKEN" \
      "https://api.github.com/repos/$REPO/releases/latest")
    
    # Identifies if the release asset is a .zip or .apk and tags it accordingly.
    DOWNLOAD_URLS=$(echo "$LATEST_RELEASE" | jq -r '
      .assets[]? 
      | select(.name | test("(?i)manager"))
      | select(.name | test("(?i)(debug|mappings|gradle)") | not)
      | select(.name | test("(?i)(armeabi-v7a|universal|x86_64)") | not)
      | if (.name | test("(?i)\\.zip$")) then "RELEASE_ZIP|\(.url)" else "RELEASE_APK|\(.url)" end')
      
    if [ -n "$DOWNLOAD_URLS" ]; then
        echo ">>> Success! Found fallback Manager asset(s) in the latest release."
    fi
fi

# ==========================================
# 3. DOWNLOAD & CLEANUP
# ==========================================
if [ -z "$DOWNLOAD_URLS" ]; then
    echo "[-] Critical: Exhausted search. Failed to locate ANY valid Manager artifacts or release assets for $REPO."
    exit 1
fi

mkdir -p manager_apk
COUNTER=1

# Change IFS so bash correctly handles entries with spaces or newlines
IFS=$'\n'
for ENTRY in $DOWNLOAD_URLS; do
  # Split the tag and the URL
  TYPE=$(echo "$ENTRY" | cut -d'|' -f1)
  URL=$(echo "$ENTRY" | cut -d'|' -f2)
  
  if [ "$TYPE" == "RELEASE_APK" ]; then
      echo ">>> Downloading standalone release APK $COUNTER..."
      curl -s -L \
        -H "Authorization: token $GH_TOKEN" \
        -o "manager_apk/manager_${COUNTER}.apk" "$URL"
        
  elif [[ "$TYPE" == *"ZIP"* ]] || [[ "$TYPE" == "ARTIFACT" ]]; then
      echo ">>> Downloading ZIP archive $COUNTER..."
      curl -s -L \
        -H "Authorization: token $GH_TOKEN" \
        -o "manager_${COUNTER}.zip" "$URL"
      
      echo ">>> Extracting archive..."
      unzip -q -o "manager_${COUNTER}.zip" -d manager_apk/
      rm "manager_${COUNTER}.zip"
  fi
  
  COUNTER=$((COUNTER+1))
done
unset IFS

echo ">>> Cleaning up unnecessary architectures..."
find manager_apk/ -type f \( -name "*armeabi-v7a*" -o -name "*universal*" -o -name "*x86_64*" \) -exec rm -f {} +

echo ">>> Manager(s) successfully staged for final upload!"
ls -1 manager_apk/


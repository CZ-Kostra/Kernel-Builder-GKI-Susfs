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
    
    # Only grab the URL if the artifact is explicitly NOT expired
    DOWNLOAD_URLS=$(echo "$ARTIFACTS_JSON" | jq -r '
      .artifacts[]? 
      | select(.name | test("(?i)(SukiSU|KernelSU|manager|spoof)")) 
      | select(.expired == false)
      | .archive_download_url // empty')
      
    if [ -n "$DOWNLOAD_URLS" ]; then
        echo ">>> Success! Found unexpired exact Manager artifacts in Run ID: $ID"
        break
    fi
done

# ==========================================
# 2. THE PAGINATED FALLBACK 
# ==========================================
if [ -z "$DOWNLOAD_URLS" ]; then
    echo "[-] Exact match missing or expired. Initiating deep search for the latest valid Manager..."
    
    PAGE=1
    MAX_PAGES=5 # Max 250 runs (Prevents infinite loops on empty repos)
    
    while [ $PAGE -le $MAX_PAGES ]; do
        echo ">>> Fetching Fallback Page $PAGE..."
        RECENT_RUNS=$(curl -s -H "Authorization: token $GH_TOKEN" \
          "https://api.github.com/repos/$REPO/actions/runs?status=success&per_page=50&page=$PAGE")
        
        FALLBACK_IDS=$(echo "$RECENT_RUNS" | jq -r '.workflow_runs[]?.id // empty')
        
        # Break out completely if we run out of history
        if [ -z "$FALLBACK_IDS" ]; then break; fi
        
        for ID in $FALLBACK_IDS; do
            echo "    -> Inspecting fallback Run ID: $ID..."
            ARTIFACTS_JSON=$(curl -s -H "Authorization: token $GH_TOKEN" \
              "https://api.github.com/repos/$REPO/actions/runs/$ID/artifacts")
            
            # Check if we hit the chronological 90-day wall
            IS_EXPIRED=$(echo "$ARTIFACTS_JSON" | jq -r '
              .artifacts[]? 
              | select(.name | test("(?i)(SukiSU|KernelSU|manager|spoof)"))
              | .expired // empty' | head -n 1)
              
            if [ "$IS_EXPIRED" == "true" ]; then
                echo "[-] Hit the 90-day expiration wall. Aborting deep search."
                break 2 # Breaks out of both the FOR loop and the WHILE loop
            fi
            
            # Look for a valid, unexpired download URL
            DOWNLOAD_URLS=$(echo "$ARTIFACTS_JSON" | jq -r '
              .artifacts[]? 
              | select(.name | test("(?i)(SukiSU|KernelSU|manager|spoof)")) 
              | select(.expired == false)
              | .archive_download_url // empty')
              
            if [ -n "$DOWNLOAD_URLS" ]; then
                echo ">>> Success! Found fallback Manager artifacts in Run ID: $ID"
                break 2 # Breaks out of both loops
            fi
        done
        
        PAGE=$((PAGE+1))
    done
fi

# Final sanity check before downloading
if [ -z "$DOWNLOAD_URLS" ]; then
    echo "[-] Critical: Exhausted search. Failed to locate ANY valid Manager artifacts for $REPO."
    exit 1
fi

mkdir -p manager_apk
COUNTER=1

# Change IFS so bash correctly handles URLs with spaces or newlines
IFS=$'\n'
for URL in $DOWNLOAD_URLS; do
  echo ">>> Downloading artifact $COUNTER..."
  curl -s -L -H "Authorization: token $GH_TOKEN" -o manager_${COUNTER}.zip "$URL"
  
  echo ">>> Extracting..."
  unzip -q -o manager_${COUNTER}.zip -d manager_apk/
  rm manager_${COUNTER}.zip
  
  COUNTER=$((COUNTER+1))
done
unset IFS

echo ">>> Cleaning up unnecessary architectures..."
find manager_apk/ -type f \( -name "*x86*.apk" -o -name "*armeabi-v7a*.apk" -o -name "*universal*.apk" \) -exec rm -f {} +

echo ">>> Manager(s) successfully staged for final upload!"
ls -1 manager_apk/

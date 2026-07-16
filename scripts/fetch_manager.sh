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
      | select(.name | test("(?i)manager"))
      | select(.name | test("(?i)gradle") | not)
      | select(.expired == false)
      | .archive_download_url // empty')

    if [ -n "$DOWNLOAD_URLS" ]; then
        echo ">>> Success! Found unexpired exact Manager artifacts in Run ID: $ID"
        break
    fi
done
# ==========================================
# 2. THE RELEASE TAG BRIDGE (For expired artifacts)
# ==========================================
if [ -z "$DOWNLOAD_URLS" ]; then
    echo "[-] Exact match artifacts missing/expired. Checking GitHub Releases for pinned commit..."
    
    # 1. Dynamically hunt for a Tag anchored to this exact commit hash
    # The ^{} strips the annotated tag pointer to reveal the true underlying commit hash
    TAG_NAME=$(git ls-remote --tags "https://github.com/${REPO}.git" | grep "${UPSTREAM_HASH}" | awk '{print $2}' | sed 's/\^{}//' | sed 's/refs\/tags\///' | head -n 1)
    
    if [ -n "$TAG_NAME" ]; then
        echo ">>> Found official Release Tag: $TAG_NAME. Fetching Release assets..."
        RELEASE_JSON=$(curl -s -H "Authorization: token $GH_TOKEN" \
          "https://api.github.com/repos/$REPO/releases/tags/$TAG_NAME")
        
        # 2. Extract raw APK URLs directly from the release (Pre-filtering out debug builds!)
        RELEASE_APK_URLS=$(echo "$RELEASE_JSON" | jq -r '
          .assets[]? 
          | select(.name | test("(?i)\\.apk$"))
          | select(.name | test("(?i)debug") | not)
          | .browser_download_url // empty')
          
        if [ -n "$RELEASE_APK_URLS" ]; then
            echo ">>> Success! Found Release APKs."
            mkdir -p manager_apk
            
            IFS=$'\n'
            for URL in $RELEASE_APK_URLS; do
                APK_NAME=$(basename "$URL")
                echo "  -> Downloading: $APK_NAME"
                curl -s -L -H "Authorization: token $GH_TOKEN" -o "manager_apk/$APK_NAME" "$URL"
            done
            unset IFS
            
            # Set a flag so we know we bypassed zip artifacts and don't need to unzip later
            RELEASE_MODE_SUCCESS=true
        else
            echo "[-] Tag found, but no APKs attached to the release."
        fi
    else
        echo "[-] No Release Tag found for this commit."
    fi
fi

# ==========================================
# 3. THE PAGINATED FALLBACK (Last Resort)
# ==========================================
if [ -z "$DOWNLOAD_URLS" ] && [ "${RELEASE_MODE_SUCCESS:-false}" != "true" ]; then
    echo "[-] Fallback to deep chronological search for the latest valid Manager..."
    
    PAGE=1
    MAX_PAGES=5 # Max 250 runs (Prevents infinite loops)
    
    while [ $PAGE -le $MAX_PAGES ]; do
        echo ">>> Fetching Fallback Page $PAGE..."
        RECENT_RUNS=$(curl -s -H "Authorization: token $GH_TOKEN" \
          "https://api.github.com/repos/$REPO/actions/runs?status=success&per_page=50&page=$PAGE")
        
        FALLBACK_IDS=$(echo "$RECENT_RUNS" | jq -r '.workflow_runs[]?.id // empty')
        
        if [ -z "$FALLBACK_IDS" ]; then break; fi
        
        for ID in $FALLBACK_IDS; do
            echo "    -> Inspecting fallback Run ID: $ID..."
            ARTIFACTS_JSON=$(curl -s -H "Authorization: token $GH_TOKEN" \
              "https://api.github.com/repos/$REPO/actions/runs/$ID/artifacts")
            
            IS_EXPIRED=$(echo "$ARTIFACTS_JSON" | jq -r '
              .artifacts[]? 
              | select(.name | test("(?i)(SukiSU|KernelSU|manager|spoof)"))
              | .expired // empty' | head -n 1)
              
            if [ "$IS_EXPIRED" == "true" ]; then
                echo "[-] Hit the 90-day expiration wall. Aborting deep search."
                break 2
            fi
            
            DOWNLOAD_URLS=$(echo "$ARTIFACTS_JSON" | jq -r '
              .artifacts[]? 
              | select(.name | test("(?i)(SukiSU|KernelSU|manager|spoof)")) 
              | select(.expired == false)
              | .archive_download_url // empty')
              
            if [ -n "$DOWNLOAD_URLS" ]; then
                echo ">>> Success! Found fallback Manager artifacts in Run ID: $ID"
                break 2
            fi
        done
        
        PAGE=$((PAGE+1))
    done
fi

# ==========================================
# 4. DOWNLOAD & EXTRACT ZIP ARTIFACTS
# ==========================================
# Only execute this block if we DID NOT already download raw APKs directly from a Release
if [ "${RELEASE_MODE_SUCCESS:-false}" != "true" ] && [ -n "$DOWNLOAD_URLS" ]; then
    mkdir -p manager_apk
    COUNTER=1

    IFS=$'\n'
    for URL in $DOWNLOAD_URLS; do
      echo ">>> Downloading artifact archive $COUNTER..."
      curl -s -L -H "Authorization: token $GH_TOKEN" -o manager_${COUNTER}.zip "$URL"
      
      echo ">>> Extracting..."
      unzip -q -o manager_${COUNTER}.zip -d manager_apk/
      rm manager_${COUNTER}.zip
      
      COUNTER=$((COUNTER+1))
    done
    unset IFS
fi

# ==========================================
# 5. AGGRESSIVE ARCHITECTURE & DEBUG CLEANUP
# ==========================================
echo ">>> Cleaning up unnecessary architectures & debug builds..."

# We added '-o -name "*debug*.apk"' to instantly trash the debug versions!
find manager_apk/ -type f \( -name "*x86*.apk" -o -name "*armeabi-v7a*.apk" -o -name "*universal*.apk" -o -name "*debug*.apk" \) -exec rm -f {} +

echo ">>> Manager(s) successfully staged for final upload!"
ls -1 manager_apk/




#!/bin/bash
set -euo pipefail

# ── Repo-root resolution ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"
if [ ! -d "CustomRobots" ] || [ ! -f "CustomRobots/CMakeLists.txt" ]; then
    echo "Error: not in RoboticsInfrastructure repo root" >&2
    exit 1
fi

# Output colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Base URL for Fuel
FUEL_BASE="https://fuel.gazebosim.org/1.0/OpenRobotics/models"

# Models to fetch (name -> dest subdirectory)
declare -A MODELS=(
  ["Cave Straight 02 Type B"]="tiles/cave_straight"
  ["Cave Corner 01 Type B"]="tiles/cave_corner_01"
  ["Cave Corner 02 Type A"]="tiles/cave_corner_02"
  ["Cave Cap Type A"]="tiles/cave_cap"
  ["Cave 3 Way 01 Lights Type B"]="tiles/cave_3way"
  ["Cave Vertical Shaft Lights Type B"]="tiles/cave_shaft"
  ["Mine Cart"]="props/mine_cart"
  ["Mine Cart Engine"]="props/mine_cart_engine"
)

BASE_DIR="CustomRobots/mine_inspection/models"
mkdir -p "$BASE_DIR"

downloaded=0
skipped=0
failed=0

# URL encode via Python 3
urlencode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
}

# Download file function with idempotency check
download_file() {
  local model_name="$1"
  local file_path="$2"
  local dest_dir="$3"

  # Remove leading slash if any
  file_path="${file_path#/}"

  local encoded_model
  encoded_model=$(urlencode "$model_name")

  local encoded_path
  encoded_path=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$file_path")

  local url="${FUEL_BASE}/${encoded_model}/tip/files/${encoded_path}"
  local dest_path="${dest_dir}/${file_path}"

  if [ -f "$dest_path" ]; then
    echo -e "${YELLOW}[WARN] Skipped (already exists): ${file_path}${NC}"
    skipped=$((skipped + 1)) ; :
    return 0
  fi

  mkdir -p "$(dirname "$dest_path")"

  local http_code
  http_code=$(curl -s -L -w "%{http_code}" -o "$dest_path" "$url" 2>/dev/null || echo "000")

  if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}[OK] Downloaded: ${file_path}${NC}"
    downloaded=$((downloaded + 1)) ; :
    return 0
  else
    rm -f "$dest_path"
    return 1
  fi
}

for model in "${!MODELS[@]}"; do
  sub_dir="${MODELS[$model]}"
  dest_dir="${BASE_DIR}/${sub_dir}"

  echo -e "\nProcessing model: $model -> $sub_dir"

  # 1. Download base configuration files
  for base_file in "model.config" "model.sdf"; do
    if ! download_file "$model" "$base_file" "$dest_dir"; then
      echo -e "${RED}[ERR] Failed to download ${base_file} for ${model}${NC}"
      failed=$((failed + 1)) ; :
    fi
  done

  # 2. Get the manifest API JSON
  encoded_model=$(urlencode "$model")
  manifest_url="${FUEL_BASE}/${encoded_model}/tip/files"
  manifest_json=$(curl -s -L "$manifest_url" 2>/dev/null || echo "")

  # Validate manifest JSON before use
  if [ -z "$manifest_json" ] || \
     ! echo "$manifest_json" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
      echo -e "${RED}[ERR] Could not fetch manifest for ${model}${NC}"
      failed=$((failed + 1)) ; :
      continue
  fi

  # 3. Extract paths from manifest for meshes/ and materials/
  manifest_files=$(python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    def extract_paths(node):
        paths = []
        if 'children' in node:
            for child in node['children']:
                paths.extend(extract_paths(child))
        elif 'path' in node:
            paths.append(node['path'])
        return paths

    all_paths = []
    file_tree = data.get('file_tree', [])
    for item in file_tree:
        all_paths.extend(extract_paths(item))

    for p in all_paths:
        if p.startswith('/'):
            p = p[1:]
        if p.startswith('meshes/') or p.startswith('materials/'):
            print(p)
except Exception as e:
    pass
" <<< "$manifest_json")

  # 4. Download all mesh/material files from manifest (source of truth)
  old_IFS=$IFS
  IFS=$'\n'
  for file in $manifest_files; do
    if [ -z "$file" ]; then continue; fi
    download_file "$model" "$file" "$dest_dir" || {
      echo -e "${RED}[ERR] Failed to download ${file} for ${model}${NC}"
      failed=$((failed + 1)) ; :
    }
  done
  IFS=$old_IFS
done

# ── Generate SHA-256 manifest ────────────────────────────────────────────────
MODEL_DIR="CustomRobots/mine_inspection/models"
MANIFEST_PATH="CustomRobots/mine_inspection/LICENSES/MANIFEST.sha256"
mkdir -p "$(dirname "$MANIFEST_PATH")"

echo ""
echo "Generating MANIFEST.sha256..."
find "$MODEL_DIR" -type f \
    \( -name "*.dae" -o -name "*.sdf" -o -name "*.config" \
       -o -name "*.material" -o -name "*.png" -o -name "*.jpg" \) \
    -print0 | sort -z | xargs -0 sha256sum \
    | sed "s|  $MODEL_DIR/|  |g" > "$MANIFEST_PATH"

echo "Manifest: $(wc -l < "$MANIFEST_PATH") files"

# ── Write NOTICE ─────────────────────────────────────────────────────────────
NOTICE_PATH="CustomRobots/mine_inspection/LICENSES/NOTICE"
cat > "$NOTICE_PATH" <<'EOF'
mine_inspection — vendored assets
==================================

The following 3D models under CustomRobots/mine_inspection/models/ are
redistributed from Gazebo Fuel and are the work of Open Robotics.

  Source:    https://fuel.gazebosim.org/1.0/OpenRobotics/models/<name>
  License:   Creative Commons Attribution 4.0 International (CC BY 4.0)
             https://creativecommons.org/licenses/by/4.0/
  Author:    Open Robotics

Vendored models:
  Cave Straight 02 Type B
  Cave Corner 01 Type B
  Cave Corner 02 Type A
  Cave Cap Type A
  Cave 3 Way 01 Lights Type B
  Cave Vertical Shaft Lights Type B
  Mine Cart
  Mine Cart Engine

No modifications have been made to the vendored assets. See
MANIFEST.sha256 for byte-exact verification.
EOF
echo -e "${GREEN}[OK] NOTICE written${NC}"

echo ""
echo "Summary: $downloaded files downloaded, $skipped skipped (already exist), $failed failed"
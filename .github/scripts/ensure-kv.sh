#!/usr/bin/env bash
# Ensure the GLM_TOKENS KV namespace exists and its ID is injected into wrangler.toml.
# Requires CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID to be set.

set -euo pipefail

KV_BINDING="GLM_TOKENS"
BOOTSTRAP_NAME="kv-bootstrap"

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "CLOUDFLARE_API_TOKEN is empty. Please set it in GitHub Secrets."
  exit 1
fi

if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  echo "CLOUDFLARE_ACCOUNT_ID is empty. Please set it in GitHub Variables or Secrets."
  exit 1
fi

current_id=$(awk -F'"' '/binding = "GLM_TOKENS"/{found=1} found && /^id = "/{print $4; exit}' wrangler.toml)

if [ -n "$current_id" ]; then
  echo "KV namespace already configured with id=$current_id"
  exit 0
fi

# Use a temporary minimal wrangler config to avoid validating kv_namespaces.id="" in project wrangler.toml.
tmp_config=$(mktemp)
cat > "$tmp_config" <<EOF
name = "$BOOTSTRAP_NAME"
main = "src/index.ts"
compatibility_date = "2024-05-12"
EOF

cleanup() {
  rm -f "$tmp_config"
}
trap cleanup EXIT

extract_id_from_text() {
  # 1) JSON: "id": "..."
  local id
  id=$(echo "$1" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  if [ -n "$id" ]; then
    echo "$id"
    return
  fi
  # 2) TOML-ish: id = "..."
  id=$(echo "$1" | sed -n 's/.*id = "\([^"]*\)".*/\1/p' | head -1)
  echo "$id"
}

echo "Checking existing KV namespace for binding '$KV_BINDING' ..."
set +e
list_output=$(npx wrangler --config "$tmp_config" kv namespace list 2>&1)
list_status=$?
set -e

echo "$list_output"

if [ $list_status -eq 0 ]; then
  # Try common titles in priority order.
  existing_id=$(echo "$list_output" | sed -n '/"title"[[:space:]]*:[[:space:]]*"kv-bootstrap-GLM_TOKENS"/,/}/s/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  if [ -z "$existing_id" ]; then
    existing_id=$(echo "$list_output" | sed -n '/"title"[[:space:]]*:[[:space:]]*"worker-GLM_TOKENS"/,/}/s/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  fi
  if [ -z "$existing_id" ]; then
    existing_id=$(echo "$list_output" | sed -n '/"title"[[:space:]]*:[[:space:]]*"glm-free-api-worker-GLM_TOKENS"/,/}/s/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  fi

  if [ -n "$existing_id" ]; then
    echo "Found existing KV namespace id=$existing_id"
    sed -i "s/^id = \".*\"/id = \"$existing_id\"/" wrangler.toml
    exit 0
  fi
fi

echo "Creating KV namespace '$KV_BINDING' ..."
set +e
create_output=$(npx wrangler --config "$tmp_config" kv namespace create "$KV_BINDING" 2>&1)
create_status=$?
set -e

echo "$create_output"

if [ $create_status -ne 0 ]; then
  if echo "$create_output" | grep -qiE 'already exists|code:[[:space:]]*10014'; then
    echo "Namespace already exists. Resolving its id via list..."
    set +e
    list_output=$(npx wrangler --config "$tmp_config" kv namespace list 2>&1)
    list_status=$?
    set -e
    echo "$list_output"
    if [ $list_status -eq 0 ]; then
      existing_id=$(echo "$list_output" | sed -n '/"title"[[:space:]]*:[[:space:]]*"kv-bootstrap-GLM_TOKENS"/,/}/s/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
      if [ -z "$existing_id" ]; then
        existing_id=$(echo "$list_output" | sed -n '/"title"[[:space:]]*:[[:space:]]*"worker-GLM_TOKENS"/,/}/s/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
      fi
      if [ -z "$existing_id" ]; then
        existing_id=$(echo "$list_output" | sed -n '/"title"[[:space:]]*:[[:space:]]*"glm-free-api-worker-GLM_TOKENS"/,/}/s/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
      fi
      if [ -n "$existing_id" ]; then
        echo "Resolved existing KV namespace id=$existing_id"
        sed -i "s/^id = \".*\"/id = \"$existing_id\"/" wrangler.toml
        exit 0
      fi
    fi
  fi

  echo "Failed to create KV namespace."
  exit $create_status
fi

kv_id=$(extract_id_from_text "$create_output")

if [ -z "$kv_id" ]; then
  echo "Failed to extract KV namespace ID from output:"
  echo "$create_output"
  exit 1
fi

echo "Patching id=$kv_id into wrangler.toml"
sed -i "s/^id = \".*\"/id = \"$kv_id\"/" wrangler.toml

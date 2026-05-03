#!/usr/bin/env bash
# Ensure the GLM_TOKENS KV namespace exists and its ID is injected into wrangler.toml.
# Requires CLOUDFLARE_API_TOKEN to be set.

set -euo pipefail

KV_BINDING="GLM_TOKENS"

current_id=$(awk -F'"' '/binding = "GLM_TOKENS"/{found=1} found && /^id = "/{print $4; exit}' wrangler.toml)

if [ -n "$current_id" ]; then
  echo "KV namespace already configured with id=$current_id"
  exit 0
fi

echo "Creating KV namespace '$KV_BINDING' ..."
output=$(npx wrangler kv:namespace create "$KV_BINDING" --json 2>&1)
echo "$output"

kv_id=$(echo "$output" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"')

if [ -z "$kv_id" ]; then
  echo "Failed to extract KV namespace ID from output:"
  echo "$output"
  exit 1
fi

echo "Patching id=$kv_id into wrangler.toml"
sed -i "s/^id = \".*\"/id = \"$kv_id\"/" wrangler.toml

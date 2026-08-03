#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

mode="${1:---check}"
[[ "$mode" == "--check" || "$mode" == "--apply" ]] || {
  printf 'Usage: %s [--check|--apply]\n' "$0" >&2
  exit 2
}

for command in curl jq pnpm; do require_command "$command"; done
: "${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?Set CLOUDFLARE_ACCOUNT_ID}"
: "${CLOUDFLARE_ZONE_ID:?Set CLOUDFLARE_ZONE_ID}"

bucket="$(config_value '.bucket')"
hostname="$(config_value '.hostname')"
api="https://api.cloudflare.com/client/v4"
auth=(-H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H 'Content-Type: application/json')

api_request() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-fsS -X "$method" "${auth[@]}" "$api$path")
  [[ -z "$data" ]] || args+=(--data "$data")
  curl "${args[@]}"
}

if ! pnpm exec wrangler r2 bucket info "$bucket" >/dev/null 2>&1; then
  [[ "$mode" == "--apply" ]] || { printf 'R2 bucket is missing: %s\n' "$bucket" >&2; exit 1; }
  pnpm exec wrangler r2 bucket create "$bucket"
fi

custom_domains="$(api_request GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/$bucket/domains/custom")"
if ! jq -e --arg hostname "$hostname" \
  '.success and any(.result.domains[]?;
    .domain == $hostname and
    .enabled == true and
    .status.ownership == "active" and
    .status.ssl == "active")' \
  <<< "$custom_domains" >/dev/null; then
  [[ "$mode" == "--apply" ]] || { printf 'R2 custom domain is missing: %s\n' "$hostname" >&2; exit 1; }
  api_request POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/$bucket/domains/custom" "$(jq -cn --arg domain "$hostname" '{domain:$domain,enabled:true,zoneId:env.CLOUDFLARE_ZONE_ID}')" >/dev/null
fi

managed="$(api_request GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/$bucket/domains/managed")"
if ! jq -e '.success and (.result.enabled == false)' <<< "$managed" >/dev/null; then
  [[ "$mode" == "--apply" ]] || { printf 'Managed r2.dev domain is enabled\n' >&2; exit 1; }
  api_request PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/$bucket/domains/managed" '{"enabled":false}' >/dev/null
fi

if [[ "$mode" == "--apply" ]]; then
  api_request PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/$bucket/lifecycle" "$(< "$ROOT_DIR/config/r2-lifecycle.json")" >/dev/null
fi

printf 'R2 bucket and public-domain checks passed for %s\n' "$hostname"
printf 'Cache Rule drift is validated separately until the zone ruleset contract is implemented.\n'

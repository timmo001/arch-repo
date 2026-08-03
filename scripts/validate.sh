#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

for command in jq shellcheck; do require_command "$command"; done

jq -e . "$REPOSITORY_CONFIG" "$PACKAGE_CONFIG" \
  "$ROOT_DIR/config/cache-rule.json" \
  "$ROOT_DIR/config/r2-lifecycle.json" >/dev/null

while IFS= read -r script; do
  bash -n "$script"
done < <(find "$ROOT_DIR/scripts" -type f -name '*.sh' -print)

shellcheck -x -P "$ROOT_DIR/scripts" \
  "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/scripts/lib/*.sh

if [[ -e "$(public_key_file)" || -e "$(fingerprint_file)" ]]; then
  verify_public_key
else
  printf 'Signing key not created yet; key validation skipped\n'
fi

if [[ "${1:-}" == "--remote" ]]; then
  "$ROOT_DIR/scripts/health-check.sh"
fi

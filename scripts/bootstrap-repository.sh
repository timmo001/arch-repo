#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

for command in gpg jq repo-add; do require_command "$command"; done
verify_public_key
: "${ARCH_REPO_SIGNING_KEY:?Set ARCH_REPO_SIGNING_KEY to the signing key file}"

repository="$(config_value '.repository')"
architecture="$(config_value '.architectures[0]')"
work="$(mktemp -d)"
gnupg="$(mktemp -d)"
trap 'rm -rf "$work" "$gnupg"' EXIT
chmod 0700 "$gnupg"
export GNUPGHOME="$gnupg"
import_signing_key "$ARCH_REPO_SIGNING_KEY"

repo-add "$work/$repository.db.tar.zst"
ln -s "$repository.db.tar.zst" "$work/$repository.db"
ln -s "$repository.files.tar.zst" "$work/$repository.files"
mkdir -p "$work/recovery"
jq -n \
  --arg repository "$repository" \
  --arg architecture "$architecture" \
  --arg generatedAt "$(date --utc +%Y-%m-%dT%H:%M:%SZ)" \
  --arg signingFingerprint "$(normalised_fingerprint)" \
  '{schemaVersion:1,repository:$repository,architecture:$architecture,generatedAt:$generatedAt,workflowRun:null,signingFingerprint:$signingFingerprint,packages:[]}' \
  > "$work/recovery/current.json"
sign_file "$work/recovery/current.json"

printf 'Initial repository created at %s\n' "$work"
printf 'Upload is deliberately delegated to the publication workflow.\n'

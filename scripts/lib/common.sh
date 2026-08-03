#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC2034
REPOSITORY_CONFIG="$ROOT_DIR/config/repository.json"
export PACKAGE_CONFIG="$ROOT_DIR/config/packages.json"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command missing: %s\n' "$1" >&2
    exit 1
  }
}

config_value() {
  jq -er "$1" "$REPOSITORY_CONFIG"
}

fingerprint_file() {
  printf '%s/keys/FINGERPRINT\n' "$ROOT_DIR"
}

public_key_file() {
  printf '%s/keys/timmo-arch-repo.asc\n' "$ROOT_DIR"
}

require_key_material() {
  local key fingerprint
  key="$(public_key_file)"
  fingerprint="$(fingerprint_file)"
  [[ -s "$key" ]] || { printf 'Missing public key: %s\n' "$key" >&2; exit 1; }
  [[ -s "$fingerprint" ]] || { printf 'Missing fingerprint: %s\n' "$fingerprint" >&2; exit 1; }
}

normalised_fingerprint() {
  tr -d '[:space:]' < "$(fingerprint_file)" | tr '[:lower:]' '[:upper:]'
}

verify_public_key() {
  require_command gpg
  require_key_material
  local actual expected
  expected="$(normalised_fingerprint)"
  [[ "$expected" =~ ^[A-F0-9]{40}$ ]] || { printf 'Invalid configured fingerprint\n' >&2; exit 1; }
  actual="$(gpg --batch --with-colons --import-options show-only --import "$(public_key_file)" 2>/dev/null | awk -F: '$1 == "fpr" { print toupper($10); exit }')"
  [[ "$actual" == "$expected" ]] || { printf 'Public key fingerprint mismatch\n' >&2; exit 1; }
}

import_signing_key() {
  local signing_key="$1" expected secret_fingerprints
  expected="$(normalised_fingerprint)"
  gpg --batch --import "$signing_key" >/dev/null
  secret_fingerprints="$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print toupper($10) }')"
  grep -qx "$expected" <<< "$secret_fingerprints" || {
    printf 'Signing key does not contain the published primary fingerprint\n' >&2
    exit 1
  }
}

sign_file() {
  local file="$1"
  local args=(--batch --yes --local-user "$(normalised_fingerprint)" --detach-sign)
  if [[ -n "${ARCH_REPO_SIGNING_PASSPHRASE:-}" ]]; then
    args+=(--pinentry-mode loopback --passphrase-fd 0)
    printf '%s\n' "$ARCH_REPO_SIGNING_PASSPHRASE" | gpg "${args[@]}" "$file"
  else
    gpg "${args[@]}" "$file"
  fi
}

validate_object_key() {
  [[ "$1" =~ ^[A-Za-z0-9._+@/-]+$ && "$1" != /* && "$1" != *".."* ]]
}

sha256_file() {
  sha256sum "$1" | awk '{ print $1 }'
}

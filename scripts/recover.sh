#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

selection="${1:-previous}"
[[ "$selection" == "current" || "$selection" == "previous" ]] || {
  printf 'Usage: %s [current|previous]\n' "$0" >&2
  exit 2
}

printf 'Recovery selection: %s\n' "$selection"
: "${ARCH_REPO_STATE_DIR:?Set ARCH_REPO_STATE_DIR}"
: "${ARCH_REPO_CANDIDATE_DIR:?Set ARCH_REPO_CANDIDATE_DIR}"

manifest="$ARCH_REPO_STATE_DIR/recovery/$selection.json"
signature="$manifest.sig"
[[ -s "$manifest" && -s "$signature" ]] || {
  printf 'Missing signed recovery manifest: %s\n' "$manifest" >&2
  exit 1
}

verify_public_key
gnupg="$(mktemp -d)"
trap 'rm -rf "$gnupg"' EXIT
chmod 0700 "$gnupg"
export GNUPGHOME="$gnupg"
gpg --batch --import "$(public_key_file)" >/dev/null 2>&1
verify_signature "$signature" "$manifest"
[[ "$(jq -r '.signingFingerprint' "$manifest")" == \
  "$(normalised_fingerprint)" ]] || {
  printf 'Recovery manifest signing fingerprint mismatch\n' >&2
  exit 1
}

rm -rf "$ARCH_REPO_CANDIDATE_DIR"
mkdir -p "$ARCH_REPO_CANDIDATE_DIR"
while IFS=$'\t' read -r filename sha256 signature_name signature_sha256; do
  [[ "$(sha256_file "$ARCH_REPO_STATE_DIR/$filename")" == "$sha256" ]] || {
    printf 'Recovery package checksum mismatch: %s\n' "$filename" >&2
    exit 1
  }
  [[ "$(sha256_file "$ARCH_REPO_STATE_DIR/$signature_name")" == \
    "$signature_sha256" ]] || {
    printf 'Recovery signature checksum mismatch: %s\n' "$signature_name" >&2
    exit 1
  }
  verify_signature "$ARCH_REPO_STATE_DIR/$signature_name" \
    "$ARCH_REPO_STATE_DIR/$filename"
  cp "$ARCH_REPO_STATE_DIR/$filename" "$ARCH_REPO_CANDIDATE_DIR/"
done < <(jq -r '.packages[] | select(.active) |
  [.filename,.sha256,.signature,.signatureSha256] | @tsv' "$manifest")

empty_state="$(mktemp -d)"
trap 'rm -rf "$gnupg" "$empty_state"' EXIT
ARCH_REPO_STATE_DIR="$empty_state" \
ARCH_REPO_PROVENANCE_MANIFEST="$manifest" \
  "$ROOT_DIR/scripts/publish.sh"

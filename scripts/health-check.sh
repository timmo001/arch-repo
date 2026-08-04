#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

for command in curl gpg jq sha256sum tar; do require_command "$command"; done
verify_public_key

hostname="$(config_value '.hostname')"
repository="$(config_value '.repository')"
architecture="$(config_value '.architectures[0]')"
base_url="https://$hostname/$architecture"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsS "https://$hostname/timmo-arch-repo.asc" -o "$work/key.asc"
curl -fsS "https://$hostname/FINGERPRINT" -o "$work/FINGERPRINT"
cmp -s "$work/key.asc" "$(public_key_file)" || { printf 'Published key differs from Git source\n' >&2; exit 1; }
[[ "$(tr -d '[:space:]' < "$work/FINGERPRINT")" == "$(normalised_fingerprint)" ]] || { printf 'Published fingerprint differs from Git source\n' >&2; exit 1; }

curl -fsS "$base_url/$repository.db" -o "$work/$repository.db"
tar -tf "$work/$repository.db" >/dev/null

curl -fsS "$base_url/recovery/current.json" -o "$work/current.json"
curl -fsS "$base_url/recovery/current.json.sig" -o "$work/current.json.sig"
export GNUPGHOME="$work/gnupg"
mkdir -m 0700 "$GNUPGHOME"
gpg --batch --import "$work/key.asc" >/dev/null 2>&1
verify_signature "$work/current.json.sig" "$work/current.json"
jq -e --arg repository "$repository" --arg architecture "$architecture" '.repository == $repository and .architecture == $architecture' "$work/current.json" >/dev/null
jq -e '
  .schemaVersion == 1 and
  (.signingFingerprint | test("^[A-F0-9]{40}$")) and
  all(.packages[];
    (.pkgname | test("^[a-z0-9@_+][a-z0-9@._+-]*$")) and
    (.filename | test("^[^/]+\\.pkg\\.tar\\.zst$")) and
    (.sha256 | test("^[a-f0-9]{64}$")) and
    (.signatureSha256 | test("^[a-f0-9]{64}$")) and
    (.sourceSha | test("^[a-f0-9]{40}$")))
' "$work/current.json" >/dev/null
[[ "$(jq -r '.signingFingerprint' "$work/current.json")" == \
  "$(normalised_fingerprint)" ]] || {
  printf 'Recovery manifest signing fingerprint mismatch\n' >&2
  exit 1
}

database_packages="$work/database-packages"
: > "$database_packages"
while IFS= read -r entry; do
  tar -xOf "$work/$repository.db" "$entry" \
    | awk '$0 == "%NAME%" { getline; print; exit }' \
    >> "$database_packages"
done < <(tar -tf "$work/$repository.db" | grep '/desc$')
sort -u -o "$database_packages" "$database_packages"

manifest_packages="$work/manifest-packages"
jq -r '.packages[] | select(.active) | .pkgname' "$work/current.json" \
  | sort -u > "$manifest_packages"
cmp -s "$database_packages" "$manifest_packages" || {
  printf 'Repository database differs from active recovery manifest\n' >&2
  exit 1
}

while IFS=$'\t' read -r filename sha256 signature active; do
  [[ "$active" == true ]] || continue
  curl -fsS "$base_url/$filename" -o "$work/$filename"
  curl -fsS "$base_url/$signature" -o "$work/$signature"
  [[ "$(sha256_file "$work/$filename")" == "$sha256" ]] || {
    printf 'Package checksum mismatch: %s\n' "$filename" >&2
    exit 1
  }
  expected_signature_sha="$(jq -r --arg filename "$filename" '.packages[] | select(.filename == $filename) | .signatureSha256' "$work/current.json")"
  [[ "$(sha256_file "$work/$signature")" == "$expected_signature_sha" ]] || {
    printf 'Package signature checksum mismatch: %s\n' "$signature" >&2
    exit 1
  }
  verify_signature "$work/$signature" "$work/$filename"
done < <(jq -r '.packages[] | [.filename,.sha256,.signature,(.active|tostring)] | @tsv' "$work/current.json")

printf 'Public repository health check passed\n'

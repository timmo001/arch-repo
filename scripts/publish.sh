#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

for command in gpg jq repo-add sha256sum tar vercmp; do
  require_command "$command"
done
verify_public_key

: "${ARCH_REPO_CANDIDATE_DIR:?Set ARCH_REPO_CANDIDATE_DIR}"
: "${ARCH_REPO_STATE_DIR:?Set ARCH_REPO_STATE_DIR}"
: "${ARCH_REPO_OUTPUT_DIR:?Set ARCH_REPO_OUTPUT_DIR}"
: "${ARCH_REPO_SIGNING_KEY:?Set ARCH_REPO_SIGNING_KEY}"

repository="$(config_value '.repository')"
architecture="$(config_value '.architectures[0]')"
retained="$(config_value '.retainedVersions')"
gnupg="$(mktemp -d)"
trap 'rm -rf "$gnupg"' EXIT
chmod 0700 "$gnupg"
export GNUPGHOME="$gnupg"
import_signing_key "$ARCH_REPO_SIGNING_KEY"
signing_fingerprint="$(normalised_fingerprint)"

rm -rf "$ARCH_REPO_OUTPUT_DIR"
mkdir -p "$ARCH_REPO_OUTPUT_DIR/recovery"
cp -a "$ARCH_REPO_STATE_DIR"/*.pkg.tar.zst \
  "$ARCH_REPO_OUTPUT_DIR/" 2>/dev/null || true
cp -a "$ARCH_REPO_CANDIDATE_DIR"/*.pkg.tar.zst \
  "$ARCH_REPO_OUTPUT_DIR/"

declare -A allowed=()
while IFS= read -r package; do
  allowed["$package"]=1
done < <(jq -r '.packages | keys[]' "$PACKAGE_CONFIG")

package_field() {
  tar -xOf "$1" .PKGINFO | awk -v field="$2" '$1 == field { print $3; exit }'
}

package_version() {
  local epoch pkgver pkgrel
  epoch="$(package_field "$1" epoch)"
  pkgver="$(package_field "$1" pkgver)"
  pkgrel="$(package_field "$1" pkgrel)"
  [[ -z "$epoch" || "$epoch" == 0 ]] \
    && printf '%s-%s\n' "$pkgver" "$pkgrel" \
    || printf '%s:%s-%s\n' "$epoch" "$pkgver" "$pkgrel"
}

for package_file in "$ARCH_REPO_OUTPUT_DIR"/*.pkg.tar.zst; do
  filename="${package_file##*/}"
  [[ "$filename" != *-debug-* ]] || {
    printf 'Debug package rejected: %s\n' "$filename" >&2
    exit 1
  }
  pkgname="$(package_field "$package_file" pkgname)"
  pkgarch="$(package_field "$package_file" arch)"
  [[ -n "${allowed[$pkgname]:-}" ]] || {
    printf 'Unexpected package identity: %s\n' "$pkgname" >&2
    exit 1
  }
  [[ "$pkgarch" == "$architecture" || "$pkgarch" == "any" ]] || {
    printf 'Unexpected architecture: %s\n' "$pkgarch" >&2
    exit 1
  }
done

active_files=()
while IFS= read -r pkgname; do
  selected=()
  while IFS= read -r package_file; do
    inserted=false
    version="$(package_version "$package_file")"
    for index in "${!selected[@]}"; do
      selected_version="$(package_version "${selected[$index]}")"
      if [[ "$(vercmp "$version" "$selected_version")" -gt 0 ]]; then
        selected=("${selected[@]:0:$index}" "$package_file" "${selected[@]:$index}")
        inserted=true
        break
      fi
    done
    [[ "$inserted" == true ]] || selected+=("$package_file")
  done < <(
    for package_file in "$ARCH_REPO_OUTPUT_DIR"/*.pkg.tar.zst; do
      [[ "$(package_field "$package_file" pkgname)" == "$pkgname" ]] \
        && printf '%s\n' "$package_file"
    done
  )

  for index in "${!selected[@]}"; do
    if (( index == 0 )); then
      active_files+=("${selected[$index]}")
    elif (( index >= retained )); then
      rm -f "${selected[$index]}" "${selected[$index]}.sig"
    fi
  done
done < <(jq -r '.packages | keys[]' "$PACKAGE_CONFIG")

for package_file in "$ARCH_REPO_OUTPUT_DIR"/*.pkg.tar.zst; do
  sign_file "$package_file"
done

repo-add --include-sigs "$ARCH_REPO_OUTPUT_DIR/$repository.db.tar.zst" \
  "${active_files[@]}"
ln -sfn "$repository.db.tar.zst" "$ARCH_REPO_OUTPUT_DIR/$repository.db"
ln -sfn "$repository.files.tar.zst" "$ARCH_REPO_OUTPUT_DIR/$repository.files"

if [[ -s "$ARCH_REPO_STATE_DIR/recovery/current.json" ]]; then
  cp "$ARCH_REPO_STATE_DIR/recovery/current.json" \
    "$ARCH_REPO_OUTPUT_DIR/recovery/previous.json"
  cp "$ARCH_REPO_STATE_DIR/recovery/current.json.sig" \
    "$ARCH_REPO_OUTPUT_DIR/recovery/previous.json.sig"
fi

manifest_packages='[]'
provenance_manifest="${ARCH_REPO_PROVENANCE_MANIFEST:-$ARCH_REPO_STATE_DIR/recovery/current.json}"
for package_file in "$ARCH_REPO_OUTPUT_DIR"/*.pkg.tar.zst; do
  filename="${package_file##*/}"
  pkgname="$(package_field "$package_file" pkgname)"
  pkgver="$(package_version "$package_file")"
  pkgarch="$(package_field "$package_file" arch)"
  active=false
  for active_file in "${active_files[@]}"; do
    [[ "$active_file" != "$package_file" ]] || active=true
  done
  source_repository="$(jq -r --arg name "$pkgname" '.packages[$name].repository' "$PACKAGE_CONFIG")"
  source_sha="${ARCH_REPO_SOURCE_SHA:-0000000000000000000000000000000000000000}"
  if [[ -s "$provenance_manifest" ]]; then
    retained_source_sha="$(jq -r --arg filename "$filename" \
      '.packages[] | select(.filename == $filename) | .sourceSha' \
      "$provenance_manifest")"
    [[ -z "$retained_source_sha" ]] || source_sha="$retained_source_sha"
  fi
  entry="$(jq -n \
    --arg pkgname "$pkgname" --arg pkgver "$pkgver" --arg arch "$pkgarch" \
    --arg filename "$filename" --arg sha256 "$(sha256_file "$package_file")" \
    --arg signature "$filename.sig" \
    --arg signatureSha256 "$(sha256_file "$package_file.sig")" \
    --arg sourceRepository "$source_repository" --arg sourceSha "$source_sha" \
    --argjson active "$active" \
    '{pkgname:$pkgname,pkgver:$pkgver,arch:$arch,filename:$filename,sha256:$sha256,signature:$signature,signatureSha256:$signatureSha256,active:$active,sourceRepository:$sourceRepository,sourceSha:$sourceSha}')"
  manifest_packages="$(jq -c --argjson entry "$entry" '. + [$entry]' <<< "$manifest_packages")"
done

jq -n \
  --arg repository "$repository" --arg architecture "$architecture" \
  --arg generatedAt "$(date --utc +%Y-%m-%dT%H:%M:%SZ)" \
  --arg workflowRun "${GITHUB_RUN_ID:-}" \
  --arg signingFingerprint "$signing_fingerprint" \
  --argjson packages "$manifest_packages" \
  '{schemaVersion:1,repository:$repository,architecture:$architecture,generatedAt:$generatedAt,workflowRun:(if $workflowRun == "" then null else $workflowRun end),signingFingerprint:$signingFingerprint,packages:$packages}' \
  > "$ARCH_REPO_OUTPUT_DIR/recovery/current.json"
sign_file "$ARCH_REPO_OUTPUT_DIR/recovery/current.json"

printf 'Prepared publication tree: %s\n' "$ARCH_REPO_OUTPUT_DIR"

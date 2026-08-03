# Arch Repository Guidance

## Scope

- This repository owns the public `timmo` pacman repository served from `packages.timmo.dev`.
- Package identities and source repositories are allowlisted in `config/packages.json`.
- Built packages and repository databases belong in R2, not Git.

## Safety

- Never commit private keys, passphrases, API tokens, built packages, signatures, or downloaded recovery material.
- Never publish, prune, recover, or mutate Cloudflare resources without an explicit request.
- Keep current and previous package versions. A failed publication should leave extra objects rather than delete recovery material.
- Build only allowlisted public repositories at exact commit SHAs.
- Reject debug packages and package identities that do not match the allowlist.

## Validation

Run `pnpm check` before committing. Run `pnpm provision:check` and `pnpm health` when credentials and the live repository are available.

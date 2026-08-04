# Operations

The protected publisher accepts only allowlisted package identities from public `timmo001` repositories at exact commit SHAs. Build jobs do not receive signing or Cloudflare credentials.

Publication validates the candidate, signs packages, reconstructs the database, uploads immutable package objects first, publishes `timmo.db` last, purges mutable URLs, and verifies the result through `packages.timmo.dev`. After successful public verification, package objects absent from the prepared current-plus-previous publication tree are pruned. A failure before that point leaves extra package objects available for recovery.

The central workflow serialises publication by waiting for every lower run ID. A concurrency group alone is insufficient because GitHub retains only one pending run.

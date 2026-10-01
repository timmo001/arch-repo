# Operations

The protected publisher accepts only allowlisted package identities from public `timmo001` repositories at exact commit SHAs. Build jobs do not receive signing or Cloudflare credentials. Removing a package from `config/packages.json` drops it from the database; its stored files stay as inactive recovery material.

Publication validates the candidate, signs packages, reconstructs the database, uploads immutable package objects first, publishes `timmo.db` last, purges mutable URLs, and verifies the result through `packages.timmo.dev`. After successful public verification, package objects absent from the prepared current-plus-previous publication tree are pruned. A failure before that point leaves extra package objects available for recovery.

The central workflow serialises publication by waiting for every lower run ID. A concurrency group alone is insufficient because GitHub retains only one pending run.

Each publication is also recorded as a deployment on the source repository at the published commit through the `arch-source-deployment` action in `timmo001/workflows`, linking back to the publish run and, on success, to the package file. Each package gets its own environment, `arch-git/<package>` for `-git` packages and `arch-bin/<package>` for everything else, so a new publish only supersedes earlier deployments of the same package. This uses `SOURCE_ARTIFACT_TOKEN`, which needs Deployments read and write access alongside Actions read on every allowlisted source repository. Deployment recording is best effort and never blocks publication.

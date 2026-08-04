# Recovery

The repository keeps current and previous package objects plus signed `current` and `previous` recovery manifests. Run the `Recover repository` workflow with the `previous` manifest for a normal rollback. It verifies the selected manifest and retained package signatures, rebuilds the current-only database, republishes through the same package-first sequence, purges mutable URLs, and verifies the public repository. Recovery preserves the selected immutable package objects and does not prune recovery material.

A signing-key compromise is not an ordinary rollback. Follow `SECURITY.md`, revoke the compromised subkey, and require independent verification of the replacement fingerprint.

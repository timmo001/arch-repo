# Recovery

The repository keeps current and previous package objects plus signed `current` and `previous` recovery manifests. A normal rollback verifies the previous manifest, downloads its package set, rebuilds the current-only database, and republishes through the same package-first sequence.

A signing-key compromise is not an ordinary rollback. Follow `SECURITY.md`, revoke the compromised subkey, and require independent verification of the replacement fingerprint.

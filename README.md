# Timmo Arch Repository

Public Arch Linux binary packages for projects maintained under `timmo001`.
The repository overlays the same package names maintained through AUR, so
`-git`, `-bin`, and un-suffixed channels keep their existing meaning. AUR
remains an independent source-build fallback.

The repository is not live until R2, the signing key, and the initial empty
database have been provisioned.

## Client configuration

Verify the full fingerprint in `keys/FINGERPRINT` before trusting the key. The
file is intentionally absent until the key ceremony is complete.

```bash
curl -fsSLO https://packages.timmo.dev/timmo-arch-repo.asc
pacman-key --add timmo-arch-repo.asc
pacman-key --finger <full-fingerprint>
pacman-key --lsign-key <full-fingerprint>
```

Add the repository before other repository sections in `/etc/pacman.conf`:

```ini
[timmo]
SigLevel = PackageRequired DatabaseOptional TrustedOnly
Server = https://packages.timmo.dev/$arch
```

Run a full upgrade when refreshing package databases:

```bash
pacman -Syu
```

These are unofficial packages and are not supported by Arch Linux.

## Operations

- [Bootstrap](docs/bootstrap.md)
- [Cache policy](docs/cache-policy.md)
- [Publication](docs/operations.md)
- [Recovery](docs/recovery.md)
- [Security](SECURITY.md)

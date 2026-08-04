# Cache policy

| Object | Cache-Control |
| --- | --- |
| Versioned packages and signatures | `public, max-age=31536000, immutable` |
| Public key and fingerprint | `public, max-age=3600, must-revalidate` |
| Repository databases and aliases | `public, max-age=60, s-maxage=300, must-revalidate` |
| Current and previous recovery manifests | `public, max-age=60, s-maxage=300, must-revalidate` |

Publication purges only mutable database and recovery-manifest URLs. Immutable package URLs are never purged.
If an immutable package filename is accidentally reused with different bytes, the manual package-cache purge workflow can repair exactly that package and signature pair after the origin objects are verified.

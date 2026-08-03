# Security

Report vulnerabilities privately through GitHub's security advisory form.
Do not include private key material, passphrases, or Cloudflare credentials in
an issue.

For a signing-key compromise, stop publication, remove the compromised signing
subkey from the production environment, publish the revocation through an
independent channel, and require clients to verify the replacement fingerprint.

For a Cloudflare credential compromise, revoke the token before restoring
bucket or domain configuration. Disconnect public access if repository objects
cannot be trusted.

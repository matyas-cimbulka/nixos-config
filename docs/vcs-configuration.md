# VCS configuration and deferred development setup

## Current baseline

The shared Matyas environment installs Git and Jujutsu with ordinary tool
preferences. It does not configure author identity, automatic commit signing,
credential providers, or an HTTPS-to-SSH URL rewrite. Public HTTPS access needs
no personal credentials. This is an unauthenticated baseline, not an enforced
read-only security boundary; repository configuration or externally supplied
credentials may still enable other operations.

Neither VCS module selects an editor. Both use their normal environment-based
editor selection, including the shared EDITOR setting and any explicit overrides.
Keep the editor choice with the editor configuration.

## Future development configuration

Implementation is deferred until a development deployment needs it.

- Keep the existing Git and Jujutsu modules. Add typed options and conditional
  configuration within those modules instead of separate named development,
  remote, or workstation VCS variants.
- Development configuration is explicitly enabled and defaults off. This selects
  an additional capability; applicable integrations still default on and permit
  explicit opt-out.
- Require author identity only while its development configuration is active,
  and signing parameters only while signing is active. Deployment supplies the
  public key references, credential connection, and provider-specific settings.
- Reuse native options where suitable, and define shared identity values once in
  the selecting profile. Keep authentication and signing requirements distinct.
- Let repositories select SSH remotes explicitly rather than rewriting all GitHub
  HTTPS URLs globally.

## Deferred credential delivery

Remote development VMs will not require 1Password. Provision the necessary
credentials as SOPS-encrypted secrets, decrypt them only at runtime, and expose
them through the deployment's credential mechanism. Prefer dedicated, revocable
development keys. Never embed private keys or decrypted values in Nix expressions
or the Nix store.

Workstations will use 1Password for secrets and SSH keys, with its SSH agent and
the appropriate signing configuration for each VCS tool. The workstation
deployment owns those provider-specific details.

AI agents are intended to authenticate and sign using SSH keys through a socket
exposed by the sandbox host. The sandbox must hide private key files and other
secrets, while deliberately allowing access to that socket. Socket access grants
use of its exposed identities even though it does not expose private key material.
The execution boundary must also prevent unrestricted privilege escalation from
bypassing secret isolation; the current Matyas passwordless-sudo account alone
does not establish this boundary. Sandbox implementation is deferred.

## Validation when implemented

Check the baseline and development variants, missing active parameters, and
disabled integrations. Verify public access without credentials, authentication,
Git and Jujutsu signature verification, and the sandbox's permitted socket access
and denied secret-file access. Evaluation alone does not prove these runtime
properties.

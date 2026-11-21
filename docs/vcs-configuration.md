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

## Optional development configuration

The existing VCS modules now expose development capabilities, disabled by default.
Matyas's workstation home enables them for Git and Jujutsu with author name
`Matyas Cimbulka` and email `matyas.cimbulka@gmail.com`. It installs the supplied
public SSH signing key at `~/.ssh/signing.pub`; both tools use that file and the
shared trusted-signers file at `~/.config/git/allowed_signers`. Git signs commits
and tags by default, and Jujutsu signs its own commits. The shared and server homes retain
their unauthenticated baseline.

Enable `deployment.git.development.enable` and supply author identity through
`programs.git.settings.user`. Git defaults to SSH signing when its native
`programs.git.signing.key` is set; `signByDefault = false` permits an explicit
opt-out. Automatic signing without a key is rejected.

Enable `deployment.jujutsu.development.enable` and supply identity through
`programs.jujutsu.settings.user`. Set
`deployment.jujutsu.development.signing.key` to a public key or runtime public-key
file reference. This defaults its signing integration on, using the SSH backend
and `own` behavior. An explicit `signing.enable = false` removes those defaults.
Enabling signing without a key is rejected.

Define the identity once in the selecting home profile and reuse it for both
tools. A public key can be written declaratively to `~/.ssh/signing.pub`; point
both tools at that file. Configure Git's native `signing.allowedSigners` with the
author email and public key when local verification is wanted. Never put a private
key in these options. The workstation's session-wide 1Password socket supplies
signing operations after the app's SSH agent is enabled and authorized.

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

The workstation selects 1Password's desktop app and CLI and configures its
SSH-agent socket. Account sign-in, enabling the app's SSH agent, and authorizing
use of the matching key remain installation steps. The workstation deployment
owns those provider-specific details.

AI agents are intended to authenticate and sign using SSH keys through a socket
exposed by the sandbox host. The sandbox must hide private key files and other
secrets, while deliberately allowing access to that socket. Socket access grants
use of its exposed identities even though it does not expose private key material.
The execution boundary must also prevent unrestricted privilege escalation from
bypassing secret isolation; the current Matyas passwordless-sudo account alone
does not establish this boundary. Sandbox implementation is deferred.

## Validation

Composition tests cover baseline and development behavior, required identity and
signing parameters, and opt-outs. `runtime-vcs` creates and verifies Git and Jujutsu
signatures through a temporary SSH agent inside a VM, after removing its private-key
file. It uses test identity data and does not access a real 1Password account.

After installation, verify real remote authentication and signed commits through
1Password. Future remote-development credential delivery and sandbox socket/secret
isolation need their own runtime checks. Evaluation alone does not prove these
properties.

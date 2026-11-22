# Enroll a NixOS node in Teleport

New nodes select the `teleport-node` and `teleport-enrollment` modules. The
agent connects directly to the cluster proxy; there is no enrollment broker.
Enrollment is a one-time setup per node, not a step for ordinary rebuilds.

## Behemoth

Tycho's deployment already generates the `behemoth-node` token resource.
On your Mac with Tailscale connected, generate Behemoth's static key in a temporary Docker container:

```sh
mkdir -p "$HOME/teleport-enrollment"
chmod 700 "$HOME/teleport-enrollment"
docker run --rm \
  --add-host=teleport.cimbulka.net:100.119.128.83 \
  --mount "type=bind,source=$HOME/teleport-enrollment,target=/keys" \
  --entrypoint /usr/local/bin/tbot \
  public.ecr.aws/gravitational/teleport-distroless:18.11.10 \
  keypair create --proxy-server=teleport.cimbulka.net:443 \
  --static --static-key-path=/keys/behemoth-teleport.key
```

`--add-host` maps the cluster name to Behemoth's Tailscale IP without disabling
TLS verification. If Docker Desktop cannot route to that IP, run the same
image on Behemoth with `--network host` and a root-only bind mount. Do not use
`docker exec` for key generation: the running container's bridge path to the
proxy times out.

Set `deployment.teleportEnrollmentPublicKeys.behemoth` in Tycho's deployment
configuration to the `ssh-ed25519 …` line printed by `tbot` (algorithm and key
data only). The public key is not a SOPS secret. Until it is set, the native
agent is disabled and the startup manifest omits Behemoth's join token.

Transfer `~/teleport-enrollment/behemoth-teleport.key` securely into the
`behemoth-teleport-enrollment-key` entry in `modules/hosts/tycho/sops.yaml`.
Use `sops` to edit it, use a YAML `|` block scalar, and preserve the file's line
breaks. Once the secret is encrypted and verified, remove temporary private-key
copies. Deploy Tycho and restart Behemoth
so it receives the new credentials. The Docker control plane applies the public
key on startup, and the native agent receives the private key separately. Do not
run `tctl create` for Behemoth or delete its existing `/var/lib/teleport` volume.

## Anderson, Thoth, and Tycho

Use the same procedure with a distinct keypair for each machine. Set the
corresponding `deployment.teleportEnrollmentPublicKeys` entry and store the
private key as `<machine>-teleport-enrollment-key` in Tycho's SOPS file. Tycho
provides the private key to each guest at boot and loads its own key directly
from SOPS. All four agents use the cluster hostname; Tycho's internal DNS
resolves it to Behemoth's bridge address without changing the TLS name.

After deploying Tycho, restart Behemoth first to apply the new tokens, then
restart Anderson and Thoth to load their credentials. The Tycho agent can
retry enrollment once Behemoth is back. Check `tsh ls` and test each node as
`matyas` before relying on Teleport for access.

## Manual registration for other nodes

1. Generate a dedicated static key on the target machine using Teleport's
   [`tbot keypair create`](https://goteleport.com/docs/installation/agents/bound-keypair-static-keys/):

   ```sh
   sudo tbot keypair create --proxy-server teleport.cimbulka.net:443 \
     --static --static-key-path /var/lib/teleport-enrollment/example.key
   ```

   Create the parent directory root-only first and keep the private key
   root-only. On a MicroVM, the key path must be on persistent storage or
   supplied at boot by the host's runtime credential delivery. Never put the
   private key in a Nix string, the Nix store, or unencrypted in version control.

2. Register only the **public** key printed by `tbot`. Apply this resource to the
   cluster with `tctl create -f` as an administrator:

   ```yaml
   kind: token
   version: v2
   metadata:
     name: example-node
   spec:
     roles: [Node]
     join_method: bound_keypair
     bound_keypair:
       onboarding:
         initial_public_key: "ssh-ed25519 REPLACE_WITH_THE_GENERATED_PUBLIC_KEY"
       recovery:
         mode: insecure
   ```

   `insecure` is Teleport's required recovery mode for static keys. It does not
   disable transport TLS; it lets anyone holding that private key re-enroll
   under this token without the prior local join state. Use a distinct key per
   machine and remove the token resource if the key is compromised or the node
   no longer needs to enroll. Revoking a join token does not revoke an already
   issued node identity.

3. In the machine profile, set `deployment.teleport-enrollment.tokenName` to
   `example-node` and `privateKeyFile` to the target's runtime path. Set
   `deployment.teleport-node.proxyServer` to `teleport.cimbulka.net:443` and
   choose the node labels. Persist `/var/lib/teleport` separately from the
   enrollment key so the agent retains its issued identity across reboots.

After deployment, check `journalctl -u teleport`, confirm the node appears in
`tsh ls` under an authorized account, and verify it reconnects after reboot.

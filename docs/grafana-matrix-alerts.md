# Send Grafana alerts to Matrix

Hookshot runs on Behemoth. Thoth's dedicated `grafana-hookshot` Teleport bot
opens a local tunnel at `127.0.0.1:9900` to the `hookshot-webhook` app. The
bot can access only that app; it has no Matrix token or SSH role.

## Enroll the tunnel

Generate a dedicated key on a trusted machine with `tbot` 18 and access to the
Teleport proxy. Do not reuse a node or Grafana MCP identity:

```sh
umask 077
tbot keypair create --proxy-server=teleport.cimbulka.net:443 \
  --static --static-key-path="$HOME/grafana-hookshot.key"
```

1. Use `sops modules/hosts/tycho/sops.yaml` to store the private key under
   `hookshot-tbot-key` as a YAML block scalar (`|`). Keep the original line
   breaks. Never paste the private key into chat or Nix.
2. Set `deployment.grafanaHookshotPublicKey` in
   `modules/hosts/tycho/default.nix` to the `ssh-ed25519 …` public key printed
   by `tbot`. The tunnel and Teleport resources are disabled until this is set.
3. Deploy Tycho. Restart Behemoth first so the control plane applies the bot,
   role, and join token. Then restart Thoth to load the key and start `tbot`.
4. On Thoth check `sudo journalctl -b -u grafana-hookshot-tunnel`. Then probe
   `curl -i --max-time 5 http://127.0.0.1:9900/`. Expect Hookshot's HTTP 404
   for the root path, not a TLS error, timeout, or Teleport authorization error.

## Configure Grafana

After the tunnel works, add a Grafana webhook contact point. Enter the current
Hookshot URL privately and use a custom JSON payload with a `text` field. Include
only firing/resolved, severity, a short summary, and a link to authenticated
Grafana. Do not send the default full Grafana JSON: Hookshot may post the entire
payload if `text` is missing. Keep resolved notifications enabled.

Route one synthetic alert to this contact point. Verify firing and resolved
messages in `#ops-alerts`, then verify locked-phone notifications in Element X.
Do not remove other notification routes until the end-to-end test succeeds.

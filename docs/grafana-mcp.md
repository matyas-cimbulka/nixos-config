# Enable Grafana MCP on Thoth

Pocket ID still handles human Grafana login. One loopback-only `mcp-grafana`
service uses a single Grafana service account. Teleport authenticates each bot
and enforces its tool allowlist. Both bots can read dashboards and query
Prometheus and Loki, including raw logs. Only `grafana-mcp-repo` can create or
update dashboards; `grafana-mcp-debug` cannot. Grafana sees the service account;
use Teleport audit events to distinguish the bots.

## Activate the deployment

1. As a Grafana organization administrator, create a dedicated `grafana-mcp`
   service account. Give it dashboard create/write and datasource query access.
   The built-in **Editor** role is the starting point on Grafana OSS; the MCP
   tool boundary is enforced by Teleport, not by that role. In Pocket ID, add
   your user to `grafan-admin`, then sign out of Grafana and sign in again after
   deploying the role mapping. The existing `admin` group still maps to Editor.
2. Create a service-account token and add it as `grafana-mcp-token` with
   `sops modules/hosts/tycho/sops.yaml`. Do not put the token in Nix or pass it on
   a command line. Only after adding the token, set
   `deployment.enableGrafanaMcp = true;` in Tycho's deployment configuration.
3. Deploy Tycho, then restart **Behemoth before Thoth**. Behemoth applies the two
   bots and roles and updates the existing `thoth-node` token to include `App`.
   Thoth uses its existing Teleport state and key. Do not delete its state
   volume or rotate its enrollment key as part of this rollout.
4. Check the control-plane and Thoth `teleport` and `grafana-mcp` journals. Verify
   that Thoth still accepts `tsh ssh` and that port 8000 listens only on
   `127.0.0.1` on Thoth. If the App role does not register, inspect the agent's
   rejoin errors before proceeding; SSH working alone does not prove App access.

The startup manifest creates bots, not their join credentials. For the harness
smoke test, enroll a separate `tbot` instance for each existing bot using a
[Machine ID join method](https://goteleport.com/docs/machine-workload-identity/deployment/).
Use its short-lived identity with `tsh mcp connect`; do not use a human session.
Test dashboard create/update as the repo bot, then verify the debug bot can
read the dashboard but cannot invoke `update_dashboard` directly. Test both
query types with both bots. Keep join credentials and identity files outside
workspaces and sandboxes.

To stop serving MCP, disable `deployment.enableGrafanaMcp` and redeploy.
Removing entries from `--apply-on-startup` does not delete stored Teleport
resources: explicitly revoke any bot join credentials and remove the bots and
roles if decommissioning. Revoke the Grafana service-account token as well.

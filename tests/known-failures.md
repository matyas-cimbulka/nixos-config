# Composition findings awaiting fixes

The current evaluation run contains 207 tests in 24 suites: 195 pass and the
following 12 fail. These are ordinary failing expectations, not skipped tests or
expected-success exceptions. No implementation fixes are included in this pass.
Update this inventory after later fixes and test additions.

All current findings concern required deployment values being accepted when
omitted. Collection-valued options can evaluate to empty lists or attribute sets
despite having no explicit default. The tests require explicit selection; an
explicit empty selection is distinct from omission where the feature permits it.

| Suite | Failing test | Observed behavior when the value is omitted |
| --- | --- | --- |
| `alloy` | `active-alloy-requires-http-interfaces` | HTTP interfaces become empty; no interface opening is contributed. |
| `grafana` | `missing-interface-is-rejected` | HTTP interfaces become empty. |
| `loki` | `missing-interface-is-rejected` | HTTP interfaces become empty. |
| `prometheus` | `missing-interface-is-rejected` | API interfaces become empty. |
| `tempo` | `missing-api-interface-is-rejected` | API exposure is omitted while the other supplied interface remains valid. |
| `tempo` | `missing-otlp-interface-is-rejected` | OTLP exposure is omitted while the supplied API interface remains valid. |
| `tailscale` | `missing-transport-interfaces-is-rejected` | UDP transport interfaces become empty. |
| `tailscale-dns` | `missing-dns-interfaces-is-rejected` | DNS interfaces become empty. |
| `tailscale-dns` | `missing-metrics-interfaces-is-rejected` | Metrics interfaces become empty. |
| `tailscale-dns` | `missing-upstreams-is-rejected` | Upstream DNS servers become an empty list. |
| `traefik` | `missing-exposure-selection-is-rejected` | Exposure selection becomes an empty set and no ports are published. |
| `pocket-id` | `missing-trusted-proxies-is-rejected` | Trusted proxies become an empty list and `TRUST_PROXY` becomes `false`. |

These observations come from evaluated configuration. They do not establish what
an application will accept at startup or how a deployed host behaves.

Fixes should preserve the passing cases: disabled features and opted-out
integrations must continue to evaluate without the settings they no longer use.
Keep negative fixtures focused, so unrelated missing credentials or option
conflicts do not masquerade as the expected prerequisite failure. Native OCI
containers normally enable their backend; the deliberately invalid Docker-disabled
container fixtures therefore use `lib.mkForce false` to exercise the feature's
own prerequisite diagnostic.

See [README.md](README.md) for commands that report every test result despite
individual assertion failures. A targeted command exposes the specific diagnostic:

```sh
nix eval --json .#lib.compositionTests.pocket-id.missing-trusted-proxies-is-rejected
```

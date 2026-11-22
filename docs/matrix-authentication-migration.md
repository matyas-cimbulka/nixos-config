# Switch Matrix to MAS with a fresh homeserver database

The current Matrix accounts, rooms, and sessions are disposable. Start with a
fresh Synapse database and a separate MAS database rather than importing legacy
identities with `syn2mas`. Keep the old database intact during cutover so it is
available for rollback. After cutover, sign out of old Element sessions and
sign in again; the same Matrix ID will be a newly provisioned account.

Keep `cimbulka.net` as the Matrix ID domain and
`https://matrix.cimbulka.net` as the homeserver URL. Run MAS at
`https://mas.cimbulka.net` on the tailnet. Pocket ID remains the identity
provider; keep federation and password login disabled.

## Prepare Pocket ID

On the existing Matrix OIDC client, add:

```text
https://mas.cimbulka.net/upstream/callback/01M82BRDFNG4EK61TR5Y0W3NHQ
```

Keep the client confidential, access set to **All users**, and its secret in
SOPS. Keep the old callback until the new login is verified. The final path
segment is the stable MAS upstream provider ID.

## Deploy and check

Deploy Tycho from a checkout containing the new `modules/containers/mas.nix`
module and restart `microvm@behemoth.service` to pick up its new volumes and
credential wiring. Behemoth keeps the old PostgreSQL volume mounted but uses a
new volume at `/var/lib/matrix-postgres-mas` for Synapse. The MAS database and its
keys live at `/var/lib/matrix-authentication`.

From a tailnet client, check that Synapse advertises the MAS issuer and that the
MAS discovery document is reachable over verified TLS:

```sh
curl -fsS https://matrix.cimbulka.net/_matrix/client/v1/auth_metadata | jq -r .issuer
curl -fsS https://mas.cimbulka.net/.well-known/openid-configuration | jq -r .issuer
```

Both should report `https://mas.cimbulka.net/` (possibly without the trailing
slash). If not, check `docker-mas`, `docker-mas-postgres`, `docker-synapse`, and
`mas-state` in Behemoth's journal. Don't remove any old state while debugging.

Then test clients:
- Sign in with Pocket ID in Element Web and Element X and confirm both see the
  same newly provisioned Matrix account. Test QR sign-in and locked-phone push
  separately. QR sign-in is not cross-signing device verification.
- Once the replacement is verified, remove the old Pocket ID callback. Remove
  the old database only as a separate, explicit cleanup.

Upstream: [Configure Synapse for MAS](https://element-hq.github.io/matrix-authentication-service/setup/homeserver.html).

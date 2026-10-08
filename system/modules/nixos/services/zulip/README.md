# Zulip

A disabled-by-default, self-hosted Zulip organization for the Overseer trial.
The official server, PostgreSQL, RabbitMQ, Redis and memcached images are pinned
in `images.nix`. Data is separate from existing services under
`/var/lib/zulip-trial`. Only the web endpoint is published, on 127.0.0.1:23248.
Databases and queues have no published ports.

## Provisioning prerequisites

After explicit deployment/credential approval:

1. Check that `chat.shulker.link`, port 23248 and the proposed state directory
   are unused. Set `publicUrl`, `administratorEmail`, `oidcIssuer`, `oidcClientId`
   and the actual `trustedProxyAddresses`; never trust arbitrary forwarded headers.
2. Create a dedicated PocketID client with callback
   `https://chat.shulker.link/complete/oidc/` and restrict access to Conquerix.
   Keep native Zulip authentication in front of all chat and attachment access.
   Pangolin supplies HTTPS routing without an extra interactive login over the
   mobile API. Test both browser and native-mobile authentication.
3. Store a JSON object in the dedicated `secretReference`, with exactly these
   keys: `postgres_password`, `memcached_password`, `rabbitmq_password`,
   `redis_password`, `secret_key`, `email_password`, `social_auth_oidc_secret`.
   Use unique random single-line credentials. Values never belong in Nix or
   command arguments. Configure SMTP host/user/from/port for that credential;
   this trial uses implicit TLS (default port 465).
4. Set `impermanence = true` for Shulker. Build and review the enabled configuration
   before deployment. Shulker enables the loopback-only Zulip trial;
   `hermes-trial.enable` remains false until its bot and provider are provisioned.
5. Start Zulip on loopback and create one invitation-only organization using its
   local organization-creation procedure. Preserve an administrator recovery
   credential. In organization settings, require end-to-end encrypted push
   notifications. Register for Zulip's push service after reviewing its terms.
   This registration is not performed automatically by the module.
6. Before enabling public ingress, verify invitation-only membership and required
   encrypted push using `policy-check.py` inside the server's Django shell.
   The check excludes Zulip's internal system-bot realm and accepts only one
   private root-domain organization. PocketID login does not automatically grant
   organization membership.
7. Create the non-admin Overseer bot and its private channel. Obtain real numeric
   IDs for the Overseer module. Confirm an unauthorized account cannot use it.

The server can read stored messages. Encrypted push protects notification
payloads from intermediaries, not chat content from the host administrator.
Optional Zulip usage statistics are disabled. Push registration still sends
required service metadata.

Shulker declares the `zulip-trial` HTTPS resource in its native Newt blueprint,
forwarding to 127.0.0.1:23248. Proxy SSO is disabled for this resource because
Zulip's native login protects messages and its mobile API. Changes to the blueprint
restart Newt and briefly reconnect this host's tunnel. Verify the TLS certificate,
OIDC callback, anonymous access denial, and actual mobile login after applying it.

## Operations and backups

`zulip-trial-compose` operates only this named stack. `zulip-trial-backup` locks
maintenance, pauses the Zulip application, takes a logical PostgreSQL dump and
archives uploads/configuration with it, then unpauses. This causes a brief Zulip
interruption during backup. A failed dump/archive does not replace the previous
backup. Unpause failures are explicit and require operator attention. Borgmatic
runs the backup hook before create and stores `backups/zulip.tar.gz` off-host.
The archive contains credentials and must retain the fleet's private/encrypted
backup protections. Do not publish it.

Restore only into an empty stack using matching pinned images: extract `data/`,
restore `database.sql` into an empty Zulip database, then start and verify login,
messages and attachment access. Do not overwrite the running database or use
`down -v` as a routine recovery command. A real Linux restore rehearsal remains
part of deployment acceptance; fixture tests only establish script behavior.

Rollback stops `zulip-trial` and its ingress route while preserving state.
Production Hermes/Telegram remains available until a separately approved cutover.

Sources: [official container documentation](https://zulip.readthedocs.io/projects/docker/),
[authentication](https://zulip.readthedocs.io/en/stable/production/authentication-methods.html),
[push notifications](https://zulip.com/help/mobile-notifications).

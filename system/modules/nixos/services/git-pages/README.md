# Git Pages

Git Pages serves declaratively configured Git repositories as static sites on
Shulker. Each repository entry supplies its name, URL, branch, optional path,
listener port, and synchronisation policy. The module turns enabled entries
into a git-sync container and an nginx web container; it does not own a public
route or external repository administration.

## Deployment and networking

The public options are `enable`, `impermanence`, `stateDir`, `basePort`,
`bindAddress`, `pullInterval`, and `repos`. The default state directory is
`/var/lib/git-pages`; the default listener address is loopback and the default
base port is 3000. Shulker configures repository listeners on loopback, so any
public Pangolin route is external control-plane state rather than module
configuration. The module creates no firewall rule and owns no secret.

For each synchronised repository, the generated units are
`docker-git-pages-<repository>-sync.service` and
`docker-git-pages-<repository>-web.service`; they are grouped by
`docker-compose-git-pages-root.target`. The web unit depends on its matching
synchronisation unit. Do not rename repository entries casually: their safe
names form container, unit, and state-directory identities.

## State, backup, and recovery

The module creates the configured state directory with restricted permissions.
When `impermanence` is enabled, it persists that directory below
`/nix/persist`, and it contributes the same directory to Borgmatic's source
list. Repository working trees and rendered sites live there. A backup is not
a substitute for validating repository access or a public route after an
approved deployment.

Before changing a repository, listener, image, state path, or external route,
validate the flake and preserve a recoverable archive. After an approved
deployment, inspect the generated units and their recent journals, then test
the intended loopback listener. Do not change public routing, repository
credentials, or live state as part of a structural module change.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Shulker host report](https://github.com/Conquerix/shulker/wiki/Host-shulker)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)

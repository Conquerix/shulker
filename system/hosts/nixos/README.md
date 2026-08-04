# Generated server documentation

Server documentation is generated from each host's evaluated NixOS
configuration. Host-specific details are not maintained manually in this file.

Every host that enables `shulker.system.profiles.server` automatically gets a
dedicated `server-docs-<host>` flake package. For example:

```sh
nix build .#server-docs-shulker
```

Every NixOS host also receives the generic `host-docs-<host>` target, and
`host-docs` combines all NixOS and nix-darwin reports:

```sh
nix build .#host-docs-shulker
nix build .#host-docs
```

The resulting Markdown file is available as `result/<host>.md`.

Build the complete server fleet into one output directory with:

```sh
nix build .#server-docs
ls result/*.md
```

Build the aggregate Wiki navigation, fleet and service catalogs, public-service
inventory, diagrams, and runbooks with:

```sh
nix build .#wiki-docs
ls result/*.md
```

The generator lives in [`lib/server-docs.nix`](../../../lib/server-docs.nix).
It derives enabled profiles and modules, service endpoints, firewall and
container exposure, filesystems, persistence, backup sources, secret names, and
operational warnings from the merged configuration. Secret references, secret
values, generated secret paths, password hashes, and Pelican node credentials
are deliberately excluded.

When a host or shared module changes, rebuild its target rather than editing the
generated Markdown. Add reusable fields to the generator when new module types
need richer service details.

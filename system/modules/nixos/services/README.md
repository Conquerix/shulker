# Service module convention

Each retained deployable service belongs in one direct child directory of this
directory. Every service directory owns a `default.nix` NixOS entry point and a
canonical `README.md` runbook. Split implementations use an explicit, sorted
`imports` list in `default.nix`; helpers, tests, and package expressions are
never imported implicitly.

The retained service families are `backup`, `beszel`, `forgejo`, `git-pages`,
`hermes-agent`, `home-assistant`, `immich`, `newt`, `nextcloud`, `ollama`,
`pangolin`, `paperless`, `pelican`, `plex`, `pocket-id`, `seafile`, `sunshine`,
`torrent`, and `webdav`. This tree does not own the platform or capability
modules `core/`, `containers.nix`, `impermanence.nix`, `nvidia.nix`,
`steam.nix`, or `yubikey.nix`.

The first line of a service README is its only H1. It is the canonical public
title and determines the published `Service-<Title>.md` Wiki page, so changing
it is a reviewed public URL change. Titles use ASCII letters and digits with
single spaces and normalize to the directory name (for example, `hermes-agent`
uses `# Hermes Agent`).

Service READMEs are the sole authored service runbooks. Keep operational facts,
secret *names*, and recovery guidance here; never add secret values, private
identifiers, raw API payloads, or user data. Fleet operations and project
documentation remain under `docs/wiki/`.

`default.nix` is the only retained-service composition boundary and explicitly
imports all nineteen service directories in lexical order. The root NixOS
module composer flattens that manifest with the six platform and capability
modules listed above so their existing lexical evaluation order remains
unchanged.

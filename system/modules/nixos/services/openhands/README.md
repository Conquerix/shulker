# OpenHands

Enderdragon runs the official all-in-one Agent Canvas container. NixOS controls
its image version and the docker-openhands service. The frontend and native
OpenHands agent share one container and one loopback port, 23249. Pangolin
publishes https://code.shulker.link privately to the owner.

The writable home is /var/lib/openhands-clean/home; shared projects live under
/srv/ai-projects, mounted as /projects. Connect VS Code through SSH and open
the same host project directory. The workspace ACL lets both the container and
Conquerix edit files. Model profiles and credentials are configured in Canvas;
no agent profiles are created or rewritten by NixOS. Use the native OpenHands
agent, not an ACP agent. Model access must use the owner's ChatGPT subscription;
paid API fallback is not authorized. The pinned SDK's native subscription
catalog includes gpt-6-astra but does not yet include gpt-6.1-sol. Subscription
model access remains unverified until a real agent turn completes.

The initial workspace is the dev branch of Conquerix/shulker at
/srv/ai-projects/shulker (VS Code) and /projects/shulker (Canvas). Model profiles
are editable application settings, not Nix seeds. The initial API-based model
test failed because API billing was inactive; the owner revoked that key.

OpNix provisions LOCAL_BACKEND_API_KEY and OH_SECRET_KEY from the OpenHands
section of the enderdragon server item in 1Password. The container waits for
secret provisioning; the generated environment file is readable only by root.
GitHub API Token is a fine-grained token restricted to shulker, with Contents
and Pull requests write permissions. OpNix mounts it read-only for Git's
credential helper; it is never embedded in remote URLs. The same token is saved
as github_token in Canvas for repository discovery and pull-request operations.
After rotating it, update the native Canvas secret as well as the server item.
Only the Pangolin-protected loopback frontend receives the backend key. Neither
the Docker socket nor host credentials are mounted in the container. The home
and project directories are persistent and included in encrypted backups.

Development Nix uses its own single-user store at /var/lib/openhands-nix,
mounted as /nix. It persists across container replacement; its reproducible
contents are excluded from application backups. It does not use the host store
or daemon. Initialize a fresh store with the official pinned installer:

```sh
sudo docker exec openhands sh -c 'curl -fsSL https://releases.nixos.org/nix/nix-2.34.7/install | sh -s -- --no-daemon --yes --no-channel-add'
sudo docker exec -it -w /projects/shulker openhands nix develop
```

NixOS supplies the flake settings and limits builds to two jobs and two cores.
The container has an 8 GiB memory ceiling for fleet configuration evaluation.
Install project-specific tools through development shells; for example, Rust
projects can include cargo and rustc in their own flake. Container recreation
preserves the Nix profile in the mounted home and the store in its own directory.

```sh
sudo docker logs --tail 100 openhands
sudo systemctl restart docker-openhands
```

Old worker data and projects remain in their original persistent directories
for recovery. They are not mounted into this fresh installation.

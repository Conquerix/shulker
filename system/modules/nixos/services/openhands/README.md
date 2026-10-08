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
agent, not an ACP agent. For an OpenAI API key, choose the OpenAI provider;
gpt-6.1-sol can be entered as a custom model. API usage is billed separately.
The pinned SDK's native subscription picker still needs upstream 6.1 Sol support.

The owner-only server.env file holds LOCAL_BACKEND_API_KEY and OH_SECRET_KEY.
Only the Pangolin-protected loopback frontend receives the backend key. Neither
the Docker socket nor host credentials are mounted in the container. The home
and project directories are persistent and included in encrypted backups.

```sh
sudo docker logs --tail 100 openhands
sudo systemctl restart docker-openhands
```

Old worker data and projects remain in their original persistent directories
for recovery. They are not mounted into this fresh installation.

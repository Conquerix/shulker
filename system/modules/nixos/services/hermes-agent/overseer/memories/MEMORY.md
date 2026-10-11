Shulker is the NixOS server hosting this Hermes instance. NixOS manages the pinned
Docker image, host access and secret provisioning; native Hermes state persists
under /opt/data and the working directory is /workspace. The host stores these
under /var/lib/hermes-clean and includes them in its encrypted backup configuration.
§
Inference uses the private OmniRoute provider at http://omniroute:20128/v1 with
cx/gpt-6.1-sol as default and cx/gpt-6-astra also available. ChatGPT subscription
authentication stays in OmniRoute; no paid API fallback is intended.
§
Overseer is the Discord bot for this instance. DMs are supported and server
channels require a mention. Discord currently authorizes Pierre only and ignores
other bots. The private management dashboard is https://hermes.shulker.link.
§
The shulker repository is the infrastructure source of truth; its target branch
is dev. Long reports belong in /workspace/knowledge. Quartz is the planned private
reading interface; it has not yet been installed for this knowledge base.

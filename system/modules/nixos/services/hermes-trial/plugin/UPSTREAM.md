# Maintained Zulip adapter

Upstream: https://github.com/apresourcing/hermes-zulip
Revision: d48267dde228cb7cbdfcd463e2627a936d8c21db
License: MIT (retained in LICENSE).

Target Hermes: v2026.9.24, f97608f178d1ffeca59860195ab7da295f7c8e5f.
The pinned Docker manifest's amd64 image labels verify this source revision.
Local policy requires numeric user/channel IDs, once-only exact-request approvals,
and rejects all slash commands in this initial trial. No claim of upstream support.
The narrow core patch propagates request identity and requesting user into metadata.
All application code must be mounted read-only; state and skills are separate.

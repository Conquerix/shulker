# Official stack images resolved on 2026-10-04.
{
  zulip = "ghcr.io/zulip/zulip-server:12.3-0@sha256:76a1ecc4ba5470869d9609ef1ec16497b410189918b2daba85862183a59aa275";
  database = "docker.io/zulip/zulip-postgresql:14@sha256:e71ba8616fa42cdc1b248f51263d9290c29681cb8c1992eb9b498af0bb656b29";
  memcached = "docker.io/library/memcached:alpine@sha256:9e4de012dc607573052061c0bcb38abc775e1dd59b24e7ac38d1892842094aaf";
  rabbitmq = "docker.io/library/rabbitmq:4.2@sha256:625f3c5b063f807ac7355705a113b3ab55fc2bef4e472139b23ead3b75c4bc25";
  redis = "docker.io/library/redis:alpine@sha256:3811787313eba226a2ef38658c6ccb91cd5e110edc89c37767de373120a0e5a0";
}

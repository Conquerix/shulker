# Reviewed TaskView release and dependency image lock.
{
  api = "docker.io/gimanhead/taskview-ce-api-server:1.53.0@sha256:faa371c81f46450f59453004c48cc3df60171fdb87e85ff21e7dc75fc59d07b8";
  web = "docker.io/gimanhead/taskview-ce-webapp:1.53.0@sha256:b0c2e84724d76f69ebe80f678fda956146a63339f46282c35a5ce96a7c12e5fc";
  migration = "docker.io/gimanhead/taskview-ce-db-migration:1.53.0@sha256:0bdc9ee77945429a3d9c6e1a8d146a33cc1f54b0c9146395cc4029103b111dfb";
  mcp = "docker.io/gimanhead/taskview-ce-mcp:1.53.0@sha256:b2fbfdf5d7ee26d62bacec2a31930b115da60d939bee11429ab39fa5f86460d3";
  database = "docker.io/library/postgres:17.11@sha256:f4c66b820c6f974249089d3d16d86a3698eae11e8746eb6644b2271031e91232";
  centrifugo = "docker.io/centrifugo/centrifugo:v6.9.6@sha256:3cfded0eb9216882dcb2a77256a89d185654b4e32294934f8de2935fff3c70ec";
}

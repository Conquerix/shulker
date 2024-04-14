{
version = "v1";
subnets = [
  {name = "simple";}
];
groups = [];
peers = [
  {
    name = "shulker";
    isPublic = true;
    subnets = {
      simple = {
        listenPort = 51821;
        ipAddresses = [ "10.10.10.0/24" ];
        # no ipAddresses field will auto generate an IPv6 address
      };
    };
    publicKey = "vLo4XYe84WcCnkLynjO2SjBzHmFuYeuFN0CF5b/CfBc=";
    privateKeyFile = "/secrets/wireguard-private-key";
    endpoints = [
      {
        # no match can be any
        ip = "51.178.27.137";
        port = "51821";
        persistentKeepalive = 25;
      }
    ];
  }
  {
    name = "warden";
    subnets = {
      simple = {
        listenPort = 51821;
        ipAddresses = [ "10.10.10.1" ];
      };
    };
    publicKey = "gfwhPNVOMoBxaCXP+dIcuLv+r2aat127wE+vO20Y/l0=";
    privateKeyFile = "/secrets/wireguard-private-key";
  }
  {
    name = "wither";
    subnets = {
      simple = {
        listenPort = 51821;
        ipAddresses = [ "10.10.10.2" ];
      };
    };
    publicKey = "9JNyydvMlIDGpOCwAW6a8TzPALGvRq2UKBiPFLV8GwM=";
    privateKeyFile = "/secrets/wireguard-private-key";
  }
];
connections = [
  {
    a = [{type= "subnet"; rule = "is"; value = "simple";}];
    b = [{type= "subnet"; rule = "is"; value = "simple";}];#[{type= "group"; rule = "is"; value = "public";}];
  }
];
}

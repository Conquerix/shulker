{
version = "v1";
subnets = [
  {name = "simple";}
];
groups = [
  {name = "public";}
  {name = "private";}
];
peers = [
  {
    name = "shulker";
    groups = [ "public" ];
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
    name = "wither";
    groups = [ "private" ];
    subnets = {
      simple = {
        listenPort = 51821;
        ipAddresses = [ "10.10.10.2" ];
      };
    };
    publicKey = "9JNyydvMlIDGpOCwAW6a8TzPALGvRq2UKBiPFLV8GwM=";
    privateKeyFile = "/secrets/wireguard-private-key";
    #endpoints = [ ];
  }
];
connections = [
  {
    a = [{type= "group"; rule = "is"; value = "private";}];
    b = [{type= "group"; rule = "is"; value = "public";}];
  }
];
}

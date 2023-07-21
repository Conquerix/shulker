{ ... }:

{
  config.virtualisation.oci-containers.containers = {
  	turbopilot = {
  	  image = "ghcr.io/ravenscroftj/turbopilot:latest";
  	  ports = [ "23238:18080"];
  	  volumes = [
  	  	"/storage/fast/models:/models"
  	  ];
  	  environment = {
  	    MODEL = "/models/ggml-model-16B-f32-q4_1.bin";
  	    THREADS = "24";
  	  };
  	};
  };
}

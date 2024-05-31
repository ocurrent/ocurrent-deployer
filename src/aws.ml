(* Compose configuration for a AWS ECS *)

type t = {
  name: string;
  branch: string;
  vcpu: float;
  memory: int;
  storage: int option;
  replicas: int;
  command: string option;
  port: int;
  certificate: string;
}

let show t = t.name

let pp ppf t =
  Format.pp_print_string ppf @@
  Printf.sprintf "%s/%s" t.name t.branch

let command_colon = function
  | None -> ""
  | Some cmd -> "    command: " ^ cmd ^ "\n"

let storage_colon n gb =
  match gb with
  | None -> ""
  | Some gb -> Fmt.str {|    %sTaskDefinition:
      Properties:
        EphemeralStorage:
          SizeInGiB: %i
|} n gb

let compose s =
  let capitalized_branch = String.capitalize_ascii s.branch in
  let service = Fmt.str {|
version: "3.4"
services:
  %s:
    image: $IMAGE_HASH
%s    ports:
      - target: %i
        x-aws-protocol: http
    deploy:
      replicas: %i
      resources:
        limits:
          cpus: '%f'
          memory: %iM

x-aws-logs_retention: 90

x-aws-cloudformation:
  Resources:
    %sService:
      Properties:
        DeploymentConfiguration:
          MaximumPercent: 100
          MinimumHealthyPercent: 50
%s    Default%iIngress:
      Properties:
        FromPort: 443
        Description: %s:443/tcp on default network
        ToPort: 443
    %s%iListener:
      Properties:
        Certificates:
          - CertificateArn: "%s"
        Protocol: HTTPS
        Port: 443
    HttpToHttpsListener:
      Properties:
        DefaultActions:
        - Type: redirect
          RedirectConfig:
            Port: 443
            Protocol: HTTPS
            StatusCode: HTTP_301
        LoadBalancerArn:
          Ref: LoadBalancer
        Port: 80
        Protocol: HTTP
      Type: AWS::ElasticLoadBalancingV2::Listener
|} s.branch (* service *)
   (command_colon s.command) (* command: something *)
   s.port (* ports: - n where n is the container port the service is running on *)
   s.replicas (* Number of instances to create *)
   s.vcpu (* vcpu: is a factional value 0.5 => 512 out of 1024 cpu units *)
   s.memory (* container RAM in MB *)
   capitalized_branch
   (storage_colon capitalized_branch s.storage) (* EC2 instance storage space - default 20GB *)
   s.port s.branch (* Ingress description update and set overwrite port with 443 *)
   capitalized_branch s.port s.certificate (* xxxTCPyyListerner set the SSL certificate to use *)
  in
  service

(* Replace $IMAGE_HASH in the compose file with the fixed (hash) image id *)
let replace_hash_var ~hash contents =
  Re.Str.(global_replace (regexp_string "$IMAGE_HASH") hash contents)


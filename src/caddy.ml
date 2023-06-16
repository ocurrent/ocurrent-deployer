(* Compose configuration for a Caddy HTTPS server on a particular domain/ip *)

type t = {
  name: string;
  domains: (string * string option) list; (* domain ip *)
}

let caddy_service name (domain, ip) =
  let service_name = Fmt.str "%s_%s" name (Re.Str.(global_replace (regexp_string ".") "_" domain)) in
  let net = match ip with
    | None -> ""
    | Some _ -> Fmt.str {|    networks:
    - %s_network
|} service_name in
  let service = Fmt.str {|
  %s:
    image: $IMAGE_HASH
    command: --domain %s --root /usr/share/caddy
    restart: always
%s    ports:
    - target: 80
      published: 80
      protocol: tcp
    - target: 443
      published: 443
      protocol: tcp
|} service_name domain net
  in
  let network = match ip with
  | None -> None
  | Some ip -> Some (Fmt.str {|
  %s_network:
    driver_opts:
        com.docker.network.bridge.host_binding_ipv4: "%s"
|} service_name ip)
  in
  service, network

let compose sites =
  let services, networks = sites.domains |>
    List.map (caddy_service sites.name) |>
    List.split in
  let services = List.fold_left (String.cat) "" services in
  let networks = List.fold_left (fun net n -> match n with | Some n -> net ^ n | None -> net) "" networks |>
    function "" -> "" | n -> "networks:" ^ n in
  Fmt.str {|
version: "3.7"
services:%s
%s
|} services networks

(* Replace $IMAGE_HASH in the compose file with the fixed (hash) image id *)
let replace_hash_var ~hash contents =
  Re.Str.(global_replace (regexp_string "$IMAGE_HASH") hash contents)

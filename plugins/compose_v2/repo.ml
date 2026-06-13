type t = {
  name : string;
  image : Current_docker.Raw.Image.t;
}

(* The value substituted into the compose file in place of [name].
   [Image.hash] is a pinned pull reference (e.g. [repo@sha256:...]). *)
let digest t = Current_docker.Raw.Image.hash t.image
let name t = t.name

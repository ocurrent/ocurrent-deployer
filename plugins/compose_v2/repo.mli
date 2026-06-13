type t = {
  name : string;
  image : Current_docker.Raw.Image.t;
}

val digest : t -> string
val name : t -> string

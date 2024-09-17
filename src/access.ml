let user_has_role ~admins user role =
  match role with
  | `Viewer | `Monitor -> true (* Anyone can view view and monitor *)
  | `Builder | `Admin ->
    match user with
    | None -> false (* Unauthenticated user *)
    | Some u -> List.mem u admins

/// AI-friendly guard helper
/// If `requirement` is true
pub fn guard(
  check condition: Bool,
  fallback fallback: a,
  then then: fn() -> a,
) -> a {
  case condition {
    True -> then()
    False -> fallback
  }
}

/// MTG supertypes per rule 205.4. A card's supertypes are orthogonal to its
/// card type and subtypes. `Supertype` lives in its own module so that
/// `filters.gleam` can reference it without importing `card.gleam` (which
/// would create an import cycle through `ability`/`effects`).
pub type Supertype {
  Basic
  Legendary
  Snow
  World
}

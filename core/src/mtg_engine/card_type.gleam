pub type CardType {
  Land
  Creature
  Instant
  Sorcery
  Artifact
  Enchantment
}

pub fn to_string(ct: CardType) -> String {
  case ct {
    Land -> "land"
    Creature -> "creature"
    Instant -> "instant"
    Sorcery -> "sorcery"
    Artifact -> "artifact"
    Enchantment -> "enchantment"
  }
}

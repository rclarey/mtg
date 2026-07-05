import mtg_engine/card_type
import mtg_engine/color
import mtg_engine/supertype
import mtg_engine/zone

pub type ColorRef {
  Literal(color.Color)
  Chosen
}

pub type CardRestriction {
  Tapped
  Untapped
}

pub type ControllerFilter {
  Any
  You
  Opponent
  TargetPlayer
}

pub type CardFilter {
  Types(List(card_type.CardType))
  Color(ColorRef)
  Name(String)
  Subtype(String)
  Supertype(supertype.Supertype)
  Not(CardFilter)
  And(CardFilter, CardFilter)
  Or(CardFilter, CardFilter)
  WithController(ControllerFilter)
  WithRestriction(CardRestriction)
  Zone(zone.Zone)
  AnyCard
}

pub fn creature() -> CardFilter {
  Types([card_type.Creature])
}

pub fn artifacts_and_enchantments() -> CardFilter {
  Types([card_type.Artifact, card_type.Enchantment])
}

pub fn creature_target_controls() -> CardFilter {
  And(Types([card_type.Creature]), WithController(Opponent))
}

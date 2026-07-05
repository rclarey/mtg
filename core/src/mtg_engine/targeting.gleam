import mtg_engine/filters
import mtg_engine/zone

pub type TargetType {
  Player
  Creature
  Artifact
  Enchantment
  Spell
  Land
}

pub type TargetFilter {
  Any
  Single(TargetType)
  Color(filters.ColorRef)
  Zone(zone.Zone)
  Not(TargetFilter)
  And(TargetFilter, TargetFilter)
  Or(TargetFilter, TargetFilter)
}

pub type TargetCount {
  One
  UpTo(Int)
  Exactly(Int)
  AnyNumber
}

pub type TargetInfo {
  TargetInfo(filter: TargetFilter, count: TargetCount)
}

pub type TargetRef {
  PrimaryTarget
  SecondaryTarget
  Controller
  Source
  AllOf(filters.CardFilter)
  TriggerSubject
}

pub fn target_info(filter: TargetFilter) -> TargetInfo {
  TargetInfo(filter:, count: One)
}

pub fn any_target() -> TargetInfo {
  target_info(Any)
}

pub fn player_target() -> TargetInfo {
  target_info(Single(Player))
}

pub fn creature_target() -> TargetInfo {
  target_info(Single(Creature))
}

pub type TargetIdentifier {
  TargetCard(card_id: String)
  TargetPlayer(player_id: Int)
}

pub type ChosenTargets {
  ChosenTargets(targets: List(TargetIdentifier))
}

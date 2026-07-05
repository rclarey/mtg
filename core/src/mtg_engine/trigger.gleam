import gleam/option.{type Option}
import mtg_engine/filters.{type CardFilter}
import mtg_engine/step
import mtg_engine/targeting.{type TargetFilter}

pub type Trigger {
  EntersBattlefield
  LeavesBattlefield
  Dies
  Attacks
  Blocks
  DealsDamage(filter: Option(TargetFilter))
  DealsCombatDamage(filter: Option(TargetFilter))
  Discarded(filter: CardFilter)
  AtStep(step: step.Step)
}

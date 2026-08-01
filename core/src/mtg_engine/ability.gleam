import gleam/option.{type Option}
import mtg_engine/effects
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/targeting
import mtg_engine/trigger
import mtg_engine/zone

pub type CostComponent {
  Mana(mana.Cost)
  TapSelf
  SacrificeThis
  Sacrifice(filters.CardFilter)
  SacrificeAny(filters.CardFilter)
  PayLife(Int)
}

pub type SpellAbility {
  SpellAbility(
    targets: List(targeting.TargetInfo),
    additional_costs: List(CostComponent),
    effect: effects.Effect,
  )
}

pub type ActivatedAbility {
  ActivatedAbility(
    cost: List(CostComponent),
    targets: List(targeting.TargetInfo),
    effect: effects.Effect,
  )
}

pub type TriggeredAbility {
  TriggeredAbility(
    trigger: trigger.Trigger,
    targets: List(targeting.TargetInfo),
    effect: effects.Effect,
    optional: Bool,
    intervening_if: Option(filters.CardFilter),
  )
}

pub type StaticAbility {
  StaticAbility(effect: effects.StaticEffect, zones: List(zone.Zone))
}

pub type Ability {
  Spell(SpellAbility)
  Activated(ActivatedAbility)
  Triggered(TriggeredAbility)
  Static(StaticAbility)
}

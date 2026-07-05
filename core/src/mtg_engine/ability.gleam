import gleam/option.{type Option}
import mtg_engine/effects
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/targeting
import mtg_engine/trigger
import mtg_engine/zone

pub type ActivationCost {
  NoCost
  Costs(List(CostComponent))
}

pub type CostComponent {
  Mana(mana.Cost)
  TapSelf
  SacrificeThis
  Sacrifice(filters.CardFilter)
  SacrificeAny(filters.CardFilter)
  PayLife(effects.Amount)
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
    cost: ActivationCost,
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

pub fn tap_cost() -> ActivationCost {
  Costs([TapSelf])
}

pub fn tap_mana_cost(cost: mana.Cost) -> ActivationCost {
  Costs([TapSelf, Mana(cost)])
}

pub fn sacrifice_cost(filter: filters.CardFilter) -> ActivationCost {
  Costs([Sacrifice(filter)])
}

pub fn sacrifice_this_cost() -> ActivationCost {
  Costs([SacrificeThis])
}

pub fn tap_sacrifice_cost(filter: filters.CardFilter) -> ActivationCost {
  Costs([TapSelf, Sacrifice(filter)])
}

pub fn tap_sacrifice_this_cost() -> ActivationCost {
  Costs([TapSelf, SacrificeThis])
}

pub fn life_cost(life: Int) -> ActivationCost {
  Costs([PayLife(effects.Fixed(life))])
}

pub fn mana_life_cost(cost: mana.Cost, life: Int) -> ActivationCost {
  Costs([Mana(cost), PayLife(effects.Fixed(life))])
}

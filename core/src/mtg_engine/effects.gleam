import mtg_engine/card_type
import mtg_engine/color
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/step
import mtg_engine/targeting
import mtg_engine/zone

pub type Amount {
  Fixed(Int)
  X
  Count(filters.CardFilter)
  Multiply(Amount, Int)
  PreviousStep
}

pub type Duration {
  Permanent
  EndOfTurn
  EndOfNextTurn
}

pub type Keyword {
  Flying
  Trample
  FirstStrike
  DoubleStrike
  Haste
  Vigilance
  Deathtouch
  Mountainwalk
  Hexproof
  Shroud
  ProtectionFromColor(color.Color)
  ProtectionFromType(card_type.CardType)
}

pub type TokenDefinition {
  TokenDefinition(
    name: String,
    power: Int,
    toughness: Int,
    types: List(card_type.CardType),
    keywords: List(Keyword),
  )
}

pub type Effect {
  Single(EffectStep)
  Sequence(List(EffectStep))
}

pub type ModalMode {
  ModalMode(targets: List(targeting.TargetInfo), effect: Effect)
}

pub type EffectStep {
  RevealHand(of: targeting.TargetRef, to: RevealTo)
  Discard(who: targeting.TargetRef, filter: filters.CardFilter)
  DealDamage(
    amount: Amount,
    target: targeting.TargetRef,
    source_is_combat: Bool,
  )
  DrawCards(num: Amount, target: targeting.TargetRef)
  Bounce(target: targeting.TargetRef)
  Destroy(target: targeting.TargetRef, cant_regenerate: Bool)
  MoveCard(
    target: targeting.TargetRef,
    from_zone: zone.Zone,
    to_zone: zone.Zone,
  )
  GainLife(amount: Amount, target: targeting.TargetRef)
  LoseLife(amount: Amount, target: targeting.TargetRef)
  PumpCreature(
    target: targeting.TargetRef,
    power: Amount,
    toughness: Amount,
    add_keywords: List(Keyword),
    duration: Duration,
  )
  Regenerate(target: targeting.TargetRef)
  CounterSpell(target: targeting.TargetRef)
  ProduceMana(mana: mana.Produced)
  CreateToken(token: TokenDefinition)
  ChooseColor
  PreventDamage(target: targeting.TargetRef, mode: PreventionMode)
  TapOrUntap(target: targeting.TargetRef, mode: TapMode)
  Mill(num: Amount, target: targeting.TargetRef)
  Scry(num: Amount, target: targeting.TargetRef)
  SearchLibrary(
    target: targeting.TargetRef,
    filter: filters.CardFilter,
    destination: SearchDestination,
    reveal: Bool,
    tapped: Bool,
  )
  GainControl(target: targeting.TargetRef, duration: Duration)
  DealDividedDamage(total_amount: Amount)
  ChooseOne(modes: List(ModalMode))
  FlipCoin(flipper: targeting.TargetRef)
  ManaClash(target: targeting.TargetRef)
  ExtraTurn(target: targeting.TargetRef)
  CreateDelayedTrigger(trigger: DelayedTrigger)
  LoseGame(target: targeting.TargetRef)
}

pub type PreventionMode {
  Shield(amount: Amount)
  AllFromSource
  GlobalCombat
}

pub type TapMode {
  Tap
  Untap
}

pub type RevealTo {
  Controller
  Target
}

pub type SearchDestination {
  Hand
  Battlefield
}

pub type Layer {
  LayerCopy
  LayerControl
  LayerText
  LayerType
  LayerColor
  LayerAbility
  LayerPT
}

pub type TimestampedEffect {
  TimestampedEffect(effect: StaticEffect, timestamp: Int, source: String)
}

pub type StaticEffect {
  PumpAll(
    filter: filters.CardFilter,
    power: Int,
    toughness: Int,
    keywords: List(Keyword),
  )
  GrantKeyword(filter: filters.CardFilter, keyword: Keyword)
}

/// Map a StaticEffect to its corresponding layer per MTG rule 613.
pub fn effect_layer(effect: StaticEffect) -> Layer {
  case effect {
    PumpAll(..) -> LayerPT
    GrantKeyword(..) -> LayerAbility
  }
}

/// Return a numeric priority for a Layer (lower = applied first).
pub fn layer_priority(layer: Layer) -> Int {
  case layer {
    LayerCopy -> 1
    LayerControl -> 2
    LayerText -> 3
    LayerType -> 4
    LayerColor -> 5
    LayerAbility -> 6
    LayerPT -> 7
  }
}

pub fn keyword_to_string(keyword: Keyword) -> String {
  case keyword {
    Flying -> "Flying"
    Trample -> "Trample"
    FirstStrike -> "First strike"
    DoubleStrike -> "Double strike"
    Haste -> "Haste"
    Vigilance -> "Vigilance"
    Deathtouch -> "Deathtouch"
    Mountainwalk -> "Mountainwalk"
    Hexproof -> "Hexproof"
    Shroud -> "Shroud"
    ProtectionFromColor(color) -> "Protection from " <> color_to_string(color)
    ProtectionFromType(card_type) ->
      "Protection from " <> card_type_to_protection_string(card_type)
  }
}

fn color_to_string(c: color.Color) -> String {
  case c {
    color.White -> "White"
    color.Blue -> "Blue"
    color.Black -> "Black"
    color.Red -> "Red"
    color.Green -> "Green"
    color.Colorless -> "Colorless"
  }
}

fn card_type_to_protection_string(ct: card_type.CardType) -> String {
  case ct {
    card_type.Land -> "lands"
    card_type.Creature -> "creatures"
    card_type.Instant -> "instants"
    card_type.Sorcery -> "sorceries"
    card_type.Artifact -> "artifacts"
    card_type.Enchantment -> "enchantments"
  }
}

pub type CoinFlipResult {
  Heads
  Tails
}

pub type TriggerEvent {
  AtStep(step: step.Step)
  WhenDealsDamage
  WhenLeavesBattlefield
}

pub type TriggerDuration {
  Once
  UntilEndOfTurn
}

pub type DelayedTrigger {
  DelayedTrigger(
    event: TriggerEvent,
    effect: Effect,
    controller: Int,
    duration: TriggerDuration,
  )
}

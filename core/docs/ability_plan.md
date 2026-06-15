# Ability Representation Plan

Types for encoding Magic: The Gathering abilities in Gleam. Covers spell abilities (instants/sorceries), activated abilities, triggered abilities, and static abilities with their effects, targeting, and sequencing.

---

## Table of Contents

1. [Foundational Types](#foundational-types)
2. [Targeting](#targeting)
3. [Card Filters](#card-filters)
4. [Effects](#effects)
5. [Abilities](#abilities)
6. [Design Notes](#design-notes)
7. [Open Questions](#open-questions)

---

## Foundational Types

### Amount

Numeric value that may be fixed or variable.

```gleam
pub type Amount {
  Fixed(Int)
  X
  Count(CardFilter)            // Permanents on battlefield matching filter
  Multiply(Amount, Int)        // Amount * scalar
  PreviousStep                 // Numeric output of the immediately preceding EffectStep
}
```

`PreviousStep` enables compound effects (e.g., deal damage → gain life equal to damage dealt). See Compound Effects section.

### Duration

```gleam
pub type Duration {
  Permanent
  EndOfTurn
  EndOfNextTurn
}
```

### Keyword

```gleam
pub type Keyword {
  Flying
  Trample
  FirstStrike
  Haste
  Vigilance
  Deathtouch
  Mountainwalk
}
```

### Token Definition

```gleam
pub type TokenDefinition {
  TokenDefinition(
    name: String,
    power: Int,
    toughness: Int,
    types: List(card.CardType),
    keywords: List(Keyword),
  )
}
```

### Activation Cost

```gleam
pub type ActivationCost {
  NoCost
  Costs(List(CostComponent))
}

pub type CostComponent {
  Mana(mana.Cost)
  TapSelf
  SacrificeThis
  Sacrifice(CardFilter)
  SacrificeAny(CardFilter)
  PayLife(Amount)
}
```

**Future variants (not in 7th edition):** `TapAnother(CardFilter)` for Opposition-style costs.

**Convenience aliases:**
- `tap_cost()` — `Costs([TapSelf])`
- `tap_mana_cost(cost)` — `Costs([TapSelf, Mana(cost)])`
- `sacrifice_cost(filter)` — `Costs([Sacrifice(filter)])`
- `sacrifice_this_cost()` — `Costs([SacrificeThis])`
- `tap_sacrifice_cost(filter)` — `Costs([TapSelf, Sacrifice(filter)])`
- `tap_sacrifice_this_cost()` — `Costs([TapSelf, SacrificeThis])`
- `life_cost(life)` — `Costs([PayLife(Fixed(life))])`
- `mana_life_cost(cost, life)` — `Costs([Mana(cost), PayLife(Fixed(life))])`

### TargetRef

References to objects selected during targeting or implied by game state. Used throughout `EffectStep`.

```gleam
pub type TargetRef {
  PrimaryTarget    // First declared target
  SecondaryTarget  // Second declared target
  Controller       // Controller of the spell/ability being resolved ("you", rule 109.5)
  Source           // The source permanent of the activated ability ("itself")
  AllOf(CardFilter) // All cards matching a filter on the battlefield
  TriggerSubject   // Player/object referenced by a trigger event (Phase E)
}
```

---

## Targeting

### Target Types

```gleam
pub type TargetType {
  Player
  Creature
  Artifact
  Enchantment
  Spell
  Land
}
```

### Target Filter

Combinators for complex targeting requirements.

```gleam
pub type TargetFilter {
  Any                          // Any target (creature, player, planeswalker, battle)
  Single(TargetType)           // Single(Creature)
  Color(ColorRef)              // Color(Literal(Black)), Color(Chosen)
  Zone(game.Zone)              // Zone(Graveyard) — "card in graveyard"
  Not(TargetFilter)
  And(TargetFilter, TargetFilter)
  Or(TargetFilter, TargetFilter)
}
```

**Note:** `Zone` enables zone-based targeting (e.g., "creature card in graveyard"). The "your" in phrases like "from your graveyard" is implicit — the game engine enforces that targets must be in the ability controller's corresponding zone. For "target player's graveyard," the player is specified as a separate target. The `Not` combinator is added here (vs. the original plan which only had `Any`/`Single`/`And`/`Or`) for composable negation.

### Target Count

For abilities targeting multiple objects per instance of "target."

```gleam
pub type TargetCount {
  One                    // Default
  UpTo(Int)              // "Up to N target(s)"
  Exactly(Int)           // Exactly N targets
  Any                    // Any number (min 1), e.g., divided damage
}
```

### Target Info

```gleam
pub type TargetInfo {
  TargetInfo(
    filter: TargetFilter,
    count: TargetCount,
  )
}

fn target_info(filter: TargetFilter) -> TargetInfo {
  TargetInfo(filter:, count: One)
}
```

**Helpers:** `any_target()`, `player_target()`, `creature_target()`.

---

## Card Filters

### Color Reference

```gleam
pub type ColorRef {
  Literal(card.Color)
  Chosen
}
```

`Chosen` refers to the color selected by the nearest preceding `ChooseColor` effect step.

### Card Restriction

```gleam
pub type CardRestriction {
  Tapped
  Untapped
}
```

### Controller Filter

```gleam
pub type ControllerFilter {
  Any
  You
  Opponent
  TargetPlayer
}
```

### Card Filter

```gleam
pub type CardFilter {
  Types(List(card.CardType))
  Color(ColorRef)
  Name(String)
  Subtype(String)
  Supertype(String)            // e.g., "Basic", "Legendary" — see card.Supertype
  Not(CardFilter)
  And(CardFilter, CardFilter)
  Or(CardFilter, CardFilter)
  WithController(ControllerFilter)
  WithRestriction(CardRestriction)
  Zone(game.Zone)              // for non-battlefield zones
  AnyCard
}
```

`Supertype` was added here to correctly filter "basic land" and "legendary" without conflating supertypes with card types or colors.

**Helpers:** `creature()`, `artifacts_and_enchantments()`, `creature_target_controls()`.

---

## Effects

### Effect

An ability's effect is a single step or a sequence.

```gleam
pub type Effect {
  Single(EffectStep)
  Sequence(List(EffectStep))
}
```

### Modal Mode

A single option within a "Choose one —" spell (rule 700.2).

```gleam
pub type ModalMode {
  ModalMode(
    targets: List(TargetInfo),
    effect: Effect,
  )
}
```

### Effect Step

Each step represents a discrete game action. Steps that produce a numeric result document what `Amount.PreviousStep` will yield.

```gleam
pub type EffectStep {
  // Reveal cards from a player's hand to a player
  RevealHand(of: TargetRef, to: RevealTo)
  // Discard cards — PreviousStep = number of cards discarded
  Discard(who: TargetRef, filter: CardFilter)
  // Damage — PreviousStep = damage actually dealt
  DealDamage(amount: Amount, target: TargetRef, source_is_combat: Bool)
  // Draw cards
  DrawCards(num: Amount, target: TargetRef)
  // Return permanent to hand
  Bounce(target: TargetRef)
  // Destroy — PreviousStep = 1 if destroyed, 0 otherwise
  Destroy(target: TargetRef, cant_regenerate: Bool)
  // Move card between zones
  MoveCard(target: TargetRef, from_zone: game.Zone, to_zone: game.Zone)
  // Life gain — PreviousStep = life gained
  GainLife(amount: Amount, target: TargetRef)
  // Life loss — PreviousStep = life lost
  LoseLife(amount: Amount, target: TargetRef)
  // Pump creature
  PumpCreature(
    target: TargetRef,
    power: Amount,
    toughness: Amount,
    add_keywords: List(Keyword),
    duration: Duration,
  )
  // Regenerate
  Regenerate(target: TargetRef)
  // Counter spell
  CounterSpell(target: TargetRef)
  // Add mana to pool
  ProduceMana(mana: mana.Produced)
  // Create token
  CreateToken(token: TokenDefinition)
  // Choose a color — stored for ColorRef.Chosen
  ChooseColor
  // Prevent damage — creates a continuous prevention shield
  PreventDamage(target: TargetRef, mode: PreventionMode)
  // Tap or untap
  TapOrUntap(target: TargetRef, mode: TapMode)
  // Mill — PreviousStep = cards milled (rule 701.17)
  Mill(num: Amount, target: TargetRef)
  // Scry (rule 701.22)
  Scry(num: Amount, target: TargetRef)
  // Search library — shuffles automatically per rule 701.18a
  SearchLibrary(
    target: TargetRef,
    filter: CardFilter,
    destination: SearchDestination,
    reveal: Bool,
    tapped: Bool,
  )
  // Gain control
  GainControl(target: TargetRef, duration: Duration)
  // Divided damage — per-target allocation stored on StackItem
  DealDividedDamage(total_amount: Amount)
  // Modal — "Choose one —" (rule 700.2). Chosen mode stored on StackItem.
  ChooseOne(modes: List(ModalMode))
  // Flip a coin — PreviousStep = 1 for heads, 0 for tails (rule 705)
  FlipCoin(flipper: TargetRef)
  // Dedicated step for Mana Clash's repeat-until-both-heads loop
  ManaClash(target: TargetRef)
  // Extra turn after current one (rule 500.7)
  ExtraTurn(target: TargetRef)
  // Create a delayed triggered ability (rule 603.7)
  CreateDelayedTrigger(trigger: DelayedTrigger)
  // Player loses the game (rule 104.2e)
  LoseGame(target: TargetRef)
}

pub type PreventionMode {
  Shield(amount: Amount)       // "Prevent the next N damage"
  AllFromSource                // "Prevent all damage from source"
  GlobalCombat                 // "Prevent all combat damage this turn"
}

pub type TapMode { Tap Untap }
pub type RevealTo { Controller Target }
pub type SearchDestination { Hand Battlefield }

pub type CoinFlipResult { Heads Tails }
```

### Compound Effects

Some effects chain two operations where the second depends on the first's numeric result. `Amount.PreviousStep` provides access to the preceding step's output:

**Per-step output semantics:**
- `DealDamage` → damage actually dealt (after replacement/prevention)
- `Discard` → number of cards discarded
- `GainLife` / `LoseLife` → life gained/lost
- `Mill` → cards milled
- `FlipCoin` → 1 (heads), 0 (tails)
- All others → 0

---

## Abilities

### Spell Ability

```gleam
pub type SpellAbility {
  SpellAbility(
    targets: List(TargetInfo),
    additional_costs: List(CostComponent),
    effect: Effect,
  )
}
```

### Activated Ability

```gleam
pub type ActivatedAbility {
  ActivatedAbility(
    cost: ActivationCost,
    targets: List(TargetInfo),
    effect: Effect,
  )
}
```

### Triggered Ability (Phase E)

```gleam
pub type TriggeredAbility {
  TriggeredAbility(
    trigger: Trigger,
    targets: List(TargetInfo),
    effect: Effect,
    optional: Bool,
    intervening_if: Option(CardFilter),
  )
}

pub type Trigger {
  EntersBattlefield
  LeavesBattlefield
  Dies
  Attacks
  Blocks
  DealsDamage(filter: Option(TargetFilter))
  DealsCombatDamage(filter: Option(TargetFilter))
  Discarded(filter: CardFilter)
  AtStep(step: game.Step)
}
```

### Static Ability (Phase E)

```gleam
pub type StaticAbility {
  StaticAbility(
    effect: StaticEffect,
    zones: List(game.Zone),
  )
}

pub type StaticEffect {
  PumpAll(filter: CardFilter, power: Int, toughness: Int, keywords: List(Keyword))
  GrantKeyword(filter: CardFilter, keyword: Keyword)
}
```

### Ability Union

```gleam
pub type Ability {
  Spell(SpellAbility)
  Activated(ActivatedAbility)
  Triggered(TriggeredAbility)
  Static(StaticAbility)
}
```

### Delayed Triggered Abilities

```gleam
pub type DelayedTrigger {
  DelayedTrigger(
    event: TriggerEvent,
    effect: Effect,
    controller: Int,
    duration: TriggerDuration,
  )
}

pub type TriggerEvent {
  AtStep(step: game.Step)
  WhenDealsDamage
  WhenLeavesBattlefield
}

pub type TriggerDuration {
  Once
  UntilEndOfTurn
}
```

---

## Card Examples

### 1. Simple Targeted Spells (Shock, Giant Growth, Counterspell, Inspiration)

```gleam
// Shock — "2 damage to any target"
Ability.Spell(SpellAbility(
  targets: [TargetInfo(Any)],
  additional_costs: [],
  effect: Effect.Single(EffectStep.DealDamage(
    amount: Amount.Fixed(2), target: TargetRef.PrimaryTarget,
    source_is_combat: False,
  ))
))
```

Giant Growth flips `target` to `Single(Creature)` and effect to `PumpCreature`. Counterspell uses `Single(Spell)` and `CounterSpell`. Inspiration uses `Single(Player)` and `DrawCards`. All share this same structure.

### 2. Activated Abilities (Llanowar Elves, Prodigal Sorcerer, Seeker of Skybreak)

```gleam
// Llanowar Elves — "{T}: Add {G}"
Ability.Activated(ActivatedAbility(
  cost: tap_cost(),
  targets: [],
  effect: Effect.Single(EffectStep.ProduceMana(
    mana: mana.Produced(green: 1, white: 0, blue: 0, black: 0, red: 0, colorless: 0),
  ))
))
```

Prodigal Sorcerer adds targeting and swaps effect to `DealDamage(Fixed(1), PrimaryTarget)`. Seeker of Skybreak adds targeting and uses `TapOrUntap(..., Untap)`.

### 3. Destroy Effects (Disenchant, Wrath of God, Dark Banishing)

```gleam
// Disenchant — "Destroy target artifact or enchantment"
Ability.Spell(SpellAbility(
  targets: [TargetInfo(Or(Single(Artifact), Single(Enchantment)))],
  additional_costs: [],
  effect: Effect.Single(EffectStep.Destroy(
    target: TargetRef.PrimaryTarget, cant_regenerate: False,
  ))
))

// Wrath of God — "Destroy all creatures. They can't be regenerated."
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Single(EffectStep.Destroy(
    target: TargetRef.AllOf(CardFilter.Types([card.Creature])),
    cant_regenerate: True,
  ))
))
```

**Dark Banishing** ("Destroy target nonblack creature. It can't be regenerated.") combines creature type and color. With `TargetFilter.Color(ColorRef)`, the filter is `And(Single(Creature), Not(Color(Literal(Black))))`.

### 4. Modal Spells (Healing Salve)

```gleam
// Healing Salve — "Choose one — Target player gains 3 life; or prevent next 3 damage to any target"
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Single(EffectStep.ChooseOne(modes: [
    ModalMode(targets: [TargetInfo(Single(Player))],
      effect: Effect.Single(EffectStep.GainLife(amount: Fixed(3), target: PrimaryTarget))),
    ModalMode(targets: [TargetInfo(Any)],
      effect: Effect.Single(EffectStep.PreventDamage(target: PrimaryTarget,
        mode: Shield(amount: Fixed(3))))),
  ]))
))
```

### 5. Compound Effects (Corrupt, Tolarian Winds)

```gleam
// Corrupt — "Deal damage equal to Swamps you control. Gain life equal to damage dealt."
Ability.Spell(SpellAbility(
  targets: [TargetInfo(Any)],
  additional_costs: [],
  effect: Effect.Sequence([
    EffectStep.DealDamage(
      amount: Amount.Count(And(Types([card.Land]), Name("Swamp"),
        WithController(You))),
      target: PrimaryTarget, source_is_combat: False),
    EffectStep.GainLife(amount: Amount.PreviousStep, target: Controller),
  ])
))

// Tolarian Winds — "Discard your hand, then draw that many cards."
// Same pattern: Discard → DrawCards(PreviousStep)
```

### 6. Prevention (Fog, Samite Healer, Reverse Damage, Circle of Protection: Red)

```gleam
// Fog — "Prevent all combat damage that would be dealt this turn"
EffectStep.PreventDamage(target: Controller, mode: GlobalCombat)

// Samite Healer — "{T}: Prevent next 1 damage to any target"
EffectStep.PreventDamage(target: PrimaryTarget, mode: Shield(amount: Fixed(1)))

// Reverse Damage — "Prevent all damage to you from target creature. If damage
// is prevented this way, deal that much damage to that creature's controller."
// Uses AllFromSource mode. The follow-up damage is handled by rule 615.5
// (prevention effects with additional effect) at engine level, not as a Sequence step.
```

### 7. Extra Turn / Delayed Trigger (Final Fortune)

```gleam
Ability.Spell(SpellAbility(
  targets: [], additional_costs: [],
  effect: Effect.Sequence([
    EffectStep.ExtraTurn(target: Controller),
    EffectStep.CreateDelayedTrigger(trigger: DelayedTrigger(
      event: AtStep(step: game.EndStep),
      effect: Effect.Single(EffectStep.LoseGame(target: Controller)),
      controller: 0, duration: Once,
    )),
  ])
))
```

### 8. Variable Damage (Spitting Earth, Starlight)

```gleam
// Spitting Earth — "Deals damage = number of Mountains you control"
Amount.Count(And(Types([card.Land]), Name("Mountain"), WithController(You)))

// Starlight — "You gain 3 life for each black creature target opponent controls"
Amount.Multiply(Amount.Count(And(Types([card.Creature]), Color(Literal(Black)),
  WithController(TargetPlayer))), 3)
```

### 9. Sacrifice as Cost (Bloodshot Cyclops, Ghitu Fire-Eater, Reprocess)

```gleam
// Ghitu Fire-Eater — "{T}, Sacrifice this: 2 damage to any target"
Ability.Activated(ActivatedAbility(
  cost: Costs([TapSelf, SacrificeThis]),
  targets: [TargetInfo(Any)],
  effect: Effect.Single(EffectStep.DealDamage(amount: Fixed(2),
    target: PrimaryTarget, source_is_combat: False))
))

// Bloodshot Cyclops — damage = sacrificed creature's power
// Needs Amount.PreviousStep or a dedicated Amount.PaidPower variant for the
// sacrificed creature's power. Deferred — see Open Questions.

// Reprocess — "Sacrifice any number of artifacts, creatures, and/or lands.
// Draw a card for each permanent sacrificed this way."
// Uses SacrificeAny as additional cost + DrawCards(PreviousStep)
```

### 10. Divided Damage (Pyrotechnics)

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(filter: Any, count: Any)],
  additional_costs: [],
  effect: Effect.Single(EffectStep.DealDividedDamage(total_amount: Fixed(4)))
))
```

### 11. Search Library (Rampant Growth, Goblin Matron)

```gleam
// Rampant Growth — "Search for a basic land, put onto battlefield tapped"
EffectStep.SearchLibrary(
  target: Controller,
  filter: And(Types([card.Land]), Supertype("Basic")),
  destination: Battlefield, reveal: False, tapped: True,
)
```

**Note:** "Basic" is a supertype, not a color. The `CardFilter.Supertype` variant handles this. The existing `card` module needs a `Supertype` type added.

### 12. Pay Life as Cost (Greed, Strands of Night, Phyrexian Colossus, Necrologia)

```gleam
// Greed — "{1}{B}, Pay 2 life: Draw a card"
ActivatedAbility(
  cost: Costs([Mana(Cost(black: 1, generic: 1)), PayLife(Fixed(2))]),
  targets: [],
  effect: Effect.Single(DrawCards(num: Fixed(1), target: Controller)),
)

// Necrologia — "As an additional cost, pay X life. You draw X cards."
SpellAbility(
  targets: [],
  additional_costs: [PayLife(Amount.X)],
  effect: Effect.Single(DrawCards(num: Amount.X, target: Controller)),
)
```

### 13. Static Abilities (Phase E)

```gleam
// Glorious Anthem — "Creatures you control get +1/+1"
Ability.Static(StaticAbility(
  effect: PumpAll(
    filter: And(Types([card.Creature]), WithController(You)),
    power: 1, toughness: 1, keywords: [],
  ),
  zones: [Battlefield],
))

// Goblin King — "Other Goblins get +1/+1 and have mountainwalk"
Ability.Static(StaticAbility(
  effect: PumpAll(
    filter: And(Subtype("Goblin"), Not(Name("Goblin King"))),
    power: 1, toughness: 1, keywords: [Mountainwalk],
  ),
  zones: [Battlefield],
))
```

### 14. Triggered Abilities (Phase E)

```gleam
// Abyssal Specter — "Whenever ~ deals combat damage to a player, that player discards"
Ability.Triggered(TriggeredAbility(
  trigger: DealsCombatDamage(filter: Some(Single(Player))),
  targets: [],
  effect: Effect.Single(Discard(who: TriggerSubject, filter: Zone(Hand))),
  optional: False, intervening_if: None,
))

// Seasoned Marshal — "Whenever ~ attacks, you may tap target creature"
Ability.Triggered(TriggeredAbility(
  trigger: Attacks,
  targets: [TargetInfo(Single(Creature))],
  effect: Effect.Single(TapOrUntap(target: PrimaryTarget, mode: Tap)),
  optional: True, intervening_if: None,
))
```

---

### 15. Zone-Based Targeting (Strands of Night, Gravedigger)

```gleam
// Strands of Night — "Return target creature card from your graveyard to the battlefield"
Ability.Activated(ActivatedAbility(
  cost: costs([Mana(Cost(black: 1, generic: 1)), PayLife(Fixed(2)),
    Sacrifice(And(Types([card.Land]), Name("Swamp")))]),
  targets: [TargetInfo(And(Single(Creature), Zone(Graveyard)))],
  effect: Effect.Single(EffectStep.Bounce(target: PrimaryTarget)),
))

// Gravedigger — "When Gravedigger enters the battlefield, return target
// creature card from your graveyard to your hand."
Ability.Triggered(TriggeredAbility(
  trigger: EntersBattlefield,
  targets: [TargetInfo(And(Single(Creature), Zone(Graveyard)))],
  effect: Effect.Single(EffectStep.Bounce(target: PrimaryTarget)),
  optional: False, intervening_if: None,
))
```

Note: Strands of Night's cost also demonstrates multiple cost components (mana, life, sacrifice).

---

## Design Notes

### Regeneration and "Can't Be Regenerated"

The `Destroy` effect step includes `cant_regenerate: Bool`. When `True`, the destruction cannot be replaced by regeneration shields (per rule 608.2c, 701.9, and 701.25c). This is a property of the destruction event, not a separate effect step — hence the boolean flag on `Destroy`.

Regeneration creates a replacement effect: "The next time [permanent] would be destroyed this turn, instead remove all damage marked on it and its controller taps it. If it's an attacking or blocking creature, remove it from combat." (rule 701.9, local numbering).

### Target vs Affected

- **Targeting**: What the player chooses when casting/activating — defined by `targets: List(TargetInfo)` on the ability.
- **Affected**: What the effect actually modifies — defined by `TargetRef` in effect steps.

Example: "Target player discards a card" — player is both targeted and the discard source; cards in hand are the affected objects (via `CardFilter.Zone(Hand)`).

### Variable X

Cards with X in their costs store `Amount.X` in the effect. The actual value is determined when the card is cast (rule 601.2b).

### "Other" Self-Exclusion

Lord effects exclude themselves using `CardFilter.Not(CardFilter.Name("<self>"))`. The engine passes the source's name at evaluation time.

### Layer System

Static abilities interact through the layer system (rule 613):
- Layer 6: Keyword grants (`GrantKeyword`)
- Layer 7d: Power/toughness modifications (`PumpAll`)

### Delayed vs. Standard Triggered Abilities

Standard triggered abilities are printed on cards and exist as long as the card is in the appropriate zone. Delayed triggered abilities (rule 603.7) are created during resolution and tracked separately on the game state.

---

## Implementation Notes

### Module Structure

- `ability.gleam` — Core types (Amount, Duration, Keyword, TokenDefinition, ActivationCost, Ability union)
- `targeting.gleam` — TargetType, TargetFilter, TargetInfo, TargetCount
- `filters.gleam` — CardFilter, CardRestriction, ControllerFilter, ColorRef
- `effects.gleam` — Effect, EffectStep, PreventMode, TapMode, etc.
- `trigger.gleam` — Trigger, TriggerEvent, TriggerDuration, DelayedTrigger (Phase E)

### Integration Points

- `Card` type needs `abilities: List(Ability)` field
- `StackItem` needs target choices, chosen mode, and per-target allocation tracking
- `game.State` needs active delayed triggers list and static effects tracking

### Upcoming: card.Supertype

The `card` module needs a `Supertype` type for `CardFilter.Supertype`. Basic, Legendary, Snow, and World are supertypes in MTG (rule 205.4).

### Rules Numbering Note

This document references MTG rules by the Wizards of the Coast numbering. The local `core/rules/` files may use different numbering for keyword action sub-rules (e.g., regeneration at 701.9 locally vs. 701.19 officially). When in doubt, refer to the local rules files.

---

## Open Questions

### Subtype-Based Targeting

Goblin Digging Team targets "a Wall." `TargetFilter.Subtype(String)` would handle this.

### Referencing Sacrificed Creature Power

Bloodshot Cyclops's damage depends on the sacrificed creature's power. This needs either an `Amount.PaidPower` variant or a general mechanism to reference objects paid as costs.

### "Choose Two" and Escalate

Modal spells that allow choosing more than one mode ("Choose two —") or have escalate (rule 702.120) need a `ChooseN` variant or `choices: Int` field on `ChooseOne`. Not in 7th edition.

### Replacement Effects

Cards like Ensnaring Bridge, Meekstone, and Wild Growth create replacement effects (rule 614). These require a separate framework and are deferred.

### Characteristic-Defining Abilities (rule 604.3)

CDAs like "~'s power is equal to the number of swamps you control" function in all zones. Deferred.

### Additional Costs from External Effects

"Counter target spell unless its controller pays {2}" applies additional costs from external effects — handled by the engine during resolution, not encoded in ability definitions.

### TapAnother as Cost

Opposition ("Tap an untapped creature you control") needs `CostComponent.TapAnother(CardFilter)`. Structurally similar to `Sacrifice(CardFilter)` but taps instead of sacrifices. Deferred.

### Damage Prevention with Follow-Up (Reverse Damage)

The `AllFromSource` prevention mode's follow-up damage (rule 615.5: "the rest of the effect takes place immediately afterward") is handled by the engine when prevention occurs. The exact engine-level mechanism for "immediately afterward" effects is deferred.

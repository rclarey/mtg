# Ability Representation Plan

## Overview

This document describes the design for encoding Magic: The Gathering abilities in Gleam data structures. The goal is to represent both spell abilities (instants/sorceries) and activated abilities (permanents) with their effects, targeting, and sequencing.

Based on research from the Forge rules engine (Card-Forge/forge) and analysis of Seventh Edition cards.

---

## Table of Contents

1. [Foundational Types](#foundational-types)
2. [Targeting](#targeting)
3. [Card Filters](#card-filters)
4. [Effects](#effects)
5. [Abilities](#abilities)
6. [Design Notes](#design-notes)
7. [Card Examples](#card-examples)
8. [Open Questions](#open-questions)

---

## Foundational Types

### Amount

Represents a numeric value that may be fixed or variable (X).

```gleam
pub type Amount {
  Fixed(Int)
  X
  Count(CardFilter)            // Number of permanents on battlefield matching filter
  Multiply(Amount, Int)        // Amount * scalar (e.g., "3 life for each black creature")
}
```

### Duration

For effects that modify permanents temporarily.

```gleam
pub type Duration {
  Permanent
  EndOfTurn
  EndOfNextTurn
}
```

### Keywords

Used for pump effects and token creation.

```gleam
pub type Keyword {
  Flying
  Trample
  FirstStrike
  Haste
  Vigilance
  Deathtouch
}
```

### Token Definition

For creating token permanents.

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

For activated abilities on permanents. Spell abilities use `NoCost` (mana cost is on the card).

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
  PayLife(Amount)       // Pay N life (rule 118.3b). Players can always pay 0 life.
                        // Uses Amount to support fixed (Fixed(5)) and variable (X) life payments.
}
```

**Convenience aliases** (for common patterns without wrapping in `Costs`):
- `tap_cost()` — `Costs([TapSelf])`
- `tap_mana_cost(cost)` — `Costs([TapSelf, Mana(cost)])`
- `sacrifice_cost(filter)` — `Costs([Sacrifice(filter)])`
- `sacrifice_this_cost()` — `Costs([SacrificeThis])`
- `tap_sacrifice_cost(filter)` — `Costs([TapSelf, Sacrifice(filter)])`
- `tap_sacrifice_this_cost()` — `Costs([TapSelf, SacrificeThis])`
- `life_cost(life)` — `Costs([PayLife(Fixed(life))])`
- `mana_life_cost(cost, life)` — `Costs([Mana(cost), PayLife(Fixed(life))])`

---

## Targeting

### Target Types

The basic things that can be targeted.

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

Combinators for more complex targeting requirements.

```gleam
pub type TargetFilter {
  Any                          // AnyTarget
  Single(TargetType)           // Single(Creature)
  And(TargetFilter, TargetFilter)
  Or(TargetFilter, TargetFilter)
}
```

### Target Count

For abilities that target multiple objects per instance of the word "target" (e.g., "any number of targets" for divided damage, "up to three target lands").

```gleam
pub type TargetCount {
  One                    // Exactly one target (default)
  UpTo(Int)              // Up to N targets
  Exactly(Int)           // Exactly N targets
  Any                    // Any number of targets (minimum 1)
}
```

### Target Info

Information for targets required by an ability.

```gleam
pub type TargetInfo {
  TargetInfo(
    filter: TargetFilter,
    count: TargetCount,
  )
}
```

**Helper functions:**
```gleam
fn target_info(filter: TargetFilter) -> TargetInfo {
  TargetInfo(filter:, count: One)
}
```

**Helper constructors (using `target_info`):**
- `any_target()` → `target_info(Any)`
- `player_target()` → `target_info(Single(Player))`
- `creature_target()` → `target_info(Single(Creature))`

---

## Card Filters

### Color Reference

For filters that need to match a color that may be chosen dynamically.

```gleam
pub type ColorRef {
  Literal(card.Color)
  Chosen
}
```

`Chosen` refers to the color selected by the nearest preceding `ChooseColor` effect step.

### Card Restrictions

Simple restrictions on card state.

```gleam
pub type CardRestriction {
  Tapped
  Untapped
}
```

### Controller Filter

Who controls the affected cards.

```gleam
pub type ControllerFilter {
  Any
  You
  Opponent
  TargetPlayer  // controlled by the spell's targeted player
}
```

### Card Filter

Combinators for matching cards on the battlefield.

```gleam
pub type CardFilter {
  Types(List(card.CardType))           // e.g., Types([Creature])
  Color(ColorRef)                  // e.g., Color(Literal(card.Red))
  Name(String)                     // exact card name match (e.g., "Forest")
  Subtype(String)                  // card subtype (e.g., "Goblin")
  Not(CardFilter)                  // e.g., Not(Color(Literal(card.Black)))
  And(CardFilter, CardFilter)  // e.g., creature AND flying
  Or(CardFilter, CardFilter)  // e.g., artifact OR enchantment
  WithController(ControllerFilter)
  WithRestriction(CardRestriction)
  Zone(Zone)                            // for non-battlefield zones (hand, library, graveyard)
  AnyCard                               // matches any card
}
```

**Helper constructors:**
```gleam
fn creature() -> CardFilter {
  Types([card.Creature])
}

fn artifacts_and_enchantments() -> CardFilter {
  Or(Types([card.Artifact]), Types([card.Enchantment]))
}

fn creatures_target_controls() -> CardFilter {
  And(creature(), WithController(TargetPlayer))
}
```

---

## Effects

### Effect vs Affected

- **TargetRef**: The single object targeted by the spell/ability
- **AllOf**: All cards matching a filter on the battlefield

### Affected

Which objects an effect applies to.

```gleam
pub type Affected {
  Target                           // The targeted object
  AllOf(CardFilter)                // All cards matching filter on battlefield
}
```

### RevealTo

Who sees revealed cards.

```gleam
pub type RevealTo {
  Controller          // spell/ability controller
  Target              // primary target player
}
```

### Tap Mode

Variant for `TapOrUntap` describing whether to tap or untap the target permanent.

```gleam
pub type TapMode {
  Tap
  Untap
}
```

### Prevention Mode

Variant for `PreventDamage` describing the scope of prevention.

```gleam
pub type PreventionMode {
  // "Prevent the next N damage that would be dealt to [TargetRef]"
  // Creates a prevention shield with N charges on the protected object.
  // Covers: Healing Salve, Samite Healer, Master Healer, Circle of Protection
  Shield(amount: Amount)

  // "Prevent all damage that would be dealt to you this turn by [TargetRef]"
  // TargetRef refers to the source creature. Protected entity is implicitly Controller.
  // Covers: Reverse Damage
  AllFromSource

  // "Prevent all combat damage that would be dealt this turn"
  // Global effect, TargetRef is unused.
  // Covers: Fog
  GlobalCombat
}

### Coin Flip Result

The outcome of a single coin flip (rule 705).

```gleam
pub type CoinFlipResult {
  Heads
  Tails
}
```

### Effect Step

A single instruction in an effect sequence.

```gleam
pub type EffectStep {
  // Reveal cards from target player's hand to controller
  RevealHand(
    of: TargetRef,
    to: RevealTo,
  )

  // Discard cards from hand to graveyard
  Discard(
    who: TargetRef,
    filter: CardFilter,
  )

  // Basic damage
  DealDamage(amount: Amount, target: TargetRef, source_is_combat: Bool)

  // Draw cards
  DrawCards(num: Amount, target: TargetRef)

  // Return permanent to hand
  Bounce(target: TargetRef)

  // Destroy permanent
  // When cant_regenerate is True, regeneration shields cannot
  // replace this destruction event (rule 608.2c, 701.19c).
  Destroy(target: TargetRef, cant_regenerate: Bool)

  // Move card between zones (e.g., from graveyard to battlefield)
  MoveCard(target: TargetRef, from_zone: Zone, to_zone: Zone)

  // Life gain
  GainLife(amount: Amount, target: TargetRef)

  // Life loss
  LoseLife(amount: Amount, target: TargetRef)

  // Pump a creature
  PumpCreature(
    target: TargetRef,
    power: Amount,
    toughness: Amount,
    add_keywords: List(Keyword),
    duration: Duration,
  )

  // Regenerate a permanent
  Regenerate(target: TargetRef)

  // Counter a spell
  CounterSpell(target: TargetRef)

  // Add mana to pool
  ProduceMana(mana: mana.Produced)

  // Create token
  CreateToken(token: TokenDefinition)

  // Prompt the controller to choose a color
  // Stores the choice implicitly for reference via ColorRef.Chosen
  ChooseColor

  // Prevent damage — creates a continuous prevention effect
  PreventDamage(
    target: TargetRef,
    mode: PreventionMode,
  )

  // Tap or untap a permanent
  TapOrUntap(
    target: TargetRef,
    mode: TapMode,
  )

  // Mill N cards from top of a player's library into their graveyard
  // Per rule 701.17 ("For a player to mill a number of cards, that player
  // puts that many cards from the top of their library into their graveyard.")
  Mill(num: Amount, target: TargetRef)

  // Scry N — look at the top N cards of a player's library, then put any
  // number of them on the bottom of that library in any order and the rest
  // on top in any order (rule 701.22).
  // For Sage Owl (top 4, no cards go to hand), use scry 4.
  Scry(num: Amount, target: TargetRef)

  // Search a library for cards matching a filter and put them into a
  // destination zone. The library is then shuffled (rule 701.18).
  // Covers: Rampant Growth (basic land to field tapped), Untamed Wilds
  // (basic land to field untapped), Wood Elves (Forest to field),
  // Goblin Matron (Goblin to hand, with reveal).
  SearchLibrary(
    target: TargetRef,
    filter: CardFilter,
    destination: SearchDestination,
    reveal: Bool,
    tapped: Bool,
  )

  // Gain control of a permanent indefinitely or for a duration.
  // Covers: Confiscate, Steal Artifact (Auras — the continuous effect
  // is generated by a static ability on the Aura), and also future
  // cards like Act of Treason (gain control until end of turn).
  GainControl(
    target: TargetRef,
    duration: Duration,
  )

  // Divided damage — deal a total amount of damage split among
  // the spell's targets as chosen by the controller at casting time
  // (rule 601.2d). Per-target allocation is stored on the StackItem.
  // Covers: Pyrotechnics
  DealDividedDamage(
    total_amount: Amount,
  )

  // Modal spells — "Choose one —"
  // The controller chooses exactly one mode during casting (rule 700.2a).
  // Each mode carries its own targets and effect. Only the chosen mode's
  // effect resolves. The chosen mode is stored on the StackItem.
  // Covers: Healing Salve (and all modal spells).
  ChooseOne(
    modes: List(ModalMode),
  )

  // Flip a coin for the specified player (rule 705).
  // The flipper calls heads or tails; if the call matches, they win.
  // The outcome (heads/tails) is available as step output for
  // Amount.PreviousStep (1 for heads, 0 for tails).
  FlipCoin(
    flipper: TargetRef,
  )

  // Mana Clash — dedicated effect step for the repeat-until-both-heads
  // loop pattern. You and target opponent each flip a coin; deal 1 damage
  // to each opponent whose coin comes up tails. Repeat until both come up
  // heads on the same flip (rule 705 + card-specific logic). This is a
  // specialized step because Mana Clash is the only coin-flip card in 7th
  // edition and the general RepeatUntil/conditional mechanisms are deferred.
  // Covers: Mana Clash
  ManaClash(
    target: TargetRef,
  )
}

pub type SearchDestination {
  Hand
  Battlefield
}
```

### Effect

An ability's effect can be a single step or a sequence of steps.

```gleam
pub type Effect {
  Single(EffectStep)
  Sequence(List(EffectStep))
}

### Modal Mode

A single option within a modal "Choose one —" spell or ability. Each mode
declares its own targeting requirements and effect. Rules reference: 700.2.

```gleam
pub type ModalMode {
  ModalMode(
    targets: List(TargetInfo),
    effect: Effect,
  )
}
```

The `targets` list is scoped to this mode — only the chosen mode's targets
are selected at casting time. If a mode has no targets, its list is empty.

---

## Abilities

### Spell Ability

For instants, sorceries, and creature spells.

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

For abilities on permanents that require activation costs.

```gleam
pub type ActivatedAbility {
  ActivatedAbility(
    cost: ActivationCost,
    targets: List(TargetInfo),
    effect: Effect,
  )
}
```

### Ability

The union of spell and activated abilities.

```gleam
pub type Ability {
  Spell(SpellAbility)
  Activated(ActivatedAbility)
}
```

---

## Design Notes

### Regeneration and "Can't Be Regenerated"

The `Destroy` effect step includes a `cant_regenerate: Bool` flag (default `False`). When `True`, the destruction cannot be replaced by regeneration shields (per rule 608.2c and 701.19c).

**Rules context:**
- Regeneration creates a replacement effect that substitutes destruction with "remove all damage, tap, remove from combat" (rule 701.19a).
- "Can't be regenerated" prevents that replacement effect from applying (rule 701.19c: *"Effects that say that a permanent can't be regenerated ... cause regeneration shields to not be applied."*).
- This is a property of the destruction event itself, not a separate effect step — hence the boolean flag on `Destroy`.

**Cards covered:** Wrath of God, Dark Banishing, Pillage, Befoul, Reprisal — all 7th edition cards with "can't be regenerated" on a destroy effect.

**Cards NOT covered:** Cards that say "bury" in old text (errata'd to "destroy, can't be regenerated") are handled the same way — `cant_regenerate: True`.

### Target vs Affected

**Targeting**: What the player chooses when casting/activating
- Defined by `targets: List(TargetInfo)` on the ability
- Example: "Target player" in Persecute

**Affected**: What the effect actually modifies
- Defined by `TargetRef` in effect steps (like `DealDamage(target: TargetRef)`)
- Example: In "deal 3 damage to target player", the player is both targeted AND affected
- Example: In "target player discards a card", the player is targeted, cards in hand are affected

### Zone References

When an effect references cards in a zone (like "discard from hand"):
- The `CardFilter` includes `Zone(Hand)` to specify the zone
- The `TargetRef` indicates whose zone (typically the targeted player)

### Variable X

Cards with X in their costs store `Amount.X` in the effect. The actual value is determined when the card is cast.

### Reveal Information

Effects like Persecute need to reveal hidden information to the spell controller. The `RevealHand` step handles this by indicating the game should communicate revealed cards.

---

## Card Examples

### Shock (Instant)

> "Shock deals 2 damage to any target."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Any)],
  additional_costs: [],
  effect: Effect.Single(EffectStep.DealDamage(
    amount: Amount.Fixed(2),
    target: TargetRef.PrimaryTarget,
    source_is_combat: False,
  ))
))
```

### Giant Growth (Instant)

> "Target creature gets +3/+3 until end of turn."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Single(TargetType.Creature))],
  additional_costs: [],
  effect: Effect.Single(EffectStep.PumpCreature(
    target: TargetRef.PrimaryTarget,
    power: Amount.Fixed(3),
    toughness: Amount.Fixed(3),
    add_keywords: [],
    duration: Duration.EndOfTurn,
  ))
))
```

### Disenchant (Instant)

> "Destroy target artifact or enchantment."

```gleam
Ability.Spell(SpellAbility(
  targets: [
    TargetInfo(
      TargetFilter.Or(
        TargetFilter.Single(TargetType.Artifact),
        TargetFilter.Single(TargetType.Enchantment),
      ),
    )
  ],
  additional_costs: [],
  effect: Effect.Single(EffectStep.Destroy(
    target: TargetRef.PrimaryTarget,
    cant_regenerate: False,
  ))
))
```

### Wrath of God (Sorcery)

> "Destroy all creatures."

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Single(EffectStep.Destroy(
    target: TargetRef.AllOf(CardFilter.Types([card.Creature])),
    cant_regenerate: True,
  ))
))
```

### Dark Banishing (Instant)

> "Destroy target nonblack creature. It can't be regenerated."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(
    TargetFilter.And(
      TargetFilter.Single(TargetType.Creature),
      TargetFilter.Not(TargetFilter.Single(TargetType.Creature)),  // "nonblack" — color filter
    ),
  )],
  additional_costs: [],
  effect: Effect.Single(EffectStep.Destroy(
    target: TargetRef.PrimaryTarget,
    cant_regenerate: True,
  ))
))
// Note: The "nonblack" restriction is a color-based filter on the creature type.
// A proper representation requires adding color filtering to TargetFilter
// (currently TargetFilter only has type-based filters — see Open Questions).
```

(1) **Design note on targeting filters:** Dark Banishing's "nonblack creature" restriction is a combination of creature type and color. The current `TargetFilter` system doesn't have a direct way to express color-based targeting restrictions. This will need a `Color(TargetFilter, card.Color)` combinator or similar — deferred to a future enhancement.

### Persecute (Sorcery)

> "Choose a color. Target player reveals their hand and discards all cards of that color."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Single(TargetType.Player))],
  additional_costs: [],
  effect: Effect.Sequence([
    EffectStep.ChooseColor,
    EffectStep.RevealHand(
      of: TargetRef.PrimaryTarget,
      to: RevealTo.Controller,
    ),
    EffectStep.Discard(
      who: TargetRef.PrimaryTarget,
      filter: CardFilter.Color(ColorRef.Chosen),
    ),
  ]),
))

### Gravedigger (Creature)

> "When Gravedigger enters the battlefield, return target creature card from your graveyard to your hand."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf]),
  targets: [TargetInfo(TargetFilter.Single(TargetType.Creature))],
  effect: Effect.Single(EffectStep.MoveCard(
    target: TargetRef.PrimaryTarget,
    from_zone: Zone.Graveyard,
    to_zone: Zone.Hand,
  )),
))
```
 
(1) **Design note:** Gravedigger's ability is an ETB (enters-the-battlefield) triggered ability, not an activated ability with a tap cost. The representation above uses `Costs([TapSelf])` as a placeholder — since triggered abilities are Phase E (out of scope), the effect step is correct but the ability type and cost will change when triggered ability support is added.

### Llanowar Elves (Creature)

> "{T}: Add {G}."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf]),
  targets: [],
  effect: Effect.Single(EffectStep.ProduceMana(
      mana: mana.Produced(green: 1, white: 0, blue: 0, black: 0, red: 0, colorless: 0),
  )),
))
```

### Counterspell (Instant)

> "Counter target spell."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Single(TargetType.Spell))],
  additional_costs: [],
  effect: Effect.Single(EffectStep.CounterSpell(target: TargetRef.PrimaryTarget))
))
```

### Inspiration (Instant)

> "Target player draws two cards."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Single(TargetType.Player))],
  additional_costs: [],
  effect: Effect.Single(EffectStep.DrawCards(
    num: Amount.Fixed(2),
    target: TargetRef.PrimaryTarget,
  ))
))
```

### Prodigal Sorcerer (Creature)

> "{T}: Prodigal Sorcerer deals 1 damage to any target."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf]),
  targets: [TargetInfo(TargetFilter.Any)],
  effect: Effect.Single(EffectStep.DealDamage(
    amount: Amount.Fixed(1),
    target: TargetRef.PrimaryTarget,
    source_is_combat: False,
  )),
))
```

### Fog (Instant)

> "Prevent all combat damage that would be dealt this turn."

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Single(EffectStep.PreventDamage(
    target: TargetRef.Controller,
    mode: PreventionMode.GlobalCombat,
  ))
))
```

### Healing Salve (Instant) — Prevent mode

> "Choose one — Target player gains 3 life; or prevent the next 3 damage that would be dealt to any target."

```gleam
// Prevent mode only; life gain mode is a separate ability variant via ChooseOne
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Any)],
  additional_costs: [],
  effect: Effect.Single(EffectStep.PreventDamage(
    target: TargetRef.PrimaryTarget,
    mode: PreventionMode.Shield(amount: Amount.Fixed(3)),
  ))
))
```

### Samite Healer (Creature)

> "{T}: Prevent the next 1 damage that would be dealt to any target."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf]),
  targets: [TargetInfo(TargetFilter.Any)],
  effect: Effect.Single(EffectStep.PreventDamage(
    target: TargetRef.PrimaryTarget,
    mode: PreventionMode.Shield(amount: Amount.Fixed(1)),
  ))
))
```

### Reverse Damage (Instant)

> "Prevent all damage that would be dealt to you this turn by target creature. If damage is prevented this way, Reverse Damage deals that much damage to that creature's controller."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Single(TargetType.Creature))],
  additional_costs: [],
  effect: Effect.Sequence([
    EffectStep.PreventDamage(
      target: TargetRef.PrimaryTarget,
      mode: PreventionMode.AllFromSource,
    ),
    // The "deals that much damage" part depends on the prevented amount
    // and is handled by the engine when prevention occurs (rule 615.5).
    // This is a compound effect — see Phase B notes.
  ]),
))
```

### Circle of Protection: Red (Enchantment)

> "{1}: The next time a red source of your choice would deal damage to you this turn, prevent that damage."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf, Mana(mana.Cost(generic: 1))]),
  targets: [],
  effect: Effect.Single(EffectStep.PreventDamage(
    target: TargetRef.Controller,
    mode: PreventionMode.Shield(amount: Amount.Fixed(1)),
  ))
  // The "of your choice" source selection happens at prevention time,
  // not at activation. The shield rechecks source properties per rule 615.9.
))
```

### Seeker of Skybreak (Creature)

> "{T}: Untap target creature."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf]),
  targets: [TargetInfo(TargetFilter.Single(TargetType.Creature))],
  effect: Effect.Single(EffectStep.TapOrUntap(
    target: TargetRef.PrimaryTarget,
    mode: TapMode.Untap,
  ))
))
```

### Early Harvest (Sorcery)

> "Untap up to three target lands."

```gleam
Ability.Spell(SpellAbility(
  targets: [
    TargetInfo(TargetFilter.Single(TargetType.Land)),
  ],
  additional_costs: [],
  effect: Effect.Single(EffectStep.TapOrUntap(
    target: TargetRef.AllOf(
      CardFilter.And(
        CardFilter.Types([card.Land]),
        CardFilter.WithController(ControllerFilter.TargetPlayer),
      ),
    ),
    mode: TapMode.Untap,
  ))
  // "Up to three" and the per-target selection is resolved
  // at casting time via the targeting system.
))
```

### Mana Short (Instant)

> "Tap all lands target player controls."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Single(TargetType.Player))],
  additional_costs: [],
  effect: Effect.Single(EffectStep.TapOrUntap(
    target: TargetRef.AllOf(
      CardFilter.And(
        CardFilter.Types([card.Land]),
        CardFilter.WithController(ControllerFilter.TargetPlayer),
      ),
    ),
    mode: TapMode.Tap,
  ))
))
```

### Twiddle (Sorcery)

> "Tap or untap target artifact, creature, or land."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Or(
    TargetFilter.Or(
      TargetFilter.Single(TargetType.Artifact),
      TargetFilter.Single(TargetType.Creature),
    ),
    TargetFilter.Single(TargetType.Land),
  ))],
  additional_costs: [],
  effect: Effect.Single(EffectStep.TapOrUntap(
    target: TargetRef.PrimaryTarget,
    mode: TapMode.Tap,  // or TapMode.Untap — chosen by player at casting time
  ))
))
```

(1) **Note on Twiddle's mode choice:** Twiddle lets the player choose "tap" or "untap" at casting time. This choice is analogous to a modal selection (see `ChooseOne` in Phase D). The mode field is set based on the player's choice when the spell is put on the stack.

(2) **Note on Opposition's cost:** Opposition's activation cost "Tap an untapped creature you control" would require a `TapAnother(CardFilter)` variant in `CostComponent`. The sacrifice variants added in Phase C (`Sacrifice`, `SacrificeThis`, `SacrificeAny`) are not directly suitable — tapping another creature is structurally similar but not a sacrifice. A future `TapAnother` variant would follow the same pattern. See the Phase C section for the proposed design.

### Jandor's Saddlebags (Artifact)

> "{3}, {T}: Untap target creature."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf, Mana(mana.Cost(generic: 3))]),
  targets: [TargetInfo(TargetFilter.Single(TargetType.Creature))],
  effect: Effect.Single(EffectStep.TapOrUntap(
    target: TargetRef.PrimaryTarget,
    mode: TapMode.Untap,
  ))
))
```

### Elder Druid (Creature)

> "{3}{G}, {T}: You may tap or untap target artifact, creature, or land."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf, Mana(mana.Cost(generic: 3, green: 1))]),
  targets: [TargetInfo(TargetFilter.Or(
    TargetFilter.Or(
      TargetFilter.Single(TargetType.Artifact),
      TargetFilter.Single(TargetType.Creature),
    ),
    TargetFilter.Single(TargetType.Land),
  ))],
  effect: Effect.Single(EffectStep.TapOrUntap(
    target: TargetRef.PrimaryTarget,
    mode: TapMode.Tap,  // or TapMode.Untap — chosen by player at resolution
  ))
))
```

(3) **Note on Elder Druid's mode choice:** Like Twiddle, Elder Druid lets the player choose "tap" or "untap" at resolution time (per Gatherer ruling, 2004-10-04). The mode is set based on the player's choice during resolution.

(4) **Note on Flying Carpet and Wind Dancer:** These cards have `{T}` in their activation cost (already covered by `ActivationCost.Costs([TapSelf])`) and grant flying as their effect (covered by `PumpCreature`). They are not TapOrUntap effect examples — they are listed here because their activation costs involve tapping the permanent itself.

### Millstone (Artifact)

> "{2}, {T}: Target player puts the top two cards of their library into their graveyard."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf, Mana(mana.Cost(generic: 2))]),
  targets: [TargetInfo(TargetFilter.Single(TargetType.Player))],
  effect: Effect.Single(EffectStep.Mill(
    num: Amount.Fixed(2),
    target: TargetRef.PrimaryTarget,
  ))
))
```

### Tolarian Winds (Instant)

> "Discard your hand, then draw that many cards."

This card does *not* use the Mill effect step. The effect is representable as a `Sequence` of two existing steps: `Discard` (hand) followed by `DrawCards` (draw equal to the number of discarded cards). The number of cards drawn is equal to the count of cards discarded, which requires the engine to track the count from the preceding `Discard` step during resolution. This is similar to the compound-effects pattern noted in Phase B, but does not require a new effect step.

### Agonizing Memories (Sorcery)

> "Look at target player's hand and choose two nonland cards from it. Put them on top of that player's library in any order."

This card involves looking at a player's hand (covered by `RevealHand`) and moving cards from hand to top of library. The destination (`Zone.Library`) is already available in the `MoveCard` effect step, so no new effect step is needed for the zone transfer. The "look and choose" portion relates to the `SearchLibrary` / `Scry` tasks in Phase A, and the "put on top of library" is simply `MoveCard` with `to_zone: Zone.Library`.

---

## Phase A — New Effect Steps (continued)

### Scry

#### Sage Owl (Creature)

> "When Sage Owl enters the battlefield, look at the top four cards of your library, then put them back in any order."

```gleam
// This is an ETB triggered ability (out of scope for now per Phase E).
// However, the effect step used would be:
EffectStep.Scry(
  num: Amount.Fixed(4),
  target: TargetRef.Controller,
)
```

#### Sleight of Hand (Sorcery)

> "Look at the top two cards of your library. Put one of them into your hand and the other on the bottom of your library."

This card is a compound of Scry + draw. It can be represented by composing `Scry` (to look and reorder) with `DrawCards` (to draw the kept card). However, this requires the Scry step to communicate which card was kept (top vs bottom) to the follow-up draw. A simpler representation uses a dedicated `LookAtTop` variant that combines look + keep + bottom:

```gleam
// Representation using Scry + a subsequent step that puts the
// top card into hand is tricky because scry reorders the top.
// 
// Alternative: a combined "look at top N, put X into hand,
// rest on bottom" could be added as a convenience if needed.
// For now, acknowledged as a compound pattern requiring variable
// tracking between effect steps (see Open Questions).
```

#### Ancestral Memories (Sorcery)

> "Look at the top seven cards of your library. Put two of them into your hand and the rest on the bottom of your library."

Same pattern as Sleight of Hand. A dedicated `LookAtTop` effect step that accepts `keep_count` and `bottom_count` parameters could unify both cards:

```gleam
// Future design option:
// EffectStep.LookAtTop(
//   look_count: Amount.Fixed(7),
//   keep_count: Amount.Fixed(2),
//   target: TargetRef.Controller,
// )
```

(1) **Design note:** Sage Owl is pure Scry. Sleight of Hand and Ancestral Memories combine scrying with drawing selected cards. A future `LookAtTop` variant could fold both operations into one step if needed.

### Search Library

#### Rampant Growth (Sorcery)

> "Search your library for a basic land card and put it onto the battlefield tapped. Then shuffle."

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Single(EffectStep.SearchLibrary(
    target: TargetRef.Controller,
    filter: CardFilter.And(
      CardFilter.Types([card.Land]),
      CardFilter.Color(ColorRef.Literal(card.Basic)),  // "basic" is tracked via supertype
    ),
    destination: SearchDestination.Battlefield,
    reveal: False,
    tapped: True,
  ))
))
```

#### Untamed Wilds (Sorcery)

> "Search your library for a basic land card and put it onto the battlefield. Then shuffle."

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Single(EffectStep.SearchLibrary(
    target: TargetRef.Controller,
    filter: CardFilter.And(
      CardFilter.Types([card.Land]),
      CardFilter.Color(ColorRef.Literal(card.Basic)),
    ),
    destination: SearchDestination.Battlefield,
    reveal: False,
    tapped: False,
  ))
))
```

#### Wood Elves (Creature)

> "When Wood Elves enters the battlefield, search your library for a Forest card and put it onto the battlefield. Then shuffle."

```gleam
// ETB triggered ability (Phase E), but the effect step is:
EffectStep.SearchLibrary(
  target: TargetRef.Controller,
  filter: CardFilter.And(
    CardFilter.Types([card.Land]),
    CardFilter.Color(ColorRef.Literal(card.Green)),  // Forests are green
    CardFilter.Name("Forest"),
  ),
  destination: SearchDestination.Battlefield,
  reveal: False,
  tapped: False,
)
```

#### Goblin Matron (Creature)

> "When Goblin Matron enters the battlefield, search your library for a Goblin card, reveal that card, put it into your hand, then shuffle."

```gleam
// ETB triggered ability (Phase E), but the effect step is:
EffectStep.Sequence([
  EffectStep.SearchLibrary(
    target: TargetRef.Controller,
    filter: CardFilter.Subtype("Goblin"),
    destination: SearchDestination.Hand,
    reveal: True,
    tapped: False,
  ),
  // Shuffle happens automatically after SearchLibrary per rule 701.18a
])
```

(2) **Design note on shuffle:** Per rule 701.18a, shuffling is implicit after searching a library. The `SearchLibrary` effect step handles shuffling automatically — no separate `Shuffle` step is needed. For the rare cases where a card instructs shuffling without searching, a standalone `ShuffleLibrary` step could be added later.

(3) **Design note on basic land filter:** The current `ColorRef` system uses `card.Color` which only has color values (White, Blue, Black, Red, Green). "Basic" is a supertype, not a color. The filter for "basic land" should use a `CardFilter.Supertype("Basic")` variant or equivalent. For now, the example above uses a placeholder; the exact representation depends on how supertypes are modeled in the `card` module.

### Gain Control

#### Confiscate (Enchantment — Aura)

> "Enchant permanent — You control enchanted permanent."

```gleam
// This is a static ability on an Aura, not an effect step on resolution.
// The Aura grants a continuous effect that changes control of the
// enchanted permanent (see rule 611.2c for continuous effects from
// resolution of spells/abilities, and rule 613 for layer 2 control
// effects).
//
// GainControl as an effect step would be used when a spell or
// ability directly changes control, like:
//   EffectStep.GainControl(
//     target: TargetRef.PrimaryTarget,
//     duration: Duration.Permanent,
//   )
//
// For Auras like Confiscate, the control change is handled by the
// enchantment's static ability, not an effect step. This is deferred
// to the continuous effects / static abilities system (Phase E or later).
```

#### Steal Artifact (Enchantment — Aura)

> "Enchant artifact — You control enchanted artifact."

Same design pattern as Confiscate — continuous effect from an Aura's static ability, not an effect step resolution.

---

## Phase B — New Effect Steps and Modifiers

### Divided Damage

Represented as a `DealDividedDamage` effect step that distributes a total amount of damage among the spell's targets. The division is announced at casting time per rule 601.2d, and each target must receive at least 1 of whatever is being divided.

The per-target allocation is stored on the `StackItem` as part of the target choices:

```gleam
pub type TargetChoice {
  TargetChoice(
    target_id: String,
    amount: Option(Int),     // for divided effects, the allocated amount
  )
}
```

**Rules context:**
- **601.2d**: *"If the spell requires the player to divide or distribute an effect (such as damage or counters) among one or more targets, the player announces the division. Each of these targets must receive at least one of whatever is being divided."*
- **115.7f**: *"A spell or ability may 'divide' or 'distribute' an effect (such as damage or counters) among one or more targets. When changing targets or choosing new targets for that spell or ability, the original division can't be changed."*
- **115.4**: Damage with "any target" can target creatures, players, planeswalkers, or battles — hence `TargetFilter.Any`.

**Targeting change:** Divided damage requires "any number of targets," introducing the `TargetCount` type to support variable target counts in `TargetInfo`.

#### Pyrotechnics (Sorcery)

> "Pyrotechnics deals 4 damage divided as you choose among any number of targets."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(
    filter: TargetFilter.Any,
    count: TargetCount.Any,
  )],
  additional_costs: [],
  effect: Effect.Single(EffectStep.DealDividedDamage(
    total_amount: Amount.Fixed(4),
  ))
))
```

**Design notes:**
- `TargetCount.Any` allows the player to choose any number of targets (minimum 1 per rule 601.2d).
- The damage division is stored in the `StackItem`'s target choices at casting time (each target gets its allocated amount).
- On resolution, `DealDividedDamage` iterates over all targets and deals the allocated damage to each.
- The `total_amount` is used for validation: the sum of per-target allocations must equal the total.

### Variable-Value Effects

Some effects use a numeric value that depends on the game state rather than being fixed. The two patterns in 7th edition are:

1. **Count of permanents** — "damage equal to the number of Swamps you control" (`Amount.Count(filter)`)
2. **Count × multiplier** — "gain 3 life for each black creature" (`Amount.Multiply(Amount.Count(filter), 3)`)

These are evaluated at resolution time, not at casting time (rule 608.2c: *"The spell or ability is applied to the current state of the game."*).

**Rules context:**
- Rule 608.2c: *"If it needs information about the game state, it uses the current state."*
- For `Count(CardFilter)`, the filter is matched against permanents on the battlefield at resolution time.
- The `ControllerFilter` within the `CardFilter` determines whose permanents are counted (e.g., `You` for "Swamps you control", `TargetPlayer` for "target opponent controls").

#### Corrupt (Sorcery)

> "Corrupt deals damage equal to the number of Swamps you control to target creature or player. You gain life equal to the damage dealt this way."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Any)],
  additional_costs: [],
  effect: Effect.Sequence([
    EffectStep.DealDamage(
      amount: Amount.Count(
        CardFilter.And(
          CardFilter.Types([card.Land]),
          CardFilter.Name("Swamp"),
          CardFilter.WithController(ControllerFilter.You),
        ),
      ),
      target: TargetRef.PrimaryTarget,
      source_is_combat: False,
    ),
    // "You gain life equal to the damage dealt this way" is a compound effect
    // (see Compound Effects below). The life gain amount is determined by the
    // damage actually dealt in the preceding step.
  ]),
))
```

(1) **Design note:** The life gain portion of Corrupt is a compound effect. The `GainLife` step would need to reference the damage dealt by the preceding `DealDamage` step. This is addressed in the Compound Effects section.

#### Spitting Earth (Sorcery)

> "Spitting Earth deals damage to target creature equal to the number of Mountains you control."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Single(TargetType.Creature))],
  additional_costs: [],
  effect: Effect.Single(EffectStep.DealDamage(
    amount: Amount.Count(
      CardFilter.And(
        CardFilter.Types([card.Land]),
        CardFilter.Name("Mountain"),
        CardFilter.WithController(ControllerFilter.You),
      ),
    ),
    target: TargetRef.PrimaryTarget,
    source_is_combat: False,
  )),
))
```

#### Starlight (Sorcery)

> "You gain 3 life for each black creature target opponent controls."

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Single(TargetType.Player))],
  additional_costs: [],
  effect: Effect.Single(EffectStep.GainLife(
    amount: Amount.Multiply(
      Amount.Count(
        CardFilter.And(
          CardFilter.Types([card.Creature]),
          CardFilter.Color(ColorRef.Literal(card.Black)),
          CardFilter.WithController(ControllerFilter.TargetPlayer),
        ),
      ),
      3,
    ),
    target: TargetRef.Controller,
  )),
))
```

**Alternative design:** Instead of `Multiply(Count, N)`, a `ForEach` effect step (see Open Questions) could handle the "for each" pattern more generally. The `Multiply` approach is simpler and sufficient for 7th edition.

---

### Compound Effects

Some effects chain two operations together where the second operation's parameter depends on the numeric result of the first. The key patterns in 7th edition are:

1. **Deal damage, then gain life equal to that damage** (Corrupt)
2. **Discard hand, then draw equal to number discarded** (Tolarian Winds)
3. **Prevent damage, then deal equal damage to a different target** (Reverse Damage — handled by rules 615.5, not a compound effect in the Sequence sense)

#### Design

A general `Amount` variant provides access to the numeric result of the preceding effect step:

```gleam
pub type Amount {
  Fixed(Int)
  X
  Count(CardFilter)
  Multiply(Amount, Int)
  PreviousStep    // The numeric output of the immediately preceding EffectStep
                  // in the Sequence. Each EffectStep type defines what its output
                  // represents (damage dealt, cards discarded, life gained/lost, etc.).
}
```

During resolution of a `Sequence`, each step can produce a numeric result. The `PreviousStep` variant evaluates to the result of the step that ran immediately before the current one. This enables patterns like:

**Corrupt** — deal damage equal to Swamps, then gain life equal to damage dealt:

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Any)],
  additional_costs: [],
  effect: Effect.Sequence([
    EffectStep.DealDamage(
      amount: Amount.Count(swamps_filter),
      target: TargetRef.PrimaryTarget,
      source_is_combat: False,
    ),
    EffectStep.GainLife(
      amount: Amount.PreviousStep,
      target: TargetRef.Controller,
    ),
  ]),
))
```

**Tolarian Winds** — discard hand, then draw that many:

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Sequence([
    EffectStep.Discard(
      who: TargetRef.Controller,
      filter: CardFilter.Zone(Zone.Hand),
    ),
    EffectStep.DrawCards(
      num: Amount.PreviousStep,
      target: TargetRef.Controller,
    ),
  ]),
))
```

**Reverse Damage** is NOT a compound effect in the Sequence sense. Per rule 615.5, the additional effect (dealing damage equal to the amount prevented) is part of the prevention effect itself, applied when the prevention event occurs. The existing `PreventDamage` with `PreventionMode.AllFromSource` handles this — the engine applies the follow-up damage as part of the prevention effect's resolution.

**Soul Feast** ("Target player loses 4 life. You gain 4 life.") is representable with a simple `Sequence` of two independent steps — no compound mechanism needed:

```gleam
Effect.Sequence([
  EffectStep.LoseLife(amount: Amount.Fixed(4), target: TargetRef.PrimaryTarget),
  EffectStep.GainLife(amount: Amount.Fixed(4), target: TargetRef.Controller),
])
```

#### Step Output Semantics

Each `EffectStep` that produces a numeric result documents what `PreviousStep` will yield:

- `DealDamage` → the damage actually dealt (after replacement/prevention effects)
- `Discard` → the number of cards discarded (after any replacement effects)
- `GainLife` / `LoseLife` → the life gained or lost
- `Mill` → the number of cards milled
- Steps that don't naturally produce a numeric value → `0`

This approach avoids introducing dedicated compound step variants while keeping the system extensible for future compound patterns.

---

### Self-Damage and Damage to Controller

Some activated abilities cause the source permanent to deal damage to itself or its controller. In MTG rules text, "you" refers to the controller of the ability (rule 109.5), and "itself" refers to the source permanent. These references are representable through `TargetRef.Controller` and `TargetRef.Source` respectively.

**Rules context:**
- **109.5**: *"The words 'you' and 'your' on an object refer to the object's controller..."* — already covered by `TargetRef.Controller`.
- **113.7**: The source of an activated ability on the stack is the object whose ability was activated. This is what "itself" refers to in cards like Reckless Embermage.

No new effect steps are required. Cards with "damage to you" use `TargetRef.Controller`. Cards with "damage to itself" use `TargetRef.Source`. Both are representable as a `Sequence` of `DealDamage` steps (the "and" connective in card text means the actions happen simultaneously per rule 608.2f, but sequential representation is functionally equivalent when both steps are independent damage events).

#### Orcish Artillery (Creature)

> "{T}: Orcish Artillery deals 2 damage to any target and 3 damage to you."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf]),
  targets: [TargetInfo(TargetFilter.Any)],
  effect: Effect.Sequence([
    EffectStep.DealDamage(
      amount: Amount.Fixed(2),
      target: TargetRef.PrimaryTarget,
      source_is_combat: False,
    ),
    EffectStep.DealDamage(
      amount: Amount.Fixed(3),
      target: TargetRef.Controller,
      source_is_combat: False,
    ),
  ]),
))
```

#### Reckless Embermage (Creature)

> "{T}: Reckless Embermage deals 1 damage to any target and 1 damage to itself."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf]),
  targets: [TargetInfo(TargetFilter.Any)],
  effect: Effect.Sequence([
    EffectStep.DealDamage(
      amount: Amount.Fixed(1),
      target: TargetRef.PrimaryTarget,
      source_is_combat: False,
    ),
    EffectStep.DealDamage(
      amount: Amount.Fixed(1),
      target: TargetRef.Source,
      source_is_combat: False,
    ),
  ]),
))
```

(1) **Design note on `TargetRef.Source`:** For activated abilities, `Source` resolves to the permanent on the battlefield whose ability was activated. For spell abilities (instants/sorceries), `Source` would refer to the spell on the stack, but "itself" damage patterns typically only appear on activated abilities of permanents. If a future spell ability needs to reference itself, the stack object is available via the same mechanism.

---

## Phase C — Activation Cost Expansion

### Sacrifice as Cost

Sacrifice as a cost follows rule 701.21 ("To sacrifice a permanent, its controller moves it from the battlefield directly to its owner's graveyard.") and rule 118.8 (additional costs). Two patterns appear in 7th edition:

1. **Self-sacrifice** ("Sacrifice this creature/permanent") — the source permanent itself is sacrificed
2. **Sacrifice another** ("Sacrifice a creature") — the player chooses a matching permanent they control
3. **Sacrifice any number** ("Sacrifice any number of artifacts, creatures, and/or lands") — the player chooses zero or more matching permanents

The `CostComponent` variants handle these:
- `SacrificeThis` — self-sacrifice (source is sacrificed)
- `Sacrifice(CardFilter)` — sacrifice exactly one permanent matching the filter
- `SacrificeAny(CardFilter)` — sacrifice any number of permanents matching the filter

**Rules context:**
- **701.21a**: *"To sacrifice a permanent, its controller moves it from the battlefield directly to its owner's graveyard. A player can't sacrifice something that isn't a permanent, or something that's a permanent they don't control. Sacrificing a permanent doesn't destroy it, so regeneration or other effects that replace destruction can't affect this action."*
- **118.10**: Each payment of a cost applies to only one spell, ability, or effect.
- The "sacrifice this" pattern is governed by rule 602.1 (the activation cost is everything before the colon) and rule 201.4b (self-reference by name in abilities).

#### Bloodshot Cyclops (Creature)

> "{T}, Sacrifice a creature: Bloodshot Cyclops deals damage equal to the sacrificed creature's power to any target."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf, Sacrifice(CardFilter.Types([card.Creature]))]),
  targets: [TargetInfo(TargetFilter.Any)],
  effect: Effect.Single(EffectStep.DealDamage(
    amount: // needs reference to sacrificed creature's power (see design note below)
    target: TargetRef.PrimaryTarget,
    source_is_combat: False,
  )),
))
```

(1) **Design note on referencing sacrificed creature:** Bloodshot Cyclops's damage amount depends on the power of the creature sacrificed as the activation cost. This requires the ability to reference objects paid as costs — a pattern not yet supported by the current `Amount` type. A future `Amount.PaidPower` or `Amount.PaidCreaturePower` variant would enable this. For now, acknowledged as a deferred compound-pattern design.

(2) **Design note on Order of Cost Payments:** Per rule 601.2h, costs that don't involve moving objects from the library to a public zone are paid first, in any order. Sacrifice costs are paid during this step. The sacrificed creature is in the graveyard before the effect resolves, so the effect must reference the cost payment state.

#### Stronghold Assassin (Creature)

> "{T}, Sacrifice a creature: Destroy target creature."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf, Sacrifice(CardFilter.Types([card.Creature]))]),
  targets: [TargetInfo(TargetFilter.Single(TargetType.Creature))],
  effect: Effect.Single(EffectStep.Destroy(
    target: TargetRef.PrimaryTarget,
    cant_regenerate: False,
  )),
))
```

#### Ghitu Fire-Eater (Creature)

> "{T}, Sacrifice this creature: Ghitu Fire-Eater deals 2 damage to any target."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([TapSelf, SacrificeThis]),
  targets: [TargetInfo(TargetFilter.Any)],
  effect: Effect.Single(EffectStep.DealDamage(
    amount: Amount.Fixed(2),
    target: TargetRef.PrimaryTarget,
    source_is_combat: False,
  )),
))
```

#### Goblin Digging Team (Creature)

> "{R}, Sacrifice this creature: Destroy target Wall."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([Mana(mana.Cost(red: 1)), SacrificeThis]),
  targets: [TargetInfo(TargetFilter.Single(TargetType.Creature))],  // filtered to Walls at resolution
  effect: Effect.Single(EffectStep.Destroy(
    target: TargetRef.PrimaryTarget,
    cant_regenerate: False,
  )),
))
```

(1) **Design note on "Wall" target:** Goblin Digging Team targets a Wall (a creature subtype). The targeting restriction is not a `TargetType` (which only has `Creature`, not subtypes). A future `TargetFilter.Subtype("Wall")` variant would handle this — for now, represented as a creature target with subtype checking at resolution.

#### Scavenger Folk (Creature)

> "{G}, Sacrifice this creature: Destroy target artifact."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([Mana(mana.Cost(green: 1)), SacrificeThis]),
  targets: [TargetInfo(TargetFilter.Single(TargetType.Artifact))],
  effect: Effect.Single(EffectStep.Destroy(
    target: TargetRef.PrimaryTarget,
    cant_regenerate: False,
  )),
))
```

#### Reprocess (Sorcery)

> "Sacrifice any number of artifacts, creatures, and/or lands. Draw a card for each permanent sacrificed this way."

Reprocess uses the `SacrificeAny` cost pattern combined with a compound draw effect:

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [SacrificeAny(
    CardFilter.Or(
      CardFilter.Or(
        CardFilter.Types([card.Artifact]),
        CardFilter.Types([card.Creature]),
      ),
      CardFilter.Types([card.Land]),
    ),
  )],
  effect: Effect.Single(EffectStep.DrawCards(
    num: Amount.PreviousStep,  // number of cards sacrificed is the PreviousStep output
    target: TargetRef.Controller,
  )),
))
```

(1) **Design note on Reprocess's additional cost:** `SacrificeAny` allows the player to sacrifice zero or more permanents matching the filter. The cost output (number sacrificed) flows to the effect via `Amount.PreviousStep`, similar to the compound-effects pattern in Phase B.

(2) **Design note on zero sacrifice:** Per Reprocess's Oracle text, "any number" includes zero. If no permanents are sacrificed, the effect draws zero cards — a valid but typically pointless play. The `additional_costs` system should allow zero-cost activations for `SacrificeAny`.

### Opposition's Tap Cost (Design Note)

Opposition ("Tap an untapped creature you control") has a tap-another cost that is structurally similar to sacrifice-another. This would become a `TapAnother(CardFilter)` variant in a future expansion of `CostComponent`:

```gleam
// Future design option:
// ActivationCost.Costs([TapAnother(CardFilter.Types([card.Creature]))])
```

For now, acknowledged as a deferred design.

### Pay Life as Cost

Paying life as a cost follows rule 118.3b ("Paying life is done by subtracting the indicated amount of life from a player's life total.") and rule 118.3 ("A player can't pay a cost without having the necessary resources to pay it fully."). The `PayLife(Int)` variant in `CostComponent` handles this pattern.

In 7th edition, paying life appears exclusively as an activation cost (before the colon), never as an additional cost on casting — the latter (Necrologia's "pay X life as additional cost") is deferred to a future "additional costs on cast" expansion.

**Rules context:**
- **118.3b**: *"Paying life is done by subtracting the indicated amount of life from a player's life total. (Players can always pay 0 life.)"*
- **118.3**: *"A player can't pay a cost without having the necessary resources to pay it fully."*
- **119**: Life total rules — paying life reduces a player's life total.
- The payment is made during the cost payment step of activating an ability (rule 602.2b), at the same time as mana and other cost components.

**Convenience aliases:**
```gleam
// Cost with mana + life
fn mana_life_cost(cost: mana.Cost, life: Int) -> ActivationCost {
  Costs([Mana(cost), PayLife(Fixed(life))])
}

// Life-only cost
fn life_cost(life: Int) -> ActivationCost {
  Costs([PayLife(Fixed(life))])
}
```

#### Greed (Enchantment)

> "{1}{B}, Pay 2 life: Draw a card."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([
    Mana(mana.Cost(black: 1, generic: 1)),
    PayLife(Fixed(2)),
  ]),
  targets: [],
  effect: Effect.Single(EffectStep.DrawCards(
    num: Amount.Fixed(1),
    target: TargetRef.Controller,
  )),
))
```

#### Strands of Night (Enchantment)

> "{1}{B}, Pay 2 life, Sacrifice a Swamp: Return target creature card from your graveyard to the battlefield."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([
    Mana(mana.Cost(black: 1, generic: 1)),
    PayLife(Fixed(2)),
    Sacrifice(CardFilter.And(
      CardFilter.Types([card.Land]),
      CardFilter.Name("Swamp"),
    )),
  ]),
  targets: [TargetInfo(
    TargetFilter.And(
      TargetFilter.Single(TargetType.Creature),
      // Future: card-in-graveyard targeting — for now, represented as
      // a creature target with zone checking at resolution.
    ),
  )],
  effect: Effect.Single(EffectStep.MoveCard(
    target: TargetRef.PrimaryTarget,
    from_zone: Zone.Graveyard,
    to_zone: Zone.Battlefield,
  )),
))
```

(1) **Design note on graveyard targeting:** Strands of Night returns a creature card from *your* graveyard to the battlefield. The current `TargetFilter` system doesn't have a way to specify "a card in your graveyard" as a target type. A future `TargetFilter.Zone(Zone.Graveyard)` combinator would handle this. For now, acknowledged as a deferred targeting enhancement.

#### Phyrexian Colossus (Artifact Creature)

> "{8}: Untap Phyrexian Colossus. Pay 8 life. Activate only before attackers are declared."

```gleam
Ability.Activated(ActivatedAbility(
  cost: ActivationCost.Costs([
    Mana(mana.Cost(generic: 8)),
    PayLife(Fixed(8)),
  ]),
  targets: [],
  effect: Effect.Single(EffectStep.TapOrUntap(
    target: TargetRef.Source,
    mode: TapMode.Untap,
  )),
))
```

(2) **Design note on Phyrexian Colossus:** Per 7th edition wording, "Pay 8 life" appears after the colon but functions as part of the activation cost. In modern Oracle text, this is formatted as a separate cost — the representation above treats it as part of the unified `CostComponent` list for consistency.

(3) **Design note on Necrologia (Additional Cost):** Necrologia's "As an additional cost to cast this spell, pay X life" is a separate pattern — an additional cost on casting, not an activation cost. See the "Additional Costs on Cast" section below.

---

## Phase C — Additional Costs on Cast

### Design

Some spells have additional costs that must be paid when casting (rule 118.8). These are costs listed in a spell's rules text that its controller pays at the same time as the spell's mana cost (rule 601.2b, 601.2f, 601.2h).

The existing `CostComponent` variants used for activation costs also serve for additional costs on cast. A `SpellAbility` now carries an `additional_costs: List(CostComponent)` field alongside its targets and effect:

```gleam
pub type SpellAbility {
  SpellAbility(
    targets: List(TargetInfo),
    additional_costs: List(CostComponent),
    effect: Effect,
  )
}
```

**Rules context:**
- **118.8**: *"Some spells and abilities have additional costs. An additional cost is a cost listed in a spell's rules text, or applied to a spell or ability from another effect, that its controller must pay at the same time they pay the spell's mana cost or the ability's activation cost."*
- **118.8a**: *"Any number of additional costs may be applied to a spell as it's being cast or to an ability as it's being activated."*
- **118.8d**: *"Additional costs don't change a spell's mana cost, only what its controller has to pay to cast it."*
- **601.2b**: The player announces their intention to pay additional costs when proposing the spell.
- **601.2h**: Additional costs are paid during the cost payment step, in any order with other cost components.

### PayLife Supports Amount

To support variable life payments (like Necrologia's "pay X life"), `CostComponent.PayLife` now takes `Amount` instead of a bare `Int`:

```gleam
pub type CostComponent {
  Mana(mana.Cost)
  TapSelf
  SacrificeThis
  Sacrifice(CardFilter)
  SacrificeAny(CardFilter)
  PayLife(Amount)    // Amount.Fixed(N) for fixed, Amount.X for variable
}
```

Existing activated-ability examples use `PayLife(Fixed(N))` for fixed values.

### Design decisions

1. **Reuse of `CostComponent`**: Additional costs on cast share the same `CostComponent` type as activation cost components. Both are paid during the cost payment step (rule 601.2h), so no new type is needed.

2. **Variable life with `Amount.X`**: Necrologia's life payment uses the same X value chosen for the mana cost. By using `Amount.X` in `PayLife`, the system naturally ties the life payment amount to the chosen X value — no new mechanism is required.

3. **Multiple additional costs**: Per rule 118.8a, any number of additional costs may apply. The `List(CostComponent)` model supports this directly.

4. **Spell vs. Activated Ability**: For `SpellAbility`, the additional costs are in the `additional_costs` field alongside `targets` and `effect`. For `ActivatedAbility`, additional costs that are part of the ability text go in the `cost` field (the activation cost). Additional costs from external effects (like "Counter target spell unless its controller pays {2}") are applied by the engine, not encoded in the ability definition — those are deferred to the spell resolution / cost modification system.

### Card Examples

#### Necrologia (Sorcery)

> "As an additional cost to cast this spell, pay X life. You draw X cards."

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [PayLife(Amount.X)],
  effect: Effect.Single(EffectStep.DrawCards(
    num: Amount.X,
    target: TargetRef.Controller,
  )),
))
```

(1) **Design note:** Necrologia's mana cost is `XBB` (defined on the card), and "pay X life" is an additional cost. Both use the same X value chosen at casting time (rule 601.2b). The `PayLife(Amount.X)` variant ensures the life payment equals that X value.

---

## Phase D — Complex Cards

### Modal Spells ("Choose one —")

Modal spells present the caster with a list of options ("modes"), typically "Choose one —" (rule 700.2). The controller chooses the mode as part of casting the spell (rule 700.2a). Each mode may have different targets and effects.

The `ChooseOne` effect step stores the list of available modes. At casting time, the player picks exactly one mode. The mode choice and its target selections are stored on the `StackItem`. Only the chosen mode's effect is resolved — the unchosen modes are discarded.

**Targeting rules per mode:**
- Each `ModalMode` in the list carries its own `targets` and `effect`.
- At casting time, only the chosen mode's targets need to be declared (rule 700.2a: if the chosen mode would be illegal due to inability to choose legal targets, that mode can't be chosen).
- Different modes may target different types of objects (e.g., one mode targets a player, another targets any target).

**Rules context:**
- **700.2**: *"A spell or ability is modal if it has two or more options in a bulleted list preceded by instructions for a player to choose a number of those options, such as 'Choose one —'."*
- **700.2a**: *"The controller of a modal spell or activated ability chooses the mode(s) as part of casting that spell or activating that ability. If one of the modes would be illegal (due to an inability to choose legal targets, for example), that mode can't be chosen."*
- **700.2g**: *"A copy of a modal spell or ability copies the mode(s) chosen for it."*

#### Healing Salve (Instant)

> "Choose one — Target player gains 3 life; or prevent the next 3 damage that would be dealt to any target."

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Single(EffectStep.ChooseOne(
    modes: [
      ModalMode(
        targets: [TargetInfo(Single(Player))],
        effect: Effect.Single(EffectStep.GainLife(
          amount: Amount.Fixed(3),
          target: TargetRef.PrimaryTarget,
        )),
      ),
      ModalMode(
        targets: [TargetInfo(Any)],
        effect: Effect.Single(EffectStep.PreventDamage(
          target: TargetRef.PrimaryTarget,
          mode: PreventionMode.Shield(amount: Amount.Fixed(3)),
        )),
      ),
    ],
  )),
))
```

(1) **Design note on top-level targets:** For modal spells, the `targets` field on `SpellAbility` is empty (`[]`). Targets are declared per-mode within each `ModalMode`. This is consistent with rule 700.2a — each mode independently defines what it targets, and only the chosen mode's targets are selected.

(2) **Design note on "Choose two —":** Some modal spells allow the player to choose more than one mode (e.g., "Choose two —" or "Choose one or more —"). A future `ChooseN` variant or a `choices: Int` field on `ChooseOne` could extend this design. For 7th edition, all modal spells use exactly "Choose one —".

(3) **Design note on Escalate (rule 702.120):** Escalate adds a cost for each additional mode chosen beyond the first. This is a keyword that modifies how modal spells work. Escalate cards are not present in 7th edition and are deferred.

(4) **Design note on Entwine (rule 702.42):** Entwine allows choosing all modes for a cost. Also not in 7th edition, deferred.

---

### Extra Turn

Effects that create extra turns follow rule 500.7: *"Some effects can give a player extra turns. They do this by adding the turns directly after the specified turn. If a player is given multiple extra turns, the extra turns are added one at a time. If multiple players are given extra turns, the extra turns are added one at a time, in APNAP order. The most recently created turn will be taken first."*

#### Design

A simple `ExtraTurn` effect step adds an extra turn after the current one for the specified player:

```gleam
EffectStep.ExtraTurn(
  target: TargetRef,
)
```

**Rules context:**
- **500.7**: Extra turns are inserted directly after the specified turn. Multiple extra turns stack in LIFO order (most recently created resolves first).
- **500.8**: Some effects add phases or steps rather than full turns — those follow a similar ordering but are a separate mechanism.
- **608.2c**: The turn is added during resolution as a one-shot effect. The turn insertion itself does not use the stack.

#### Final Fortune (Sorcery)

> "Take an extra turn after this one. At the beginning of that turn's end step, you lose the game."

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Sequence([
    EffectStep.ExtraTurn(
      target: TargetRef.Controller,
    ),
    // The "you lose the game at the beginning of that turn's end step"
    // is a delayed triggered ability created by the same spell.
    // Per rule 603.7, delayed triggered abilities are created during
    // resolution and trigger later. The linking mechanism ("that turn")
    // references the extra turn just created — see Delayed Triggers
    // section below for the full design.
  ]),
))
```

(1) **Design note on delayed trigger integration:** Final Fortune's "lose the game" rider is a delayed triggered ability (rule 603.7), not part of the `ExtraTurn` effect step itself. The `ExtraTurn` step is intentionally simple — it only adds a turn. The follow-up trigger ("at the beginning of that turn's end step") is a separate mechanism that references the extra turn via the engine's turn-tracking state. This separation keeps `ExtraTurn` reusable for cards like Time Walk that have no rider, while allowing Final Fortune to compose ExtraTurn with a delayed trigger. See the Delayed Triggers section for the full mechanism.

(2) **Design note on `LoseGame` step:** A `LoseGame` effect step will be needed for the delayed trigger to reference. Per rule 104.2e, "An effect may state that a player loses the game." This is a one-shot effect (rule 610), applied when the delayed trigger resolves:

```gleam
// Future addition to EffectStep:
LoseGame(target: TargetRef)
```

(3) **Design note on turn ordering:** Per rule 500.7, extra turns are inserted directly after the current turn. If multiple extra-turn effects resolve in the same turn, they are added one at a time in LIFO order. The engine's turn scheduler must support dynamic insertion of turns between the current turn and the next scheduled turn.

(4) **Cards covered by this design:**
- `Final Fortune` — ExtraTurn + delayed LoseGame trigger at end step
- `Time Walk`, `Temporal Manipulation`, `Capture of Jingzhou` and similar — ExtraTurn only (no rider)
- `Savor the Moment` — ExtraTurn + skip untap step (requires a future `SkipStep` mechanism)

---

### Coin Flips

Effects that instruct a player to flip a coin follow rule 705. The coin has two
sides (heads/tails) with equal probability. For effects that care about win/loss,
the flipper calls heads or tails — if the call matches, they win; otherwise they
lose (rule 705.2). Effects may also override the result outright (rule 705.3).

#### Design

A `FlipCoin` effect step flips a coin for the specified player. The outcome
(heads or tails) is available as step output for `Amount.PreviousStep`
(1 for heads, 0 for tails). The win/loss determination follows from the
flipper's call and the result.

```gleam
EffectStep.FlipCoin(
  flipper: TargetRef,
)
```

#### Mana Clash (Sorcery)

> "You and target opponent each flip a coin. Mana Clash deals 1 damage to each
> opponent whose coin comes up tails. Repeat this process until both players'
> coins come up heads on the same flip."

Mana Clash uses the dedicated `ManaClash` effect step rather than composing
`FlipCoin` with a general loop/conditional mechanism (general `RepeatUntil`
and conditional branching are deferred):

```gleam
Ability.Spell(SpellAbility(
  targets: [TargetInfo(TargetFilter.Single(TargetType.Player))],
  additional_costs: [],
  effect: Effect.Single(EffectStep.ManaClash(
    target: TargetRef.PrimaryTarget,
  )),
))
```

**Design rationale:** Mana Clash is the only coin-flip card in 7th edition.
A dedicated step avoids the complexity of adding general-purpose
`RepeatUntil` and conditional `If` mechanisms for a single card.

---

### Delayed Triggered Abilities

Some effects create delayed triggered abilities that fire later — most commonly "at [step]" or "when [event]". Per rule 603.7, delayed triggered abilities are created during the resolution of a spell or ability and trigger only once unless given a stated duration.

#### Design

```gleam
pub type DelayedTrigger {
  DelayedTrigger(
    // The event that causes this trigger to fire.
    event: TriggerEvent,
    // The effect that resolves when the trigger fires.
    effect: Effect,
    // The controller of the delayed ability per rule 603.7d–f.
    controller: Int,
    // The lifetime of the trigger — Once (fires once then ceases)
    // or UntilEndOfTurn (can fire multiple times during the turn).
    duration: TriggerDuration,
  )
}

pub type TriggerEvent {
  // "At the beginning of [step]" — fires when the given step begins.
  // Step references the game engine's Step type (EndStep, Upkeep, etc.).
  // The trigger fires at the beginning of the NEXT occurrence of this step
  // after the delayed trigger is created (rule 603.7a: "won't trigger until
  // it has actually been created").
  AtStep(step: game.Step)

  // "Whenever [source] deals damage" — fires when the tracked source
  // deals any damage. Used for cards like Spirit Link.
  // Note: Spirit Link is a static ability on an Aura that grants a
  // triggered ability — it belongs in Phase E (triggered abilities).
  // This variant is reserved for delayed triggers that reference
  // damage events.
  WhenDealsDamage

  // "When [permanent] leaves the battlefield" — fires when a tracked
  // permanent moves from battlefield to another zone. Used for cards
  // like Delusions of Mediocrity.
  // Note: Delusions of Mediocrity's LTB trigger is printed on the card,
  // not created as a delayed trigger during resolution. This variant is
  // reserved for delayed-trigger equivalents if the engine needs them.
  WhenLeavesBattlefield
}

pub type TriggerDuration {
  // Triggers exactly once, then ceases to exist.
  // Corresponds to rule 603.7b: triggers only once at the next occurrence.
  Once

  // Can trigger multiple times until end of turn.
  // For triggers with stated duration like "this turn" (rule 603.7b).
  // Each time the event occurs, the trigger fires. After the turn ends,
  // the delayed trigger ceases to exist.
  UntilEndOfTurn
}
```

**Engine integration:** The game engine must maintain a list of active delayed triggered abilities (on the `State` type or alongside it). At the beginning of each step (for `AtStep` triggers) and after each damage event (for `WhenDealsDamage`), the engine iterates the list and fires matching triggers, removing `Once`-duration triggers after their first firing and all triggers at end of turn.

#### New Effect Steps

```gleam
// Create a delayed triggered ability during resolution.
// The trigger is linked to the current spell/ability being resolved.
CreateDelayedTrigger(
  trigger: DelayedTrigger,
)

// Make a player lose the game (rule 104.2e).
// Applied as a one-shot effect when this step resolves.
LoseGame(
  target: TargetRef,
)
```

#### Card Examples

##### Final Fortune (Sorcery)

> "Take an extra turn after this one. At the beginning of that turn's end step, you lose the game."

```gleam
Ability.Spell(SpellAbility(
  targets: [],
  additional_costs: [],
  effect: Effect.Sequence([
    EffectStep.ExtraTurn(
      target: TargetRef.Controller,
    ),
    EffectStep.CreateDelayedTrigger(
      trigger: DelayedTrigger(
        event: TriggerEvent.AtStep(step: game.EndStep),
        effect: Effect.Single(EffectStep.LoseGame(
          target: TargetRef.Controller,
        )),
        controller: 0,  // filled from current spell controller at resolution
        duration: TriggerDuration.Once,
      ),
    ),
  ]),
))
```

(1) **Design note on turn referencing:** Final Fortune's trigger text says "that turn's end step" — the `AtStep(EndStep)` event will trigger at the end step of the extra turn just created. Since `ExtraTurn` adds a turn directly after the current one, and the delayed trigger doesn't check *which* turn's end step, it naturally fires during the next end step encountered. Rule 603.7a ensures it doesn't retroactively trigger on the current turn's already-passed end step.

(2) **Design note on `controller` field:** The `controller` field is populated by the engine at resolution time based on rule 603.7d (the controller is the player who controlled the spell as it resolved). The ability definition uses a placeholder (0) that the engine replaces with the actual controller ID when creating the delayed trigger.

##### Delusions of Mediocrity (Enchantment)

> "When Delusions of Mediocrity enters the battlefield, you gain 10 life. When Delusions of Mediocrity leaves the battlefield, you lose 10 life."

(3) **Design note:** Delusions of Mediocrity has two triggered abilities printed on the card itself — not delayed triggered abilities created during resolution. The ETB is a standard enters-the-battlefield trigger (Phase E), and the LTB is a standard leaves-the-battlefield trigger (Phase E). Neither is a delayed triggered ability under rule 603.7. This card is deferred to Phase E (Triggered Abilities).

##### Spirit Link (Enchantment — Aura)

> "Whenever enchanted creature deals damage, you gain that much life."

(4) **Design note:** Spirit Link is a static ability on an Aura that grants a triggered ability to the enchanted creature. This is not a delayed triggered ability — it's a continuous effect that creates a triggered ability from the enchanted creature. Deferred to Phase E (Static Abilities / Triggered Abilities).

---

## Phase E — Triggered and Static Abilities

### Overview

Phase E adds support for triggered abilities (rule 603) and static abilities (rule 604) — the remaining ability categories needed to represent 7th edition cards. These cover:

1. **ETB triggered abilities** — Gravedigger, Cloudchaser Eagle, Sage Owl, etc.
2. **Combat damage triggers** — Abyssal Specter, Thieving Magpie, etc.
3. **Attack / block triggers** — Seasoned Marshal, Gang of Elk, etc.
4. **Death / sacrifice triggers** — Goblin Gardener, Soul Net, etc.
5. **Continuous / lord effects** — Glorious Anthem, Goblin King, etc.

Replacement effects (rule 614) remain out of scope — they require a separate continuous-effects layer system.

### 5.1 Triggered Abilities

#### Design

Triggered abilities follow the pattern "[Trigger condition], [effect]" (rule 113.3c). When the trigger event occurs, the ability goes on the stack independently of the triggering event (rule 603.2). The controller is the player who controlled its source when it triggered (rule 603.3a).

```gleam
pub type TriggeredAbility {
  TriggeredAbility(
    trigger: Trigger,
    targets: List(TargetInfo),
    effect: Effect,
    optional: Bool,                     // "you may"
    intervening_if: Option(CardFilter), // rule 603.4 intervening "if" clause
  )
}
```

**Trigger events:**

```gleam
pub type Trigger {
  // "When [this] enters the battlefield, ..." — rule 603.6a
  EntersBattlefield
  // "When [this] leaves the battlefield, ..." — rule 603.6c
  LeavesBattlefield
  // "When [this] dies, ..." — "put into graveyard from battlefield" (rule 700.4)
  Dies
  // "Whenever [this] attacks, ..."
  Attacks
  // "Whenever [this] blocks, ..."
  Blocks
  // "Whenever [this] deals damage, ..." — optional filter (to player, to creature)
  DealsDamage(filter: Option(TargetFilter))
  // "Whenever [this] deals combat damage, ..." — optional filter
  DealsCombatDamage(filter: Option(TargetFilter))
  // "Whenever a player discards a card, ..." — filter specifies the player
  Discarded(filter: CardFilter)
  // "At the beginning of [step], ..." — rule 603.2b
  AtStep(step: game.Step)
}
```

**Trigger context reference:** Effects often reference the subject of the trigger event (e.g. "that player" in "whenever ~ deals damage to a player, that player discards"). A new `TargetRef` variant provides this reference:

```gleam
pub type TargetRef {
  // ...existing variants (PrimaryTarget, SecondaryTarget, Controller, Source, AllOf)...
  TriggerSubject    // The player or object referenced by the trigger event
}
```

#### Card Examples

##### Gravedigger (Creature)

> "When Gravedigger enters the battlefield, return target creature card from your graveyard to your hand."

```gleam
Ability.Triggered(TriggeredAbility(
  trigger: Trigger.EntersBattlefield,
  targets: [TargetInfo(
    filter: TargetFilter.And(
      TargetFilter.Single(TargetType.Creature),
      // Zone(Graveyard) — handled by engine at resolution (rule 608.2b)
    ),
  )],
  effect: Effect.Single(EffectStep.MoveCard(
    target: TargetRef.PrimaryTarget,
    from_zone: Zone.Graveyard,
    to_zone: Zone.Hand,
  )),
  optional: False,
  intervening_if: None,
))
```

##### Cloudchaser Eagle (Creature)

> "When Cloudchaser Eagle enters the battlefield, destroy target enchantment."

```gleam
Ability.Triggered(TriggeredAbility(
  trigger: Trigger.EntersBattlefield,
  targets: [TargetInfo(TargetFilter.Single(TargetType.Enchantment))],
  effect: Effect.Single(EffectStep.Destroy(
    target: TargetRef.PrimaryTarget,
    cant_regenerate: False,
  )),
  optional: False,
  intervening_if: None,
))
```

##### Abyssal Specter (Creature)

> "Whenever Abyssal Specter deals damage to a player, that player discards a card."

```gleam
Ability.Triggered(TriggeredAbility(
  trigger: Trigger.DealsCombatDamage(
    filter: Some(TargetFilter.Single(TargetType.Player)),
  ),
  targets: [],
  effect: Effect.Single(EffectStep.Discard(
    who: TargetRef.TriggerSubject,
    filter: CardFilter.Zone(Zone.Hand),
  )),
  optional: False,
  intervening_if: None,
))
```

##### Megrim (Enchantment)

> "Whenever an opponent discards a card, Megrim deals 2 damage to that player."

```gleam
Ability.Triggered(TriggeredAbility(
  trigger: Trigger.Discarded(
    filter: CardFilter.WithController(ControllerFilter.Opponent),
  ),
  targets: [],
  effect: Effect.Single(EffectStep.DealDamage(
    amount: Amount.Fixed(2),
    target: TargetRef.TriggerSubject,
    source_is_combat: False,
  )),
  optional: False,
  intervening_if: None,
))
```

##### Seasoned Marshal (Creature)

> "Whenever Seasoned Marshal attacks, you may tap target creature."

```gleam
Ability.Triggered(TriggeredAbility(
  trigger: Trigger.Attacks,
  targets: [TargetInfo(TargetFilter.Single(TargetType.Creature))],
  effect: Effect.Single(EffectStep.TapOrUntap(
    target: TargetRef.PrimaryTarget,
    mode: TapMode.Tap,
  )),
  optional: True,
  intervening_if: None,
))
```

#### Design Notes

(1) **Intervening "if" clause:** Per rule 603.4, intervening "if" clauses are checked both at trigger time and at resolution. The `intervening_if` field stores the condition as a `CardFilter` evaluated against the game state at both points. If false at either point, the ability does nothing.

(2) **TriggerSubject resolution:** The engine fills `TargetRef.TriggerSubject` based on the trigger event context:
- `DealsCombatDamage` / `DealsDamage` — the damaged entity (player or creature)
- `Discarded` — the discarding player
- Other triggers — resolves to `None` (no subject available)

(3) **Delayed vs. standard triggered abilities:** Standard triggered abilities are printed on cards and exist as long as the card is in the appropriate zone. Delayed triggered abilities (rule 603.7) are created during resolution and tracked separately. The `TriggeredAbility` type covers standard triggers; delayed triggers use the existing `DelayedTrigger` type from Phase D.

(4) **Gang of Elk (deferred detail):** Gang of Elk's "gets +2/+2 for each creature blocking it" requires counting blockers at resolution. This needs either an `Amount.CountOfBlockers` variant or a general `ForEach` loop mechanism. Deferred as a special case.

(5) **Soul Net (sacrifice trigger):** "Whenever a creature dies, you may pay {1}. If you do, you gain 1 life." uses `Trigger.Dies`. This is a triggered ability with a cost on resolution — the "you may pay {1}" is a modal choice during resolution, not an activation cost. The engine must support optional payments during triggered ability resolution.

### 5.2 Static Abilities

#### Design

Static abilities continuously modify game state, characteristics, or rules without using the stack (rule 604.1). They create continuous effects active as long as the source permanent is on the battlefield (rule 604.2).

```gleam
pub type StaticAbility {
  StaticAbility(
    effect: StaticEffect,
    zones: List(Zone),       // zones where ability functions (default: [Battlefield])
  )
}

pub type StaticEffect {
  // "Creatures you control get +1/+1" — layer 7d continuous pump
  PumpAll(
    filter: CardFilter,
    power: Int,
    toughness: Int,
    keywords: List(Keyword),
  )
  // "Creatures you control have flying" — layer 6 keyword grant
  GrantKeyword(
    filter: CardFilter,
    keyword: Keyword,
  )
}
```

#### Ability Union Update

```gleam
pub type Ability {
  Spell(SpellAbility)
  Activated(ActivatedAbility)
  Triggered(TriggeredAbility)
  Static(StaticAbility)
}
```

#### Card Examples

##### Glorious Anthem (Enchantment)

> "Creatures you control get +1/+1."

```gleam
Ability.Static(StaticAbility(
  effect: StaticEffect.PumpAll(
    filter: CardFilter.And(
      CardFilter.Types([card.Creature]),
      CardFilter.WithController(ControllerFilter.You),
    ),
    power: 1,
    toughness: 1,
    keywords: [],
  ),
  zones: [Zone.Battlefield],
))
```

##### Goblin King (Creature)

> "Other Goblins get +1/+1 and have mountainwalk."

```gleam
Ability.Static(StaticAbility(
  effect: StaticEffect.PumpAll(
    filter: CardFilter.And(
      CardFilter.Subtype("Goblin"),
      CardFilter.Not(CardFilter.Name("Goblin King")),
    ),
    power: 1,
    toughness: 1,
    keywords: [Keyword.Mountainwalk],
  ),
  zones: [Zone.Battlefield],
))
```

##### Fervor (Enchantment)

> "Creatures you control have haste."

```gleam
Ability.Static(StaticAbility(
  effect: StaticEffect.GrantKeyword(
    filter: CardFilter.And(
      CardFilter.Types([card.Creature]),
      CardFilter.WithController(ControllerFilter.You),
    ),
    keyword: Keyword.Haste,
  ),
  zones: [Zone.Battlefield],
))
```

#### Design Notes

(1) **"Other" self-exclusion:** Lord effects exclude themselves using `CardFilter.Not(CardFilter.Name("<self>"))`. The engine passes the source's name at evaluation time.

(2) **Layer system:** Static abilities interact through the layer system (rule 613):
- Layer 6: Keyword grants (`GrantKeyword`) — applies first
- Layer 7d: Power/toughness modifications (`PumpAll`) — applies after keywords
The engine must apply static effects in layer order when computing permanent characteristics.

(3) **Replacement effects remain out of scope:** Cards like Ensnaring Bridge, Meekstone, Worship, and Wild Growth create replacement effects (rule 614) or conditional rule-modifying static abilities. These require a separate replacement-effect framework and are not addressed by the current `StaticEffect` design.

(4) **Characteristic-defining abilities (rule 604.3):** CDAs like "~'s power is equal to the number of swamps you control" function in all zones and are not represented by the `StaticEffect` types above. They are deferred to a future expansion.

### 5.3 Stack Representation

Per rule 603.3, triggered abilities on the stack are objects with the text of the triggering ability. The existing `StackItem` type needs a new variant:

```gleam
pub type StackItem {
  StackItem(card: card.Card, controller_id: Int)
  // Add:
  TriggeredAbilityOnStack(
    ability: TriggeredAbility,
    controller_id: Int,
    source_permanent_id: String,
    trigger_subject: Option(Int),
  )
}
```

### Implementation Notes

Phase E implementation requires:
1. Adding `TriggeredAbility`, `Trigger`, `StaticAbility`, and `StaticEffect` types to `ability.gleam`
2. Updating the `Ability` union type
3. Adding `TargetRef.TriggerSubject` variant
4. Adding `StackItem.TriggeredAbilityOnStack` variant
5. Engine support for: detecting trigger events during game actions, putting triggered abilities on the stack, resolving triggered abilities, and applying static continuous effects in layer order

---

## Open Questions

### Variable Storage

Effect steps like `ChooseColor` implicitly store variables during resolution.  
Subsequent steps reference the choice through dedicated types (`ColorRef.Chosen`).

**Decision**: Effect steps that produce a value store it implicitly, and a `*Ref` type (e.g. `ColorRef`) with a `Chosen` variant exposes the result to later steps. The engine tracks the most recent value from the corresponding step type during sequence resolution.

### Loops and Repetition

Cards like "for each creature, deal 1 damage" need iteration.

**Options:**
1. Add a `ForEach` effect step with a filter and a body effect
2. Handle repetition at resolution time by calling the effect multiple times
3. Use a separate `Repeat` effect step

**Decision needed**: Do we need this for 7ED cards, or defer?

**Status**: Deferred. No 7th edition card requires a general loop mechanism.
Mana Clash's repeat-until-both-heads pattern is handled by a dedicated
`ManaClash` effect step (see Coin Flips in Phase D) rather than general
`RepeatUntil` / conditional branching.

### Conditions

Some effects have "if X, then Y" (e.g., "if you control a creature, get +2"). Coin flip outcomes also need conditional branching ("if tails, deal 1 damage").

**Current**: Not represented. Can add `If(Condition, then, else)` if needed.

### Multi-target Effects

Some cards like "deal 2 damage to each of X creatures" might need:
- Multiple targets in the targeting phase
- A single effect that applies to all

**Current**: Multiple targets = multiple `TargetInfo` entries, each with `TargetRef.PrimaryTarget`, `TargetRef.SecondaryTarget`, etc.

### TargetRef

References to objects selected during targeting or implied by the game state.

```gleam
pub type TargetRef {
  PrimaryTarget    // First declared target
  SecondaryTarget  // Second declared target
  Controller       // The controller of the spell/ability ("you", rule 109.5)
  Source           // The source permanent of the activated ability ("itself")
  AllOf(CardFilter) // All cards matching a filter on the battlefield
}
```

`Controller` refers to the controller of the spell or ability being resolved — equivalent to "you" in card text.

### Static Abilities

Not in scope for now, but future design needed for:
- Passive effects (e.g., "creatures you control get +1/+1")
- Replacement effects
- Layer system interactions

---

## Implementation Notes

### Module Structure

Proposed modules:
- `ability.gleam` - Core types (Amount, Duration, Keyword, TokenDefinition, ActivationCost)
- `targeting.gleam` - TargetType, TargetFilter, TargetInfo
- `filters.gleam` - CardFilter, CardRestriction, ControllerFilter, helper constructors
- `effects.gleam` - Effect, EffectStep, Affected, RevealTo
- `ability_type.gleam` - SpellAbility, ActivatedAbility, Ability

### Integration Points

- `Card` type will need `abilities: List(Ability)` field
- `StackItem` will need to track resolved targets and chosen modes/variables
- `Permanent` may need to track activated abilities with their state (tapped, etc.)

### Next Steps

1. Implement core types in `ability.gleam`
2. Add abilities to card definitions for test cards
3. Update stack resolution to handle effects
4. Implement effect resolution for core effects
5. Add activated ability handling
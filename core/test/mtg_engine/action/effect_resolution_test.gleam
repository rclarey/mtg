import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import mtg_engine/ability
import mtg_engine/action
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/effects
import mtg_engine/error
import mtg_engine/mana
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import test_helpers.{
  add_card_to_hand, add_creature_to_battlefield, create_test_creature,
  get_permanent, get_player, pass, pass_until,
}

// ── Helper: add a card to a player's library ──────────────────────────────

fn add_card_to_library(
  state: state.State,
  player_id: Int,
  card: card.Card,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, library: [card, ..p.library])
    }),
  )
}

// ── Helper: produce mana, cast an instant/sorcery, and choose targets ─────

fn cast_spell_with_targets(
  state: state.State,
  caster_id: Int,
  spell: card.Card,
  mana_to_produce: mana.Produced,
  chosen_targets: List(targeting.ChosenTargets),
) -> Result(state.State, error.Error) {
  use state <- result.try(action.dispatch(
    state,
    action.ProduceMana(caster_id, mana_to_produce),
  ))
  let cast_action = case spell.card_type {
    card_type.Instant -> action.CastInstant(caster_id, spell.id, 0)
    card_type.Sorcery -> action.CastSorcery(caster_id, spell.id, 0)
    _ -> action.CastCreature(caster_id, spell.id, 0)
  }
  use state <- result.try(action.dispatch(state, cast_action))
  action.dispatch(
    state,
    action.ChooseTargets(caster_id, spell.id, chosen_targets, None, []),
  )
}

// ── Helper: produce mana and cast a spell with no targets ─────────────────

fn cast_spell_no_targets(
  state: state.State,
  caster_id: Int,
  spell: card.Card,
  mana_to_produce: mana.Produced,
) -> Result(state.State, error.Error) {
  use state <- result.try(action.dispatch(
    state,
    action.ProduceMana(caster_id, mana_to_produce),
  ))
  let cast_action = case spell.card_type {
    card_type.Instant -> action.CastInstant(caster_id, spell.id, 0)
    card_type.Sorcery -> action.CastSorcery(caster_id, spell.id, 0)
    _ -> action.CastCreature(caster_id, spell.id, 0)
  }
  action.dispatch(state, cast_action)
}

// ══════════════════════════════════════════════════════════════════════════
// 1. DealDamage to player
// ══════════════════════════════════════════════════════════════════════════

pub fn deal_damage_to_player_test() {
  let state = state.new()

  // Lightning Bolt — Instant dealing 3 damage to target player
  let bolt =
    card.Card(
      id: "bolt1",
      name: "Lightning Bolt",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 1,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.player_target()],
          additional_costs: [],
          effect: effects.Single(effects.DealDamage(
            amount: effects.Fixed(3),
            target: targeting.PrimaryTarget,
            source_is_combat: False,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, bolt)
  let state = pass_until(state, step.PreCombatMain)

  // Produce red mana, cast bolt targeting player 2
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 0)
  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]
  let assert Ok(state) = cast_spell_with_targets(state, 1, bolt, mana, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify player 2 lost 3 life
  let p2 = get_player(state, 2)
  assert p2.life == 17
}

// ══════════════════════════════════════════════════════════════════════════
// 2. DealDamage to creature
// ══════════════════════════════════════════════════════════════════════════

pub fn deal_damage_to_creature_test() {
  let state = state.new()

  // Opponent controls a 5/5 creature (high toughness so it survives the damage)
  let bear =
    card.Card(
      id: "bear1",
      name: "Tough Bear",
      card_type: card_type.Creature,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 3,
        colorless: 0,
        x: 0,
      ),
      power: Some(5),
      toughness: Some(5),
      supertypes: [],
      subtypes: [],
      abilities: [],
      is_token: False,
    )
  let state = add_creature_to_battlefield(state, 2, bear, 0)

  // Shock — Instant dealing 2 damage to target creature
  let shock =
    card.Card(
      id: "shock1",
      name: "Shock",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 1,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.creature_target()],
          additional_costs: [],
          effect: effects.Single(effects.DealDamage(
            amount: effects.Fixed(2),
            target: targeting.PrimaryTarget,
            source_is_combat: False,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, shock)
  let state = pass_until(state, step.PreCombatMain)

  // Produce red mana, cast shock targeting the bear
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 0)
  let targets = [
    targeting.ChosenTargets(targets: [targeting.TargetCard("bear1")]),
  ]
  let assert Ok(state) = cast_spell_with_targets(state, 1, shock, mana, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify bear has 2 damage marked
  let bear_perm = get_permanent(state, 2, "bear1")
  assert bear_perm.damage == 2
}

// ══════════════════════════════════════════════════════════════════════════
// 3. DrawCards
// ══════════════════════════════════════════════════════════════════════════

pub fn draw_cards_test() {
  let state = state.new()

  // Create a sorcery that draws 2 cards
  let divination =
    card.Card(
      id: "div1",
      name: "Divination",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 1,
        white: 0,
        blue: 1,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [],
          additional_costs: [],
          effect: effects.Single(effects.DrawCards(
            num: effects.Fixed(2),
            target: targeting.Controller,
          )),
        )),
      ],
      is_token: False,
    )

  // Add some cards to the library so there's something to draw
  let filler1 =
    card.Card(
      id: "filler1",
      name: "Filler Card 1",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [],
      is_token: False,
    )
  let filler2 =
    card.Card(
      id: "filler2",
      name: "Filler Card 2",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [],
      is_token: False,
    )
  let state = add_card_to_library(state, 1, filler1)
  let state = add_card_to_library(state, 1, filler2)

  let state = add_card_to_hand(state, 1, divination)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (1 generic + 1 blue)
  let mana =
    mana.Produced(white: 0, blue: 1, black: 0, red: 0, green: 0, colorless: 1)
  let assert Ok(state) = cast_spell_no_targets(state, 1, divination, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify hand size increased by 2
  let p1 = get_player(state, 1)
  assert list.length(p1.hand) == 2

  // Verify library decreased by 2
  assert p1.library == []
}

// ══════════════════════════════════════════════════════════════════════════
// 4. GainLife
// ══════════════════════════════════════════════════════════════════════════

pub fn gain_life_test() {
  let state = state.new()

  // Instant that gains 4 life
  let healing =
    card.Card(
      id: "heal1",
      name: "Healing Salve",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 1,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [],
          additional_costs: [],
          effect: effects.Single(effects.GainLife(
            amount: effects.Fixed(4),
            target: targeting.Controller,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, healing)
  let state = pass_until(state, step.PreCombatMain)

  // Produce white mana
  let mana =
    mana.Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
  let assert Ok(state) = cast_spell_no_targets(state, 1, healing, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify player 1 gained 4 life
  let p1 = get_player(state, 1)
  assert p1.life == 24
}

// ══════════════════════════════════════════════════════════════════════════
// 5. LoseLife
// ══════════════════════════════════════════════════════════════════════════

pub fn lose_life_test() {
  let state = state.new()

  // Instant that makes target player lose 3 life
  let drain =
    card.Card(
      id: "drain1",
      name: "Drain Life",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 1,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.player_target()],
          additional_costs: [],
          effect: effects.Single(effects.LoseLife(
            amount: effects.Fixed(3),
            target: targeting.PrimaryTarget,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, drain)
  let state = pass_until(state, step.PreCombatMain)

  // Produce black mana, cast targeting opponent
  let mana =
    mana.Produced(white: 0, blue: 0, black: 1, red: 0, green: 0, colorless: 0)
  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]
  let assert Ok(state) = cast_spell_with_targets(state, 1, drain, mana, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify opponent lost 3 life
  let p2 = get_player(state, 2)
  assert p2.life == 17
}

// ══════════════════════════════════════════════════════════════════════════
// 6. Mill
// ══════════════════════════════════════════════════════════════════════════

pub fn mill_test() {
  let state = state.new()

  // Add 3 cards to opponent's library (range from 1 to 3 inclusive = [1,2,3])
  let cards =
    list.range(1, 3)
    |> list.map(fn(i) {
      card.Card(
        id: "lib" <> int.to_string(i),
        name: "Library Card " <> int.to_string(i),
        card_type: card_type.Instant,
        mana_cost: mana.Cost(
          generic: 0,
          white: 0,
          blue: 0,
          black: 0,
          red: 0,
          green: 0,
          colorless: 0,
          x: 0,
        ),
        power: None,
        toughness: None,
        supertypes: [],
        subtypes: [],
        abilities: [],
        is_token: False,
      )
    })
  let state = list.fold(cards, state, fn(s, c) { add_card_to_library(s, 2, c) })

  // Verify library has 3 cards before continuing
  let p2_before = get_player(state, 2)
  assert list.length(p2_before.library) == 3

  // Sorcery that mills 2 cards from target player
  let mill_spell =
    card.Card(
      id: "mill1",
      name: "Mind Sculpt",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 1,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.player_target()],
          additional_costs: [],
          effect: effects.Single(effects.Mill(
            num: effects.Fixed(2),
            target: targeting.PrimaryTarget,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, mill_spell)
  let state = pass_until(state, step.PreCombatMain)

  // Produce blue mana, cast targeting opponent
  let mana =
    mana.Produced(white: 0, blue: 1, black: 0, red: 0, green: 0, colorless: 0)
  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]
  let assert Ok(state) =
    cast_spell_with_targets(state, 1, mill_spell, mana, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify opponent's library decreased by 2 and graveyard increased by 2
  let p2 = get_player(state, 2)
  assert list.length(p2.library) == 1
  assert list.length(p2.graveyard) == 2
}

// ══════════════════════════════════════════════════════════════════════════
// 7. Destroy
// ══════════════════════════════════════════════════════════════════════════

pub fn destroy_creature_test() {
  let state = state.new()

  // Opponent controls a creature
  let bear = create_test_creature("bear1", "Runeclaw Bear")
  let state = add_creature_to_battlefield(state, 2, bear, 0)

  // Instant that destroys target creature
  let murder =
    card.Card(
      id: "murder1",
      name: "Murder",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 1,
        white: 0,
        blue: 0,
        black: 1,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.creature_target()],
          additional_costs: [],
          effect: effects.Single(effects.Destroy(
            target: targeting.PrimaryTarget,
            cant_regenerate: False,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, murder)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (1 generic + 1 black), cast targeting the bear
  let mana =
    mana.Produced(white: 0, blue: 0, black: 1, red: 0, green: 0, colorless: 1)
  let targets = [
    targeting.ChosenTargets(targets: [targeting.TargetCard("bear1")]),
  ]
  let assert Ok(state) =
    cast_spell_with_targets(state, 1, murder, mana, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify creature is gone from battlefield and in graveyard
  let p2 = get_player(state, 2)
  assert dict.has_key(p2.battlefield, "bear1") == False
  assert list.length(p2.graveyard) >= 1
  let assert Ok(gy_card) = list.first(p2.graveyard)
  assert gy_card.id == "bear1"
}

// ══════════════════════════════════════════════════════════════════════════
// 8. Bounce
// ══════════════════════════════════════════════════════════════════════════

pub fn bounce_creature_test() {
  let state = state.new()

  // Opponent controls a creature
  let bear = create_test_creature("bear1", "Runeclaw Bear")
  let state = add_creature_to_battlefield(state, 2, bear, 0)

  // Instant that returns target creature to owner's hand
  let unsummon =
    card.Card(
      id: "unsum1",
      name: "Unsummon",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 1,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.creature_target()],
          additional_costs: [],
          effect: effects.Single(effects.Bounce(target: targeting.PrimaryTarget)),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, unsummon)
  let state = pass_until(state, step.PreCombatMain)

  // Produce blue mana, cast targeting the bear
  let mana =
    mana.Produced(white: 0, blue: 1, black: 0, red: 0, green: 0, colorless: 0)
  let targets = [
    targeting.ChosenTargets(targets: [targeting.TargetCard("bear1")]),
  ]
  let assert Ok(state) =
    cast_spell_with_targets(state, 1, unsummon, mana, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify creature is back in opponent's hand
  let p2 = get_player(state, 2)
  assert dict.has_key(p2.battlefield, "bear1") == False
  assert list.length(p2.hand) >= 1
  let assert Ok(hand_card) = list.first(p2.hand)
  assert hand_card.id == "bear1"
}

// ══════════════════════════════════════════════════════════════════════════
// 9. TapOrUntap (Tap)
// ══════════════════════════════════════════════════════════════════════════

pub fn tap_or_untap_test() {
  let state = state.new()

  // Player 1 controls an untapped creature
  let bear = create_test_creature("bear1", "Runeclaw Bear")
  let state = add_creature_to_battlefield(state, 1, bear, 0)

  // Sorcery that taps target permanent
  let tap_spell =
    card.Card(
      id: "tap1",
      name: "Tap Down",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 1,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.creature_target()],
          additional_costs: [],
          effect: effects.Single(effects.TapOrUntap(
            target: targeting.PrimaryTarget,
            mode: effects.Tap,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, tap_spell)
  let state = pass_until(state, step.PreCombatMain)

  // Produce blue mana, cast targeting own creature
  let mana =
    mana.Produced(white: 0, blue: 1, black: 0, red: 0, green: 0, colorless: 0)
  let targets = [
    targeting.ChosenTargets(targets: [targeting.TargetCard("bear1")]),
  ]
  let assert Ok(state) =
    cast_spell_with_targets(state, 1, tap_spell, mana, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify creature is now tapped
  let bear_perm = get_permanent(state, 1, "bear1")
  assert bear_perm.tapped == True
}

// ══════════════════════════════════════════════════════════════════════════
// 10. CounterSpell
// ══════════════════════════════════════════════════════════════════════════

pub fn counterspell_test() {
  let state = state.new()

  // Player 1 has a creature and a counterspell in hand
  let bear = create_test_creature("bear1", "Runeclaw Bear")

  // Counterspell — Instant that counters target spell
  let counter =
    card.Card(
      id: "counter1",
      name: "Counterspell",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 2,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.target_info(targeting.Single(targeting.Spell))],
          additional_costs: [],
          effect: effects.Single(effects.CounterSpell(
            target: targeting.PrimaryTarget,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, bear)
  let state = add_card_to_hand(state, 1, counter)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana for both spells (2 green for bear + 2 blue for counterspell)
  let mana =
    mana.Produced(white: 0, blue: 2, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Player 1 casts the creature spell
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "bear1", 0))
  assert list.length(state.stack) == 1

  // Player 1 casts Counterspell targeting their own creature spell
  let assert Ok(state) =
    action.dispatch(state, action.CastInstant(1, "counter1", 0))
  assert list.length(state.stack) == 2

  // Choose targets for Counterspell — target the creature spell on the stack
  let targets = [
    targeting.ChosenTargets(targets: [targeting.TargetCard("bear1")]),
  ]
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ChooseTargets(1, "counter1", targets, None, []),
    )
  assert list.length(state.stack) == 2

  // Both players pass — top of stack (Counterspell) resolves first (LIFO)
  let state = pass(state)

  // Counterspell resolved and countered the creature spell.
  // The creature spell was removed from the stack.
  // The Counterspell (instant) went to the graveyard.
  assert state.stack == []

  // Verify counterspell is in graveyard and creature is NOT on battlefield
  let p1 = get_player(state, 1)
  assert dict.has_key(p1.battlefield, "bear1") == False

  // The counterspell (instant) should be in the graveyard after resolving
  let found_counter = list.find(p1.graveyard, fn(c) { c.id == "counter1" })
  assert result.is_ok(found_counter)
}

// ══════════════════════════════════════════════════════════════════════════
// 11. PumpCreature (with keywords)
// ══════════════════════════════════════════════════════════════════════════

pub fn pump_creature_test() {
  let state = state.new()

  // Player 1 controls a 1/1 creature
  let elf =
    card.Card(
      id: "elf1",
      name: "Llanowar Elves",
      card_type: card_type.Creature,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
        x: 0,
      ),
      power: Some(1),
      toughness: Some(1),
      supertypes: [],
      subtypes: [],
      abilities: [],
      is_token: False,
    )
  let state = add_creature_to_battlefield(state, 1, elf, 0)

  // Instant that gives +2/+1 and Flying to target creature
  let pump =
    card.Card(
      id: "pump1",
      name: "Growth Charm",
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.creature_target()],
          additional_costs: [],
          effect: effects.Single(effects.PumpCreature(
            target: targeting.PrimaryTarget,
            power: effects.Fixed(2),
            toughness: effects.Fixed(1),
            add_keywords: [effects.Flying],
            duration: effects.EndOfTurn,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, pump)
  let state = pass_until(state, step.PreCombatMain)

  // Produce green mana, cast targeting own elf
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let targets = [
    targeting.ChosenTargets(targets: [targeting.TargetCard("elf1")]),
  ]
  let assert Ok(state) = cast_spell_with_targets(state, 1, pump, mana, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify creature has +2/+1 and Flying
  let elf_perm = get_permanent(state, 1, "elf1")
  assert elf_perm.card.power == Some(3)
  assert elf_perm.card.toughness == Some(2)
  assert list.contains(elf_perm.granted_keywords, "Flying")
}

// ══════════════════════════════════════════════════════════════════════════
// 12. CreateToken
// ══════════════════════════════════════════════════════════════════════════

pub fn create_token_test() {
  let state = state.new()

  // Sorcery that creates a 1/1 green Elf Warrior creature token
  let make_token =
    card.Card(
      id: "token_spell1",
      name: "Elf Strike",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [],
          additional_costs: [],
          effect: effects.Single(
            effects.CreateToken(
              token: effects.TokenDefinition(
                name: "Elf Warrior",
                power: 1,
                toughness: 1,
                types: [card_type.Creature],
                keywords: [],
              ),
            ),
          ),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, make_token)
  let state = pass_until(state, step.PreCombatMain)

  // Produce green mana, cast
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = cast_spell_no_targets(state, 1, make_token, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify token exists on the battlefield
  let p1 = get_player(state, 1)
  assert dict.size(p1.battlefield) == 1

  // Find the token (it should be the only permanent)
  let assert Ok(token_perm) = list.first(dict.values(p1.battlefield))
  assert token_perm.card.is_token == True
  assert token_perm.card.name == "Elf Warrior"
  assert token_perm.card.power == Some(1)
  assert token_perm.card.toughness == Some(1)
}

// ══════════════════════════════════════════════════════════════════════════
// 13. ProduceMana
// ══════════════════════════════════════════════════════════════════════════

pub fn produce_mana_test() {
  let state = state.new()

  // Sorcery that adds {R}{R}
  let rite_of_flame =
    card.Card(
      id: "rof1",
      name: "Rite of Flame",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 1,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      supertypes: [],
      subtypes: [],
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [],
          additional_costs: [],
          effect: effects.Single(
            effects.ProduceMana(mana: mana.Produced(
              white: 0,
              blue: 0,
              black: 0,
              red: 2,
              green: 0,
              colorless: 0,
            )),
          ),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, rite_of_flame)
  let state = pass_until(state, step.PreCombatMain)

  // Produce red mana to cast
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 0)
  let assert Ok(state) = cast_spell_no_targets(state, 1, rite_of_flame, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify mana pool has 2 red mana
  let p1 = get_player(state, 1)
  assert p1.mana_pool.red == 2
}

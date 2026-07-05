import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import mtg_engine/ability
import mtg_engine/action
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/effects
import mtg_engine/error
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import test_helpers.{
  add_card_to_hand, add_creature_to_battlefield, create_test_creature,
  get_player, pass, pass_until,
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

// ── Helper: produce mana, cast an instant/sorcery with X value, and choose targets ──

fn cast_spell_with_x_and_targets(
  state: state.State,
  caster_id: Int,
  spell: card.Card,
  mana_to_produce: mana.Produced,
  x_value: Int,
  chosen_targets: List(targeting.ChosenTargets),
) -> Result(state.State, error.Error) {
  use state <- result.try(action.dispatch(
    state,
    action.ProduceMana(caster_id, mana_to_produce),
  ))
  let cast_action = case spell.card_type {
    card_type.Instant -> action.CastInstant(caster_id, spell.id, x_value)
    card_type.Sorcery -> action.CastSorcery(caster_id, spell.id, x_value)
    _ -> action.CastCreature(caster_id, spell.id, x_value)
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
// 1. Fixed amount — sanity check
// ══════════════════════════════════════════════════════════════════════════

pub fn fixed_amount_sanity_test() {
  let state = state.new()

  // Instant that deals 3 fixed damage
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
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastInstant(1, "bolt1", 0))
  let assert Ok(state) =
    action.dispatch(state, action.ChooseTargets(1, "bolt1", targets, None, []))

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify player 2 lost 3 life
  let p2 = get_player(state, 2)
  assert p2.life == 17
}

// ══════════════════════════════════════════════════════════════════════════
// 2. X amount
// ══════════════════════════════════════════════════════════════════════════

pub fn x_amount_test() {
  let state = state.new()

  // Fireball — Instant dealing X damage to target player
  let fireball =
    card.Card(
      id: "fire1",
      name: "Fireball",
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
            amount: effects.X,
            target: targeting.PrimaryTarget,
            source_is_combat: False,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, fireball)
  let state = pass_until(state, step.PreCombatMain)

  // Cast with X=5: produce 1 red + 5 colorless (to cover X in cost)
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 5)
  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]
  let assert Ok(state) =
    cast_spell_with_x_and_targets(state, 1, fireball, mana, 5, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify player 2 lost 5 life
  let p2 = get_player(state, 2)
  assert p2.life == 15
}

pub fn x_amount_different_values_test() {
  let state = state.new()

  // Same Fireball card but with X=3
  let fireball =
    card.Card(
      id: "fire2",
      name: "Fireball",
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
            amount: effects.X,
            target: targeting.PrimaryTarget,
            source_is_combat: False,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, fireball)
  let state = pass_until(state, step.PreCombatMain)

  // Cast with X=3: produce 1 red + 3 colorless
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 3)
  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]
  let assert Ok(state) =
    cast_spell_with_x_and_targets(state, 1, fireball, mana, 3, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify player 2 lost 3 life
  let p2 = get_player(state, 2)
  assert p2.life == 17
}

// ══════════════════════════════════════════════════════════════════════════
// 3. Count amount
// ══════════════════════════════════════════════════════════════════════════

pub fn count_amount_zero_test() {
  let state = state.new()

  // Sorcery that makes you gain life equal to the number of creatures
  let life_bloom =
    card.Card(
      id: "bloom1",
      name: "Life Bloom",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 1,
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
            amount: effects.Count(filters.creature()),
            target: targeting.Controller,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, life_bloom)
  let state = pass_until(state, step.PreCombatMain)

  // No creatures on the battlefield
  // Produce mana (1 generic + 1 white)
  let mana =
    mana.Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 1)
  let assert Ok(state) = cast_spell_no_targets(state, 1, life_bloom, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // With 0 creatures, should gain 0 life
  let p1 = get_player(state, 1)
  assert p1.life == 20
}

pub fn count_amount_test() {
  let state = state.new()

  // Add 2 creatures to player 1's battlefield
  let bear1 = create_test_creature("bear1", "Runeclaw Bear")
  let bear2 = create_test_creature("bear2", "Silverback Bear")
  let state = add_creature_to_battlefield(state, 1, bear1, 0)
  let state = add_creature_to_battlefield(state, 1, bear2, 0)

  // Sorcery that makes you gain life equal to the number of creatures
  let life_bloom =
    card.Card(
      id: "bloom2",
      name: "Life Bloom",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 1,
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
            amount: effects.Count(filters.creature()),
            target: targeting.Controller,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, life_bloom)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (1 generic + 1 white)
  let mana =
    mana.Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 1)
  let assert Ok(state) = cast_spell_no_targets(state, 1, life_bloom, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // With 2 creatures, should gain 2 life
  let p1 = get_player(state, 1)
  assert p1.life == 22
}

pub fn count_amount_five_test() {
  let state = state.new()

  // Add 5 creatures to player 1's battlefield
  let ids = list.range(1, 5)
  let state =
    list.fold(ids, state, fn(s, i) {
      let creature = create_test_creature("bear" <> int.to_string(i), "Bear")
      add_creature_to_battlefield(s, 1, creature, 0)
    })

  // Sorcery that makes you gain life equal to the number of creatures
  let life_bloom =
    card.Card(
      id: "bloom3",
      name: "Life Bloom",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 1,
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
            amount: effects.Count(filters.creature()),
            target: targeting.Controller,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, life_bloom)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (1 generic + 1 white)
  let mana =
    mana.Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 1)
  let assert Ok(state) = cast_spell_no_targets(state, 1, life_bloom, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // With 5 creatures, should gain 5 life
  let p1 = get_player(state, 1)
  assert p1.life == 25
}

// ══════════════════════════════════════════════════════════════════════════
// 4. Multiply amount
// ══════════════════════════════════════════════════════════════════════════

pub fn multiply_amount_test() {
  let state = state.new()

  // Add 2 creatures — Count will be 2, Multiply by 3 = 6 life gained
  let bear1 = create_test_creature("bear1", "Runeclaw Bear")
  let bear2 = create_test_creature("bear2", "Silverback Bear")
  let state = add_creature_to_battlefield(state, 1, bear1, 0)
  let state = add_creature_to_battlefield(state, 1, bear2, 0)

  // Sorcery: gain 3 life for each creature you control
  let life_triple =
    card.Card(
      id: "triple1",
      name: "Life Tripler",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 1,
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
            amount: effects.Multiply(effects.Count(filters.creature()), 3),
            target: targeting.Controller,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, life_triple)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (1 generic + 1 white)
  let mana =
    mana.Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 1)
  let assert Ok(state) = cast_spell_no_targets(state, 1, life_triple, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // Count=2, Multiply*3 = 6 life gained
  let p1 = get_player(state, 1)
  assert p1.life == 26
}

pub fn multiply_amount_zero_test() {
  let state = state.new()

  // No creatures on the battlefield

  // Sorcery: gain 3 life for each creature you control
  let life_triple =
    card.Card(
      id: "triple2",
      name: "Life Tripler",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 1,
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
            amount: effects.Multiply(effects.Count(filters.creature()), 3),
            target: targeting.Controller,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, life_triple)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (1 generic + 1 white)
  let mana =
    mana.Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 1)
  let assert Ok(state) = cast_spell_no_targets(state, 1, life_triple, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // Count=0, Multiply*3 = 0 life gained
  let p1 = get_player(state, 1)
  assert p1.life == 20
}

pub fn multiply_nested_test() {
  let state = state.new()

  // Nested Multiply: Multiply(Multiply(Fixed(2), 3), 4) = 2*3*4 = 24
  let nested_card =
    card.Card(
      id: "nested1",
      name: "Exponential Blessing",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 2,
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
            amount: effects.Multiply(effects.Multiply(effects.Fixed(2), 3), 4),
            target: targeting.Controller,
          )),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, nested_card)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (2 generic + 1 white)
  let mana =
    mana.Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 2)
  let assert Ok(state) = cast_spell_no_targets(state, 1, nested_card, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // Gain 24 life
  let p1 = get_player(state, 1)
  assert p1.life == 44
}

// ══════════════════════════════════════════════════════════════════════════
// 5. PreviousStep in Sequence — Tolarian Winds pattern
// ══════════════════════════════════════════════════════════════════════════

pub fn previous_step_discard_draw_test() {
  let state = state.new()

  // Tolarian Winds — Discard your hand, then draw that many cards.
  let winds =
    card.Card(
      id: "winds1",
      name: "Tolarian Winds",
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
          effect: effects.Sequence([
            effects.Discard(who: targeting.Controller, filter: filters.AnyCard),
            effects.DrawCards(
              num: effects.PreviousStep,
              target: targeting.Controller,
            ),
          ]),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, winds)

  // Add 3 filler cards to hand so the player has cards to discard
  let filler = fn(id: String) {
    card.Card(
      id: id,
      name: "Filler Card " <> id,
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
  }
  let state = add_card_to_hand(state, 1, filler("filler1"))
  let state = add_card_to_hand(state, 1, filler("filler2"))
  let state = add_card_to_hand(state, 1, filler("filler3"))

  // Add cards to library so we have something to draw
  let state = add_card_to_library(state, 1, filler("lib1"))
  let state = add_card_to_library(state, 1, filler("lib2"))
  let state = add_card_to_library(state, 1, filler("lib3"))

  // Verify we have 4 cards in hand before casting (winds + 3 fillers)
  let p1_before = get_player(state, 1)
  assert list.length(p1_before.hand) == 4

  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (1 generic + 1 blue)
  let mana =
    mana.Produced(white: 0, blue: 1, black: 0, red: 0, green: 0, colorless: 1)
  let assert Ok(state) = cast_spell_no_targets(state, 1, winds, mana)

  // After casting, the spell is on the stack, so hand has 3 fillers
  let p1_after_cast = get_player(state, 1)
  assert list.length(p1_after_cast.hand) == 3

  // Both players pass — spell resolves
  let state = pass(state)

  // After resolution:
  // - Discard: 3 fillers discarded -> hand is empty, graveyard has 3
  // - DrawCards(PreviousStep=3): draws 3 cards from library
  // - Spell moves to graveyard from stack
  let p1 = get_player(state, 1)

  // Hand should have 3 cards (drawn from library)
  assert list.length(p1.hand) == 3

  // Library should be empty (3 drawn out of 3)
  assert p1.library == []

  // Graveyard should have 4 cards (3 discarded + 1 resolved spell)
  // (Note: the resolved sorcery goes to graveyard after the effect resolves)
  assert list.length(p1.graveyard) == 4
}

// ══════════════════════════════════════════════════════════════════════════
// 6. PreviousStep with damage and life — Corrupt pattern
// ══════════════════════════════════════════════════════════════════════════

pub fn previous_step_damage_life_test() {
  let state = state.new()

  // Add 4 creatures to player 1's battlefield
  let ids = list.range(1, 4)
  let state =
    list.fold(ids, state, fn(s, i) {
      let creature = create_test_creature("c" <> int.to_string(i), "Creature")
      add_creature_to_battlefield(s, 1, creature, 0)
    })

  // Corrupt — Deal damage equal to creatures you control, gain life equal
  // to damage dealt this way.
  let corrupt =
    card.Card(
      id: "corrupt1",
      name: "Corrupt",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 2,
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
          targets: [targeting.any_target()],
          additional_costs: [],
          effect: effects.Sequence([
            effects.DealDamage(
              amount: effects.Count(filters.creature()),
              target: targeting.PrimaryTarget,
              source_is_combat: False,
            ),
            effects.GainLife(
              amount: effects.PreviousStep,
              target: targeting.Controller,
            ),
          ]),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, corrupt)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (2 generic + 1 black)
  let mana =
    mana.Produced(white: 0, blue: 0, black: 1, red: 0, green: 0, colorless: 2)
  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastSorcery(1, "corrupt1", 0))
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ChooseTargets(1, "corrupt1", targets, None, []),
    )

  // Both players pass — spell resolves
  let state = pass(state)

  // Player 2 should have lost 4 life (damage from Count=4)
  let p2 = get_player(state, 2)
  assert p2.life == 16

  // Player 1 should have gained 4 life (from PreviousStep=4)
  let p1 = get_player(state, 1)
  assert p1.life == 24
}

pub fn previous_step_damage_life_zero_creatures_test() {
  let state = state.new()

  // No creatures on the battlefield

  // Corrupt with 0 creatures
  let corrupt =
    card.Card(
      id: "corrupt2",
      name: "Corrupt",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 2,
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
          targets: [targeting.any_target()],
          additional_costs: [],
          effect: effects.Sequence([
            effects.DealDamage(
              amount: effects.Count(filters.creature()),
              target: targeting.PrimaryTarget,
              source_is_combat: False,
            ),
            effects.GainLife(
              amount: effects.PreviousStep,
              target: targeting.Controller,
            ),
          ]),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, corrupt)
  let state = pass_until(state, step.PreCombatMain)

  // Produce mana (2 generic + 1 black)
  let mana =
    mana.Produced(white: 0, blue: 0, black: 1, red: 0, green: 0, colorless: 2)
  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastSorcery(1, "corrupt2", 0))
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ChooseTargets(1, "corrupt2", targets, None, []),
    )

  // Both players pass — spell resolves
  let state = pass(state)

  // Player 2 loses 0 life, player 1 gains 0 life
  let p2 = get_player(state, 2)
  assert p2.life == 20

  let p1 = get_player(state, 1)
  assert p1.life == 20
}

// ══════════════════════════════════════════════════════════════════════════
// 6b. PreviousStep reflects post-prevention damage (Task 3)
// ══════════════════════════════════════════════════════════════════════════

pub fn previous_step_post_prevention_test() {
  let state = state.new()

  // Custom spell: prevent 2 damage to target, deal 5 damage to target,
  // gain life equal to damage dealt. With the shield, only 3 damage gets
  // through, so life gain should be 3 (not 5).
  let spell =
    card.Card(
      id: "test_prevent",
      name: "Test Prevent and Drain",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 2,
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
          effect: effects.Sequence([
            effects.PreventDamage(
              target: targeting.PrimaryTarget,
              mode: effects.Shield(amount: effects.Fixed(2)),
            ),
            effects.DealDamage(
              amount: effects.Fixed(5),
              target: targeting.PrimaryTarget,
              source_is_combat: False,
            ),
            effects.GainLife(
              amount: effects.PreviousStep,
              target: targeting.Controller,
            ),
          ]),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, spell)
  let state = pass_until(state, step.PreCombatMain)

  let mana =
    mana.Produced(white: 0, blue: 0, black: 1, red: 0, green: 0, colorless: 2)
  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastSorcery(1, "test_prevent", 0))
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ChooseTargets(1, "test_prevent", targets, None, []),
    )

  // Both players pass — spell resolves
  let state = pass(state)

  // Player 2 should have lost 3 life (5 damage - 2 prevented)
  let p2 = get_player(state, 2)
  assert p2.life == 17

  // Player 1 should have gained 3 life (post-prevention amount, not 5)
  let p1 = get_player(state, 1)
  assert p1.life == 23
}

pub fn previous_step_first_in_sequence_test() {
  let state = state.new()

  // Add a card to library so we can detect if any draw occurs
  let filler =
    card.Card(
      id: "lib_check",
      name: "Library Check Card",
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
  let state = add_card_to_library(state, 1, filler)

  // A sorcery that attempts to draw PreviousStep as the first step.
  // Since previous_step_result starts at 0, this should draw 0 cards.
  let draw_zero =
    card.Card(
      id: "draw_zero1",
      name: "Draw Nothing",
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 1,
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
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [],
          additional_costs: [],
          effect: effects.Sequence([
            effects.DrawCards(
              num: effects.PreviousStep,
              target: targeting.Controller,
            ),
          ]),
        )),
      ],
      is_token: False,
    )
  let state = add_card_to_hand(state, 1, draw_zero)
  let state = pass_until(state, step.PreCombatMain)

  // Produce 1 generic mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 0, colorless: 1)
  let assert Ok(state) = cast_spell_no_targets(state, 1, draw_zero, mana)

  // Both players pass — spell resolves
  let state = pass(state)

  // Verify no cards were drawn (library still has the card)
  let p1 = get_player(state, 1)
  assert list.length(p1.library) == 1
  assert p1.hand == []
}

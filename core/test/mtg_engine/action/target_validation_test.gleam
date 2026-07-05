import gleam/list
import gleam/option.{None}
import gleam/result
import mtg_engine/ability
import mtg_engine/action
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/effects
import mtg_engine/error
import mtg_engine/mana
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import test_helpers.{
  add_card_to_hand, add_creature_to_battlefield, add_creature_with_keywords,
  create_test_creature, pass_until,
}

// Helper to create a red instant that destroys target creature
fn make_red_removal_spell(id: String, name: String) -> card.Card {
  card.Card(
    id: id,
    name: name,
    supertypes: [],
    subtypes: [],
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
}

fn cast_and_target(
  state: state.State,
  caster_id: Int,
  spell: card.Card,
  target_card_id: String,
) -> Result(state.State, error.Error) {
  // Add spell to caster's hand so it can be cast
  let state = add_card_to_hand(state, caster_id, spell)

  // First produce mana for the spell
  // The mana pool depends on the spell's mana cost
  let mana_pool =
    mana.Produced(
      white: spell.mana_cost.white,
      blue: spell.mana_cost.blue,
      black: spell.mana_cost.black,
      red: spell.mana_cost.red,
      green: spell.mana_cost.green,
      colorless: spell.mana_cost.generic + spell.mana_cost.colorless,
    )
  use state <- result.try(action.dispatch(
    state,
    action.ProduceMana(caster_id, mana_pool),
  ))

  // Cast the spell
  let cast_action = case spell.card_type {
    card_type.Instant -> action.CastInstant(caster_id, spell.id, 0)
    card_type.Sorcery -> action.CastSorcery(caster_id, spell.id, 0)
    _ -> action.CastCreature(caster_id, spell.id, 0)
  }
  use state <- result.try(action.dispatch(state, cast_action))

  // Choose targets
  let chosen_targets = [
    targeting.ChosenTargets(targets: [targeting.TargetCard(target_card_id)]),
  ]
  action.dispatch(
    state,
    action.ChooseTargets(caster_id, spell.id, chosen_targets, None, []),
  )
}

// ── Tests ───────────────────────────────────────────────────────────

// Test: can target a normal creature (no hexproof/shroud/protection)
pub fn target_normal_creature_succeeds_test() {
  let state = state.new()
  let creature = create_test_creature("target1", "Target Bear")

  // Add creature to opponent's (player 2) battlefield
  let state = add_creature_to_battlefield(state, 2, creature, 0)

  // Pass to PreCombatMain so instants can be cast
  let state = pass_until(state, step.PreCombatMain)

  // Player 1 casts a red removal spell targeting the creature
  let spell = make_red_removal_spell("bolt1", "Test Bolt")
  let assert Ok(result_state) = cast_and_target(state, 1, spell, "target1")

  // Verify spell is on stack with chosen targets
  assert list.length(result_state.stack) == 1
  let assert Ok(stack_item) = list.first(result_state.stack)
  assert stack_item.card.id == "bolt1"
}

// Test: cannot target an opponent's creature with hexproof
pub fn target_opponent_hexproof_fails_test() {
  let state = state.new()
  let creature = create_test_creature("target1", "Hexproof Bear")

  // Add creature with hexproof to opponent's (player 2) battlefield
  let state = add_creature_with_keywords(state, 2, creature, 0, ["Hexproof"])

  // Pass to PreCombatMain so instants can be cast
  let state = pass_until(state, step.PreCombatMain)

  // Player 1 tries to cast a red removal spell targeting the hexproof creature
  let spell = make_red_removal_spell("bolt1", "Test Bolt")
  let result = cast_and_target(state, 1, spell, "target1")

  // Should fail because the creature has hexproof and is controlled by opponent
  assert result
    == Error(error.InvalidAction(
      "Can't target opponent's permanent with hexproof",
    ))
}

// Test: can target own creature with hexproof
pub fn target_own_hexproof_succeeds_test() {
  let state = state.new()
  let creature = create_test_creature("target1", "My Hexproof Bear")

  // Add creature with hexproof to player 1's battlefield
  let state = add_creature_with_keywords(state, 1, creature, 0, ["Hexproof"])

  // Pass to PreCombatMain so instants can be cast
  let state = pass_until(state, step.PreCombatMain)

  // Player 1 casts a red removal spell targeting their own hexproof creature
  let spell = make_red_removal_spell("bolt1", "Test Bolt")
  let assert Ok(result_state) = cast_and_target(state, 1, spell, "target1")

  // Should succeed because the controller owns the creature
  assert list.length(result_state.stack) == 1
  let assert Ok(stack_item) = list.first(result_state.stack)
  assert stack_item.card.id == "bolt1"
}

// Test: cannot target a creature with shroud
pub fn target_shroud_fails_test() {
  let state = state.new()
  let creature = create_test_creature("target1", "Shroud Bear")

  // Add creature with shroud to opponent's (player 2) battlefield
  let state = add_creature_with_keywords(state, 2, creature, 0, ["Shroud"])

  // Pass to PreCombatMain so instants can be cast
  let state = pass_until(state, step.PreCombatMain)

  // Player 1 tries to cast a red removal spell targeting the shroud creature
  let spell = make_red_removal_spell("bolt1", "Test Bolt")
  let result = cast_and_target(state, 1, spell, "target1")

  // Should fail because the creature has shroud
  assert result
    == Error(error.InvalidAction("Can't target a permanent with shroud"))
}

// Test: cannot target a creature with protection from the source's color
pub fn target_protection_from_color_fails_test() {
  let state = state.new()
  let creature = create_test_creature("target1", "Protection Bear")

  // Add creature with protection from red to opponent's (player 2) battlefield
  let state =
    add_creature_with_keywords(state, 2, creature, 0, ["Protection from Red"])

  // Pass to PreCombatMain so instants can be cast
  let state = pass_until(state, step.PreCombatMain)

  // Player 1 tries to cast a red removal spell targeting the protected creature
  let spell = make_red_removal_spell("bolt1", "Test Bolt")
  let result = cast_and_target(state, 1, spell, "target1")

  // Should fail because the creature has protection from red
  assert result
    == Error(error.InvalidAction("Target has protection from source's colors"))
}

// Test: creature with protection from a different color can still be targeted
pub fn target_protection_from_different_color_succeeds_test() {
  let state = state.new()
  let creature = create_test_creature("target1", "Protection Bear")

  // Add creature with protection from green to opponent's battlefield
  let state =
    add_creature_with_keywords(state, 2, creature, 0, ["Protection from Green"])

  // Pass to PreCombatMain so instants can be cast
  let state = pass_until(state, step.PreCombatMain)

  // Player 1 casts a RED removal spell (different color from green)
  let spell = make_red_removal_spell("bolt1", "Test Bolt")
  let assert Ok(result_state) = cast_and_target(state, 1, spell, "target1")

  // Should succeed because protection is from green, not red
  assert list.length(result_state.stack) == 1
}

// Test: cannot target a creature with protection from the source's card type
pub fn target_protection_from_card_type_fails_test() {
  let state = state.new()
  let creature = create_test_creature("target1", "Protection Bear")

  // Add creature with protection from instants to opponent's battlefield
  let state =
    add_creature_with_keywords(state, 2, creature, 0, [
      "Protection from instants",
    ])

  // Pass to PreCombatMain so instants can be cast
  let state = pass_until(state, step.PreCombatMain)

  // Player 1 casts an instant spell targeting the creature
  let spell = make_red_removal_spell("bolt1", "Test Bolt")
  let result = cast_and_target(state, 1, spell, "target1")

  // Should fail because the creature has protection from instants
  assert result
    == Error(error.InvalidAction(
      "Target has protection from source's card type",
    ))
}

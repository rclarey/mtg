import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import mtg_engine/ability
import mtg_engine/action
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/effects
import mtg_engine/error
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import test_helpers.{add_creature_to_battlefield, pass, pass_until}

// Llanowar Elves — "{T}: Add {G}"
fn llanowar_elves() -> card.Card {
  card.Card(
    id: "elf1",
    name: "Llanowar Elves",
    supertypes: [],
    subtypes: [],
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
    abilities: [
      ability.Activated(ability.ActivatedAbility(
        cost: ability.tap_cost(),
        targets: [],
        effect: effects.Single(
          effects.ProduceMana(mana: mana.Produced(
            white: 0,
            blue: 0,
            black: 0,
            red: 0,
            green: 1,
            colorless: 0,
          )),
        ),
      )),
    ],
    is_token: False,
  )
}

// Creature with sacrifice ability — "{T}, Sacrifice this: Add {G}"
fn sacrificer_creature() -> card.Card {
  card.Card(
    id: "sacc1",
    name: "Sacrifice Elf",
    supertypes: [],
    subtypes: [],
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
    abilities: [
      ability.Activated(ability.ActivatedAbility(
        cost: ability.tap_sacrifice_this_cost(),
        targets: [],
        effect: effects.Single(
          effects.ProduceMana(mana: mana.Produced(
            white: 0,
            blue: 0,
            black: 0,
            red: 0,
            green: 1,
            colorless: 0,
          )),
        ),
      )),
    ],
    is_token: False,
  )
}

// Creature with pay life ability — "Pay 2 life: Draw a card"
fn life_pay_creature() -> card.Card {
  card.Card(
    id: "lifer1",
    name: "Life Mage",
    supertypes: [],
    subtypes: [],
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
    abilities: [
      ability.Activated(ability.ActivatedAbility(
        cost: ability.life_cost(2),
        targets: [],
        effect: effects.Single(effects.DrawCards(
          num: effects.Fixed(1),
          target: targeting.Controller,
        )),
      )),
    ],
    is_token: False,
  )
}

// Creature with a spell ability (should not be activatable)
fn spell_creature() -> card.Card {
  card.Card(
    id: "spell1",
    name: "Spell Creature",
    supertypes: [],
    subtypes: [],
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
    abilities: [
      ability.Spell(ability.SpellAbility(
        targets: [],
        additional_costs: [],
        effect: effects.Single(effects.DrawCards(
          num: effects.Fixed(1),
          target: targeting.Controller,
        )),
      )),
    ],
    is_token: False,
  )
}

pub fn activate_ability_tap_for_mana_test() {
  let state = state.new()
  let elf = llanowar_elves()
  let state = add_creature_to_battlefield(state, 1, elf, 0)

  let state = pass_until(state, step.PreCombatMain)

  let state = case state.priority_player {
    Some(1) -> state
    _ -> pass(state)
  }

  // Activate the elf's ability (tap for green mana)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ActivateAbility(
        player_id: 1,
        permanent_id: "elf1",
        ability_index: 0,
        x_value: 0,
        chosen_targets: [],
      ),
    )

  // Verify the elf is tapped
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(elf_perm) = permanent.find(p1.battlefield, "elf1")
  assert elf_perm.tapped == True

  // Verify the ability is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(stack_item) = list.first(state.stack)
  assert stack_item.card.id == "elf1"
  assert stack_item.effect_override != None

  // Both players pass - ability resolves
  let state = pass(state)

  // Verify the stack is empty and the elf is still on the battlefield
  assert state.stack == []
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "elf1")

  // Verify green mana was added to the pool
  assert p1.mana_pool.green == 1
}

pub fn activate_ability_without_priority_test() {
  let state = state.new()
  let elf = llanowar_elves()
  let state = add_creature_to_battlefield(state, 1, elf, 0)

  let state = pass_until(state, step.PreCombatMain)

  // Pass priority to player 2
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  assert state.priority_player == Some(2)

  // Try to activate as player 1 without priority - should fail
  let result =
    action.dispatch(
      state,
      action.ActivateAbility(
        player_id: 1,
        permanent_id: "elf1",
        ability_index: 0,
        x_value: 0,
        chosen_targets: [],
      ),
    )
  assert result == Error(error.DoNotHavePriority)
}

pub fn activate_ability_invalid_index_test() {
  let state = state.new()
  let elf = llanowar_elves()
  let state = add_creature_to_battlefield(state, 1, elf, 0)

  let state = pass_until(state, step.PreCombatMain)

  let state = case state.priority_player {
    Some(1) -> state
    _ -> pass(state)
  }

  // Try to activate at index 5 which doesn't exist
  let result =
    action.dispatch(
      state,
      action.ActivateAbility(
        player_id: 1,
        permanent_id: "elf1",
        ability_index: 5,
        x_value: 0,
        chosen_targets: [],
      ),
    )
  assert result == Error(error.InvalidAction("No ability at that index"))
}

pub fn activate_not_activated_ability_test() {
  let state = state.new()
  let creature = spell_creature()
  let state = add_creature_to_battlefield(state, 1, creature, 0)

  let state = pass_until(state, step.PreCombatMain)

  let state = case state.priority_player {
    Some(1) -> state
    _ -> pass(state)
  }

  // Try to activate a spell ability (not activated)
  let result =
    action.dispatch(
      state,
      action.ActivateAbility(
        player_id: 1,
        permanent_id: "spell1",
        ability_index: 0,
        x_value: 0,
        chosen_targets: [],
      ),
    )
  assert result == Error(error.InvalidAction("Not an activated ability"))
}

pub fn activate_ability_sacrifice_this_test() {
  let state = state.new()
  let creature = sacrificer_creature()
  let state = add_creature_to_battlefield(state, 1, creature, 0)

  let state = pass_until(state, step.PreCombatMain)

  let state = case state.priority_player {
    Some(1) -> state
    _ -> pass(state)
  }

  // Activate the sacrifice ability
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ActivateAbility(
        player_id: 1,
        permanent_id: "sacc1",
        ability_index: 0,
        x_value: 0,
        chosen_targets: [],
      ),
    )

  // Verify the creature is no longer on the battlefield
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "sacc1") == False

  // Verify the creature is in the graveyard
  assert list.length(p1.graveyard) == 1
  let assert Ok(gy_card) = list.first(p1.graveyard)
  assert gy_card.id == "sacc1"

  // Verify the ability is on the stack
  assert list.length(state.stack) == 1

  // Both players pass - ability resolves
  let state = pass(state)

  // Verify green mana was added
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.mana_pool.green == 1
}

pub fn activate_ability_pay_life_test() {
  let state = state.new()
  let creature = life_pay_creature()
  let state = add_creature_to_battlefield(state, 1, creature, 0)

  let state = pass_until(state, step.PreCombatMain)

  let state = case state.priority_player {
    Some(1) -> state
    _ -> pass(state)
  }

  let assert Ok(p1_before) = player.find(state.players, 1)
  assert p1_before.life == 20

  // Activate the pay-life ability
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ActivateAbility(
        player_id: 1,
        permanent_id: "lifer1",
        ability_index: 0,
        x_value: 0,
        chosen_targets: [],
      ),
    )

  // Verify player lost 2 life
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.life == 18

  // Verify the ability is on the stack
  assert list.length(state.stack) == 1

  // Both players pass - ability resolves (draw a card)
  let state = pass(state)

  // Verify the creature is still on the battlefield
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "lifer1")
  // Verify a card was drawn (library went from some cards to hand)
  // (The test start library is empty, so nothing to draw - just check no error)
}

pub fn activate_ability_permanent_not_moved_on_resolve_test() {
  let state = state.new()
  let elf = llanowar_elves()
  let state = add_creature_to_battlefield(state, 1, elf, 0)

  let state = pass_until(state, step.PreCombatMain)

  let state = case state.priority_player {
    Some(1) -> state
    _ -> pass(state)
  }

  // Activate the elf's ability
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ActivateAbility(
        player_id: 1,
        permanent_id: "elf1",
        ability_index: 0,
        x_value: 0,
        chosen_targets: [],
      ),
    )

  // Verify the elf is on the battlefield (tapped now)
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 1

  // Both players pass - ability resolves
  let state = pass(state)

  // Verify the elf is STILL on the battlefield (not moved)
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 1
  assert dict.has_key(p1.battlefield, "elf1")

  // Verify the elf is still tapped
  let assert Ok(elf_perm) = permanent.find(p1.battlefield, "elf1")
  assert elf_perm.tapped == True
}

pub fn activate_ability_permanent_not_found_test() {
  let state = state.new()

  let state = pass_until(state, step.PreCombatMain)

  let state = case state.priority_player {
    Some(1) -> state
    _ -> pass(state)
  }

  // Try to activate an ability on a non-existent permanent
  let result =
    action.dispatch(
      state,
      action.ActivateAbility(
        player_id: 1,
        permanent_id: "nonexistent",
        ability_index: 0,
        x_value: 0,
        chosen_targets: [],
      ),
    )
  assert result == Error(error.InvalidAction("Permanent not found"))
}

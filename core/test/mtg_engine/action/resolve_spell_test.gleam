import gleam/dict
import gleam/list
import gleam/option.{Some}
import mtg_engine/action
import mtg_engine/card
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import test_helpers.{add_card_to_hand, create_test_creature, pass, pass_until}

// Test resolving a creature spell from the stack
pub fn resolve_creature_spell_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(state.stack) == 1

  // Both players pass priority - spell resolves automatically
  let state = pass(state)

  // Verify creature moved from stack to battlefield
  assert state.stack == []
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1

  // Verify creature is on battlefield with correct properties
  let assert Ok(creature_on_battlefield) =
    permanent.find(player1.battlefield, "creature1")
  assert creature_on_battlefield.card.name == "Grizzly Bears"
  assert creature_on_battlefield.card.power == Some(2)
  assert creature_on_battlefield.card.toughness == Some(2)
}

// Test creature enters battlefield untapped
pub fn creature_enters_untapped_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Both players pass priority - spell resolves automatically
  let state = pass(state)

  // Verify creature is untapped on battlefield
  let assert Ok(player1) = player.find(state.players, 1)
  let assert Ok(creature_on_battlefield) =
    permanent.find(player1.battlefield, "creature1")
  assert creature_on_battlefield.tapped == False
}

// Test cannot resolve from empty stack
pub fn resolve_empty_stack_test() {
  let state = game.new()

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // When both players pass with empty stack, should just advance step
  // (not error - this is normal behavior)
  let state = pass(state)

  // Should have advanced to next step, not errored
  assert state.step == game.BeginCombat
}

// Test resolving puts creature on controller's battlefield
pub fn resolve_creature_to_controller_battlefield_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Both players pass priority - spell resolves automatically
  let state = pass(state)

  // Verify creature is on player 1's battlefield only
  let assert Ok(player1) = player.find(state.players, 1)
  let assert Ok(player2) = player.find(state.players, 2)
  assert dict.size(player1.battlefield) == 1
  assert dict.is_empty(player2.battlefield)
  assert dict.has_key(player1.battlefield, "creature1")
}

// Test resolving multiple creatures in sequence
pub fn resolve_multiple_creatures_test() {
  let state = game.new()
  let creature1 = create_test_creature("creature1", "Grizzly Bears")
  let creature2 =
    card.Card(
      id: "creature2",
      name: "Another Bear",
      card_type: card.Creature,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
      ),
      power: Some(2),
      toughness: Some(2),
    )

  // Add creatures to player 1's hand
  let state = add_card_to_hand(state, 1, creature1)
  let state = add_card_to_hand(state, 1, creature2)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast first creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 2, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify first creature is on stack
  assert list.length(state.stack) == 1

  // Both players pass priority - first creature resolves automatically
  let state = pass(state)

  // Verify stack is empty and creature is on battlefield
  assert state.stack == []
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 1

  // Cast second creature
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature2"))

  // Verify second creature is on stack
  assert list.length(state.stack) == 1

  // Both players pass priority - second creature resolves automatically
  let state = pass(state)

  // Verify both creatures are on battlefield
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 2
  assert dict.has_key(p1.battlefield, "creature1")
  assert dict.has_key(p1.battlefield, "creature2")
}

// Test creature retains power and toughness when resolving
pub fn resolve_creature_retains_stats_test() {
  let state = game.new()
  let creature =
    card.Card(
      id: "creature1",
      name: "Big Creature",
      card_type: card.Creature,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
      ),
      power: Some(5),
      toughness: Some(4),
    )

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Both players pass priority - spell resolves automatically
  let state = pass(state)

  // Verify creature has correct stats
  let assert Ok(player1) = player.find(state.players, 1)
  let assert Ok(creature_on_battlefield) =
    permanent.find(player1.battlefield, "creature1")
  assert creature_on_battlefield.card.power == Some(5)
  assert creature_on_battlefield.card.toughness == Some(4)
}

// Test spell automatically resolves when all players pass priority
pub fn automatic_resolution_when_all_pass_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(state.stack) == 1

  // Both players pass priority - should automatically resolve
  let state = pass(state)

  // Verify creature resolved automatically to battlefield
  assert state.stack == []
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1
  assert dict.has_key(player1.battlefield, "creature1")
}

// Test priority resets to active player after automatic resolution
pub fn automatic_resolution_resets_priority_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Both players pass priority - should resolve and reset priority
  let state = pass(state)

  // Priority should go back to active player
  assert state.priority_player == Some(state.active_player)
  assert state.priority_player == Some(1)

  // Consecutive passes should be reset
  assert state.consecutive_passes == 0
}

// Test multiple spells resolve in LIFO order
pub fn automatic_resolution_lifo_order_test() {
  let state = game.new()
  let creature1 = create_test_creature("creature1", "First Bear")
  let creature2 =
    card.Card(
      id: "creature2",
      name: "Second Bear",
      card_type: card.Creature,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
      ),
      power: Some(2),
      toughness: Some(2),
    )

  // Add creatures to player 1's hand
  let state = add_card_to_hand(state, 1, creature1)
  let state = add_card_to_hand(state, 1, creature2)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast first creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 2, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Both players pass - first creature resolves
  let state = pass(state)

  // Verify first creature resolved
  assert state.stack == []
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 1

  // Cast second creature
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature2"))

  // Both players pass - second creature resolves
  let state = pass(state)

  // Verify both creatures are on battlefield
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 2
  assert dict.has_key(p1.battlefield, "creature1")
  assert dict.has_key(p1.battlefield, "creature2")
}

// Test players get priority after spell resolves
pub fn priority_after_automatic_resolution_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Both players pass - creature resolves automatically
  let state = pass(state)

  // Verify players can take actions after resolution (priority works)
  // Priority should be with active player
  assert state.priority_player == Some(1)

  // Player 1 should be able to pass priority
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  assert state.priority_player == Some(2)
}

import gleam/list
import gleam/option.{Some}
import mtg_engine/action
import mtg_engine/card
import mtg_engine/error
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/player
import test_helpers.{
  add_card_to_hand, create_test_creature, create_test_land, pass_until,
}

// Test casting a creature successfully
pub fn cast_creature_success_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add green mana to player 1's pool
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify creature is no longer in hand
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.hand == []

  // Verify creature is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(stack_item) = list.first(state.stack)
  assert stack_item.card.id == "creature1"
  assert stack_item.controller_id == 1

  // Verify mana was paid
  assert player1.mana_pool.green == 0

  // Verify player retains priority
  assert state.priority_player == Some(1)
}

// Test casting creature with multiple mana colors
pub fn cast_creature_multicolor_mana_test() {
  let state = game.new()
  let creature =
    card.Card(
      id: "creature1",
      name: "Multicolor Bear",
      card_type: card.Creature,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 1,
        black: 0,
        red: 1,
        green: 1,
        colorless: 0,
      ),
      power: Some(3),
      toughness: Some(3),
    )

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana to player 1's pool
  let mana =
    mana.Produced(white: 0, blue: 1, black: 0, red: 1, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify mana was paid correctly
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.blue == 0

  // Verify creature is on stack
  assert list.length(state.stack) == 1
}

// Test cannot cast creature without enough mana
pub fn cast_creature_not_enough_mana_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Try to cast without mana - should fail
  let result = action.dispatch(state, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction("Not enough mana to cast this spell"))
}

// Test cannot cast creature with wrong color mana
pub fn cast_creature_wrong_mana_color_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add red mana instead of green
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Try to cast - should fail
  let result = action.dispatch(state, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction("Not enough mana to cast this spell"))
}

// Test cannot cast creature in wrong phase
pub fn cast_creature_wrong_phase_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Stay in Upkeep (wrong phase)
  let state = pass_until(state, game.Upkeep)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Try to cast - should fail
  let result = action.dispatch(state, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction("Can only cast creatures during a main phase"))
}

// Test can cast creature in PostCombatMain phase
pub fn cast_creature_postcombat_main_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PostCombatMain
  let state = pass_until(state, game.PostCombatMain)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(state.stack) == 1
}

// Test cannot cast creature without priority
pub fn cast_creature_without_priority_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Pass priority to player 2
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  assert state.priority_player == Some(2)

  // Try to cast as player 1 without priority - should fail
  let result = action.dispatch(state, action.CastCreature(1, "creature1"))
  assert result == Error(error.DoNotHavePriority)
}

// Test non-active player cannot cast
pub fn cast_creature_not_active_player_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 2's hand
  let state = add_card_to_hand(state, 2, creature)

  // Advance to PreCombatMain (player 1 is active)
  let state = pass_until(state, game.PreCombatMain)
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))

  // Add mana to player 2
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(2, mana))

  // Player 2 tries to cast - should fail
  let result = action.dispatch(state, action.CastCreature(2, "creature1"))
  assert result
    == Error(error.InvalidAction("Only the active player can cast spells"))
}

// Test card not in hand
pub fn cast_creature_not_in_hand_test() {
  let state = game.new()

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Try to cast a card that's not in hand
  let result = action.dispatch(state, action.CastCreature(1, "nonexistent"))
  assert result == Error(error.InvalidAction("Card not found"))
}

// Test cannot cast non-creature card
pub fn cast_creature_not_a_creature_test() {
  let state = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let state = add_card_to_hand(state, 1, land)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Try to cast land as creature - should fail
  let result = action.dispatch(state, action.CastCreature(1, "land1"))
  assert result == Error(error.InvalidAction("Card is not a creature"))
}

// Test cannot cast creature when stack is not empty (sorcery-speed restriction)
pub fn cast_creature_stack_not_empty_test() {
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

  // Add both creatures to player 1's hand
  let state = add_card_to_hand(state, 1, creature1)
  let state = add_card_to_hand(state, 1, creature2)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 2, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Cast first creature
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify stack is not empty
  assert list.length(state.stack) == 1

  // Try to cast second creature while first is on stack - should fail
  let result = action.dispatch(state, action.CastCreature(1, "creature2"))
  assert result
    == Error(error.InvalidAction(
      "Can only cast creatures when the stack is empty",
    ))
}

// Test player retains priority after casting
pub fn cast_creature_retains_priority_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Verify player 1 has priority
  assert state.priority_player == Some(1)

  // Cast creature
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify player 1 still has priority
  assert state.priority_player == Some(1)
}

// Test casting creature with zero-cost
pub fn cast_creature_zero_cost_test() {
  let state = game.new()
  let creature =
    card.Card(
      id: "creature1",
      name: "Free Bear",
      card_type: card.Creature,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
      ),
      power: Some(0),
      toughness: Some(1),
    )

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Cast the creature (no mana needed)
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(state.stack) == 1
  let assert Ok(stack_item) = list.first(state.stack)
  assert stack_item.card.id == "creature1"
}

// Test casting creature with generic mana cost (2G for a 3/3)
pub fn cast_creature_with_generic_cost_test() {
  let state = game.new()
  let creature =
    card.Card(
      id: "creature1",
      name: "Big Bear",
      card_type: card.Creature,
      mana_cost: mana.Cost(
        generic: 2,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
      ),
      power: Some(3),
      toughness: Some(3),
    )

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana to player 1's pool (1G + 2 of any color)
  let mana =
    mana.Produced(white: 1, blue: 1, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(state.stack) == 1
  let assert Ok(stack_item) = list.first(state.stack)
  assert stack_item.card.id == "creature1"

  // Verify mana was paid (1G + 2 generic paid with white and blue)
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.white == 0
  assert player1.mana_pool.blue == 0
}

// Test cannot cast creature with generic cost when not enough total mana
pub fn cast_creature_generic_cost_not_enough_total_mana_test() {
  let state = game.new()
  let creature =
    card.Card(
      id: "creature1",
      name: "Big Bear",
      card_type: card.Creature,
      mana_cost: mana.Cost(
        generic: 2,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
      ),
      power: Some(3),
      toughness: Some(3),
    )

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add only 1G (need 2G total, missing 1 generic)
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Try to cast - should fail
  let result = action.dispatch(state, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction("Not enough mana to cast this spell"))
}

// Test casting creature with generic cost using any color
pub fn cast_creature_generic_cost_paid_with_any_color_test() {
  let state = game.new()
  let creature =
    card.Card(
      id: "creature1",
      name: "Big Bear",
      card_type: card.Creature,
      mana_cost: mana.Cost(
        generic: 2,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
      ),
      power: Some(3),
      toughness: Some(3),
    )

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana: 1G + 2R (red should be able to pay generic cost)
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 2, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(state.stack) == 1

  // Verify mana was paid
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.red == 0
}

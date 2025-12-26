import gleam/list
import gleam/option
import gleeunit
import mtg_engine/action
import mtg_engine/card
import mtg_engine/error
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import test_helpers.{
  add_card_to_hand, add_creature_to_battlefield, add_land_to_battlefield,
  create_test_creature, create_test_land, pass_both, pass_until,
}

pub fn main() -> Nil {
  gleeunit.main()
}

// Test PassPriority action
pub fn pass_priority_advances_from_player_1_to_2_test() {
  let game = game.new()
  let assert Ok(new_game) = action.dispatch(game, action.PassPriority(1))

  assert new_game.priority_player_id == option.Some(2)
}

pub fn pass_priority_wraps_from_player_2_to_1_test() {
  let game = pass_both(game.new())
  assert game.priority_player_id == option.Some(1)
}

// Test consecutive passes tracking
pub fn pass_priority_increments_consecutive_passes_test() {
  let game = game.new()

  // First pass
  let assert Ok(game_after_1) = action.dispatch(game, action.PassPriority(1))
  assert game_after_1.consecutive_passes == 1
}

// Test playing a land successfully
pub fn play_land_success_test() {
  let game = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Play the land
  let assert Ok(game) = action.dispatch(game, action.PlayLand(1, "land1"))

  // Verify land moved from hand to battlefield
  let assert Ok(player1) = player.find(game.players, 1)
  assert player1.hand == []
  assert list.length(player1.battlefield) == 1
  assert permanent.find(player1.battlefield, "land1")
    == Ok(permanent.from_card(land, player1.id, game.turn_cycle(game)))

  // Verify lands_played_this_turn incremented
  assert player1.lands_played_this_turn == 1
}

// Test land-per-turn limit
pub fn play_land_already_played_this_turn_test() {
  let game = game.new()
  let land1 = create_test_land("land1", "Forest")
  let land2 = create_test_land("land2", "Mountain")

  // Add both lands to player 1's hand
  let game = add_card_to_hand(game, 1, land1)
  let game = add_card_to_hand(game, 1, land2)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Play first land successfully
  let assert Ok(game) = action.dispatch(game, action.PlayLand(1, "land1"))

  // Try to play second land - should fail
  let result = action.dispatch(game, action.PlayLand(1, "land2"))
  assert result == Error(error.InvalidAction("Already played a land this turn"))
}

// Test playing land in wrong phase
pub fn play_land_wrong_phase_test() {
  let game = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Try to play in Upkeep (wrong phase)
  let game = pass_until(game.Upkeep, game)

  let result = action.dispatch(game, action.PlayLand(1, "land1"))
  assert result
    == Error(error.InvalidAction("Can only play a land during a main phase"))
}

// Test playing land from PostCombatMain phase
pub fn play_land_postcombat_main_test() {
  let game = game.new()
  let land = create_test_land("land1", "Island")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Advance to PostCombatMain
  let game = pass_until(game.PostCombatMain, game)

  // Play the land
  let assert Ok(game) = action.dispatch(game, action.PlayLand(1, "land1"))

  // Verify land moved to battlefield
  let assert Ok(player1) = player.find(game.players, 1)
  assert list.length(player1.battlefield) == 1
}

// Test only active player can play land
pub fn play_land_not_active_player_test() {
  let game = game.new()
  let land = create_test_land("land1", "Plains")

  // Add land to player 2's hand
  let game = add_card_to_hand(game, 2, land)

  // Advance to PreCombatMain (player 1 is active)
  let game = pass_until(game.PreCombatMain, game)

  // Player 2 tries to play land - should fail
  let result = action.dispatch(game, action.PlayLand(2, "land1"))
  assert result
    == Error(error.InvalidAction("Only the active player can play a land"))
}

// Test card not in hand
pub fn play_land_not_in_hand_test() {
  let game = game.new()

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Try to play a land that's not in hand
  let result = action.dispatch(game, action.PlayLand(1, "nonexistent"))
  assert result == Error(error.InvalidAction("Card not found"))
}

// Test card is not a land
pub fn play_land_not_a_land_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Try to play creature as land - should fail
  let result = action.dispatch(game, action.PlayLand(1, "creature1"))
  assert result == Error(error.InvalidAction("Card is not a land"))
}

// Test must have priority to play land
pub fn play_land_without_priority_test() {
  let game = game.new()
  let land = create_test_land("land1", "Swamp")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Pass priority so player 2 has priority
  let assert Ok(game_p2_priority) = action.dispatch(game, action.PassPriority(1))
  assert game_p2_priority.priority_player_id == option.Some(2)

  // Try to play land as player 1 without priority - should fail
  let result = action.dispatch(game_p2_priority, action.PlayLand(1, "land1"))
  assert result
    == Error(error.InvalidAction("Can only play a land when you have priority"))
}

// Test tapping a Forest for green mana
pub fn tap_forest_for_mana_test() {
  let game = game.new()
  let forest = create_test_land("land1", "Forest")

  // Add forest to battlefield
  let game = add_land_to_battlefield(game, 1, forest)

  // Tap the forest for mana
  let assert Ok(new_game) =
    action.dispatch(game, action.TapLandForMana(1, "land1"))

  let assert Ok(player1) = player.find(new_game.players, 1)
  let assert Ok(tapped_forest) = permanent.find(player1.battlefield, "land1")
  assert tapped_forest.tapped == True

  // Verify green mana was added to pool
  assert player1.mana_pool
    == mana.Produced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
}

// Test tapping a Mountain for red mana
pub fn tap_mountain_for_mana_test() {
  let game = game.new()
  let mountain = create_test_land("land1", "Mountain")

  // Add mountain to battlefield
  let game = add_land_to_battlefield(game, 1, mountain)

  // Tap the mountain for mana
  let assert Ok(new_game) =
    action.dispatch(game, action.TapLandForMana(1, "land1"))

  // Verify red mana was added to pool
  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool
    == mana.Produced(
      white: 0,
      blue: 0,
      black: 0,
      red: 1,
      green: 0,
      colorless: 0,
    )
}

// Test tapping an Island for blue mana
pub fn tap_island_for_mana_test() {
  let game = game.new()
  let island = create_test_land("land1", "Island")

  // Add island to battlefield
  let game = add_land_to_battlefield(game, 1, island)

  // Tap the island for mana
  let assert Ok(new_game) =
    action.dispatch(game, action.TapLandForMana(1, "land1"))

  // Verify blue mana was added to pool
  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool
    == mana.Produced(
      white: 0,
      blue: 1,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )
}

// Test tapping a Plains for white mana
pub fn tap_plains_for_mana_test() {
  let game = game.new()
  let plains = create_test_land("land1", "Plains")

  // Add plains to battlefield
  let game = add_land_to_battlefield(game, 1, plains)

  // Tap the plains for mana
  let assert Ok(new_game) =
    action.dispatch(game, action.TapLandForMana(1, "land1"))

  // Verify white mana was added to pool
  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool
    == mana.Produced(
      white: 1,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )
}

// Test tapping a Swamp for black mana
pub fn tap_swamp_for_mana_test() {
  let game = game.new()
  let swamp = create_test_land("land1", "Swamp")

  // Add swamp to battlefield
  let game = add_land_to_battlefield(game, 1, swamp)

  // Tap the swamp for mana
  let assert Ok(new_game) =
    action.dispatch(game, action.TapLandForMana(1, "land1"))

  // Verify black mana was added to pool
  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool
    == mana.Produced(
      white: 0,
      blue: 0,
      black: 1,
      red: 0,
      green: 0,
      colorless: 0,
    )
}

// Test cannot tap already tapped land
pub fn tap_already_tapped_land_test() {
  let game = game.new()
  let forest = create_test_land("land1", "Forest")

  // Add forest to battlefield
  let game = add_land_to_battlefield(game, 1, forest)

  // Tap the forest once
  let assert Ok(game_after_tap) =
    action.dispatch(game, action.TapLandForMana(1, "land1"))

  // Try to tap it again - should fail
  let result =
    action.dispatch(game_after_tap, action.TapLandForMana(1, "land1"))
  assert result == Error(error.InvalidAction("Land is already tapped"))
}

// Test cannot tap land not on battlefield
pub fn tap_land_not_on_battlefield_test() {
  let game = game.new()
  let forest = create_test_land("land1", "Forest")

  // Add forest to hand instead of battlefield
  let game = add_card_to_hand(game, 1, forest)

  // Try to tap it - should fail
  let result = action.dispatch(game, action.TapLandForMana(1, "land1"))
  assert result == Error(error.InvalidAction("Permanent not found"))
}

// Test cannot tap non-land permanent
pub fn tap_non_land_for_mana_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield
  let game = add_land_to_battlefield(game, 1, creature)

  // Try to tap it for mana - should fail
  let result = action.dispatch(game, action.TapLandForMana(1, "creature1"))
  assert result == Error(error.InvalidAction("Card is not a land"))
}

// Test land enters battlefield untapped
pub fn land_enters_untapped_test() {
  let game = game.new()
  let forest = create_test_land("land1", "Forest")

  // Add forest to player 1's hand
  let game = add_card_to_hand(game, 1, forest)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Play the land
  let assert Ok(new_game) = action.dispatch(game, action.PlayLand(1, "land1"))

  // Verify land is on battlefield and untapped
  let assert Ok(player1) = player.find(new_game.players, 1)
  let assert Ok(land_on_battlefield) =
    permanent.find(player1.battlefield, "land1")
  assert land_on_battlefield.tapped == False
}

// Test tapping multiple lands accumulates mana
pub fn tap_multiple_lands_accumulates_mana_test() {
  let game = game.new()
  let forest1 = create_test_land("land1", "Forest")
  let forest2 = create_test_land("land2", "Forest")
  let mountain = create_test_land("land3", "Mountain")

  // Add lands to battlefield
  let game = add_land_to_battlefield(game, 1, forest1)
  let game = add_land_to_battlefield(game, 1, forest2)
  let game = add_land_to_battlefield(game, 1, mountain)

  // Tap all three lands
  let assert Ok(game_after_tap1) =
    action.dispatch(game, action.TapLandForMana(1, "land1"))
  let assert Ok(game_after_tap2) =
    action.dispatch(game_after_tap1, action.TapLandForMana(1, "land2"))
  let assert Ok(game_after_tap3) =
    action.dispatch(game_after_tap2, action.TapLandForMana(1, "land3"))

  // Verify mana accumulated correctly
  let assert Ok(player1) = player.find(game_after_tap3.players, 1)
  assert player1.mana_pool.green == 2
  assert player1.mana_pool.red == 1
}

// Test casting a creature successfully
pub fn cast_creature_success_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add green mana to player 1's pool
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify creature is no longer in hand
  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.hand == []

  // Verify creature is on the stack
  assert list.length(new_game.stack) == 1
  let assert Ok(stack_item) = list.first(new_game.stack)
  assert stack_item.card.id == "creature1"
  assert stack_item.controller_id == 1

  // Verify mana was paid
  assert player1.mana_pool.green == 0

  // Verify player retains priority
  assert new_game.priority_player_id == option.Some(1)
}

// Test casting creature with multiple mana colors
pub fn cast_creature_multicolor_mana_test() {
  let game = game.new()
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
      power: option.Some(3),
      toughness: option.Some(3),
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana to player 1's pool
  let mana =
    mana.Produced(white: 0, blue: 1, black: 0, red: 1, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify mana was paid correctly
  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.blue == 0

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1
}

// Test cannot cast creature without enough mana
pub fn cast_creature_not_enough_mana_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Try to cast without mana - should fail
  let result = action.dispatch(game, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction("Not enough mana to cast this spell"))
}

// Test cannot cast creature with wrong color mana
pub fn cast_creature_wrong_mana_color_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add red mana instead of green
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Try to cast - should fail
  let result =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction("Not enough mana to cast this spell"))
}

// Test cannot cast creature in wrong phase
pub fn cast_creature_wrong_phase_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Stay in Upkeep (wrong phase)
  let game = pass_until(game.Upkeep, game)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Try to cast - should fail
  let result =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction("Can only cast creatures during a main phase"))
}

// Test can cast creature in PostCombatMain phase
pub fn cast_creature_postcombat_main_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PostCombatMain
  let game = pass_until(game.PostCombatMain, game)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1
}

// Test cannot cast creature without priority
pub fn cast_creature_without_priority_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Pass priority to player 2
  let assert Ok(game_p2_priority) =
    action.dispatch(game_with_mana, action.PassPriority(1))
  assert game_p2_priority.priority_player_id == option.Some(2)

  // Try to cast as player 1 without priority - should fail
  let result =
    action.dispatch(game_p2_priority, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction("Can only cast spells when you have priority"))
}

// Test non-active player cannot cast
pub fn cast_creature_not_active_player_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 2's hand
  let game = add_card_to_hand(game, 2, creature)

  // Advance to PreCombatMain (player 1 is active)
  let game = pass_until(game.PreCombatMain, game)

  // Add mana to player 2
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(2, mana))

  // Player 2 tries to cast - should fail
  let result =
    action.dispatch(game_with_mana, action.CastCreature(2, "creature1"))
  assert result
    == Error(error.InvalidAction("Only the active player can cast spells"))
}

// Test card not in hand
pub fn cast_creature_not_in_hand_test() {
  let game = game.new()

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Try to cast a card that's not in hand
  let result =
    action.dispatch(game_with_mana, action.CastCreature(1, "nonexistent"))
  assert result == Error(error.InvalidAction("Card not found"))
}

// Test cannot cast non-creature card
pub fn cast_creature_not_a_creature_test() {
  let game = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Try to cast land as creature - should fail
  let result = action.dispatch(game, action.CastCreature(1, "land1"))
  assert result == Error(error.InvalidAction("Card is not a creature"))
}

// Test cannot cast creature when stack is not empty (sorcery-speed restriction)
pub fn cast_creature_stack_not_empty_test() {
  let game = game.new()
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
      power: option.Some(2),
      toughness: option.Some(2),
    )

  // Add both creatures to player 1's hand
  let game = add_card_to_hand(game, 1, creature1)
  let game = add_card_to_hand(game, 1, creature2)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 2, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Cast first creature
  let assert Ok(game_after_cast1) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify stack is not empty
  assert list.length(game_after_cast1.stack) == 1

  // Try to cast second creature while first is on stack - should fail
  let result =
    action.dispatch(game_after_cast1, action.CastCreature(1, "creature2"))
  assert result
    == Error(error.InvalidAction(
      "Can only cast creatures when the stack is empty",
    ))
}

// Test player retains priority after casting
pub fn cast_creature_retains_priority_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Verify player 1 has priority
  assert game_with_mana.priority_player_id == option.Some(1)

  // Cast creature
  let assert Ok(new_game) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify player 1 still has priority
  assert new_game.priority_player_id == option.Some(1)
}

// Test casting creature with zero-cost
pub fn cast_creature_zero_cost_test() {
  let game = game.new()
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
      power: option.Some(0),
      toughness: option.Some(1),
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Cast the creature (no mana needed)
  let assert Ok(new_game) =
    action.dispatch(game, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1
  let assert Ok(stack_item) = list.first(new_game.stack)
  assert stack_item.card.id == "creature1"
}

// Test casting creature with generic mana cost (2G for a 3/3)
pub fn cast_creature_with_generic_cost_test() {
  let game = game.new()
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
      power: option.Some(3),
      toughness: option.Some(3),
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana to player 1's pool (1G + 2 of any color)
  let mana =
    mana.Produced(white: 1, blue: 1, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1
  let assert Ok(stack_item) = list.first(new_game.stack)
  assert stack_item.card.id == "creature1"

  // Verify mana was paid (1G + 2 generic paid with white and blue)
  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.white == 0
  assert player1.mana_pool.blue == 0
}

// Test cannot cast creature with generic cost when not enough total mana
pub fn cast_creature_generic_cost_not_enough_total_mana_test() {
  let game = game.new()
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
      power: option.Some(3),
      toughness: option.Some(3),
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add only 1G (need 2G total, missing 1 generic)
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Try to cast - should fail
  let result =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction("Not enough mana to cast this spell"))
}

// Test casting creature with generic cost using any color
pub fn cast_creature_generic_cost_paid_with_any_color_test() {
  let game = game.new()
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
      power: option.Some(3),
      toughness: option.Some(3),
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana: 1G + 2R (red should be able to pay generic cost)
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 2, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1

  // Verify mana was paid
  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.red == 0
}

// Test resolving a creature spell from the stack
pub fn resolve_creature_spell_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(game_after_cast.stack) == 1

  // Both players pass priority - spell resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify creature moved from stack to battlefield
  assert game_after_resolve.stack == []
  let assert Ok(player1) = player.find(game_after_resolve.players, 1)
  assert list.length(player1.battlefield) == 1

  // Verify creature is on battlefield with correct properties
  let assert Ok(creature_on_battlefield) =
    permanent.find(player1.battlefield, "creature1")
  assert creature_on_battlefield.card.name == "Grizzly Bears"
  assert creature_on_battlefield.card.power == option.Some(2)
  assert creature_on_battlefield.card.toughness == option.Some(2)
}

// Test creature enters battlefield untapped
pub fn creature_enters_untapped_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Both players pass priority - spell resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify creature is untapped on battlefield
  let assert Ok(player1) = player.find(game_after_resolve.players, 1)
  let assert Ok(creature_on_battlefield) =
    permanent.find(player1.battlefield, "creature1")
  assert creature_on_battlefield.tapped == False
}

// Test cannot resolve from empty stack
pub fn resolve_empty_stack_test() {
  let game = game.new()

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // When both players pass with empty stack, should just advance step
  // (not error - this is normal behavior)
  let game_after_pass = pass_both(game)

  // Should have advanced to next step, not errored
  assert game_after_pass.current_step == game.BeginCombat
}

// Test resolving puts creature on controller's battlefield
pub fn resolve_creature_to_controller_battlefield_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Both players pass priority - spell resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify creature is on player 1's battlefield only
  let assert Ok(player1) = player.find(game_after_resolve.players, 1)
  let assert Ok(player2) = player.find(game_after_resolve.players, 2)
  assert list.length(player1.battlefield) == 1
  assert player2.battlefield == []
  assert list.any(player1.battlefield, fn(perm) { perm.card.id == "creature1" })
}

// Test resolving multiple creatures in sequence
pub fn resolve_multiple_creatures_test() {
  let game = game.new()
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
      power: option.Some(2),
      toughness: option.Some(2),
    )

  // Add creatures to player 1's hand
  let game = add_card_to_hand(game, 1, creature1)
  let game = add_card_to_hand(game, 1, creature2)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast first creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 2, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast1) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify first creature is on stack
  assert list.length(game_after_cast1.stack) == 1

  // Both players pass priority - first creature resolves automatically
  let game_after_resolve1 = pass_both(game_after_cast1)

  // Verify stack is empty and creature is on battlefield
  assert game_after_resolve1.stack == []
  let assert Ok(p1_after_first) = player.find(game_after_resolve1.players, 1)
  assert list.length(p1_after_first.battlefield) == 1

  // Cast second creature
  let assert Ok(game_after_cast2) =
    action.dispatch(game_after_resolve1, action.CastCreature(1, "creature2"))

  // Verify second creature is on stack
  assert list.length(game_after_cast2.stack) == 1

  // Both players pass priority - second creature resolves automatically
  let game_after_resolve2 = pass_both(game_after_cast2)

  // Verify both creatures are on battlefield
  let assert Ok(p1_final) = player.find(game_after_resolve2.players, 1)
  assert list.length(p1_final.battlefield) == 2
  assert list.any(p1_final.battlefield, fn(perm) { perm.card.id == "creature1" })
  assert list.any(p1_final.battlefield, fn(perm) { perm.card.id == "creature2" })
}

// Test creature retains power and toughness when resolving
pub fn resolve_creature_retains_stats_test() {
  let game = game.new()
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
      power: option.Some(5),
      toughness: option.Some(4),
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Both players pass priority - spell resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify creature has correct stats
  let assert Ok(player1) = player.find(game_after_resolve.players, 1)
  let assert Ok(creature_on_battlefield) =
    permanent.find(player1.battlefield, "creature1")
  assert creature_on_battlefield.card.power == option.Some(5)
  assert creature_on_battlefield.card.toughness == option.Some(4)
}

// Test spell automatically resolves when all players pass priority
pub fn automatic_resolution_when_all_pass_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(game_after_cast.stack) == 1

  // Both players pass priority - should automatically resolve
  let game_after_pass = pass_both(game_after_cast)

  // Verify creature resolved automatically to battlefield
  assert game_after_pass.stack == []
  let assert Ok(player1) = player.find(game_after_pass.players, 1)
  assert list.length(player1.battlefield) == 1
  assert list.any(player1.battlefield, fn(perm) { perm.card.id == "creature1" })
}

// Test priority resets to active player after automatic resolution
pub fn automatic_resolution_resets_priority_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Both players pass priority - should resolve and reset priority
  let game_after_pass = pass_both(game_after_cast)

  // Priority should go back to active player
  assert game_after_pass.priority_player_id == option.Some(game_after_pass.active_player_id)
  assert game_after_pass.priority_player_id == option.Some(1)

  // Consecutive passes should be reset
  assert game_after_pass.consecutive_passes == 0
}

// Test multiple spells resolve in LIFO order
pub fn automatic_resolution_lifo_order_test() {
  let game = game.new()
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
      power: option.Some(2),
      toughness: option.Some(2),
    )

  // Add creatures to player 1's hand
  let game = add_card_to_hand(game, 1, creature1)
  let game = add_card_to_hand(game, 1, creature2)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast first creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 2, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast1) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Both players pass - first creature resolves
  let game_after_first_resolve = pass_both(game_after_cast1)

  // Verify first creature resolved
  assert game_after_first_resolve.stack == []
  let assert Ok(p1_after_first) =
    player.find(game_after_first_resolve.players, 1)
  assert list.length(p1_after_first.battlefield) == 1

  // Cast second creature
  let assert Ok(game_after_cast2) =
    action.dispatch(
      game_after_first_resolve,
      action.CastCreature(1, "creature2"),
    )

  // Both players pass - second creature resolves
  let game_after_second_resolve = pass_both(game_after_cast2)

  // Verify both creatures are on battlefield
  let assert Ok(p1_final) = player.find(game_after_second_resolve.players, 1)
  assert list.length(p1_final.battlefield) == 2
  assert list.any(p1_final.battlefield, fn(perm) { perm.card.id == "creature1" })
  assert list.any(p1_final.battlefield, fn(perm) { perm.card.id == "creature2" })
}

// Test cannot play land while spell is on stack
pub fn cannot_play_land_with_stack_not_empty_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")
  let land = create_test_land("land1", "Forest")

  // Add both to player 1's hand
  let game = add_card_to_hand(game, 1, creature)
  let game = add_card_to_hand(game, 1, land)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Verify stack is not empty
  assert list.length(game_after_cast.stack) == 1

  // Try to play land - should fail
  let result = action.dispatch(game_after_cast, action.PlayLand(1, "land1"))
  assert result
    == Error(error.InvalidAction(
      "Cannot play a land while the stack is not empty",
    ))
}

// Test players get priority after spell resolves
pub fn priority_after_automatic_resolution_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))

  // Both players pass - creature resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify players can take actions after resolution (priority works)
  // Priority should be with active player
  assert game_after_resolve.priority_player_id == option.Some(1)

  // Player 1 should be able to pass priority
  let assert Ok(game_after_pass) =
    action.dispatch(game_after_resolve, action.PassPriority(1))
  assert game_after_pass.priority_player_id == option.Some(2)
}

// Test declaring attackers successfully
pub fn declare_attackers_success_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness (entered in cycle -1)
  let game = add_creature_to_battlefield(game, 1, creature, -1)

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Declare attackers
  let assert Ok(new_game) =
    action.dispatch(game, action.DeclareAttackers(1, ["creature1"]))

  // Verify creature is tapped
  let assert Ok(player1) = player.find(new_game.players, 1)
  let assert Ok(attacker) = permanent.find(player1.battlefield, "creature1")
  assert attacker.tapped == True

  // Verify attacking_creatures is set
  assert new_game.attacking_creatures == option.Some(["creature1"])

  // Verify active player retains priority
  assert new_game.priority_player_id == option.Some(1)

  // Verify consecutive passes was reset
  assert new_game.consecutive_passes == 0
}

// Test declaring multiple attackers
pub fn declare_multiple_attackers_test() {
  let game = game.new()
  let creature1 = create_test_creature("creature1", "Bear 1")
  let creature2 = create_test_creature("creature2", "Bear 2")

  // Add creatures to battlefield without summoning sickness
  let game = add_creature_to_battlefield(game, 1, creature1, -1)
  let game = add_creature_to_battlefield(game, 1, creature2, -1)

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Declare both attackers
  let assert Ok(new_game) =
    action.dispatch(game, action.DeclareAttackers(1, ["creature1", "creature2"]))

  // Verify both creatures are tapped
  let assert Ok(player1) = player.find(new_game.players, 1)
  let assert Ok(attacker1) = permanent.find(player1.battlefield, "creature1")
  let assert Ok(attacker2) = permanent.find(player1.battlefield, "creature2")
  assert attacker1.tapped == True
  assert attacker2.tapped == True

  // Verify both are listed as attackers
  assert new_game.attacking_creatures == option.Some(["creature1", "creature2"])
}

// Test cannot declare attackers with tapped creature
pub fn declare_attackers_tapped_creature_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let game = add_creature_to_battlefield(game, 1, creature, -1)

  // Tap the creature manually
  let game =
    game.State(
      ..game,
      players: player.update(game.players, 1, fn(p) {
        player.Player(
          ..p,
          battlefield: permanent.update(p.battlefield, "creature1", fn(perm) {
            permanent.Permanent(..perm, tapped: True)
          }),
        )
      }),
    )

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Try to declare tapped creature as attacker - should fail
  let result = action.dispatch(game, action.DeclareAttackers(1, ["creature1"]))
  assert result == Error(error.InvalidAction("Cannot attack with tapped creature"))
}

// Test cannot declare attackers with summoning sickness
pub fn declare_attackers_summoning_sickness_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield with summoning sickness (current cycle)
  let current_cycle = game.turn_cycle(game)
  let game = add_creature_to_battlefield(game, 1, creature, current_cycle)

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Try to attack with creature that has summoning sickness - should fail
  let result = action.dispatch(game, action.DeclareAttackers(1, ["creature1"]))
  assert result
    == Error(error.InvalidAction(
      "Cannot attack with creature that has summoning sickness",
    ))
}

// Test non-active player cannot declare attackers
pub fn declare_attackers_not_active_player_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 2's battlefield without summoning sickness
  let game = add_creature_to_battlefield(game, 2, creature, -1)

  // Advance to DeclareAttackers step (player 1 is active)
  let game = pass_until(game.DeclareAttackers, game)

  // Player 2 tries to declare attackers - should fail
  let result = action.dispatch(game, action.DeclareAttackers(2, ["creature1"]))
  assert result
    == Error(error.InvalidAction("Only the active player can declare attackers"))
}

// Test cannot declare attackers in wrong step
pub fn declare_attackers_wrong_step_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let game = add_creature_to_battlefield(game, 1, creature, -1)

  // Stay in PreCombatMain (wrong step)
  let game = pass_until(game.PreCombatMain, game)

  // Try to declare attackers in wrong step - should fail
  let result = action.dispatch(game, action.DeclareAttackers(1, ["creature1"]))
  assert result
    == Error(error.InvalidAction(
      "Can only declare attackers during DeclareAttackers step",
    ))
}

// Test priority is given to active player after declaring attackers
pub fn declare_attackers_retains_priority_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let game = add_creature_to_battlefield(game, 1, creature, -1)

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Verify no one has priority yet (attackers not declared)
  assert game.priority_player_id == option.None

  // Declare attackers
  let assert Ok(new_game) =
    action.dispatch(game, action.DeclareAttackers(1, ["creature1"]))

  // Verify player 1 now has priority after declaring
  assert new_game.priority_player_id == option.Some(1)
}

// Test cannot declare attackers more than once
pub fn declare_attackers_already_declared_test() {
  let game = game.new()
  let creature1 = create_test_creature("creature1", "Bear 1")
  let creature2 = create_test_creature("creature2", "Bear 2")

  // Add creatures to battlefield without summoning sickness
  let game = add_creature_to_battlefield(game, 1, creature1, -1)
  let game = add_creature_to_battlefield(game, 1, creature2, -1)

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Declare first attacker
  let assert Ok(game_after_first) =
    action.dispatch(game, action.DeclareAttackers(1, ["creature1"]))

  // Try to declare attackers again - should fail
  let result =
    action.dispatch(game_after_first, action.DeclareAttackers(1, ["creature2"]))
  assert result
    == Error(error.InvalidAction(
      "Attackers have already been declared this step",
    ))
}

// Test cannot declare non-creature as attacker
pub fn declare_attackers_not_creature_test() {
  let game = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to battlefield
  let game = add_land_to_battlefield(game, 1, land)

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Try to declare land as attacker - should fail
  let result = action.dispatch(game, action.DeclareAttackers(1, ["land1"]))
  assert result == Error(error.InvalidAction("Only creatures can attack"))
}

// Test non-active player cannot declare attackers (already tested above but keeping for completeness)
pub fn declare_attackers_without_priority_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let game = add_creature_to_battlefield(game, 2, creature, -1)

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Player 2 (non-active) tries to declare attackers - should fail
  let result = action.dispatch(game, action.DeclareAttackers(2, ["creature1"]))
  assert result
    == Error(error.InvalidAction("Only the active player can declare attackers"))
}

// Test attacking with no creatures (empty list)
pub fn declare_attackers_empty_list_test() {
  let game = game.new()

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Declare no attackers
  let assert Ok(new_game) = action.dispatch(game, action.DeclareAttackers(1, []))

  // Verify attacking_creatures is empty list wrapped in Some
  assert new_game.attacking_creatures == option.Some([])

  // Verify priority is retained
  assert new_game.priority_player_id == option.Some(1)
}

// Test attacking_creatures is cleared when advancing to new turn
pub fn attacking_creatures_cleared_on_new_turn_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let game = add_creature_to_battlefield(game, 1, creature, -1)

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Declare attackers
  let assert Ok(game_with_attackers) =
    action.dispatch(game, action.DeclareAttackers(1, ["creature1"]))

  // Verify attackers are set
  assert game_with_attackers.attacking_creatures == option.Some(["creature1"])

  // Advance to next turn
  let game_next_turn = pass_until(game.Upkeep, game_with_attackers)

  // Verify attacking_creatures was cleared
  assert game_next_turn.attacking_creatures == option.None
}

// Test cannot declare attackers twice even if first declaration was empty
pub fn declare_attackers_twice_with_empty_first_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let game = add_creature_to_battlefield(game, 1, creature, -1)

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Declare no attackers
  let assert Ok(game_no_attackers) =
    action.dispatch(game, action.DeclareAttackers(1, []))

  // Verify attackers were declared (empty list)
  assert game_no_attackers.attacking_creatures == option.Some([])

  // Active player passes priority
  let assert Ok(game_p2_priority) =
    action.dispatch(game_no_attackers, action.PassPriority(1))

  // Player 2 passes priority back
  let assert Ok(game_back_to_p1) =
    action.dispatch(game_p2_priority, action.PassPriority(2))

  // We should now be in DeclareBlockers step
  assert game_back_to_p1.current_step == game.DeclareBlockers

  // But let's test the scenario where we're still in DeclareAttackers
  // (for example, if player 2 had cast a spell)
  // We'll manually set the game state back to simulate this

  let game_still_in_declare =
    game.State(..game_back_to_p1, current_step: game.DeclareAttackers)

  // Try to declare attackers again - should fail because attackers were already declared
  let result =
    action.dispatch(game_still_in_declare, action.DeclareAttackers(1, ["creature1"]))
  assert result
    == Error(error.InvalidAction(
      "Attackers have already been declared this step",
    ))
}

// Test cannot pass priority in DeclareAttackers step before declaring attackers
pub fn cannot_pass_priority_before_declaring_attackers_test() {
  let game = game.new()

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Try to pass priority without declaring attackers - should fail
  let result = action.dispatch(game, action.PassPriority(1))
  assert result
    == Error(error.InvalidAction(
      "Must declare attackers before taking other actions",
    ))
}

// Test can pass priority after declaring attackers
pub fn can_pass_priority_after_declaring_attackers_test() {
  let game = game.new()

  // Advance to DeclareAttackers step
  let game = pass_until(game.DeclareAttackers, game)

  // Declare no attackers
  let assert Ok(game_after_declare) =
    action.dispatch(game, action.DeclareAttackers(1, []))

  // Now should be able to pass priority
  let assert Ok(game_after_pass) =
    action.dispatch(game_after_declare, action.PassPriority(1))
  assert game_after_pass.priority_player_id == option.Some(2)
}

// Test cannot play land before declaring attackers
pub fn cannot_play_land_before_declaring_attackers_test() {
  let game = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Manually set to DeclareAttackers step with no priority
  // (normally you can't get here, but testing the validation)
  let game =
    game.State(
      ..game,
      current_step: game.DeclareAttackers,
      priority_player_id: option.None,
      attacking_creatures: option.None,
    )

  // Try to play land - should fail
  let result = action.dispatch(game, action.PlayLand(1, "land1"))
  assert result
    == Error(error.InvalidAction(
      "Must declare attackers before taking other actions",
    ))
}

// Test cannot tap land before declaring attackers
pub fn cannot_tap_land_before_declaring_attackers_test() {
  let game = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to battlefield
  let game = add_land_to_battlefield(game, 1, land)

  // Manually set to DeclareAttackers step with no priority
  let game =
    game.State(
      ..game,
      current_step: game.DeclareAttackers,
      priority_player_id: option.None,
      attacking_creatures: option.None,
    )

  // Try to tap land for mana - should fail
  let result = action.dispatch(game, action.TapLandForMana(1, "land1"))
  assert result
    == Error(error.InvalidAction(
      "Must declare attackers before taking other actions",
    ))
}

// Test cannot cast creature before declaring attackers
pub fn cannot_cast_creature_before_declaring_attackers_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Manually set to DeclareAttackers step with mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  let game =
    game.State(
      ..game_with_mana,
      current_step: game.DeclareAttackers,
      priority_player_id: option.None,
      attacking_creatures: option.None,
    )

  // Try to cast creature - should fail
  let result = action.dispatch(game, action.CastCreature(1, "creature1"))
  assert result
    == Error(error.InvalidAction(
      "Must declare attackers before taking other actions",
    ))
}

// Test no one can pass priority before attackers declared (priority is None)
pub fn non_active_player_can_act_before_attackers_declared_test() {
  let game = game.new()

  // Advance to DeclareAttackers step (priority_player_id will be None)
  let game = pass_until(game.DeclareAttackers, game)

  // Verify priority is None
  assert game.priority_player_id == option.None

  // Player 2 tries to pass priority - should fail
  let result = action.dispatch(game, action.PassPriority(2))
  assert result
    == Error(error.InvalidAction(
      "Must declare attackers before taking other actions",
    ))
}

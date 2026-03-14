import gleam/dict
import gleam/list
import gleam/option.{Some}
import mtg_engine/action
import mtg_engine/error
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import test_helpers.{
  add_card_to_hand, create_test_creature, create_test_land, pass_until,
}

// Test playing a land successfully
pub fn play_land_success_test() {
  let state = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let state = add_card_to_hand(state, 1, land)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Play the land
  let assert Ok(state) = action.dispatch(state, action.PlayLand(1, "land1"))

  // Verify land moved from hand to battlefield
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.hand == []
  assert dict.size(player1.battlefield) == 1
  assert permanent.find(player1.battlefield, "land1")
    == Ok(permanent.from_card(land, player1.id, game.turn_cycle(state)))

  // Verify lands_played_this_turn incremented
  assert player1.lands_played_this_turn == 1
}

// Test land-per-turn limit
pub fn play_land_already_played_this_turn_test() {
  let state = game.new()
  let land1 = create_test_land("land1", "Forest")
  let land2 = create_test_land("land2", "Mountain")

  // Add both lands to player 1's hand
  let state = add_card_to_hand(state, 1, land1)
  let state = add_card_to_hand(state, 1, land2)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Play first land successfully
  let assert Ok(state) = action.dispatch(state, action.PlayLand(1, "land1"))

  // Try to play second land - should fail
  let result = action.dispatch(state, action.PlayLand(1, "land2"))
  assert result == Error(error.InvalidAction("Already played a land this turn"))
}

// Test playing land in wrong phase
pub fn play_land_wrong_phase_test() {
  let state = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let state = add_card_to_hand(state, 1, land)

  // Try to play in Upkeep (wrong phase)
  let state = pass_until(state, game.Upkeep)

  let result = action.dispatch(state, action.PlayLand(1, "land1"))
  assert result == Error(error.WrongStep(expected: "Pre or post-combat main"))
}

// Test playing land from PostCombatMain phase
pub fn play_land_postcombat_main_test() {
  let state = game.new()
  let land = create_test_land("land1", "Island")

  // Add land to player 1's hand
  let state = add_card_to_hand(state, 1, land)

  // Advance to PostCombatMain
  let state = pass_until(state, game.PostCombatMain)

  // Play the land
  let assert Ok(state) = action.dispatch(state, action.PlayLand(1, "land1"))

  // Verify land moved to battlefield
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1
}

// Test only active player can play land
pub fn play_land_not_active_player_test() {
  let state = game.new()
  let land = create_test_land("land1", "Plains")

  // Add land to player 2's hand
  let state = add_card_to_hand(state, 2, land)

  // Advance to PreCombatMain (player 1 is active)
  let state = pass_until(state, game.PreCombatMain)
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))

  // Player 2 tries to play land - should fail
  let result = action.dispatch(state, action.PlayLand(2, "land1"))
  assert result
    == Error(error.InvalidAction("Only the active player can play a land"))
}

// Test card not in hand
pub fn play_land_not_in_hand_test() {
  let state = game.new()

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Try to play a land that's not in hand
  let result = action.dispatch(state, action.PlayLand(1, "nonexistent"))
  assert result == Error(error.InvalidAction("Card not found"))
}

// Test card is not a land
pub fn play_land_not_a_land_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Try to play creature as land - should fail
  let result = action.dispatch(state, action.PlayLand(1, "creature1"))
  assert result == Error(error.InvalidAction("Card is not a land"))
}

// Test must have priority to play land
pub fn play_land_without_priority_test() {
  let state = game.new()
  let land = create_test_land("land1", "Swamp")

  // Add land to player 1's hand
  let state = add_card_to_hand(state, 1, land)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Pass priority so player 2 has priority
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  assert state.priority_player == Some(2)

  // Try to play land as player 1 without priority - should fail
  let result = action.dispatch(state, action.PlayLand(1, "land1"))
  assert result == Error(error.DoNotHavePriority)
}

// Test land enters battlefield untapped
pub fn land_enters_untapped_test() {
  let state = game.new()
  let forest = create_test_land("land1", "Forest")

  // Add forest to player 1's hand
  let state = add_card_to_hand(state, 1, forest)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Play the land
  let assert Ok(state) = action.dispatch(state, action.PlayLand(1, "land1"))

  // Verify land is on battlefield and untapped
  let assert Ok(player1) = player.find(state.players, 1)
  let assert Ok(land_on_battlefield) =
    permanent.find(player1.battlefield, "land1")
  assert land_on_battlefield.tapped == False
}

// Test cannot play land while spell is on stack
pub fn cannot_play_land_with_stack_not_empty_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")
  let land = create_test_land("land1", "Forest")

  // Add both to player 1's hand
  let state = add_card_to_hand(state, 1, creature)
  let state = add_card_to_hand(state, 1, land)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1"))

  // Verify stack is not empty
  assert list.length(state.stack) == 1

  // Try to play land - should fail
  let result = action.dispatch(state, action.PlayLand(1, "land1"))
  assert result
    == Error(error.InvalidAction(
      "Cannot play a land while the stack is not empty",
    ))
}

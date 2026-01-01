import gleam/list
import gleam/option.{None, Some}
import mtg_engine/action
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import test_helpers.{
  add_card_to_hand, add_land_to_battlefield, create_test_land, pass, pass_turn,
  pass_until,
}

// Test game initialization
pub fn new_game_test() {
  let state = game.new()

  // Verify two players are created
  assert list.length(state.players) == 2

  // Verify both players start with 20 life
  assert list.all(state.players, fn(player) { player.life == 20 })

  // Verify game starts at Untap step
  assert state.step == game.Untap

  // Verify no player has priority
  assert state.priority_player == None

  // Verify player 1 is the active player
  assert state.active_player == 1

  // Verify game starts at turn index 0
  assert state.turn_index == 0

  // Verify consecutive_passes starts at 0
  assert state.consecutive_passes == 0

  // Verify stack starts empty
  assert state.stack == []
}

// Test phase advancement when both players pass
pub fn both_players_pass_advances_step_test() {
  let state = game.new()

  // Both players pass in Untap (which should advance through to Upkeep)
  let state = pass(state)

  // Should advance from Untap -> Upkeep
  assert state.step == game.Upkeep
  assert state.consecutive_passes == 0
  assert state.priority_player == Some(1)
}

// Test step advancement resets consecutive passes
pub fn step_advancement_resets_consecutive_passes_test() {
  let state = game.new() |> pass_until(game.PreCombatMain)

  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  assert state.consecutive_passes == 1

  let assert Ok(state) = action.dispatch(state, action.PassPriority(2))
  assert state.consecutive_passes == 0
}

// Test priority goes to active player when entering new step
pub fn new_step_gives_priority_to_active_player_test() {
  let state = game.new()

  // Advance through Untap -> Upkeep
  let state = pass(state)

  assert state.step == game.Upkeep
  assert state.priority_player == Some(state.active_player)
  assert state.priority_player == Some(1)
}

// Test first turn draw step is skipped
pub fn first_turn_skips_draw_step_test() {
  let state = game.new()

  // Advance through Untap -> Upkeep
  let state = pass(state)
  assert state.step == game.Upkeep

  // Advance through Upkeep -> Draw (which should skip to PreCombatMain on turn 1)
  let state = pass(state)

  // Should skip Draw and go to PreCombatMain
  assert state.step == game.PreCombatMain
  assert state.turn_index == 0
}

// Test full turn cycle advances through all steps
pub fn full_turn_cycle_test() {
  let state = game.new() |> pass_until(game.Cleanup) |> pass()

  // Start: Untap
  assert state.step == game.Untap

  // Untap -> Upkeep
  let state = pass(state)
  assert state.step == game.Upkeep

  // Upkeep -> Draw
  let state = pass(state)
  assert state.step == game.Draw

  // Draw -> PreCombatMain
  let state = pass(state)
  assert state.step == game.PreCombatMain

  // PreCombatMain -> BeginCombat
  let state = pass(state)
  assert state.step == game.BeginCombat

  // BeginCombat -> DeclareAttackers
  let state = pass(state)
  assert state.step == game.DeclareAttackers

  // DeclareAttackers -> DeclareBlockers
  let state = pass(state)
  assert state.step == game.DeclareBlockers

  // DeclareBlockers -> CombatDamage
  let state = pass(state)
  assert state.step == game.CombatDamage

  // CombatDamage -> EndCombat
  let state = pass(state)
  assert state.step == game.EndCombat

  // EndCombat -> PostCombatMain
  let state = pass(state)
  assert state.step == game.PostCombatMain

  // PostCombatMain -> EndStep
  let state = pass(state)
  assert state.step == game.EndStep

  // EndStep -> Cleanup
  let state = pass(state)
  assert state.step == game.Cleanup
}

// Test turn transition changes active player
pub fn turn_transition_to_player_2_test() {
  let state = game.new()

  // Advance through entire first turn (player 1)
  let state = pass_until(state, game.Cleanup)

  assert state.step == game.Cleanup
  assert state.turn_index == 0
  assert state.active_player == 1

  let state = pass(state)
  assert state.step == game.Untap
  // Turn index increments when moving to next player
  assert state.turn_index == 1
  assert state.active_player == 2
}

// Test turn cycle increments after full round
pub fn turn_index_increments_after_full_round_test() {
  let state = game.new()

  // Complete player 1's turn
  let state = pass_turn(state)

  assert game.turn_cycle(state) == 0
  assert state.active_player == 2

  // Complete player 2's turn
  let state = pass_turn(state)

  // Now turn cycle should increment since we're back to player 1
  assert game.turn_cycle(state) == 1
  assert state.active_player == 1
}

// Test player 2 has draw step (turn_index 0 draw skip only applies to first player)
pub fn player_2_has_draw_step_test() {
  let state = game.new()

  // Advance through player 1's entire first turn
  let state = pass_turn(state)

  assert state.turn_index == 1
  assert state.active_player == 2
  assert state.step == game.Untap

  // Player 2 should have a draw step even on turn_index 1
  let state = pass(state) |> pass()
  assert state.step == game.Draw

  // Draw -> PreCombatMain
  let state = pass(state)
  assert state.step == game.PreCombatMain
}

// Test second turn cycle does not skip draw step
pub fn second_turn_cycle_has_draw_step_test() {
  let state = game.new()

  // Complete full round to reach turn cycle 1
  let state = pass_turn(state) |> pass_turn()

  assert game.turn_cycle(state) == 1
  assert state.active_player == 1
  assert state.step == game.Untap

  // Turn cycle 1 should have draw step
  let state = pass(state) |> pass()
  assert state.step == game.Draw

  // Draw -> PreCombatMain
  let state = pass(state)
  assert state.step == game.PreCombatMain
}

// Test mana empties when step advances
pub fn mana_empties_on_step_change_test() {
  let state = game.new() |> pass_until(game.PreCombatMain)
  let mana =
    mana.Produced(white: 3, blue: 2, black: 1, red: 0, green: 0, colorless: 0)

  // Produce mana for player 1
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Verify mana is in pool
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.white == 3
  assert player1.mana_pool.blue == 2
  assert player1.mana_pool.black == 1

  let state = pass(state)

  // Mana should be cleared
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.white == 0
  assert player1.mana_pool.blue == 0
  assert player1.mana_pool.black == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.colorless == 0
}

// Test mana empties for all players on step change
pub fn mana_empties_for_all_players_test() {
  let state = game.new() |> pass_until(game.PreCombatMain)
  let mana_p1 =
    mana.Produced(white: 3, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
  let mana_p2 =
    mana.Produced(white: 0, blue: 0, black: 0, red: 2, green: 1, colorless: 0)

  // Produce mana for both players
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana_p1))
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(2, mana_p2))

  // Verify both have mana
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(p2) = player.find(state.players, 2)
  assert p1.mana_pool.white == 3
  assert p2.mana_pool.red == 2
  assert p2.mana_pool.green == 1

  // Advance to next step
  let state = pass(state)

  // Both players' mana should be cleared
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(p2) = player.find(state.players, 2)
  assert p1.mana_pool.white == 0
  assert p2.mana_pool.red == 0
  assert p2.mana_pool.green == 0
}

// Test empty pools remain empty (edge case)
pub fn empty_pools_remain_empty_test() {
  let state = game.new()

  // Verify pools start empty
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.mana_pool.white == 0

  // Advance to next step
  let state = pass(state)

  // Pools should still be empty
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.mana_pool.white == 0
  assert p1.mana_pool.blue == 0
  assert p1.mana_pool.black == 0
  assert p1.mana_pool.red == 0
  assert p1.mana_pool.green == 0
  assert p1.mana_pool.colorless == 0
}

// Test mana empties across multiple step transitions
pub fn mana_empties_across_multiple_steps_test() {
  let state = game.new() |> pass_until(game.PreCombatMain)
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 5, colorless: 0)

  // Produce mana
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let state = pass(state)

  // Mana should be cleared
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.mana_pool.green == 0

  // Produce more mana
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let state = pass(state)

  // Mana should be cleared again
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.mana_pool.green == 0
}

// Test mana empties when transitioning turns
pub fn mana_empties_on_turn_transition_test() {
  let state = game.new()
  let mana =
    mana.Produced(
      white: 10,
      blue: 10,
      black: 10,
      red: 10,
      green: 10,
      colorless: 10,
    )

  // Advance to end of turn and produce lots of mana
  let state = pass_until(state, game.Cleanup)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Verify mana is there
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.mana_pool.white == 10

  // Advance to next player's turn
  let state = pass(state)
  assert state.active_player == 2

  // Player 1's mana should be cleared
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.mana_pool.white == 0
  assert p1.mana_pool.blue == 0
  assert p1.mana_pool.black == 0
  assert p1.mana_pool.red == 0
  assert p1.mana_pool.green == 0
  assert p1.mana_pool.colorless == 0
}

// Test lands_played_this_turn resets on new turn
pub fn lands_played_resets_on_new_turn_test() {
  let state = game.new()
  let land1 = create_test_land("land1", "Forest")
  let land2 = create_test_land("land2", "Mountain")

  // Add lands to player 1's hand
  let state = add_card_to_hand(state, 1, land1)
  let state = add_card_to_hand(state, 1, land2)

  // Advance to PreCombatMain
  let state = pass_until(state, game.PreCombatMain)

  // Play first land
  let assert Ok(state) = action.dispatch(state, action.PlayLand(1, "land1"))

  // Verify lands_played_this_turn is 1
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.lands_played_this_turn == 1

  // Advance to end of turn and into next player's turn
  let state = pass_until(state, game.Cleanup)
  let state = pass(state)

  // Complete player 2's turn
  let state = pass_until(state, game.Cleanup)
  let state = pass(state)

  // Now player 1's turn 2 - lands_played_this_turn should be reset
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.lands_played_this_turn == 0

  // Should be able to play second land now
  let state = pass_until(state, game.PreCombatMain)
  let assert Ok(_) = action.dispatch(state, action.PlayLand(1, "land2"))
}

// Test lands untap during untap step
pub fn lands_untap_during_untap_step_test() {
  let state = game.new() |> pass_until(game.PreCombatMain)
  let forest = create_test_land("land1", "Forest")
  let mountain = create_test_land("land2", "Mountain")

  // Add lands to battlefield
  let state = add_land_to_battlefield(state, 1, forest)
  let state = add_land_to_battlefield(state, 1, mountain)

  // Tap both lands
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land1"))
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land2"))

  // Verify both lands are tapped
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(land1) = permanent.find(p1.battlefield, "land1")
  let assert Ok(land2) = permanent.find(p1.battlefield, "land2")
  assert land1.tapped == True
  assert land2.tapped == True

  // Advance until player 1's next turn (this will trigger untap)
  let state = pass_turn(state) |> pass_turn()

  // Verify lands are now untapped
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(land1) = permanent.find(p1.battlefield, "land1")
  let assert Ok(land2) = permanent.find(p1.battlefield, "land2")
  assert land1.tapped == False
  assert land2.tapped == False
}

// Test only active player's lands untap
pub fn only_active_player_lands_untap_test() {
  let state = game.new() |> pass_until(game.PreCombatMain)
  let forest_p1 = create_test_land("land1", "Forest")
  let mountain_p2 = create_test_land("land2", "Mountain")

  // Add lands to both players' battlefields
  let state =
    add_land_to_battlefield(state, 1, forest_p1)
    |> add_land_to_battlefield(2, mountain_p2)

  // Tap both lands
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land1"))
  let state = pass_turn(state) |> pass_until(game.PreCombatMain)
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(2, "land2"))

  // Verify both are tapped
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(p2) = player.find(state.players, 2)
  let assert Ok(land1) = permanent.find(p1.battlefield, "land1")
  let assert Ok(land2) = permanent.find(p2.battlefield, "land2")
  assert land1.tapped == True
  assert land2.tapped == True

  // Advance to next player's turn (player 1)
  let state = pass_turn(state)

  // Player 1's lands should untap, player 2's should stay tapped
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(p2) = player.find(state.players, 2)
  let assert Ok(land1) = permanent.find(p1.battlefield, "land1")
  let assert Ok(land2) = permanent.find(p2.battlefield, "land2")
  assert land1.tapped == False
  assert land2.tapped == True
}

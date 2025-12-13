import gleam/list
import gleeunit
import mtg_engine/action
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import test_helpers.{
  add_card_to_hand, add_land_to_battlefield, create_test_land, pass_both,
  pass_turn, pass_until,
}

pub fn main() -> Nil {
  gleeunit.main()
}

// Test game initialization
pub fn init_game_test() {
  let game = game.new()

  // Verify two players are created
  assert list.length(game.players) == 2

  // Verify both players start with 20 life
  assert list.all(game.players, fn(player) { player.life == 20 })

  // Verify game starts at Untap step
  assert game.current_step == game.Untap

  // Verify player 1 has priority
  assert game.priority_player_id == 1

  // Verify player 1 is the active player
  assert game.active_player_id == 1

  // Verify game starts at turn 1
  assert game.turn_index == 0

  // Verify consecutive_passes starts at 0
  assert game.consecutive_passes == 0

  // Verify stack starts empty
  assert game.stack == []
}

// Test stack initialization
pub fn stack_starts_empty_test() {
  let game = game.new()

  // Verify stack is an empty list
  assert game.stack == []
}

// Test phase advancement when both players pass
pub fn both_players_pass_advances_step_test() {
  let game = game.new()

  // Both players pass in Untap (which should advance through to Upkeep)
  let game = pass_both(game)

  // Should advance from Untap -> Upkeep
  assert game.current_step == game.Upkeep
  assert game.consecutive_passes == 0
  assert game.priority_player_id == 1
}

// Test step advancement resets consecutive passes
pub fn step_advancement_resets_consecutive_passes_test() {
  let game = game.new()

  let assert Ok(game) = action.dispatch(game, action.PassPriority)
  assert game.consecutive_passes == 1

  let assert Ok(game) = action.dispatch(game, action.PassPriority)
  assert game.consecutive_passes == 0
}

// Test priority goes to active player when entering new step
pub fn new_step_gives_priority_to_active_player_test() {
  let game = game.new()

  // Advance through Untap -> Upkeep
  let game = pass_both(game)

  assert game.current_step == game.Upkeep
  assert game.priority_player_id == game.active_player_id
  assert game.priority_player_id == 1
}

// Test first turn draw step is skipped
pub fn first_turn_skips_draw_step_test() {
  let game = game.new()

  // Advance through Untap -> Upkeep
  let game = pass_both(game)
  assert game.current_step == game.Upkeep

  // Advance through Upkeep -> Draw (which should skip to PreCombatMain on turn 1)
  let game = pass_both(game)

  // Should skip Draw and go to PreCombatMain
  assert game.current_step == game.PreCombatMain
  assert game.turn_index == 0
}

// Test full turn cycle advances through all steps
pub fn full_turn_cycle_test() {
  let game = game.new()

  // Start: Untap
  assert game.current_step == game.Untap

  // Untap -> Upkeep
  let game = pass_both(game)
  assert game.current_step == game.Upkeep

  // Upkeep -> Draw (skipped) -> PreCombatMain
  let game = pass_both(game)
  assert game.current_step == game.PreCombatMain

  // PreCombatMain -> BeginCombat
  let game = pass_both(game)
  assert game.current_step == game.BeginCombat

  // BeginCombat -> DeclareAttackers
  let game = pass_both(game)
  assert game.current_step == game.DeclareAttackers

  // DeclareAttackers -> DeclareBlockers
  let game = pass_both(game)
  assert game.current_step == game.DeclareBlockers

  // DeclareBlockers -> CombatDamage
  let game = pass_both(game)
  assert game.current_step == game.CombatDamage

  // CombatDamage -> EndCombat
  let game = pass_both(game)
  assert game.current_step == game.EndCombat

  // EndCombat -> PostCombatMain
  let game = pass_both(game)
  assert game.current_step == game.PostCombatMain

  // PostCombatMain -> EndStep
  let game = pass_both(game)
  assert game.current_step == game.EndStep

  // EndStep -> Cleanup
  let game = pass_both(game)
  assert game.current_step == game.Cleanup

  // Still turn index 0
  assert game.turn_index == 0
  assert game.active_player_id == 1
}

// Test turn transition changes active player but keeps turn number
pub fn turn_transition_to_player_2_test() {
  let game = game.new()

  // Advance through entire first turn (player 1)
  let game = pass_until(game.Cleanup, game)

  assert game.current_step == game.Cleanup
  assert game.turn_index == 0
  assert game.active_player_id == 1

  // Cleanup -> Untap (skipped) -> Upkeep of player 2's turn
  let game = pass_both(game)

  assert game.current_step == game.Upkeep
  assert game.turn_index == 1
  // Turn index increments when moving to next player
  assert game.active_player_id == 2
  assert game.priority_player_id == 2
}

// Test turn cycle increments after full round
pub fn turn_index_increments_after_full_round_test() {
  let game = game.new()

  // Complete player 1's turn
  let game = pass_turn(game)

  assert game.turn_cycle(game) == 0
  assert game.active_player_id == 2

  // Complete player 2's turn
  let game = pass_turn(game)

  // Now turn cycle should increment since we're back to player 1
  assert game.turn_cycle(game) == 1
  assert game.active_player_id == 1
  // Player 1 gets a draw step on the second turn cycle
  assert game.current_step == game.Upkeep
}

// Test player 2 has draw step (turn_index 0 draw skip only applies to first player)
pub fn player_2_has_draw_step_test() {
  let game = game.new()

  // Advance through player 1's entire first turn
  let game = pass_turn(game)

  assert game.turn_index == 1
  assert game.active_player_id == 2
  assert game.current_step == game.Upkeep

  // Player 2 should have a draw step even on turn_index 1
  let game = pass_both(game)
  assert game.current_step == game.Draw

  // Draw -> PreCombatMain
  let game = pass_both(game)
  assert game.current_step == game.PreCombatMain
}

// Test second turn cycle does not skip draw step
pub fn second_turn_cycle_has_draw_step_test() {
  let game = game.new()

  // Complete full round to reach turn cycle 1
  let game = pass_turn(game) |> pass_turn()

  assert game.turn_cycle(game) == 1
  assert game.active_player_id == 1
  assert game.current_step == game.Upkeep

  // Turn cycle 1 should have draw step
  let game = pass_both(game)
  assert game.current_step == game.Draw

  // Draw -> PreCombatMain
  let game = pass_both(game)
  assert game.current_step == game.PreCombatMain
}

// Test mana empties when step advances
pub fn mana_empties_on_step_change_test() {
  let game = game.new()
  let mana =
    mana.Produced(white: 3, blue: 2, black: 1, red: 0, green: 0, colorless: 0)

  // Produce mana for player 1 in Untap step
  let assert Ok(game) = action.dispatch(game, action.ProduceMana(1, mana))

  // Verify mana is in pool
  let assert Ok(player1) = player.find(game.players, 1)
  assert player1.mana_pool.white == 3
  assert player1.mana_pool.blue == 2
  assert player1.mana_pool.black == 1

  // Both players pass to advance to Upkeep
  let game = pass_both(game)
  assert game.current_step == game.Upkeep

  // Mana should be cleared
  let assert Ok(player1_after) = player.find(game.players, 1)
  assert player1_after.mana_pool.white == 0
  assert player1_after.mana_pool.blue == 0
  assert player1_after.mana_pool.black == 0
  assert player1_after.mana_pool.red == 0
  assert player1_after.mana_pool.green == 0
  assert player1_after.mana_pool.colorless == 0
}

// Test mana empties for all players on step change
pub fn mana_empties_for_all_players_test() {
  let game = game.new()
  let mana_p1 =
    mana.Produced(white: 3, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
  let mana_p2 =
    mana.Produced(white: 0, blue: 0, black: 0, red: 2, green: 1, colorless: 0)

  // Produce mana for both players
  let assert Ok(game) = action.dispatch(game, action.ProduceMana(1, mana_p1))
  let assert Ok(game) = action.dispatch(game, action.ProduceMana(2, mana_p2))

  // Verify both have mana
  let assert Ok(p1) = player.find(game.players, 1)
  let assert Ok(p2) = player.find(game.players, 2)
  assert p1.mana_pool.white == 3
  assert p2.mana_pool.red == 2
  assert p2.mana_pool.green == 1

  // Advance to next step
  let game = pass_both(game)

  // Both players' mana should be cleared
  let assert Ok(p1_after) = player.find(game.players, 1)
  let assert Ok(p2_after) = player.find(game.players, 2)
  assert p1_after.mana_pool.white == 0
  assert p2_after.mana_pool.red == 0
  assert p2_after.mana_pool.green == 0
}

// Test empty pools remain empty (edge case)
pub fn empty_pools_remain_empty_test() {
  let game = game.new()

  // Verify pools start empty
  let assert Ok(p1) = player.find(game.players, 1)
  assert p1.mana_pool.white == 0

  // Advance to next step
  let game = pass_both(game)

  // Pools should still be empty
  let assert Ok(p1_after) = player.find(game.players, 1)
  assert p1_after.mana_pool.white == 0
  assert p1_after.mana_pool.blue == 0
  assert p1_after.mana_pool.black == 0
  assert p1_after.mana_pool.red == 0
  assert p1_after.mana_pool.green == 0
  assert p1_after.mana_pool.colorless == 0
}

// Test mana empties across multiple step transitions
pub fn mana_empties_across_multiple_steps_test() {
  let game = game.new()
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 5, colorless: 0)

  // Produce mana
  let assert Ok(game) = action.dispatch(game, action.ProduceMana(1, mana))

  // Advance through Untap -> Upkeep
  let game = pass_both(game)
  assert game.current_step == game.Upkeep

  // Mana should be cleared
  let assert Ok(p1) = player.find(game.players, 1)
  assert p1.mana_pool.green == 0

  // Produce more mana in Upkeep
  let assert Ok(game) = action.dispatch(game, action.ProduceMana(1, mana))

  // Advance through Upkeep -> PreCombatMain (Draw skipped on turn 1)
  let game = pass_both(game)
  assert game.current_step == game.PreCombatMain

  // Mana should be cleared again
  let assert Ok(p1_after) = player.find(game.players, 1)
  assert p1_after.mana_pool.green == 0
}

// Test mana empties when transitioning turns
pub fn mana_empties_on_turn_transition_test() {
  let game = game.new()
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
  let game = pass_until(game.Cleanup, game)
  let assert Ok(game) = action.dispatch(game, action.ProduceMana(1, mana))

  // Verify mana is there
  let assert Ok(p1) = player.find(game.players, 1)
  assert p1.mana_pool.white == 10

  // Advance to next player's turn
  let game = pass_both(game)
  assert game.active_player_id == 2

  // Player 1's mana should be cleared
  let assert Ok(p1_after) = player.find(game.players, 1)
  assert p1_after.mana_pool.white == 0
  assert p1_after.mana_pool.blue == 0
  assert p1_after.mana_pool.black == 0
  assert p1_after.mana_pool.red == 0
  assert p1_after.mana_pool.green == 0
  assert p1_after.mana_pool.colorless == 0
}

// Test lands_played_this_turn resets on new turn
pub fn lands_played_resets_on_new_turn_test() {
  let game = game.new()
  let land1 = create_test_land("land1", "Forest")
  let land2 = create_test_land("land2", "Mountain")

  // Add lands to player 1's hand
  let game = add_card_to_hand(game, 1, land1)
  let game = add_card_to_hand(game, 1, land2)

  // Advance to PreCombatMain
  let game = pass_until(game.PreCombatMain, game)

  // Play first land
  let assert Ok(game) = action.dispatch(game, action.PlayLand(1, "land1"))

  // Verify lands_played_this_turn is 1
  let assert Ok(p1) = player.find(game.players, 1)
  assert p1.lands_played_this_turn == 1

  // Advance to end of turn and into next player's turn
  let game = pass_until(game.Cleanup, game)
  let game = pass_both(game)

  // Complete player 2's turn
  let game = pass_until(game.Cleanup, game)
  let game = pass_both(game)

  // Now player 1's turn 2 - lands_played_this_turn should be reset
  let assert Ok(p1_turn2) = player.find(game.players, 1)
  assert p1_turn2.lands_played_this_turn == 0

  // Should be able to play second land now
  let game = pass_until(game.PreCombatMain, game)
  let assert Ok(_new_game) = action.dispatch(game, action.PlayLand(1, "land2"))
}

// Test lands untap during untap step
pub fn lands_untap_during_untap_step_test() {
  let game = game.new()
  let forest = create_test_land("land1", "Forest")
  let mountain = create_test_land("land2", "Mountain")

  // Add lands to battlefield
  let game = add_land_to_battlefield(game, 1, forest)
  let game = add_land_to_battlefield(game, 1, mountain)

  // Tap both lands
  let assert Ok(game) = action.dispatch(game, action.TapLandForMana(1, "land1"))
  let assert Ok(game) = action.dispatch(game, action.TapLandForMana(1, "land2"))

  // Verify both lands are tapped
  let assert Ok(p1) = player.find(game.players, 1)
  let assert Ok(land1) = permanent.find(p1.battlefield, "land1")
  let assert Ok(land2) = permanent.find(p1.battlefield, "land2")
  assert land1.tapped == True
  assert land2.tapped == True

  // Advance until player 1's next turn (this will trigger untap)
  let game = pass_turn(game) |> pass_turn()

  // Verify lands are now untapped
  let assert Ok(p1_after) = player.find(game.players, 1)
  let assert Ok(land1_after) = permanent.find(p1_after.battlefield, "land1")
  let assert Ok(land2_after) = permanent.find(p1_after.battlefield, "land2")
  assert land1_after.tapped == False
  assert land2_after.tapped == False
}

// Test only active player's lands untap
pub fn only_active_player_lands_untap_test() {
  let game = game.new()
  let forest_p1 = create_test_land("land1", "Forest")
  let mountain_p2 = create_test_land("land2", "Mountain")

  // Add lands to both players' battlefields
  let game = add_land_to_battlefield(game, 1, forest_p1)
  let game = add_land_to_battlefield(game, 2, mountain_p2)

  // Tap both lands
  let assert Ok(game) = action.dispatch(game, action.TapLandForMana(1, "land1"))
  let assert Ok(game) = action.dispatch(game, action.TapLandForMana(2, "land2"))

  // Verify both are tapped
  let assert Ok(p1) = player.find(game.players, 1)
  let assert Ok(p2) = player.find(game.players, 2)
  let assert Ok(land1) = permanent.find(p1.battlefield, "land1")
  let assert Ok(land2) = permanent.find(p2.battlefield, "land2")
  assert land1.tapped == True
  assert land2.tapped == True

  // Advance to next player's turn (player 2)
  let game = pass_turn(game)

  // Player 2's lands should untap, player 1's should stay tapped
  let assert Ok(p1_after) = player.find(game.players, 1)
  let assert Ok(p2_after) = player.find(game.players, 2)
  let assert Ok(land1_after) = permanent.find(p1_after.battlefield, "land1")
  let assert Ok(land2_after) = permanent.find(p2_after.battlefield, "land2")
  assert land1_after.tapped == True
  assert land2_after.tapped == False
}

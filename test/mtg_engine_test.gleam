import gleam/list
import gleeunit
import mtg_engine
import types

pub fn main() -> Nil {
  gleeunit.main()
}

// Test game initialization
pub fn init_game_test() {
  let game = mtg_engine.init_game()

  // Verify two players are created
  assert list.length(game.players) == 2

  // Verify both players start with 20 life
  assert list.all(game.players, fn(player) { player.life == 20 })

  // Verify game starts at Untap step
  assert game.current_step == types.Untap

  // Verify player 1 has priority
  assert game.priority_player_id == 1

  // Verify player 1 is the active player
  assert game.active_player_id == 1

  // Verify game starts at turn 1
  assert game.turn_number == 1

  // Verify consecutive_passes starts at 0
  assert game.consecutive_passes == 0
}

// Test PassPriority action
pub fn pass_priority_advances_from_player_1_to_2_test() {
  let game = mtg_engine.init_game()
  let assert Ok(new_game) = mtg_engine.dispatch(game, types.PassPriority)

  assert new_game.priority_player_id == 2
}

pub fn pass_priority_wraps_from_player_2_to_1_test() {
  let game = mtg_engine.init_game()
  let assert Ok(game_p2) = mtg_engine.dispatch(game, types.PassPriority)
  let assert Ok(game_p1_again) = mtg_engine.dispatch(game_p2, types.PassPriority)

  assert game_p1_again.priority_player_id == 1
}

// Test consecutive passes tracking
pub fn pass_priority_increments_consecutive_passes_test() {
  let game = mtg_engine.init_game()

  // First pass
  let assert Ok(game_after_1) = mtg_engine.dispatch(game, types.PassPriority)
  assert game_after_1.consecutive_passes == 1
}

// Test phase advancement when both players pass
pub fn both_players_pass_advances_step_test() {
  let game = mtg_engine.init_game()

  // Both players pass in Untap (which should advance through to Upkeep)
  let assert Ok(game_p2) = mtg_engine.dispatch(game, types.PassPriority)
  let assert Ok(game_advanced) = mtg_engine.dispatch(game_p2, types.PassPriority)

  // Should advance from Untap -> Upkeep
  assert game_advanced.current_step == types.Upkeep
  assert game_advanced.consecutive_passes == 0
  assert game_advanced.priority_player_id == 1
}

// Test step advancement resets consecutive passes
pub fn step_advancement_resets_consecutive_passes_test() {
  let game = mtg_engine.init_game()

  let assert Ok(game_p2) = mtg_engine.dispatch(game, types.PassPriority)
  assert game_p2.consecutive_passes == 1

  let assert Ok(game_advanced) = mtg_engine.dispatch(game_p2, types.PassPriority)
  assert game_advanced.consecutive_passes == 0
}

// Test priority goes to active player when entering new step
pub fn new_step_gives_priority_to_active_player_test() {
  let game = mtg_engine.init_game()

  // Advance through Untap -> Upkeep
  let assert Ok(game_p2) = mtg_engine.dispatch(game, types.PassPriority)
  let assert Ok(game_upkeep) = mtg_engine.dispatch(game_p2, types.PassPriority)

  assert game_upkeep.current_step == types.Upkeep
  assert game_upkeep.priority_player_id == game_upkeep.active_player_id
  assert game_upkeep.priority_player_id == 1
}

// Test first turn draw step is skipped
pub fn first_turn_skips_draw_step_test() {
  let game = mtg_engine.init_game()

  // Advance through Untap -> Upkeep
  let assert Ok(game_p2) = mtg_engine.dispatch(game, types.PassPriority)
  let assert Ok(game_upkeep) = mtg_engine.dispatch(game_p2, types.PassPriority)
  assert game_upkeep.current_step == types.Upkeep

  // Advance through Upkeep -> Draw (which should skip to PreCombatMain on turn 1)
  let assert Ok(game_p2_2) = mtg_engine.dispatch(game_upkeep, types.PassPriority)
  let assert Ok(game_after_draw) = mtg_engine.dispatch(game_p2_2, types.PassPriority)

  // Should skip Draw and go to PreCombatMain
  assert game_after_draw.current_step == types.PreCombatMain
  assert game_after_draw.turn_number == 1
}

fn pass_both(state: types.GameState) {
    let assert Ok(s1) = mtg_engine.dispatch(state, types.PassPriority)
    let assert Ok(s2) = mtg_engine.dispatch(s1, types.PassPriority)
    s2
}

fn pass_until(target_step: types.Step, state: types.GameState) {
  case state.current_step {
    step if step == target_step -> state
    _ -> pass_until(target_step, pass_both(state))
  }
}

// Test full turn cycle advances through all steps
pub fn full_turn_cycle_test() {
  let game = mtg_engine.init_game()

  // Start: Untap
  assert game.current_step == types.Untap

  // Untap -> Upkeep
  let game = pass_both(game)
  assert game.current_step == types.Upkeep

  // Upkeep -> Draw (skipped) -> PreCombatMain
  let game = pass_both(game)
  assert game.current_step == types.PreCombatMain

  // PreCombatMain -> BeginCombat
  let game = pass_both(game)
  assert game.current_step == types.BeginCombat

  // BeginCombat -> DeclareAttackers
  let game = pass_both(game)
  assert game.current_step == types.DeclareAttackers

  // DeclareAttackers -> DeclareBlockers
  let game = pass_both(game)
  assert game.current_step == types.DeclareBlockers

  // DeclareBlockers -> CombatDamage
  let game = pass_both(game)
  assert game.current_step == types.CombatDamage

  // CombatDamage -> EndCombat
  let game = pass_both(game)
  assert game.current_step == types.EndCombat

  // EndCombat -> PostCombatMain
  let game = pass_both(game)
  assert game.current_step == types.PostCombatMain

  // PostCombatMain -> EndStep
  let game = pass_both(game)
  assert game.current_step == types.EndStep

  // EndStep -> Cleanup
  let game = pass_both(game)
  assert game.current_step == types.Cleanup

  // Still turn 1
  assert game.turn_number == 1
  assert game.active_player_id == 1
}

// Test turn transition changes active player but keeps turn number
pub fn turn_transition_to_player_2_test() {
  let game = mtg_engine.init_game()

  // Advance through entire first turn (player 1)
  let game = pass_until(types.Cleanup, game)

  assert game.current_step == types.Cleanup
  assert game.turn_number == 1
  assert game.active_player_id == 1

  // Cleanup -> Untap (skipped) -> Upkeep of player 2's turn
  let game = pass_both(game)

  assert game.current_step == types.Upkeep
  assert game.turn_number == 1 // Still turn 1, player 2 hasn't finished yet
  assert game.active_player_id == 2
  assert game.priority_player_id == 2
}

// Test turn number increments after full round
pub fn turn_number_increments_after_full_round_test() {
  let game = mtg_engine.init_game()

  let pass_both = fn(state) {
    let assert Ok(s1) = mtg_engine.dispatch(state, types.PassPriority)
    let assert Ok(s2) = mtg_engine.dispatch(s1, types.PassPriority)
    s2
  }

  // Complete player 1's turn
  let game = pass_until(types.Cleanup, game)
  let game = pass_both(game) // Cleanup -> Player 2's Upkeep

  assert game.turn_number == 1
  assert game.active_player_id == 2

  // Complete player 2's turn
  let game = pass_until(types.Cleanup, game)
  let game = pass_both(game) // Cleanup -> Back to Player 1's Upkeep

  // Now turn number should increment since we're back to player 1
  assert game.turn_number == 2
  assert game.active_player_id == 1
  // Player 1 still gets draw step on turn 2
  assert game.current_step == types.Upkeep
}

// Test player 2 has draw step (turn 1 draw skip only applies to first player)
pub fn player_2_has_draw_step_test() {
  let game = mtg_engine.init_game()

  // Advance through player 1's entire first turn
  let game = pass_until(types.Cleanup, game)
  let game = pass_both(game) // Cleanup -> Player 2's Upkeep

  assert game.turn_number == 1
  assert game.active_player_id == 2
  assert game.current_step == types.Upkeep

  // Player 2 should have a draw step even on turn 1
  let game = pass_both(game)
  assert game.current_step == types.Draw

  // Draw -> PreCombatMain
  let game = pass_both(game)
  assert game.current_step == types.PreCombatMain
}

// Test turn 2 does not skip draw step
pub fn turn_2_has_draw_step_test() {
  let game = mtg_engine.init_game()

  // Complete full round to reach turn 2
  // Player 1's turn 1
  let game = pass_until(types.Cleanup, game)
  let game = pass_both(game) // Cleanup -> Player 2's Upkeep

  // Player 2's turn 1
  let game = pass_until(types.Cleanup, game)
  let game = pass_both(game) // Cleanup -> Player 1's turn 2 Upkeep

  assert game.turn_number == 2
  assert game.active_player_id == 1
  assert game.current_step == types.Upkeep

  // Turn 2 should have draw step
  let game = pass_both(game)
  assert game.current_step == types.Draw

  // Draw -> PreCombatMain
  let game = pass_both(game)
  assert game.current_step == types.PreCombatMain
}

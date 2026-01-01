import gleam/option.{Some}
import mtg_engine/action
import mtg_engine/game
import test_helpers.{pass_until}

// Test PassPriority action
pub fn pass_priority_advances_from_player_1_to_2_test() {
  let state = game.new() |> pass_until(game.PreCombatMain)
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))

  assert state.priority_player == Some(2)
}

// Test consecutive passes tracking
pub fn pass_priority_increments_consecutive_passes_test() {
  let state = game.new() |> pass_until(game.PreCombatMain)

  assert state.consecutive_passes == 0
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  assert state.consecutive_passes == 1
}

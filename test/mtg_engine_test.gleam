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
  assert game.players |> list.length == 2

  // Verify both players start with 20 life
  assert game.players |> list.all(fn(player) { player.life == 20 })

  // Verify game starts at Untap step
  assert game.current_step == types.Untap

  // Verify player 1 has priority
  assert game.priority_player_id == 1

  // Verify player 1 is the active player
  assert game.active_player_id == 1
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

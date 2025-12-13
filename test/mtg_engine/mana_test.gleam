import gleeunit
import mtg_engine/action
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/player

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn produce_single_white_mana_test() {
  let game = game.new()
  let mana =
    mana.Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 0)

  let assert Ok(new_game) = action.dispatch(game, action.ProduceMana(1, mana))

  // Find player 1 and check mana pool
  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool.white == 1
  assert player1.mana_pool.blue == 0
  assert player1.mana_pool.black == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.colorless == 0
}

// Test producing multiple colors at once
pub fn produce_multiple_colors_mana_test() {
  let game = game.new()
  let mana =
    mana.Produced(white: 1, blue: 2, black: 0, red: 0, green: 1, colorless: 0)

  let assert Ok(new_game) = action.dispatch(game, action.ProduceMana(1, mana))

  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool.white == 1
  assert player1.mana_pool.blue == 2
  assert player1.mana_pool.green == 1
}

// Test mana accumulates with multiple productions
pub fn mana_accumulates_test() {
  let game = game.new()
  let mana1 =
    mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 0)
  let mana2 =
    mana.Produced(white: 0, blue: 0, black: 0, red: 2, green: 0, colorless: 0)

  let assert Ok(game_after_1) =
    action.dispatch(game, action.ProduceMana(1, mana1))
  let assert Ok(game_after_2) =
    action.dispatch(game_after_1, action.ProduceMana(1, mana2))

  let assert Ok(player1) = player.find(game_after_2.players, 1)
  assert player1.mana_pool.red == 3
}

// Test producing mana for different players
pub fn produce_mana_different_players_test() {
  let game = game.new()
  let mana_p1 =
    mana.Produced(white: 2, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
  let mana_p2 =
    mana.Produced(white: 0, blue: 3, black: 0, red: 0, green: 0, colorless: 0)

  let assert Ok(game_after_p1) =
    action.dispatch(game, action.ProduceMana(1, mana_p1))
  let assert Ok(game_after_p2) =
    action.dispatch(game_after_p1, action.ProduceMana(2, mana_p2))

  let assert Ok(player1) = player.find(game_after_p2.players, 1)
  let assert Ok(player2) = player.find(game_after_p2.players, 2)

  assert player1.mana_pool.white == 2
  assert player1.mana_pool.blue == 0
  assert player2.mana_pool.white == 0
  assert player2.mana_pool.blue == 3
}

// Test producing zero mana (edge case)
pub fn produce_zero_mana_test() {
  let game = game.new()
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 0, colorless: 0)

  let assert Ok(new_game) = action.dispatch(game, action.ProduceMana(1, mana))

  let assert Ok(player1) = player.find(new_game.players, 1)
  assert player1.mana_pool.white == 0
  assert player1.mana_pool.blue == 0
  assert player1.mana_pool.black == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.colorless == 0
}

// Test mana persists within a step (doesn't empty on priority pass)
pub fn mana_persists_within_step_test() {
  let game = game.new()
  let mana =
    mana.Produced(white: 2, blue: 1, black: 0, red: 0, green: 0, colorless: 0)

  // Produce mana for player 1
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Player 1 passes priority (but stays in same step)
  let assert Ok(game_after_pass) =
    action.dispatch(game_with_mana, action.PassPriority)

  // Mana should still be in player 1's pool
  let assert Ok(player1) = player.find(game_after_pass.players, 1)
  assert player1.mana_pool.white == 2
  assert player1.mana_pool.blue == 1
}

import mtg_engine/action
import mtg_engine/mana
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import test_helpers.{pass_until}

pub fn produce_single_white_mana_test() {
  let state = state.new()
  let mana =
    mana.Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 0)

  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Find player 1 and check mana pool
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.white == 1
  assert player1.mana_pool.blue == 0
  assert player1.mana_pool.black == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.colorless == 0
}

// Test producing multiple colors at once
pub fn produce_multiple_colors_mana_test() {
  let state = state.new()
  let mana =
    mana.Produced(white: 1, blue: 2, black: 0, red: 0, green: 1, colorless: 0)

  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.white == 1
  assert player1.mana_pool.blue == 2
  assert player1.mana_pool.green == 1
}

// Test mana accumulates with multiple productions
pub fn mana_accumulates_test() {
  let state = state.new()
  let mana1 =
    mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 0)
  let mana2 =
    mana.Produced(white: 0, blue: 0, black: 0, red: 2, green: 0, colorless: 0)

  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana1))
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana2))

  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.red == 3
}

// Test producing mana for different players
pub fn produce_mana_different_players_test() {
  let state = state.new()
  let mana_p1 =
    mana.Produced(white: 2, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
  let mana_p2 =
    mana.Produced(white: 0, blue: 3, black: 0, red: 0, green: 0, colorless: 0)

  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana_p1))
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(2, mana_p2))

  let assert Ok(player1) = player.find(state.players, 1)
  let assert Ok(player2) = player.find(state.players, 2)

  assert player1.mana_pool.white == 2
  assert player1.mana_pool.blue == 0
  assert player2.mana_pool.white == 0
  assert player2.mana_pool.blue == 3
}

// Test producing zero mana (edge case)
pub fn produce_zero_mana_test() {
  let state = state.new()
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 0, colorless: 0)

  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.white == 0
  assert player1.mana_pool.blue == 0
  assert player1.mana_pool.black == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.colorless == 0
}

// Test mana persists within a step (doesn't empty on priority pass)
pub fn mana_persists_within_step_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let mana =
    mana.Produced(white: 2, blue: 1, black: 0, red: 0, green: 0, colorless: 0)

  // Produce mana for player 1
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Player 1 passes priority (but stays in same step)
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))

  // Mana should still be in player 1's pool
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.white == 2
  assert player1.mana_pool.blue == 1
}

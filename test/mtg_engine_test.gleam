import gleam/list
import gleam/option
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
  let assert Ok(game_p1_again) =
    mtg_engine.dispatch(game_p2, types.PassPriority)

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
  let assert Ok(game_advanced) =
    mtg_engine.dispatch(game_p2, types.PassPriority)

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

  let assert Ok(game_advanced) =
    mtg_engine.dispatch(game_p2, types.PassPriority)
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
  let assert Ok(game_p2_2) =
    mtg_engine.dispatch(game_upkeep, types.PassPriority)
  let assert Ok(game_after_draw) =
    mtg_engine.dispatch(game_p2_2, types.PassPriority)

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
  assert game.turn_number == 1
  // Still turn 1, player 2 hasn't finished yet
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
  let game = pass_both(game)
  // Cleanup -> Player 2's Upkeep

  assert game.turn_number == 1
  assert game.active_player_id == 2

  // Complete player 2's turn
  let game = pass_until(types.Cleanup, game)
  let game = pass_both(game)
  // Cleanup -> Back to Player 1's Upkeep

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
  let game = pass_both(game)
  // Cleanup -> Player 2's Upkeep

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
  let game = pass_both(game)
  // Cleanup -> Player 2's Upkeep

  // Player 2's turn 1
  let game = pass_until(types.Cleanup, game)
  let game = pass_both(game)
  // Cleanup -> Player 1's turn 2 Upkeep

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

// Mana Production Tests

// Test producing a single color of mana
pub fn produce_single_white_mana_test() {
  let game = mtg_engine.init_game()
  let mana =
    types.ManaProduced(
      white: 1,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )

  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Find player 1 and check mana pool
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.white == 1
  assert player1.mana_pool.blue == 0
  assert player1.mana_pool.black == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.colorless == 0
}

// Test producing multiple colors at once
pub fn produce_multiple_colors_mana_test() {
  let game = mtg_engine.init_game()
  let mana =
    types.ManaProduced(
      white: 1,
      blue: 2,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )

  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.white == 1
  assert player1.mana_pool.blue == 2
  assert player1.mana_pool.green == 1
}

// Test mana accumulates with multiple productions
pub fn mana_accumulates_test() {
  let game = mtg_engine.init_game()
  let mana1 =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 1,
      green: 0,
      colorless: 0,
    )
  let mana2 =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 2,
      green: 0,
      colorless: 0,
    )

  let assert Ok(game_after_1) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana1))
  let assert Ok(game_after_2) =
    mtg_engine.dispatch(game_after_1, types.ProduceMana(1, mana2))

  let assert Ok(player1) = list.find(game_after_2.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.red == 3
}

// Test producing mana for different players
pub fn produce_mana_different_players_test() {
  let game = mtg_engine.init_game()
  let mana_p1 =
    types.ManaProduced(
      white: 2,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )
  let mana_p2 =
    types.ManaProduced(
      white: 0,
      blue: 3,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )

  let assert Ok(game_after_p1) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana_p1))
  let assert Ok(game_after_p2) =
    mtg_engine.dispatch(game_after_p1, types.ProduceMana(2, mana_p2))

  let assert Ok(player1) = list.find(game_after_p2.players, fn(p) { p.id == 1 })
  let assert Ok(player2) = list.find(game_after_p2.players, fn(p) { p.id == 2 })

  assert player1.mana_pool.white == 2
  assert player1.mana_pool.blue == 0
  assert player2.mana_pool.white == 0
  assert player2.mana_pool.blue == 3
}

// Test producing zero mana (edge case)
pub fn produce_zero_mana_test() {
  let game = mtg_engine.init_game()
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )

  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.white == 0
  assert player1.mana_pool.blue == 0
  assert player1.mana_pool.black == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.colorless == 0
}

// Mana Pool Emptying Tests

// Test mana persists within a step (doesn't empty on priority pass)
pub fn mana_persists_within_step_test() {
  let game = mtg_engine.init_game()
  let mana =
    types.ManaProduced(
      white: 2,
      blue: 1,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )

  // Produce mana for player 1
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Player 1 passes priority (but stays in same step)
  let assert Ok(game_after_pass) =
    mtg_engine.dispatch(game_with_mana, types.PassPriority)

  // Mana should still be in player 1's pool
  let assert Ok(player1) =
    list.find(game_after_pass.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.white == 2
  assert player1.mana_pool.blue == 1
}

// Test mana empties when step advances
pub fn mana_empties_on_step_change_test() {
  let game = mtg_engine.init_game()
  let mana =
    types.ManaProduced(
      white: 3,
      blue: 2,
      black: 1,
      red: 0,
      green: 0,
      colorless: 0,
    )

  // Produce mana for player 1 in Untap step
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Verify mana is in pool
  let assert Ok(player1) =
    list.find(game_with_mana.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.white == 3
  assert player1.mana_pool.blue == 2
  assert player1.mana_pool.black == 1

  // Both players pass to advance to Upkeep
  let game_after_step = pass_both(game_with_mana)
  assert game_after_step.current_step == types.Upkeep

  // Mana should be cleared
  let assert Ok(player1_after) =
    list.find(game_after_step.players, fn(p) { p.id == 1 })
  assert player1_after.mana_pool.white == 0
  assert player1_after.mana_pool.blue == 0
  assert player1_after.mana_pool.black == 0
  assert player1_after.mana_pool.red == 0
  assert player1_after.mana_pool.green == 0
  assert player1_after.mana_pool.colorless == 0
}

// Test mana empties for all players on step change
pub fn mana_empties_for_all_players_test() {
  let game = mtg_engine.init_game()
  let mana_p1 =
    types.ManaProduced(
      white: 3,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )
  let mana_p2 =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 2,
      green: 1,
      colorless: 0,
    )

  // Produce mana for both players
  let assert Ok(game_p1_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana_p1))
  let assert Ok(game_both_mana) =
    mtg_engine.dispatch(game_p1_mana, types.ProduceMana(2, mana_p2))

  // Verify both have mana
  let assert Ok(p1) = list.find(game_both_mana.players, fn(p) { p.id == 1 })
  let assert Ok(p2) = list.find(game_both_mana.players, fn(p) { p.id == 2 })
  assert p1.mana_pool.white == 3
  assert p2.mana_pool.red == 2
  assert p2.mana_pool.green == 1

  // Advance to next step
  let game_after_step = pass_both(game_both_mana)

  // Both players' mana should be cleared
  let assert Ok(p1_after) =
    list.find(game_after_step.players, fn(p) { p.id == 1 })
  let assert Ok(p2_after) =
    list.find(game_after_step.players, fn(p) { p.id == 2 })
  assert p1_after.mana_pool.white == 0
  assert p2_after.mana_pool.red == 0
  assert p2_after.mana_pool.green == 0
}

// Test empty pools remain empty (edge case)
pub fn empty_pools_remain_empty_test() {
  let game = mtg_engine.init_game()

  // Verify pools start empty
  let assert Ok(p1) = list.find(game.players, fn(p) { p.id == 1 })
  assert p1.mana_pool.white == 0

  // Advance to next step
  let game_after_step = pass_both(game)

  // Pools should still be empty
  let assert Ok(p1_after) =
    list.find(game_after_step.players, fn(p) { p.id == 1 })
  assert p1_after.mana_pool.white == 0
  assert p1_after.mana_pool.blue == 0
  assert p1_after.mana_pool.black == 0
  assert p1_after.mana_pool.red == 0
  assert p1_after.mana_pool.green == 0
  assert p1_after.mana_pool.colorless == 0
}

// Test mana empties across multiple step transitions
pub fn mana_empties_across_multiple_steps_test() {
  let game = mtg_engine.init_game()
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 5,
      colorless: 0,
    )

  // Produce mana
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Advance through Untap -> Upkeep
  let game = pass_both(game_with_mana)
  assert game.current_step == types.Upkeep

  // Mana should be cleared
  let assert Ok(p1) = list.find(game.players, fn(p) { p.id == 1 })
  assert p1.mana_pool.green == 0

  // Produce more mana in Upkeep
  let assert Ok(game_with_mana2) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Advance through Upkeep -> PreCombatMain (Draw skipped on turn 1)
  let game = pass_both(game_with_mana2)
  assert game.current_step == types.PreCombatMain

  // Mana should be cleared again
  let assert Ok(p1_after) = list.find(game.players, fn(p) { p.id == 1 })
  assert p1_after.mana_pool.green == 0
}

// Test mana empties when transitioning turns
pub fn mana_empties_on_turn_transition_test() {
  let game = mtg_engine.init_game()
  let mana =
    types.ManaProduced(
      white: 10,
      blue: 10,
      black: 10,
      red: 10,
      green: 10,
      colorless: 10,
    )

  // Advance to end of turn and produce lots of mana
  let game = pass_until(types.Cleanup, game)
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Verify mana is there
  let assert Ok(p1) = list.find(game_with_mana.players, fn(p) { p.id == 1 })
  assert p1.mana_pool.white == 10

  // Advance to next player's turn
  let game_next_turn = pass_both(game_with_mana)
  assert game_next_turn.active_player_id == 2

  // Player 1's mana should be cleared
  let assert Ok(p1_after) =
    list.find(game_next_turn.players, fn(p) { p.id == 1 })
  assert p1_after.mana_pool.white == 0
  assert p1_after.mana_pool.blue == 0
  assert p1_after.mana_pool.black == 0
  assert p1_after.mana_pool.red == 0
  assert p1_after.mana_pool.green == 0
  assert p1_after.mana_pool.colorless == 0
}

// Play Land Tests

// Helper function to create a test land card
fn create_test_land(id: String, name: String) -> types.Card {
  types.Card(
    id: id,
    name: name,
    card_type: types.Land,
    mana_cost: [],
    power: option.None,
    toughness: option.None,
  )
}

// Helper function to create a test creature card
fn create_test_creature(id: String, name: String) -> types.Card {
  types.Card(
    id: id,
    name: name,
    card_type: types.Creature,
    mana_cost: [types.Green],
    power: option.Some(2),
    toughness: option.Some(2),
  )
}

// Helper function to add a card to a player's hand
fn add_card_to_hand(
  game: types.GameState,
  player_id: Int,
  card: types.Card,
) -> types.GameState {
  types.GameState(
    ..game,
    players: list.map(game.players, fn(p) {
      case p.id == player_id {
        True -> types.Player(..p, hand: [card, ..p.hand])
        False -> p
      }
    }),
  )
}

// Test playing a land successfully
pub fn play_land_success_test() {
  let game = mtg_engine.init_game()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Play the land
  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.PlayLand(1, "land1"))

  // Verify land moved from hand to battlefield
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert list.length(player1.hand) == 0
  assert list.length(player1.battlefield) == 1
  assert list.any(player1.battlefield, fn(c) { c.id == "land1" })

  // Verify lands_played_this_turn incremented
  assert player1.lands_played_this_turn == 1
}

// Test land-per-turn limit
pub fn play_land_already_played_this_turn_test() {
  let game = mtg_engine.init_game()
  let land1 = create_test_land("land1", "Forest")
  let land2 = create_test_land("land2", "Mountain")

  // Add both lands to player 1's hand
  let game = add_card_to_hand(game, 1, land1)
  let game = add_card_to_hand(game, 1, land2)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Play first land successfully
  let assert Ok(game_after_land1) =
    mtg_engine.dispatch(game, types.PlayLand(1, "land1"))

  // Try to play second land - should fail
  let result = mtg_engine.dispatch(game_after_land1, types.PlayLand(1, "land2"))
  assert result == Error(types.InvalidAction("Already played a land this turn"))
}

// Test playing land in wrong phase
pub fn play_land_wrong_phase_test() {
  let game = mtg_engine.init_game()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Try to play in Upkeep (wrong phase)
  let game = pass_until(types.Upkeep, game)

  let result = mtg_engine.dispatch(game, types.PlayLand(1, "land1"))
  assert result
    == Error(types.InvalidAction("Can only play a land during a main phase"))
}

// Test playing land from PostCombatMain phase
pub fn play_land_postcombat_main_test() {
  let game = mtg_engine.init_game()
  let land = create_test_land("land1", "Island")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Advance to PostCombatMain
  let game = pass_until(types.PostCombatMain, game)

  // Play the land
  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.PlayLand(1, "land1"))

  // Verify land moved to battlefield
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert list.length(player1.battlefield) == 1
}

// Test only active player can play land
pub fn play_land_not_active_player_test() {
  let game = mtg_engine.init_game()
  let land = create_test_land("land1", "Plains")

  // Add land to player 2's hand
  let game = add_card_to_hand(game, 2, land)

  // Advance to PreCombatMain (player 1 is active)
  let game = pass_until(types.PreCombatMain, game)

  // Player 2 tries to play land - should fail
  let result = mtg_engine.dispatch(game, types.PlayLand(2, "land1"))
  assert result
    == Error(types.InvalidAction("Only the active player can play a land"))
}

// Test card not in hand
pub fn play_land_not_in_hand_test() {
  let game = mtg_engine.init_game()

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Try to play a land that's not in hand
  let result = mtg_engine.dispatch(game, types.PlayLand(1, "nonexistent"))
  assert result == Error(types.InvalidAction("Card not found in hand"))
}

// Test card is not a land
pub fn play_land_not_a_land_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Try to play creature as land - should fail
  let result = mtg_engine.dispatch(game, types.PlayLand(1, "creature1"))
  assert result == Error(types.InvalidAction("Card is not a land"))
}

// Test lands_played_this_turn resets on new turn
pub fn lands_played_resets_on_new_turn_test() {
  let game = mtg_engine.init_game()
  let land1 = create_test_land("land1", "Forest")
  let land2 = create_test_land("land2", "Mountain")

  // Add lands to player 1's hand
  let game = add_card_to_hand(game, 1, land1)
  let game = add_card_to_hand(game, 1, land2)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Play first land
  let assert Ok(game_after_land1) =
    mtg_engine.dispatch(game, types.PlayLand(1, "land1"))

  // Verify lands_played_this_turn is 1
  let assert Ok(p1) = list.find(game_after_land1.players, fn(p) { p.id == 1 })
  assert p1.lands_played_this_turn == 1

  // Advance to end of turn and into next player's turn
  let game = pass_until(types.Cleanup, game_after_land1)
  let game = pass_both(game)

  // Complete player 2's turn
  let game = pass_until(types.Cleanup, game)
  let game = pass_both(game)

  // Now player 1's turn 2 - lands_played_this_turn should be reset
  let assert Ok(p1_turn2) = list.find(game.players, fn(p) { p.id == 1 })
  assert p1_turn2.lands_played_this_turn == 0

  // Should be able to play second land now
  let game = pass_until(types.PreCombatMain, game)
  let assert Ok(_new_game) =
    mtg_engine.dispatch(game, types.PlayLand(1, "land2"))
}

// Test must have priority to play land
pub fn play_land_without_priority_test() {
  let game = mtg_engine.init_game()
  let land = create_test_land("land1", "Swamp")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Pass priority so player 2 has priority
  let assert Ok(game_p2_priority) =
    mtg_engine.dispatch(game, types.PassPriority)
  assert game_p2_priority.priority_player_id == 2

  // Try to play land as player 1 without priority - should fail
  let result = mtg_engine.dispatch(game_p2_priority, types.PlayLand(1, "land1"))
  assert result
    == Error(types.InvalidAction("Can only play a land when you have priority"))
}

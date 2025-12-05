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

  // Verify stack starts empty
  assert game.stack == []
}

// Test stack initialization
pub fn stack_starts_empty_test() {
  let game = mtg_engine.init_game()

  // Verify stack is an empty list
  assert game.stack == []
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
    mana_cost: types.ManaCost(
      generic: 0,
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    ),
    power: option.None,
    toughness: option.None,
    tapped: False,
  )
}

// Helper function to create a test creature card
fn create_test_creature(id: String, name: String) -> types.Card {
  types.Card(
    id: id,
    name: name,
    card_type: types.Creature,
    mana_cost: types.ManaCost(
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
    tapped: False,
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
  assert player1.hand == []
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
  assert result == Error(types.InvalidAction("Card not found"))
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

// Land Tapping Tests

// Helper function to add a land directly to battlefield
fn add_land_to_battlefield(
  game: types.GameState,
  player_id: Int,
  land: types.Card,
) -> types.GameState {
  types.GameState(
    ..game,
    players: list.map(game.players, fn(p) {
      case p.id == player_id {
        True -> types.Player(..p, battlefield: [land, ..p.battlefield])
        False -> p
      }
    }),
  )
}

// Test tapping a Forest for green mana
pub fn tap_forest_for_mana_test() {
  let game = mtg_engine.init_game()
  let forest = create_test_land("land1", "Forest")

  // Add forest to battlefield
  let game = add_land_to_battlefield(game, 1, forest)

  // Tap the forest for mana
  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))

  // Verify forest is tapped
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  let assert Ok(tapped_forest) =
    list.find(player1.battlefield, fn(c) { c.id == "land1" })
  assert tapped_forest.tapped == True

  // Verify green mana was added to pool
  assert player1.mana_pool.green == 1
  assert player1.mana_pool.white == 0
  assert player1.mana_pool.blue == 0
  assert player1.mana_pool.black == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.colorless == 0
}

// Test tapping a Mountain for red mana
pub fn tap_mountain_for_mana_test() {
  let game = mtg_engine.init_game()
  let mountain = create_test_land("land1", "Mountain")

  // Add mountain to battlefield
  let game = add_land_to_battlefield(game, 1, mountain)

  // Tap the mountain for mana
  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))

  // Verify red mana was added to pool
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.red == 1
  assert player1.mana_pool.green == 0
}

// Test tapping an Island for blue mana
pub fn tap_island_for_mana_test() {
  let game = mtg_engine.init_game()
  let island = create_test_land("land1", "Island")

  // Add island to battlefield
  let game = add_land_to_battlefield(game, 1, island)

  // Tap the island for mana
  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))

  // Verify blue mana was added to pool
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.blue == 1
}

// Test tapping a Plains for white mana
pub fn tap_plains_for_mana_test() {
  let game = mtg_engine.init_game()
  let plains = create_test_land("land1", "Plains")

  // Add plains to battlefield
  let game = add_land_to_battlefield(game, 1, plains)

  // Tap the plains for mana
  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))

  // Verify white mana was added to pool
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.white == 1
}

// Test tapping a Swamp for black mana
pub fn tap_swamp_for_mana_test() {
  let game = mtg_engine.init_game()
  let swamp = create_test_land("land1", "Swamp")

  // Add swamp to battlefield
  let game = add_land_to_battlefield(game, 1, swamp)

  // Tap the swamp for mana
  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))

  // Verify black mana was added to pool
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.black == 1
}

// Test cannot tap already tapped land
pub fn tap_already_tapped_land_test() {
  let game = mtg_engine.init_game()
  let forest = create_test_land("land1", "Forest")

  // Add forest to battlefield
  let game = add_land_to_battlefield(game, 1, forest)

  // Tap the forest once
  let assert Ok(game_after_tap) =
    mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))

  // Try to tap it again - should fail
  let result =
    mtg_engine.dispatch(game_after_tap, types.TapLandForMana(1, "land1"))
  assert result == Error(types.InvalidAction("Land is already tapped"))
}

// Test cannot tap land not on battlefield
pub fn tap_land_not_on_battlefield_test() {
  let game = mtg_engine.init_game()
  let forest = create_test_land("land1", "Forest")

  // Add forest to hand instead of battlefield
  let game = add_card_to_hand(game, 1, forest)

  // Try to tap it - should fail
  let result = mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))
  assert result == Error(types.InvalidAction("Card not found"))
}

// Test cannot tap non-land permanent
pub fn tap_non_land_for_mana_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield
  let game = add_land_to_battlefield(game, 1, creature)

  // Try to tap it for mana - should fail
  let result = mtg_engine.dispatch(game, types.TapLandForMana(1, "creature1"))
  assert result == Error(types.InvalidAction("Card is not a land"))
}

// Test land enters battlefield untapped
pub fn land_enters_untapped_test() {
  let game = mtg_engine.init_game()
  let forest = create_test_land("land1", "Forest")

  // Add forest to player 1's hand
  let game = add_card_to_hand(game, 1, forest)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Play the land
  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.PlayLand(1, "land1"))

  // Verify land is on battlefield and untapped
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  let assert Ok(land_on_battlefield) =
    list.find(player1.battlefield, fn(c) { c.id == "land1" })
  assert land_on_battlefield.tapped == False
}

// Test lands untap during untap step
pub fn lands_untap_during_untap_step_test() {
  let game = mtg_engine.init_game()
  let forest = create_test_land("land1", "Forest")
  let mountain = create_test_land("land2", "Mountain")

  // Add lands to battlefield
  let game = add_land_to_battlefield(game, 1, forest)
  let game = add_land_to_battlefield(game, 1, mountain)

  // Tap both lands
  let assert Ok(game_after_tap1) =
    mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))
  let assert Ok(game_after_tap2) =
    mtg_engine.dispatch(game_after_tap1, types.TapLandForMana(1, "land2"))

  // Verify both lands are tapped
  let assert Ok(p1) = list.find(game_after_tap2.players, fn(p) { p.id == 1 })
  let assert Ok(land1) = list.find(p1.battlefield, fn(c) { c.id == "land1" })
  let assert Ok(land2) = list.find(p1.battlefield, fn(c) { c.id == "land2" })
  assert land1.tapped == True
  assert land2.tapped == True

  // Advance to end of turn
  let game = pass_until(types.Cleanup, game_after_tap2)

  // Advance to next player's turn (which skips through Untap step)
  let game = pass_both(game)

  // Advance back to player 1's turn (this will trigger untap)
  let game = pass_until(types.Cleanup, game)
  let game = pass_both(game)

  // Verify lands are now untapped
  let assert Ok(p1_after) = list.find(game.players, fn(p) { p.id == 1 })
  let assert Ok(land1_after) =
    list.find(p1_after.battlefield, fn(c) { c.id == "land1" })
  let assert Ok(land2_after) =
    list.find(p1_after.battlefield, fn(c) { c.id == "land2" })
  assert land1_after.tapped == False
  assert land2_after.tapped == False
}

// Test tapping multiple lands accumulates mana
pub fn tap_multiple_lands_accumulates_mana_test() {
  let game = mtg_engine.init_game()
  let forest1 = create_test_land("land1", "Forest")
  let forest2 = create_test_land("land2", "Forest")
  let mountain = create_test_land("land3", "Mountain")

  // Add lands to battlefield
  let game = add_land_to_battlefield(game, 1, forest1)
  let game = add_land_to_battlefield(game, 1, forest2)
  let game = add_land_to_battlefield(game, 1, mountain)

  // Tap all three lands
  let assert Ok(game_after_tap1) =
    mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))
  let assert Ok(game_after_tap2) =
    mtg_engine.dispatch(game_after_tap1, types.TapLandForMana(1, "land2"))
  let assert Ok(game_after_tap3) =
    mtg_engine.dispatch(game_after_tap2, types.TapLandForMana(1, "land3"))

  // Verify mana accumulated correctly
  let assert Ok(player1) =
    list.find(game_after_tap3.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.green == 2
  assert player1.mana_pool.red == 1
}

// Test only active player's lands untap
pub fn only_active_player_lands_untap_test() {
  let game = mtg_engine.init_game()
  let forest_p1 = create_test_land("land1", "Forest")
  let mountain_p2 = create_test_land("land2", "Mountain")

  // Add lands to both players' battlefields
  let game = add_land_to_battlefield(game, 1, forest_p1)
  let game = add_land_to_battlefield(game, 2, mountain_p2)

  // Tap both lands
  let assert Ok(game_after_tap1) =
    mtg_engine.dispatch(game, types.TapLandForMana(1, "land1"))
  let assert Ok(game_after_tap2) =
    mtg_engine.dispatch(game_after_tap1, types.TapLandForMana(2, "land2"))

  // Verify both are tapped
  let assert Ok(p1) = list.find(game_after_tap2.players, fn(p) { p.id == 1 })
  let assert Ok(p2) = list.find(game_after_tap2.players, fn(p) { p.id == 2 })
  let assert Ok(land1) = list.find(p1.battlefield, fn(c) { c.id == "land1" })
  let assert Ok(land2) = list.find(p2.battlefield, fn(c) { c.id == "land2" })
  assert land1.tapped == True
  assert land2.tapped == True

  // Advance to next player's turn (player 2)
  let game = pass_until(types.Cleanup, game_after_tap2)
  let game = pass_both(game)

  // Player 2's lands should untap, player 1's should stay tapped
  let assert Ok(p1_after) = list.find(game.players, fn(p) { p.id == 1 })
  let assert Ok(p2_after) = list.find(game.players, fn(p) { p.id == 2 })
  let assert Ok(land1_after) =
    list.find(p1_after.battlefield, fn(c) { c.id == "land1" })
  let assert Ok(land2_after) =
    list.find(p2_after.battlefield, fn(c) { c.id == "land2" })
  assert land1_after.tapped == True
  assert land2_after.tapped == False
}

// Cast Creature Tests

// Test casting a creature successfully
pub fn cast_creature_success_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add green mana to player 1's pool
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify creature is no longer in hand
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.hand == []

  // Verify creature is on the stack
  assert list.length(new_game.stack) == 1
  let assert Ok(stack_item) = list.first(new_game.stack)
  assert stack_item.card.id == "creature1"
  assert stack_item.controller_id == 1

  // Verify mana was paid
  assert player1.mana_pool.green == 0

  // Verify player retains priority
  assert new_game.priority_player_id == 1
}

// Test casting creature with multiple mana colors
pub fn cast_creature_multicolor_mana_test() {
  let game = mtg_engine.init_game()
  let creature =
    types.Card(
      id: "creature1",
      name: "Multicolor Bear",
      card_type: types.Creature,
      mana_cost: types.ManaCost(
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
      tapped: False,
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana to player 1's pool
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 1,
      black: 0,
      red: 1,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify mana was paid correctly
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.red == 0
  assert player1.mana_pool.blue == 0

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1
}

// Test cannot cast creature without enough mana
pub fn cast_creature_not_enough_mana_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Try to cast without mana - should fail
  let result = mtg_engine.dispatch(game, types.CastCreature(1, "creature1"))
  assert result
    == Error(types.InvalidAction("Not enough mana to cast this spell"))
}

// Test cannot cast creature with wrong color mana
pub fn cast_creature_wrong_mana_color_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add red mana instead of green
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 1,
      green: 0,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Try to cast - should fail
  let result =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))
  assert result
    == Error(types.InvalidAction("Not enough mana to cast this spell"))
}

// Test cannot cast creature in wrong phase
pub fn cast_creature_wrong_phase_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Stay in Upkeep (wrong phase)
  let game = pass_until(types.Upkeep, game)

  // Add mana
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Try to cast - should fail
  let result =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))
  assert result
    == Error(types.InvalidAction("Can only cast creatures during a main phase"))
}

// Test can cast creature in PostCombatMain phase
pub fn cast_creature_postcombat_main_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PostCombatMain
  let game = pass_until(types.PostCombatMain, game)

  // Add mana
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1
}

// Test cannot cast creature without priority
pub fn cast_creature_without_priority_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Pass priority to player 2
  let assert Ok(game_p2_priority) =
    mtg_engine.dispatch(game_with_mana, types.PassPriority)
  assert game_p2_priority.priority_player_id == 2

  // Try to cast as player 1 without priority - should fail
  let result =
    mtg_engine.dispatch(game_p2_priority, types.CastCreature(1, "creature1"))
  assert result
    == Error(types.InvalidAction("Can only cast spells when you have priority"))
}

// Test non-active player cannot cast
pub fn cast_creature_not_active_player_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 2's hand
  let game = add_card_to_hand(game, 2, creature)

  // Advance to PreCombatMain (player 1 is active)
  let game = pass_until(types.PreCombatMain, game)

  // Add mana to player 2
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(2, mana))

  // Player 2 tries to cast - should fail
  let result =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(2, "creature1"))
  assert result
    == Error(types.InvalidAction("Only the active player can cast spells"))
}

// Test card not in hand
pub fn cast_creature_not_in_hand_test() {
  let game = mtg_engine.init_game()

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Try to cast a card that's not in hand
  let result =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "nonexistent"))
  assert result == Error(types.InvalidAction("Card not found"))
}

// Test cannot cast non-creature card
pub fn cast_creature_not_a_creature_test() {
  let game = mtg_engine.init_game()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let game = add_card_to_hand(game, 1, land)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Try to cast land as creature - should fail
  let result = mtg_engine.dispatch(game, types.CastCreature(1, "land1"))
  assert result == Error(types.InvalidAction("Card is not a creature"))
}

// Test cannot cast creature when stack is not empty (sorcery-speed restriction)
pub fn cast_creature_stack_not_empty_test() {
  let game = mtg_engine.init_game()
  let creature1 = create_test_creature("creature1", "Grizzly Bears")
  let creature2 =
    types.Card(
      id: "creature2",
      name: "Another Bear",
      card_type: types.Creature,
      mana_cost: types.ManaCost(
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
      tapped: False,
    )

  // Add both creatures to player 1's hand
  let game = add_card_to_hand(game, 1, creature1)
  let game = add_card_to_hand(game, 1, creature2)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 2,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Cast first creature
  let assert Ok(game_after_cast1) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify stack is not empty
  assert list.length(game_after_cast1.stack) == 1

  // Try to cast second creature while first is on stack - should fail
  let result =
    mtg_engine.dispatch(game_after_cast1, types.CastCreature(1, "creature2"))
  assert result
    == Error(types.InvalidAction(
      "Can only cast creatures when the stack is empty",
    ))
}

// Test player retains priority after casting
pub fn cast_creature_retains_priority_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Verify player 1 has priority
  assert game_with_mana.priority_player_id == 1

  // Cast creature
  let assert Ok(new_game) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify player 1 still has priority
  assert new_game.priority_player_id == 1
}

// Test casting creature with zero-cost
pub fn cast_creature_zero_cost_test() {
  let game = mtg_engine.init_game()
  let creature =
    types.Card(
      id: "creature1",
      name: "Free Bear",
      card_type: types.Creature,
      mana_cost: types.ManaCost(
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
      tapped: False,
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Cast the creature (no mana needed)
  let assert Ok(new_game) =
    mtg_engine.dispatch(game, types.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1
  let assert Ok(stack_item) = list.first(new_game.stack)
  assert stack_item.card.id == "creature1"
}

// Test casting creature with generic mana cost (2G for a 3/3)
pub fn cast_creature_with_generic_cost_test() {
  let game = mtg_engine.init_game()
  let creature =
    types.Card(
      id: "creature1",
      name: "Big Bear",
      card_type: types.Creature,
      mana_cost: types.ManaCost(
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
      tapped: False,
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana to player 1's pool (1G + 2 of any color)
  let mana =
    types.ManaProduced(
      white: 1,
      blue: 1,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1
  let assert Ok(stack_item) = list.first(new_game.stack)
  assert stack_item.card.id == "creature1"

  // Verify mana was paid (1G + 2 generic paid with white and blue)
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.white == 0
  assert player1.mana_pool.blue == 0
}

// Test cannot cast creature with generic cost when not enough total mana
pub fn cast_creature_generic_cost_not_enough_total_mana_test() {
  let game = mtg_engine.init_game()
  let creature =
    types.Card(
      id: "creature1",
      name: "Big Bear",
      card_type: types.Creature,
      mana_cost: types.ManaCost(
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
      tapped: False,
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add only 1G (need 2G total, missing 1 generic)
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Try to cast - should fail
  let result =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))
  assert result
    == Error(types.InvalidAction("Not enough mana to cast this spell"))
}

// Test casting creature with generic cost using any color
pub fn cast_creature_generic_cost_paid_with_any_color_test() {
  let game = mtg_engine.init_game()
  let creature =
    types.Card(
      id: "creature1",
      name: "Big Bear",
      card_type: types.Creature,
      mana_cost: types.ManaCost(
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
      tapped: False,
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana: 1G + 2R (red should be able to pay generic cost)
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 2,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))

  // Cast the creature
  let assert Ok(new_game) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(new_game.stack) == 1

  // Verify mana was paid
  let assert Ok(player1) = list.find(new_game.players, fn(p) { p.id == 1 })
  assert player1.mana_pool.green == 0
  assert player1.mana_pool.red == 0
}

// Spell Resolution Tests

// Test resolving a creature spell from the stack
pub fn resolve_creature_spell_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(game_after_cast.stack) == 1

  // Both players pass priority - spell resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify creature moved from stack to battlefield
  assert game_after_resolve.stack == []
  let assert Ok(player1) =
    list.find(game_after_resolve.players, fn(p) { p.id == 1 })
  assert list.length(player1.battlefield) == 1

  // Verify creature is on battlefield with correct properties
  let assert Ok(creature_on_battlefield) =
    list.find(player1.battlefield, fn(c) { c.id == "creature1" })
  assert creature_on_battlefield.name == "Grizzly Bears"
  assert creature_on_battlefield.power == option.Some(2)
  assert creature_on_battlefield.toughness == option.Some(2)
}

// Test creature enters battlefield untapped
pub fn creature_enters_untapped_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Both players pass priority - spell resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify creature is untapped on battlefield
  let assert Ok(player1) =
    list.find(game_after_resolve.players, fn(p) { p.id == 1 })
  let assert Ok(creature_on_battlefield) =
    list.find(player1.battlefield, fn(c) { c.id == "creature1" })
  assert creature_on_battlefield.tapped == False
}

// Test cannot resolve from empty stack
pub fn resolve_empty_stack_test() {
  let game = mtg_engine.init_game()

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // When both players pass with empty stack, should just advance step
  // (not error - this is normal behavior)
  let game_after_pass = pass_both(game)

  // Should have advanced to next step, not errored
  assert game_after_pass.current_step == types.BeginCombat
}

// Test resolving puts creature on controller's battlefield
pub fn resolve_creature_to_controller_battlefield_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Both players pass priority - spell resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify creature is on player 1's battlefield only
  let assert Ok(player1) =
    list.find(game_after_resolve.players, fn(p) { p.id == 1 })
  let assert Ok(player2) =
    list.find(game_after_resolve.players, fn(p) { p.id == 2 })
  assert list.length(player1.battlefield) == 1
  assert player2.battlefield == []
  assert list.any(player1.battlefield, fn(c) { c.id == "creature1" })
}

// Test resolving multiple creatures in sequence
pub fn resolve_multiple_creatures_test() {
  let game = mtg_engine.init_game()
  let creature1 = create_test_creature("creature1", "Grizzly Bears")
  let creature2 =
    types.Card(
      id: "creature2",
      name: "Another Bear",
      card_type: types.Creature,
      mana_cost: types.ManaCost(
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
      tapped: False,
    )

  // Add creatures to player 1's hand
  let game = add_card_to_hand(game, 1, creature1)
  let game = add_card_to_hand(game, 1, creature2)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast first creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 2,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast1) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify first creature is on stack
  assert list.length(game_after_cast1.stack) == 1

  // Both players pass priority - first creature resolves automatically
  let game_after_resolve1 = pass_both(game_after_cast1)

  // Verify stack is empty and creature is on battlefield
  assert game_after_resolve1.stack == []
  let assert Ok(p1_after_first) =
    list.find(game_after_resolve1.players, fn(p) { p.id == 1 })
  assert list.length(p1_after_first.battlefield) == 1

  // Cast second creature
  let assert Ok(game_after_cast2) =
    mtg_engine.dispatch(game_after_resolve1, types.CastCreature(1, "creature2"))

  // Verify second creature is on stack
  assert list.length(game_after_cast2.stack) == 1

  // Both players pass priority - second creature resolves automatically
  let game_after_resolve2 = pass_both(game_after_cast2)

  // Verify both creatures are on battlefield
  let assert Ok(p1_final) =
    list.find(game_after_resolve2.players, fn(p) { p.id == 1 })
  assert list.length(p1_final.battlefield) == 2
  assert list.any(p1_final.battlefield, fn(c) { c.id == "creature1" })
  assert list.any(p1_final.battlefield, fn(c) { c.id == "creature2" })
}

// Test creature retains power and toughness when resolving
pub fn resolve_creature_retains_stats_test() {
  let game = mtg_engine.init_game()
  let creature =
    types.Card(
      id: "creature1",
      name: "Big Creature",
      card_type: types.Creature,
      mana_cost: types.ManaCost(
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
      tapped: False,
    )

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Both players pass priority - spell resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify creature has correct stats
  let assert Ok(player1) =
    list.find(game_after_resolve.players, fn(p) { p.id == 1 })
  let assert Ok(creature_on_battlefield) =
    list.find(player1.battlefield, fn(c) { c.id == "creature1" })
  assert creature_on_battlefield.power == option.Some(5)
  assert creature_on_battlefield.toughness == option.Some(4)
}

// Automatic Resolution Tests

// Test spell automatically resolves when all players pass priority
pub fn automatic_resolution_when_all_pass_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify creature is on stack
  assert list.length(game_after_cast.stack) == 1

  // Both players pass priority - should automatically resolve
  let game_after_pass = pass_both(game_after_cast)

  // Verify creature resolved automatically to battlefield
  assert game_after_pass.stack == []
  let assert Ok(player1) =
    list.find(game_after_pass.players, fn(p) { p.id == 1 })
  assert list.length(player1.battlefield) == 1
  assert list.any(player1.battlefield, fn(c) { c.id == "creature1" })
}

// Test priority resets to active player after automatic resolution
pub fn automatic_resolution_resets_priority_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Both players pass priority - should resolve and reset priority
  let game_after_pass = pass_both(game_after_cast)

  // Priority should go back to active player
  assert game_after_pass.priority_player_id == game_after_pass.active_player_id
  assert game_after_pass.priority_player_id == 1

  // Consecutive passes should be reset
  assert game_after_pass.consecutive_passes == 0
}

// Test multiple spells resolve in LIFO order
pub fn automatic_resolution_lifo_order_test() {
  let game = mtg_engine.init_game()
  let creature1 = create_test_creature("creature1", "First Bear")
  let creature2 =
    types.Card(
      id: "creature2",
      name: "Second Bear",
      card_type: types.Creature,
      mana_cost: types.ManaCost(
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
      tapped: False,
    )

  // Add creatures to player 1's hand
  let game = add_card_to_hand(game, 1, creature1)
  let game = add_card_to_hand(game, 1, creature2)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast first creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 2,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast1) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Both players pass - first creature resolves
  let game_after_first_resolve = pass_both(game_after_cast1)

  // Verify first creature resolved
  assert game_after_first_resolve.stack == []
  let assert Ok(p1_after_first) =
    list.find(game_after_first_resolve.players, fn(p) { p.id == 1 })
  assert list.length(p1_after_first.battlefield) == 1

  // Cast second creature
  let assert Ok(game_after_cast2) =
    mtg_engine.dispatch(
      game_after_first_resolve,
      types.CastCreature(1, "creature2"),
    )

  // Both players pass - second creature resolves
  let game_after_second_resolve = pass_both(game_after_cast2)

  // Verify both creatures are on battlefield
  let assert Ok(p1_final) =
    list.find(game_after_second_resolve.players, fn(p) { p.id == 1 })
  assert list.length(p1_final.battlefield) == 2
  assert list.any(p1_final.battlefield, fn(c) { c.id == "creature1" })
  assert list.any(p1_final.battlefield, fn(c) { c.id == "creature2" })
}

// Test cannot play land while spell is on stack
pub fn cannot_play_land_with_stack_not_empty_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")
  let land = create_test_land("land1", "Forest")

  // Add both to player 1's hand
  let game = add_card_to_hand(game, 1, creature)
  let game = add_card_to_hand(game, 1, land)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Verify stack is not empty
  assert list.length(game_after_cast.stack) == 1

  // Try to play land - should fail
  let result = mtg_engine.dispatch(game_after_cast, types.PlayLand(1, "land1"))
  assert result
    == Error(types.InvalidAction(
      "Cannot play a land while the stack is not empty",
    ))
}

// Test players get priority after spell resolves
pub fn priority_after_automatic_resolution_test() {
  let game = mtg_engine.init_game()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let game = add_card_to_hand(game, 1, creature)

  // Advance to PreCombatMain
  let game = pass_until(types.PreCombatMain, game)

  // Add mana and cast the creature
  let mana =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
  let assert Ok(game_with_mana) =
    mtg_engine.dispatch(game, types.ProduceMana(1, mana))
  let assert Ok(game_after_cast) =
    mtg_engine.dispatch(game_with_mana, types.CastCreature(1, "creature1"))

  // Both players pass - creature resolves automatically
  let game_after_resolve = pass_both(game_after_cast)

  // Verify players can take actions after resolution (priority works)
  // Priority should be with active player
  assert game_after_resolve.priority_player_id == 1

  // Player 1 should be able to pass priority
  let assert Ok(game_after_pass) =
    mtg_engine.dispatch(game_after_resolve, types.PassPriority)
  assert game_after_pass.priority_player_id == 2
}

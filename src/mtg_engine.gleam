import gleam/io
import gleam/list

import types.{type Action, type Error, type GameState, type Player}

pub fn main() -> Nil {
  io.println("Hello from mtg_engine!")
}

// Initialize a new game with two players
pub fn init_game() -> GameState {
  let player1 =
    types.Player(
      id: 1,
      life: 20,
      hand: [],
      battlefield: [],
      graveyard: [],
      library: [],
      exile: [],
    )

  let player2 =
    types.Player(
      id: 2,
      life: 20,
      hand: [],
      battlefield: [],
      graveyard: [],
      library: [],
      exile: [],
    )

  types.GameState(
    players: [player1, player2],
    active_player_id: 1,
    priority_player_id: 1,
    current_step: types.Untap,
    consecutive_passes: 0,
    turn_number: 1,
  )
}

// Main dispatch function - handles all game actions
pub fn dispatch(state: GameState, action: Action) -> Result(GameState, Error) {
  case action {
    types.PassPriority -> Ok(handle_pass_priority(state))
  }
}

// Get the next step in the turn sequence
fn get_next_step(current_step: types.Step) -> types.Step {
  case current_step {
    types.Untap -> types.Upkeep
    types.Upkeep -> types.Draw
    types.Draw -> types.PreCombatMain
    types.PreCombatMain -> types.BeginCombat
    types.BeginCombat -> types.DeclareAttackers
    types.DeclareAttackers -> types.DeclareBlockers
    types.DeclareBlockers -> types.CombatDamage
    types.CombatDamage -> types.EndCombat
    types.EndCombat -> types.PostCombatMain
    types.PostCombatMain -> types.EndStep
    types.EndStep -> types.Cleanup
    types.Cleanup -> types.Untap
  }
}

// Get the next active player (for when turn ends)
fn get_next_player(state: GameState, current_player_id: Int) -> Player {
  let assert [_cur, ..rest] =
    list.drop_while(state.players, fn(p) { p.id != current_player_id })
  case rest {
    [] -> {
      let assert Ok(first_player) = list.first(state.players)
      first_player
    }
    [next_player, ..] -> next_player
  }
}

// Advance to the next step/phase
fn advance_step(state: GameState) -> GameState {
  let next_step = get_next_step(state.current_step)
  let assert Ok(first_player) = list.first(state.players)

  // Check if we're transitioning to a new turn (next step is Untap)
  case next_step {
    types.Untap -> {
      // Move to next player's turn
      let next_active_player = get_next_player(state, state.active_player_id)

      // Increment turn number if we're back to the first player
      let new_turn_number = case next_active_player.id == first_player.id {
        True -> state.turn_number + 1
        False -> state.turn_number
      }

      // Since Untap has no priority, immediately advance to Upkeep
      types.GameState(
        ..state,
        active_player_id: next_active_player.id,
        priority_player_id: next_active_player.id,
        current_step: types.Upkeep,
        consecutive_passes: 0,
        turn_number: new_turn_number,
      )
    }
    types.Draw
      if state.turn_number == 1 && state.active_player_id == first_player.id
    ->
      types.GameState(
        ..state,
        current_step: types.PreCombatMain,
        priority_player_id: state.active_player_id,
        consecutive_passes: 0,
      )
    types.Draw ->
      types.GameState(
        ..state,
        current_step: types.Draw,
        priority_player_id: state.active_player_id,
        consecutive_passes: 0,
      )
    _ -> {
      // Normal step advancement within a turn
      // Priority goes to active player when entering a new step
      types.GameState(
        ..state,
        current_step: next_step,
        priority_player_id: state.active_player_id,
        consecutive_passes: 0,
      )
    }
  }
}

fn handle_pass_priority(state: GameState) -> GameState {
  let new_consecutive_passes = state.consecutive_passes + 1
  let num_players = list.length(state.players)

  // Check if all players have passed
  case new_consecutive_passes >= num_players {
    True -> {
      // All players passed, advance to next step
      advance_step(state)
    }
    False -> {
      // Not all players passed yet, give priority to next player
      let next_player = get_next_player(state, state.priority_player_id)

      types.GameState(
        ..state,
        priority_player_id: next_player.id,
        consecutive_passes: new_consecutive_passes,
      )
    }
  }
}

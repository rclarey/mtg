import gleam/bool
import gleam/list
import mtg_engine/card
import mtg_engine/error
import mtg_engine/permanent
import mtg_engine/player

pub type Zone {
  Hand
  Battlefield
  Graveyard
  Library
  Stack
  Exile
}

pub type Step {
  // Beginning phase
  Untap
  Upkeep
  Draw
  // Pre-combat main phase
  PreCombatMain
  // Combat phase
  BeginCombat
  DeclareAttackers
  DeclareBlockers
  CombatDamage
  EndCombat
  // Post-combat main phase
  PostCombatMain
  // End phase
  EndStep
  Cleanup
}

pub type StackItem {
  StackItem(
    card: card.Card,
    controller_id: Int,
    // Targets will be added in later phases when targeting is implemented
  )
}

pub type State {
  State(
    players: List(player.Player),
    active_player_id: Int,
    priority_player_id: Int,
    current_step: Step,
    consecutive_passes: Int,
    turn_index: Int,
    stack: List(StackItem),
  )
}

pub fn new() -> State {
  let player1 = player.new(1)
  let player2 = player.new(2)

  State(
    players: [player1, player2],
    active_player_id: 1,
    priority_player_id: 1,
    current_step: Untap,
    consecutive_passes: 0,
    turn_index: 0,
    stack: [],
  )
}

// Calculate the turn cycle from turn_index
// Turn cycle increments after all players complete their turns
// With 2 players: turn_index 0,1 = cycle 0; turn_index 2,3 = cycle 1, etc.
pub fn turn_cycle(state: State) -> Int {
  let num_players = list.length(state.players)
  state.turn_index / num_players
}

pub fn next_player(state: State, current_player_id: Int) -> player.Player {
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

pub fn advance_step(state: State) -> State {
  let next_step = next_step(state.current_step)
  let assert Ok(first_player) = list.first(state.players)

  // Clear all mana pools when transitioning between steps (rule 106.4)
  let cleared_players = list.map(state.players, player.clear_mana_pool)

  // Check if we're transitioning to a new turn (next step is Untap)
  case next_step {
    Untap -> {
      // Move to next player's turn
      let next_active_player = next_player(state, state.active_player_id)

      // Reset lands_played_this_turn for all players
      let players_with_reset_lands =
        list.map(cleared_players, player.reset_lands_played)

      // Untap all permanents for the new active player (Untap step)
      let players_with_untapped =
        player.update(
          players_with_reset_lands,
          next_active_player.id,
          player.untap_permanents,
        )

      // Since Untap has no priority, immediately advance to Upkeep
      State(
        ..state,
        players: players_with_untapped,
        active_player_id: next_active_player.id,
        priority_player_id: next_active_player.id,
        current_step: Upkeep,
        consecutive_passes: 0,
        turn_index: state.turn_index + 1,
      )
    }
    Draw if state.turn_index == 0 && state.active_player_id == first_player.id ->
      State(
        ..state,
        players: cleared_players,
        current_step: PreCombatMain,
        priority_player_id: state.active_player_id,
        consecutive_passes: 0,
      )
    Draw ->
      State(
        ..state,
        players: cleared_players,
        current_step: Draw,
        priority_player_id: state.active_player_id,
        consecutive_passes: 0,
      )
    _ -> {
      // Normal step advancement within a turn
      // Priority goes to active player when entering a new step
      State(
        ..state,
        players: cleared_players,
        current_step: next_step,
        priority_player_id: state.active_player_id,
        consecutive_passes: 0,
      )
    }
  }
}

fn next_step(current_step: Step) -> Step {
  case current_step {
    Untap -> Upkeep
    Upkeep -> Draw
    Draw -> PreCombatMain
    PreCombatMain -> BeginCombat
    BeginCombat -> DeclareAttackers
    DeclareAttackers -> DeclareBlockers
    DeclareBlockers -> CombatDamage
    CombatDamage -> EndCombat
    EndCombat -> PostCombatMain
    PostCombatMain -> EndStep
    EndStep -> Cleanup
    Cleanup -> Untap
  }
}

pub fn resolve_top_of_stack(state: State) -> Result(State, error.Error) {
  // Validate: stack must not be empty
  use <- bool.guard(
    state.stack == [],
    Error(error.InvalidAction("Cannot resolve spell from empty stack")),
  )

  // Get the top item from the stack
  let assert [top_item, ..remaining_stack] = state.stack

  // For now, we only handle creature spells
  // In the future, this will be extended for other spell types
  use <- bool.guard(
    top_item.card.card_type != card.Creature,
    Error(error.InvalidAction("Can only resolve creature spells currently")),
  )

  // Move the creature from the stack to the battlefield
  // Creatures enter the battlefield untapped
  // Record the turn cycle when the creature entered (for summoning sickness)
  let current_cycle = turn_cycle(state)
  let creature_permanent =
    permanent.from_card(
      top_item.card,
      top_item.controller_id,
      current_cycle,
    )

  // Update the controller's battlefield
  let new_players =
    player.update(state.players, top_item.controller_id, fn(p) {
      player.Player(..p, battlefield: [creature_permanent, ..p.battlefield])
    })

  Ok(State(..state, players: new_players, stack: remaining_stack))
}

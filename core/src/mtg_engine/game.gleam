import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
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
  DeclareBlockers(declaring_player_id: Option(Int))
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

pub type AttackPair {
  AttackPair(attacker: String, target: AttackTarget)
}

pub type AttackTarget {
  AttackPlayer(player_id: Int)
  // TODO add planeswalkers and battles
}

pub type BlockPair {
  BlockPair(blocker: String, attacker: String)
}

pub type State {
  State(
    players: List(player.Player),
    active_player: Int,
    priority_player: Option(Int),
    step: Step,
    consecutive_passes: Int,
    turn_index: Int,
    stack: List(StackItem),
    // None means attackers not yet declared, Some([]) means no attackers, Some([pairs]) means attackers declared
    attacking_creatures: Option(List(AttackPair)),
    blocking_creatures: List(BlockPair),
  )
}

pub fn new() -> State {
  new_multiplayer(2)
}

pub fn new_multiplayer(n: Int) -> State {
  let players = list.range(1, n) |> list.map(player.new)
  State(
    players:,
    active_player: 1,
    priority_player: None,
    step: Untap,
    consecutive_passes: 0,
    turn_index: 0,
    stack: [],
    attacking_creatures: None,
    blocking_creatures: [],
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

// Given current declaring player, return next defender in APNAP order
// Returns None if this was the last defender
pub fn get_next_defending_player(
  state: State,
  current_player_id: Int,
) -> Option(Int) {
  case next_player(state, current_player_id) {
    player if player.id == state.active_player -> None
    player -> {
      use attackers <- option.then(state.attacking_creatures)
      let is_attacked =
        list.any(attackers, fn(attack) {
          case attack.target {
            AttackPlayer(id) -> id == player.id
          }
        })
      case is_attacked {
        True -> Some(player.id)
        False -> get_next_defending_player(state, player.id)
      }
    }
  }
}

pub fn advance_step(state: State) -> State {
  let step = next_step(state)
  let first_defender = case step {
    DeclareBlockers(_) -> get_next_defending_player(state, state.active_player)
    _ -> None
  }
  let priority_player = case step {
    Untap | DeclareAttackers | CombatDamage | Cleanup -> None
    DeclareBlockers(_) ->
      case first_defender {
        Some(_) -> None
        None -> Some(state.active_player)
      }
    _ -> Some(state.active_player)
  }

  // Clear all mana pools when transitioning between steps (rule 106.4)
  let players = list.map(state.players, player.clear_mana_pool)

  let state =
    State(..state, players:, priority_player:, step:, consecutive_passes: 0)

  case step {
    Untap -> {
      // Move to next player's turn
      let active_player = next_player(state, state.active_player)

      let players =
        // Reset lands_played_this_turn for all players
        list.map(players, player.reset_lands_played)
        // Untap all permanents for the new active player (Untap step)
        |> player.update(active_player.id, player.untap_permanents)

      State(
        ..state,
        players:,
        active_player: active_player.id,
        turn_index: state.turn_index + 1,
      )
    }
    DeclareBlockers(_) ->
      State(
        ..state,
        step: DeclareBlockers(first_defender),
        priority_player:,
        blocking_creatures: [],
      )
    PostCombatMain ->
      State(..state, attacking_creatures: None, blocking_creatures: [])
    _ -> state
  }
}

fn next_step(state: State) -> Step {
  case state.step {
    Untap -> Upkeep
    Upkeep -> {
      let assert Ok(first_player) = list.first(state.players)
      case state.turn_index == 0 && state.active_player == first_player.id {
        True -> PreCombatMain
        False -> Draw
      }
    }
    Draw -> PreCombatMain
    PreCombatMain -> BeginCombat
    BeginCombat -> DeclareAttackers
    DeclareAttackers -> DeclareBlockers(None)
    DeclareBlockers(_) -> CombatDamage
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
    permanent.from_card(top_item.card, top_item.controller_id, current_cycle)

  // Update the controller's battlefield
  let new_players =
    player.update(state.players, top_item.controller_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(
          p.battlefield,
          top_item.card.id,
          creature_permanent,
        ),
      )
    })

  Ok(State(..state, players: new_players, stack: remaining_stack))
}

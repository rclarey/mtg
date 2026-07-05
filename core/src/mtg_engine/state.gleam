import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import mtg_engine/ability
import mtg_engine/card
import mtg_engine/combat
import mtg_engine/effects
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/stack
import mtg_engine/step
import mtg_engine/targeting
import prng/random

pub type PendingTrigger {
  PendingTrigger(
    source_card: card.Card,
    controller: Int,
    ability: ability.TriggeredAbility,
    trigger_subject: Option(targeting.TargetIdentifier),
  )
}

/// Task 7: Pending Scry awaiting the player's reorder decision.
pub type ScryPending {
  ScryPending(num: Int, player_id: Int)
}

pub type State {
  State(
    players: List(player.Player),
    active_player: Int,
    priority_player: Option(Int),
    choice_player: Option(Int),
    step: step.Step,
    consecutive_passes: Int,
    turn_index: Int,
    stack: List(stack.StackItem),
    attacking_creatures: Option(List(combat.AttackPair)),
    blocking_creatures: List(combat.BlockPair),
    assigned_damage: List(combat.DamageAssignment),
    prevention_shields: Dict(String, Int),
    global_combat_prevention: Bool,
    pending_delayed_triggers: List(effects.DelayedTrigger),
    pending_optional_trigger: Option(PendingTrigger),
    pending_removed_sources: List(String),
    // Task 5: Extra turn queue (rule 500.7). Player ids take their extra
    // turns in FIFO order before normal turn rotation resumes.
    pending_extra_turns: List(Int),
    // Task 5: Regeneration shields keyed by card id (rule 701.9).
    regeneration_shields: Dict(String, Int),
    // Task 5: Card ids whose damage is fully prevented (AllFromSource).
    source_prevention: List(String),
    // Task 7: Pending Scry awaiting the player's reorder decision.
    pending_scry: Option(ScryPending),
    // PRNG seed threaded through the state so random effects (coin flips,
    // library shuffles) are deterministic given an initial seed.
    seed: random.Seed,
  )
}

pub fn new() -> State {
  new_multiplayer(2)
}

pub fn new_multiplayer(n: Int) -> State {
  new_multiplayer_with_seed(n, random.new_seed(0))
}

/// Like `new_multiplayer` but with an explicit PRNG seed. Tests use this
/// with a fixed seed to keep random effects deterministic.
pub fn new_multiplayer_with_seed(n: Int, seed: random.Seed) -> State {
  let players = list.range(1, n) |> list.map(player.new)
  State(
    players:,
    active_player: 1,
    priority_player: None,
    choice_player: None,
    step: step.Untap,
    consecutive_passes: 0,
    turn_index: 0,
    stack: [],
    attacking_creatures: None,
    blocking_creatures: [],
    assigned_damage: [],
    prevention_shields: dict.new(),
    global_combat_prevention: False,
    pending_delayed_triggers: [],
    pending_optional_trigger: None,
    pending_removed_sources: [],
    pending_extra_turns: [],
    regeneration_shields: dict.new(),
    source_prevention: [],
    pending_scry: None,
    seed:,
  )
}

pub fn turn_cycle(state: State) -> Int {
  let num_players = list.length(state.players)
  state.turn_index / num_players
}

pub fn next_player(state: State, current_player_id: Int) -> player.Player {
  case list.drop_while(state.players, fn(p) { p.id != current_player_id }) {
    [_, ..rest] ->
      case rest {
        [] -> {
          // Wrap around to first player
          case list.first(state.players) {
            Ok(p) -> p
            Error(_) -> panic as "No players in game"
          }
        }
        [next, ..] -> next
      }
    [] -> panic as "Current player not found"
  }
}

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
            combat.AttackPlayer(id) -> id == player.id
            combat.AttackPlaneswalker(player_id, _) -> player_id == player.id
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
  let next = next_step(state)

  // Check if we need to insert a first strike damage step
  let step = case
    state.step == step.DeclareBlockers
    && next == step.CombatDamage
    && has_first_strike_or_double_strike(state)
  {
    True -> step.FirstStrikeDamage
    False -> next
  }

  let first_defender = case step {
    step.DeclareBlockers ->
      get_next_defending_player(state, state.active_player)
    _ -> None
  }
  let priority_player = case step {
    step.Untap
    | step.DeclareAttackers
    | step.FirstStrikeDamage
    | step.CombatDamage
    | step.Cleanup -> None
    step.DeclareBlockers ->
      case first_defender {
        Some(_) -> None
        None -> Some(state.active_player)
      }
    _ -> Some(state.active_player)
  }

  let players =
    list.map(state.players, fn(p) { player.Player(..p, mana_pool: mana.none()) })

  let state =
    State(..state, players:, priority_player:, step:, consecutive_passes: 0)

  case step {
    step.Untap -> {
      // Check for pending extra turns (rule 500.7). If a player has an
      // extra turn queued, they become the active player instead of the
      // next player in normal rotation.
      case state.pending_extra_turns {
        [extra_player_id, ..rest] -> {
          let players =
            list.map(players, fn(p) {
              player.Player(
                ..p,
                lands_played_this_turn: 0,
                battlefield: dict.map_values(p.battlefield, fn(_, perm) {
                  permanent.Permanent(
                    ..perm,
                    damage: 0,
                    tapped: case p.id == extra_player_id {
                      True -> False
                      False -> perm.tapped
                    },
                  )
                }),
              )
            })

          State(
            ..state,
            players:,
            active_player: extra_player_id,
            turn_index: state.turn_index + 1,
            pending_extra_turns: rest,
          )
        }
        [] -> {
          let active_player = next_player(state, state.active_player)

          let players =
            list.map(players, fn(p) {
              player.Player(
                ..p,
                lands_played_this_turn: 0,
                battlefield: dict.map_values(p.battlefield, fn(_, perm) {
                  permanent.Permanent(
                    ..perm,
                    damage: 0,
                    tapped: case p.id == active_player.id {
                      True -> False
                      False -> perm.tapped
                    },
                  )
                }),
              )
            })

          State(
            ..state,
            players:,
            active_player: active_player.id,
            turn_index: state.turn_index + 1,
          )
        }
      }
    }
    step.DeclareBlockers -> State(..state, choice_player: first_defender)
    step.FirstStrikeDamage ->
      State(..state, choice_player: Some(state.active_player))
    step.CombatDamage ->
      State(..state, choice_player: Some(state.active_player))
    step.PostCombatMain ->
      State(..state, attacking_creatures: None, blocking_creatures: [])
    _ -> state
  }
}

fn has_first_strike_or_double_strike(state: State) -> Bool {
  let attacker_ids = case state.attacking_creatures {
    None -> []
    Some(attacks) -> list.map(attacks, fn(a) { a.attacker })
  }
  let blocker_ids = list.map(state.blocking_creatures, fn(b) { b.blocker })
  let creature_ids = list.unique(list.append(attacker_ids, blocker_ids))

  list.any(state.players, fn(p) {
    list.any(creature_ids, fn(id) {
      case permanent.find(p.battlefield, id) {
        Ok(perm) ->
          list.contains(perm.granted_keywords, "First strike")
          || list.contains(perm.granted_keywords, "Double strike")
        Error(_) -> False
      }
    })
  })
}

fn next_step(state: State) -> step.Step {
  case state.step {
    step.Untap -> step.Upkeep
    step.Upkeep -> {
      case list.first(state.players) {
        Ok(first_player) ->
          case state.turn_index == 0 && state.active_player == first_player.id {
            True -> step.PreCombatMain
            False -> step.Draw
          }
        Error(_) -> step.Draw
      }
    }
    step.Draw -> step.PreCombatMain
    step.PreCombatMain -> step.BeginCombat
    step.BeginCombat -> step.DeclareAttackers
    step.DeclareAttackers -> step.DeclareBlockers
    step.DeclareBlockers -> step.CombatDamage
    step.FirstStrikeDamage -> step.CombatDamage
    step.CombatDamage -> step.EndCombat
    step.EndCombat -> step.PostCombatMain
    step.PostCombatMain -> step.EndStep
    step.EndStep -> step.Cleanup
    step.Cleanup -> step.Untap
  }
}

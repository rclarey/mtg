import gleam/io
import gleam/list
import gleam/result

import types.{type Action, type Error, type GameState, type Player}

pub fn main() -> Nil {
  io.println("Hello from mtg_engine!")
}

// Main dispatch function - handles all game actions
pub fn dispatch(state: GameState, action: Action) -> Result(GameState, Error) {
  case action {
    types.PassPriority -> handle_pass_priority(state)
  }
}

fn get_next_priority_player(state: GameState) -> Result(Player, Error) {
  let cur_and_after =
    list.drop_while(state.players, fn(p) { p.id != state.priority_player_id })
  case cur_and_after {
    [] -> Error(types.InvariantBroken("missing current priority player"))
    [_] ->
      list.first(state.players)
      |> result.replace_error(types.InvariantBroken("missing first player"))
    [_, next, ..] -> Ok(next)
  }
}

fn handle_pass_priority(state: GameState) -> Result(GameState, Error) {
  use next_player <- result.map(get_next_priority_player(state))

  types.GameState(..state, priority_player_id: next_player.id)
}

import gleam/list
import gleam/result
import mtg_engine/card
import mtg_engine/error
import mtg_engine/mana
import mtg_engine/permanent

// Player state
pub type Player {
  Player(
    id: Int,
    life: Int,
    mana_pool: mana.Produced,
    lands_played_this_turn: Int,
    hand: List(card.Card),
    battlefield: List(permanent.Permanent),
    graveyard: List(card.Card),
    library: List(card.Card),
    exile: List(card.Card),
  )
}

pub fn new(id: Int) -> Player {
  Player(
    id: id,
    life: 20,
    mana_pool: mana.none(),
    lands_played_this_turn: 0,
    hand: [],
    battlefield: [],
    graveyard: [],
    library: [],
    exile: [],
  )
}

pub fn find(players: List(Player), player_id: Int) -> Result(Player, error.Error) {
  list.find(players, fn(p) { p.id == player_id })
  |> result.replace_error(error.InvalidAction("Player not found"))
}

pub fn update(
  players: List(Player),
  player_id: Int,
  f: fn(Player) -> Player,
) -> List(Player) {
  case players {
    [] -> []
    [p, ..rest] if p.id == player_id -> [f(p), ..rest]
    [p, ..rest] -> [p, ..update(rest, player_id, f)]
  }
}

pub fn clear_mana_pool(player: Player) -> Player {
  Player(..player, mana_pool: mana.none())
}

pub fn reset_lands_played(player: Player) -> Player {
  Player(..player, lands_played_this_turn: 0)
}

pub fn untap_permanents(player: Player) -> Player {
  let untapped_battlefield = list.map(player.battlefield, permanent.untap)
  Player(..player, battlefield: untapped_battlefield)
}

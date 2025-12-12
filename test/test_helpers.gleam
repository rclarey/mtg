import gleam/list
import gleam/option
import mtg_engine/action
import mtg_engine/card
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player

// Helper to pass priority for both players
pub fn pass_both(state: game.State) {
  let assert Ok(s1) = action.dispatch(state, action.PassPriority)
  let assert Ok(s2) = action.dispatch(s1, action.PassPriority)
  s2
}

// Helper to pass until reaching a target step
pub fn pass_until(target_step: game.Step, state: game.State) {
  case state.current_step {
    step if step == target_step -> state
    _ -> pass_until(target_step, pass_both(state))
  }
}

// Helper function to create a test land card
pub fn create_test_land(id: String, name: String) -> card.Card {
  card.Card(
    id: id,
    name: name,
    card_type: card.Land,
    mana_cost: mana.Cost(
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
  )
}

// Helper function to create a test creature card
pub fn create_test_creature(id: String, name: String) -> card.Card {
  card.Card(
    id: id,
    name: name,
    card_type: card.Creature,
    mana_cost: mana.Cost(
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
  )
}

// Helper function to add a card to a player's hand
pub fn add_card_to_hand(
  game: game.State,
  player_id: Int,
  card: card.Card,
) -> game.State {
  game.State(
    ..game,
    players: list.map(game.players, fn(p) {
      case p.id == player_id {
        True -> player.Player(..p, hand: [card, ..p.hand])
        False -> p
      }
    }),
  )
}

// Helper function to add a land directly to battlefield
pub fn add_land_to_battlefield(
  game: game.State,
  player_id: Int,
  land: card.Card,
) -> game.State {
  let land_permanent =
    permanent.Permanent(
      card: land,
      owner_id: player_id,
      tapped: False,
      entered_battlefield_cycle: 0,
    )
  game.State(
    ..game,
    players: list.map(game.players, fn(p) {
      case p.id == player_id {
        True ->
          player.Player(..p, battlefield: [land_permanent, ..p.battlefield])
        False -> p
      }
    }),
  )
}

import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import mtg_engine/action
import mtg_engine/card
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player

// Helper to pass priority for both players
// Automatically declares attackers if in DeclareAttackers step and not yet declared
// Automatically declares no blockers if in DeclareBlockers step and blockers not yet declared
pub fn pass(state: game.State) {
  // If we're in DeclareAttackers step and attackers not declared, declare no attackers
  let state = case
    state.current_step == game.DeclareAttackers
    && option.is_none(state.attacking_creatures)
  {
    True -> {
      let assert Ok(s) =
        action.dispatch(
          state,
          action.DeclareAttackers(state.active_player_id, []),
        )
      s
    }
    False -> state
  }

  // If we're in DeclareBlockers step and there's a declaring player, declare no blockers
  // This might result in moving to the next defender, so we recursively call pass
  let state = case state.current_step {
    game.DeclareBlockers(Some(declaring_player_id)) -> {
      let assert Ok(s) =
        action.dispatch(state, action.DeclareBlockers(declaring_player_id, []))
      // After declaring, if there's another defender, recursively handle it
      case s.current_step {
        game.DeclareBlockers(Some(_)) -> pass(s)
        _ -> s
      }
    }
    _ -> state
  }

  let assert Some(priority_player) = state.priority_player_id
  let not_priority_player = fn(p: player.Player) { p.id != priority_player }
  list.drop_while(state.players, not_priority_player)
  |> list.append(list.take_while(state.players, not_priority_player))
  |> list.fold(state, fn(state, player) {
    let assert Ok(state) =
      action.dispatch(state, action.PassPriority(player.id))
    state
  })
}

// Helper to pass until reaching a target step
pub fn pass_until(target_step: game.Step, state: game.State) {
  case state.current_step {
    step if step == target_step -> state
    _ -> pass_until(target_step, pass(state))
  }
}

pub fn pass_turn(state: game.State) {
  pass_until(game.Cleanup, state)
  |> pass()
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
    power: None,
    toughness: None,
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
    power: Some(2),
    toughness: Some(2),
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
    players: player.update(game.players, player_id, fn(p) {
      player.Player(..p, hand: [card, ..p.hand])
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
    players: player.update(game.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(p.battlefield, land.id, land_permanent),
      )
    }),
  )
}

// Helper function to add a creature directly to battlefield
pub fn add_creature_to_battlefield(
  game: game.State,
  player_id: Int,
  creature: card.Card,
  entered_cycle: Int,
) -> game.State {
  let creature_permanent =
    permanent.Permanent(
      card: creature,
      owner_id: player_id,
      tapped: False,
      entered_battlefield_cycle: entered_cycle,
    )
  game.State(
    ..game,
    players: player.update(game.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(p.battlefield, creature.id, creature_permanent),
      )
    }),
  )
}

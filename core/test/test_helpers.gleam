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
// Automatically assigns no damage if in CombatDamage step
pub fn pass(state: game.State) {
  let state = case state.step {
    // If we're in DeclareAttackers step and attackers not declared, declare no attackers
    game.DeclareAttackers if state.attacking_creatures == None -> {
      let assert Ok(state) =
        action.dispatch(state, action.DeclareAttackers(state.active_player, []))
      state
    }
    // If we're in DeclareBlockers then declare no blockers
    game.DeclareBlockers -> declare_no_blockers(state)
    // If we're in CombatDamage then assign no damage
    game.CombatDamage -> assign_no_damage(state)
    _ -> state
  }

  case state.step, state.priority_player {
    // Handle Untap
    // TODO do something better than this
    game.Untap, _ ->
      game.State(
        ..state,
        step: game.Upkeep,
        priority_player: Some(state.active_player),
      )
    // TODO for now just ignore unimplemented steps that don't start with priority
    _, None ->
      pass(game.State(..state, priority_player: Some(state.active_player)))
    _, Some(priority_player) -> {
      let not_priority_player = fn(p: player.Player) { p.id != priority_player }
      list.drop_while(state.players, not_priority_player)
      |> list.append(list.take_while(state.players, not_priority_player))
      |> list.fold(state, fn(state, player) {
        let assert Ok(state) =
          action.dispatch(state, action.PassPriority(player.id))
        state
      })
    }
  }
}

pub fn assign_no_damage(state: game.State) {
  case state.step, state.choice_player {
    game.CombatDamage, Some(p) -> {
      let assert Ok(state) = action.dispatch(state, action.AssignDamage(p, []))
      assign_no_damage(state)
    }
    _, _ -> state
  }
}

pub fn declare_no_blockers(state: game.State) {
  case state.step, state.choice_player {
    game.DeclareBlockers, Some(p) -> {
      let assert Ok(state) =
        action.dispatch(state, action.DeclareBlockers(p, []))
      declare_no_blockers(state)
    }
    _, _ -> state
  }
}

// Helper to pass until reaching a target step
pub fn pass_until(state: game.State, target_step: game.Step) {
  case state.step {
    step if step == target_step -> state
    _ -> pass_until(pass(state), target_step)
  }
}

pub fn pass_turn(state: game.State) {
  pass_until(state, game.Cleanup)
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

// Helper function to create a creature with specific power/toughness
pub fn create_creature(
  id: String,
  name: String,
  power: Int,
  toughness: Int,
) -> card.Card {
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
    power: Some(power),
    toughness: Some(toughness),
  )
}

// Helper function to add a card to a player's hand
pub fn add_card_to_hand(
  state: game.State,
  player_id: Int,
  card: card.Card,
) -> game.State {
  game.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, hand: [card, ..p.hand])
    }),
  )
}

// Helper function to add a land directly to battlefield
pub fn add_land_to_battlefield(
  state: game.State,
  player_id: Int,
  land: card.Card,
) -> game.State {
  let land_permanent =
    permanent.Permanent(
      card: land,
      owner_id: player_id,
      tapped: False,
      entered_battlefield_cycle: 0,
      damage: 0,
    )
  game.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(p.battlefield, land.id, land_permanent),
      )
    }),
  )
}

// Helper function to add a creature directly to battlefield
pub fn add_creature_to_battlefield(
  state: game.State,
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
      damage: 0,
    )
  game.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(p.battlefield, creature.id, creature_permanent),
      )
    }),
  )
}

// Helper to get a permanent from a player's battlefield
pub fn get_permanent(
  state: game.State,
  player_id: Int,
  card_id: String,
) -> permanent.Permanent {
  let player = get_player(state, player_id)
  let assert Ok(perm) = permanent.find(player.battlefield, card_id)
  perm
}

// Helper to get a player
pub fn get_player(state: game.State, player_id: Int) -> player.Player {
  let assert Ok(p) = player.find(state.players, player_id)
  p
}

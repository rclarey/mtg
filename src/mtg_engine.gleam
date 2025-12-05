import gleam/bool
import gleam/io
import gleam/list
import gleam/option
import gleam/result

import types.{type Action, type Error, type GameState, type Player}

pub fn main() -> Nil {
  io.println("Hello from mtg_engine!")
}

// Initialize a new game with two players
pub fn init_game() -> GameState {
  let empty_mana_pool =
    types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )

  let player1 =
    types.Player(
      id: 1,
      life: 20,
      mana_pool: empty_mana_pool,
      lands_played_this_turn: 0,
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
      mana_pool: empty_mana_pool,
      lands_played_this_turn: 0,
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
    stack: [],
  )
}

// Main dispatch function - handles all game actions
pub fn dispatch(state: GameState, action: Action) -> Result(GameState, Error) {
  case action {
    types.PassPriority -> handle_pass_priority(state)
    types.ProduceMana(player_id, mana) ->
      Ok(handle_produce_mana(state, player_id, mana))
    types.PlayLand(player_id, card_id) ->
      handle_play_land(state, player_id, card_id)
    types.TapLandForMana(player_id, card_id) ->
      handle_tap_land_for_mana(state, player_id, card_id)
    types.CastCreature(player_id, card_id) ->
      handle_cast_creature(state, player_id, card_id)
  }
}

fn update_player(
  players: List(types.Player),
  player_id: Int,
  f: fn(types.Player) -> types.Player,
) -> List(types.Player) {
  case players {
    [] -> []
    [p, ..rest] if p.id == player_id -> [f(p), ..rest]
    [p, ..rest] -> [p, ..update_player(rest, player_id, f)]
  }
}

// Find a player by ID, returning an error if not found
fn find_player(
  players: List(types.Player),
  player_id: Int,
) -> Result(types.Player, types.Error) {
  list.find(players, fn(p) { p.id == player_id })
  |> result.replace_error(types.InvalidAction("Player not found"))
}

// Add mana to a player's pool
fn add_mana(
  pool: types.ManaProduced,
  produced: types.ManaProduced,
) -> types.ManaProduced {
  types.ManaProduced(
    white: pool.white + produced.white,
    blue: pool.blue + produced.blue,
    black: pool.black + produced.black,
    red: pool.red + produced.red,
    green: pool.green + produced.green,
    colorless: pool.colorless + produced.colorless,
  )
}

// Clear a player's mana pool (rule 106.4: mana pools empty at end of each step/phase)
fn clear_mana_pool(player: types.Player) -> types.Player {
  types.Player(
    ..player,
    mana_pool: types.ManaProduced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    ),
  )
}

// Clear all players' mana pools
fn clear_all_mana_pools(players: List(types.Player)) -> List(types.Player) {
  list.map(players, clear_mana_pool)
}

// Handle producing mana for a player
fn handle_produce_mana(
  state: GameState,
  player_id: Int,
  mana: types.ManaProduced,
) -> GameState {
  types.GameState(
    ..state,
    players: update_player(state.players, player_id, fn(p) {
      types.Player(..p, mana_pool: add_mana(p.mana_pool, mana))
    }),
  )
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

  // Clear all mana pools when transitioning between steps (rule 106.4)
  let cleared_players = clear_all_mana_pools(state.players)

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

      // Reset lands_played_this_turn for all players
      let players_with_reset_lands = reset_all_lands_played(cleared_players)

      // Untap all permanents for the new active player (Untap step)
      let players_with_untapped =
        untap_active_player_permanents(
          players_with_reset_lands,
          next_active_player.id,
        )

      // Since Untap has no priority, immediately advance to Upkeep
      types.GameState(
        ..state,
        players: players_with_untapped,
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
        players: cleared_players,
        current_step: types.PreCombatMain,
        priority_player_id: state.active_player_id,
        consecutive_passes: 0,
      )
    types.Draw ->
      types.GameState(
        ..state,
        players: cleared_players,
        current_step: types.Draw,
        priority_player_id: state.active_player_id,
        consecutive_passes: 0,
      )
    _ -> {
      // Normal step advancement within a turn
      // Priority goes to active player when entering a new step
      types.GameState(
        ..state,
        players: cleared_players,
        current_step: next_step,
        priority_player_id: state.active_player_id,
        consecutive_passes: 0,
      )
    }
  }
}

fn handle_pass_priority(state: GameState) -> Result(GameState, types.Error) {
  let new_consecutive_passes = state.consecutive_passes + 1
  let num_players = list.length(state.players)

  // Check if all players have passed
  case new_consecutive_passes >= num_players {
    True -> {
      // All players passed - check if there's anything on the stack to resolve
      case state.stack {
        [] -> {
          // Stack is empty, advance to next step
          Ok(advance_step(state))
        }
        _ -> {
          // Stack has items, resolve the top one and reset priority
          use resolved_state <- result.try(resolve_top_of_stack(state))
          // Reset consecutive passes and give priority to active player
          Ok(
            types.GameState(
              ..resolved_state,
              priority_player_id: resolved_state.active_player_id,
              consecutive_passes: 0,
            ),
          )
        }
      }
    }
    False -> {
      // Not all players passed yet, give priority to next player
      let next_player = get_next_player(state, state.priority_player_id)

      Ok(
        types.GameState(
          ..state,
          priority_player_id: next_player.id,
          consecutive_passes: new_consecutive_passes,
        ),
      )
    }
  }
}

// Reset lands_played_this_turn for a player
fn reset_lands_played(player: types.Player) -> types.Player {
  types.Player(..player, lands_played_this_turn: 0)
}

// Reset lands_played_this_turn for all players
fn reset_all_lands_played(players: List(types.Player)) -> List(types.Player) {
  list.map(players, reset_lands_played)
}

// Untap all permanents for a player
fn untap_all_permanents(player: types.Player) -> types.Player {
  let untapped_battlefield =
    list.map(player.battlefield, fn(card) { types.Card(..card, tapped: False) })
  types.Player(..player, battlefield: untapped_battlefield)
}

// Untap all permanents for the active player
fn untap_active_player_permanents(
  players: List(types.Player),
  active_player_id: Int,
) -> List(types.Player) {
  list.map(players, fn(player) {
    case player.id == active_player_id {
      True -> untap_all_permanents(player)
      False -> player
    }
  })
}

// Find a card in a list by its ID
fn find_card(
  cards: List(types.Card),
  card_id: String,
) -> Result(types.Card, types.Error) {
  list.find(cards, fn(card) { card.id == card_id })
  |> result.replace_error(types.InvalidAction("Card not found"))
}

// Remove a card from a list by its ID
fn remove_card(cards: List(types.Card), card_id: String) -> List(types.Card) {
  list.filter(cards, fn(card) { card.id != card_id })
}

// Get mana produced by a land based on its name
fn get_land_mana_production(land_name: String) -> types.ManaProduced {
  case land_name {
    "Forest" ->
      types.ManaProduced(
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
      )
    "Mountain" ->
      types.ManaProduced(
        white: 0,
        blue: 0,
        black: 0,
        red: 1,
        green: 0,
        colorless: 0,
      )
    "Island" ->
      types.ManaProduced(
        white: 0,
        blue: 1,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
      )
    "Plains" ->
      types.ManaProduced(
        white: 1,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
      )
    "Swamp" ->
      types.ManaProduced(
        white: 0,
        blue: 0,
        black: 1,
        red: 0,
        green: 0,
        colorless: 0,
      )
    _ ->
      types.ManaProduced(
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
      )
  }
}

// Update a card's tapped state in a list
fn update_card_tapped(
  cards: List(types.Card),
  card_id: String,
  tapped: Bool,
) -> List(types.Card) {
  list.map(cards, fn(card) {
    case card.id == card_id {
      True -> types.Card(..card, tapped: tapped)
      False -> card
    }
  })
}

// Handle tapping a land for mana
fn handle_tap_land_for_mana(
  state: GameState,
  player_id: Int,
  card_id: String,
) -> Result(GameState, types.Error) {
  // Find the player
  use player <- result.try(find_player(state.players, player_id))

  // Find the card on the battlefield
  use card <- result.try(find_card(player.battlefield, card_id))

  // Validate: card must be a land
  use <- bool.guard(
    card.card_type != types.Land,
    Error(types.InvalidAction("Card is not a land")),
  )

  // Validate: card must be untapped
  use <- bool.guard(
    card.tapped,
    Error(types.InvalidAction("Land is already tapped")),
  )

  // Tap the land
  let new_battlefield = update_card_tapped(player.battlefield, card_id, True)

  // Determine mana production based on land name
  let mana = get_land_mana_production(card.name)

  // Add mana to player's pool
  let updated_player =
    types.Player(
      ..player,
      battlefield: new_battlefield,
      mana_pool: add_mana(player.mana_pool, mana),
    )

  let new_players =
    update_player(state.players, player_id, fn(_) { updated_player })

  Ok(types.GameState(..state, players: new_players))
}

// Handle playing a land from hand to battlefield
fn handle_play_land(
  state: GameState,
  player_id: Int,
  card_id: String,
) -> Result(GameState, types.Error) {
  use <- bool.guard(
    state.current_step != types.PreCombatMain
      && state.current_step != types.PostCombatMain,
    Error(types.InvalidAction("Can only play a land during a main phase")),
  )
  use <- bool.guard(
    player_id != state.active_player_id,
    Error(types.InvalidAction("Only the active player can play a land")),
  )
  use <- bool.guard(
    player_id != state.priority_player_id,
    Error(types.InvalidAction("Can only play a land when you have priority")),
  )

  // Find the player
  use player <- result.try(find_player(state.players, player_id))

  // Validate: stack must be empty (playing lands is a special action)
  use <- bool.guard(
    state.stack != [],
    Error(types.InvalidAction("Cannot play a land while the stack is not empty")),
  )

  // Validate: land-per-turn limit
  use <- bool.guard(
    player.lands_played_this_turn >= 1,
    Error(types.InvalidAction("Already played a land this turn")),
  )

  use card <- result.try(find_card(player.hand, card_id))
  use <- bool.guard(
    card.card_type != types.Land,
    Error(types.InvalidAction("Card is not a land")),
  )

  // All validations passed, play the land
  let new_hand = remove_card(player.hand, card_id)
  // Land enters battlefield untapped and record when it entered
  let untapped_card =
    types.Card(
      ..card,
      tapped: False,
      entered_battlefield_turn: option.Some(state.turn_number),
    )
  let new_battlefield = [untapped_card, ..player.battlefield]
  let updated_player =
    types.Player(
      ..player,
      hand: new_hand,
      battlefield: new_battlefield,
      lands_played_this_turn: player.lands_played_this_turn + 1,
    )
  let new_players =
    update_player(state.players, player_id, fn(_) { updated_player })
  Ok(types.GameState(..state, players: new_players))
}

const not_enough_mana = Error(
  types.InvalidAction("Not enough mana to cast this spell"),
)

// Deduct mana cost from a mana pool
fn pay_mana_cost(
  pool: types.ManaProduced,
  cost: types.ManaCost,
) -> Result(types.ManaProduced, types.Error) {
  // Check if we have enough of each specific color
  use <- bool.guard(
    pool.white < cost.white
      || pool.blue < cost.blue
      || pool.black < cost.black
      || pool.red < cost.red
      || pool.green < cost.green
      || pool.colorless < cost.colorless,
    not_enough_mana,
  )

  // First, pay the specific colored costs
  let after_specific =
    types.ManaProduced(
      white: pool.white - cost.white,
      blue: pool.blue - cost.blue,
      black: pool.black - cost.black,
      red: pool.red - cost.red,
      green: pool.green - cost.green,
      colorless: pool.colorless - cost.colorless,
    )

  // Then pay the generic cost from remaining mana
  pay_generic_from_pool(after_specific, cost.generic)
}

// Helper function to pay generic mana cost from any available mana
fn pay_generic_from_pool(
  pool: types.ManaProduced,
  generic_cost: Int,
) -> Result(types.ManaProduced, types.Error) {
  // Base case: no generic cost to pay
  use <- bool.guard(generic_cost <= 0, Ok(pool))

  // TODO some smarter heuristic for deducting mana
  // For now try to deduct from each mana type in WUBRG order
  use <- bool.guard(
    pool.white > 0,
    pay_generic_from_pool(
      types.ManaProduced(..pool, white: pool.white - 1),
      generic_cost - 1,
    ),
  )
  use <- bool.guard(
    pool.blue > 0,
    pay_generic_from_pool(
      types.ManaProduced(..pool, blue: pool.blue - 1),
      generic_cost - 1,
    ),
  )
  use <- bool.guard(
    pool.black > 0,
    pay_generic_from_pool(
      types.ManaProduced(..pool, black: pool.black - 1),
      generic_cost - 1,
    ),
  )
  use <- bool.guard(
    pool.red > 0,
    pay_generic_from_pool(
      types.ManaProduced(..pool, red: pool.red - 1),
      generic_cost - 1,
    ),
  )
  use <- bool.guard(
    pool.green > 0,
    pay_generic_from_pool(
      types.ManaProduced(..pool, green: pool.green - 1),
      generic_cost - 1,
    ),
  )
  use <- bool.guard(
    pool.colorless > 0,
    pay_generic_from_pool(
      types.ManaProduced(..pool, colorless: pool.colorless - 1),
      generic_cost - 1,
    ),
  )

  not_enough_mana
}

// Handle casting a creature spell
fn handle_cast_creature(
  state: GameState,
  player_id: Int,
  card_id: String,
) -> Result(GameState, types.Error) {
  // Validate: must be active player
  use <- bool.guard(
    player_id != state.active_player_id,
    Error(types.InvalidAction("Only the active player can cast spells")),
  )

  // Validate: must have priority
  use <- bool.guard(
    player_id != state.priority_player_id,
    Error(types.InvalidAction("Can only cast spells when you have priority")),
  )

  // Validate: must be in a main phase (sorcery-speed for creatures)
  use <- bool.guard(
    state.current_step != types.PreCombatMain
      && state.current_step != types.PostCombatMain,
    Error(types.InvalidAction("Can only cast creatures during a main phase")),
  )

  // Validate: stack must be empty (sorcery-speed restriction)
  use <- bool.guard(
    state.stack != [],
    Error(types.InvalidAction("Can only cast creatures when the stack is empty")),
  )

  // Find the player
  use player <- result.try(find_player(state.players, player_id))

  // Validate: card must be in hand
  use card <- result.try(find_card(player.hand, card_id))

  // Validate: card must be a creature
  use <- bool.guard(
    card.card_type != types.Creature,
    Error(types.InvalidAction("Card is not a creature")),
  )

  // Try to pay the mana cost
  use new_mana_pool <- result.try(pay_mana_cost(
    player.mana_pool,
    card.mana_cost,
  ))
  let new_hand = remove_card(player.hand, card_id)

  Ok(
    types.GameState(
      ..state,
      players: update_player(state.players, player_id, fn(_) {
        types.Player(..player, hand: new_hand, mana_pool: new_mana_pool)
      }),
      stack: [
        types.StackItem(card: card, controller_id: player_id),
        ..state.stack
      ],
    ),
  )
}

// Check if a creature has summoning sickness
// Rule 302.6: A creature can't attack or use tap abilities unless it has been
// under its controller's control continuously since their most recent turn began
//
// This function should be used to validate:
// - Declaring attackers (Phase 6)
// - Activated abilities with tap symbol (future phases)
//
// Usage: has_summoning_sickness(creature, state.turn_number)
pub fn has_summoning_sickness(
  creature: types.Card,
  current_turn: Int,
) -> Bool {
  case creature.entered_battlefield_turn {
    option.None -> False
    option.Some(entered_turn) -> {
      // Creature has summoning sickness if it entered this turn
      // TODO: Add haste keyword support to bypass this check
      entered_turn >= current_turn
    }
  }
}

// Resolve the top spell from the stack
fn resolve_top_of_stack(state: GameState) -> Result(GameState, types.Error) {
  // Validate: stack must not be empty
  use <- bool.guard(
    state.stack == [],
    Error(types.InvalidAction("Cannot resolve spell from empty stack")),
  )

  // Get the top item from the stack
  let assert [top_item, ..remaining_stack] = state.stack

  // For now, we only handle creature spells
  // In the future, this will be extended for other spell types
  use <- bool.guard(
    top_item.card.card_type != types.Creature,
    Error(types.InvalidAction("Can only resolve creature spells currently")),
  )

  // Move the creature from the stack to the battlefield
  // Creatures enter the battlefield untapped
  // Record the turn number when the creature entered (for summoning sickness)
  let creature_card =
    types.Card(
      ..top_item.card,
      tapped: False,
      entered_battlefield_turn: option.Some(state.turn_number),
    )

  // Update the controller's battlefield
  let new_players =
    update_player(state.players, top_item.controller_id, fn(player) {
      types.Player(..player, battlefield: [creature_card, ..player.battlefield])
    })

  Ok(types.GameState(..state, players: new_players, stack: remaining_stack))
}

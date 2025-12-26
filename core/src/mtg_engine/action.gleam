import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/result
import mtg_engine/card
import mtg_engine/error
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player

pub type Action {
  PassPriority(player_id: Int)
  ProduceMana(player_id: Int, mana: mana.Produced)
  PlayLand(player_id: Int, card_id: String)
  TapLandForMana(player_id: Int, card_id: String)
  CastCreature(player_id: Int, card_id: String)
  DeclareAttackers(player_id: Int, attacks: List(game.AttackPair))
}

pub fn dispatch(
  state: game.State,
  action: Action,
) -> Result(game.State, error.Error) {
  case action {
    PassPriority(player_id) -> handle_pass_priority(state, player_id)
    ProduceMana(player_id, mana) ->
      Ok(handle_produce_mana(state, player_id, mana))
    PlayLand(player_id, card_id) -> handle_play_land(state, player_id, card_id)
    TapLandForMana(player_id, card_id) ->
      handle_tap_land_for_mana(state, player_id, card_id)
    CastCreature(player_id, card_id) ->
      handle_cast_creature(state, player_id, card_id)
    DeclareAttackers(player_id, attacks) ->
      handle_declare_attackers(state, player_id, attacks)
  }
}

// Handle passing priority
fn handle_pass_priority(
  state: game.State,
  player_id: Int,
) -> Result(game.State, error.Error) {
  // Check if anyone has priority yet (attackers must be declared first in DeclareAttackers step)
  use current_priority_player <- result.try(case state.priority_player_id {
    option.None ->
      Error(error.InvalidAction(
        "Must declare attackers before taking other actions",
      ))
    option.Some(id) -> Ok(id)
  })

  // Validate: player must have priority
  use <- bool.guard(
    player_id != current_priority_player,
    Error(error.InvalidAction("Can only pass priority when you have priority")),
  )

  let new_consecutive_passes = state.consecutive_passes + 1
  let num_players = list.length(state.players)

  // Check if all players have passed
  case new_consecutive_passes >= num_players {
    True -> {
      // All players passed - check if there's anything on the stack to resolve
      case state.stack {
        [] -> {
          // Stack is empty, advance to next step
          Ok(game.advance_step(state))
        }
        _ -> {
          // Stack has items, resolve the top one and reset priority
          use resolved_state <- result.try(game.resolve_top_of_stack(state))
          // Reset consecutive passes and give priority to active player
          Ok(
            game.State(
              ..resolved_state,
              priority_player_id: option.Some(resolved_state.active_player_id),
              consecutive_passes: 0,
            ),
          )
        }
      }
    }
    False -> {
      // Not all players passed yet, give priority to next player
      let next_player = game.next_player(state, current_priority_player)

      Ok(
        game.State(
          ..state,
          priority_player_id: option.Some(next_player.id),
          consecutive_passes: new_consecutive_passes,
        ),
      )
    }
  }
}

// Handle producing mana for a player
// Note: This is primarily used for testing. In real gameplay, mana comes from tapping lands.
fn handle_produce_mana(
  state: game.State,
  player_id: Int,
  mana: mana.Produced,
) -> game.State {
  game.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, mana_pool: mana.add(p.mana_pool, mana))
    }),
  )
}

// Handle playing a land from hand to battlefield
fn handle_play_land(
  state: game.State,
  player_id: Int,
  card_id: String,
) -> Result(game.State, error.Error) {
  // Check if anyone has priority yet (must be checked first)
  use <- bool.guard(
    option.is_none(state.priority_player_id),
    Error(error.InvalidAction(
      "Must declare attackers before taking other actions",
    )),
  )

  use <- bool.guard(
    state.current_step != game.PreCombatMain
      && state.current_step != game.PostCombatMain,
    Error(error.InvalidAction("Can only play a land during a main phase")),
  )
  use <- bool.guard(
    player_id != state.active_player_id,
    Error(error.InvalidAction("Only the active player can play a land")),
  )

  // Check if player has priority
  use <- bool.guard(
    state.priority_player_id != option.Some(player_id),
    Error(error.InvalidAction("Can only play a land when you have priority")),
  )

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Validate: stack must be empty (playing lands is a special action)
  use <- bool.guard(
    state.stack != [],
    Error(error.InvalidAction("Cannot play a land while the stack is not empty")),
  )

  // Validate: land-per-turn limit
  use <- bool.guard(
    p.lands_played_this_turn >= 1,
    Error(error.InvalidAction("Already played a land this turn")),
  )

  use c <- result.try(card.find(p.hand, card_id))
  use <- bool.guard(
    c.card_type != card.Land,
    Error(error.InvalidAction("Card is not a land")),
  )

  // All validations passed, play the land
  let new_hand = card.remove(p.hand, card_id)
  // Land enters battlefield untapped and record when it entered
  let current_cycle = game.turn_cycle(state)
  let land_permanent = permanent.from_card(c, player_id, current_cycle)
  let new_battlefield = dict.insert(p.battlefield, card_id, land_permanent)
  let updated_player =
    player.Player(
      ..p,
      hand: new_hand,
      battlefield: new_battlefield,
      lands_played_this_turn: p.lands_played_this_turn + 1,
    )
  let new_players =
    player.update(state.players, player_id, fn(_) { updated_player })
  Ok(game.State(..state, players: new_players))
}

// Handle tapping a land for mana
fn handle_tap_land_for_mana(
  state: game.State,
  player_id: Int,
  card_id: String,
) -> Result(game.State, error.Error) {
  // Check if anyone has priority yet (attackers must be declared first)
  use <- bool.guard(
    option.is_none(state.priority_player_id),
    Error(error.InvalidAction(
      "Must declare attackers before taking other actions",
    )),
  )

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Find the permanent on the battlefield
  use perm <- result.try(permanent.find(p.battlefield, card_id))

  // Validate: card must be a land
  use <- bool.guard(
    perm.card.card_type != card.Land,
    Error(error.InvalidAction("Card is not a land")),
  )

  // Validate: permanent must be untapped
  use <- bool.guard(
    perm.tapped,
    Error(error.InvalidAction("Land is already tapped")),
  )

  // Tap the land
  let new_battlefield =
    permanent.update(p.battlefield, card_id, fn(permanent) {
      permanent.Permanent(..permanent, tapped: True)
    })

  // Determine mana production based on land name
  let produced = mana.from_basic_land(perm.card.name)

  // Add mana to player's pool
  let updated_player =
    player.Player(
      ..p,
      battlefield: new_battlefield,
      mana_pool: mana.add(p.mana_pool, produced),
    )

  let new_players =
    player.update(state.players, player_id, fn(_) { updated_player })

  Ok(game.State(..state, players: new_players))
}

// Handle casting a creature spell
fn handle_cast_creature(
  state: game.State,
  player_id: Int,
  card_id: String,
) -> Result(game.State, error.Error) {
  // Check if anyone has priority yet (must be checked first)
  use <- bool.guard(
    option.is_none(state.priority_player_id),
    Error(error.InvalidAction(
      "Must declare attackers before taking other actions",
    )),
  )

  // Validate: must be active player
  use <- bool.guard(
    player_id != state.active_player_id,
    Error(error.InvalidAction("Only the active player can cast spells")),
  )

  // Validate: must have priority
  use <- bool.guard(
    state.priority_player_id != option.Some(player_id),
    Error(error.InvalidAction("Can only cast spells when you have priority")),
  )

  // Validate: must be in a main phase (sorcery-speed for creatures)
  use <- bool.guard(
    state.current_step != game.PreCombatMain
      && state.current_step != game.PostCombatMain,
    Error(error.InvalidAction("Can only cast creatures during a main phase")),
  )

  // Validate: stack must be empty (sorcery-speed restriction)
  use <- bool.guard(
    state.stack != [],
    Error(error.InvalidAction("Can only cast creatures when the stack is empty")),
  )

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Validate: card must be in hand
  use c <- result.try(card.find(p.hand, card_id))

  // Validate: card must be a creature
  use <- bool.guard(
    c.card_type != card.Creature,
    Error(error.InvalidAction("Card is not a creature")),
  )

  // Try to pay the mana cost
  use new_mana_pool <- result.try(mana.pay_cost(p.mana_pool, c.mana_cost))
  let new_hand = card.remove(p.hand, card_id)

  Ok(
    game.State(
      ..state,
      players: player.update(state.players, player_id, fn(_) {
        player.Player(..p, hand: new_hand, mana_pool: new_mana_pool)
      }),
      stack: [game.StackItem(card: c, controller_id: player_id), ..state.stack],
    ),
  )
}

// Handle declaring attackers
fn handle_declare_attackers(
  state: game.State,
  player_id: Int,
  attacks: List(game.AttackPair),
) -> Result(game.State, error.Error) {
  // Validate: must be in DeclareAttackers step
  use <- bool.guard(
    state.current_step != game.DeclareAttackers,
    Error(error.InvalidAction(
      "Can only declare attackers during DeclareAttackers step",
    )),
  )

  // Validate: must be active player
  use <- bool.guard(
    player_id != state.active_player_id,
    Error(error.InvalidAction("Only the active player can declare attackers")),
  )

  // Validate: attackers must not already be declared this step
  use <- bool.guard(
    option.is_some(state.attacking_creatures),
    Error(error.InvalidAction("Attackers have already been declared this step")),
  )

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Get current turn cycle for summoning sickness check
  let current_cycle = game.turn_cycle(state)

  // Validate each attacker and collect them
  use validated_attackers <- result.try(validate_attackers(
    p.battlefield,
    attacks,
    current_cycle,
    player_id,
  ))

  // Tap all attacking creatures
  let new_battlefield =
    list.fold(validated_attackers, p.battlefield, fn(battlefield, attacker) {
      permanent.update(battlefield, attacker.card.id, fn(perm) {
        permanent.Permanent(..perm, tapped: True)
      })
    })

  // Update player's battlefield
  let updated_player = player.Player(..p, battlefield: new_battlefield)
  let new_players =
    player.update(state.players, player_id, fn(_) { updated_player })

  // Update state with attacking creatures and give priority to active player
  // Reset consecutive passes since this is an action
  Ok(
    game.State(
      ..state,
      players: new_players,
      attacking_creatures: option.Some(attacks),
      priority_player_id: option.Some(player_id),
      consecutive_passes: 0,
    ),
  )
}

// Helper function to validate all attackers
fn validate_attackers(
  battlefield: Dict(String, permanent.Permanent),
  attacks: List(game.AttackPair),
  current_cycle: Int,
  attacking_player_id: Int,
) -> Result(List(permanent.Permanent), error.Error) {
  // Validate each attacker
  list.try_map(attacks, fn(attack_pair) {
    // Validate: cannot attack yourself
    use <- bool.guard(
      case attack_pair.target {
        game.AttackPlayer(player_id) -> player_id == attacking_player_id
      },
      Error(error.InvalidAction("Cannot attack yourself")),
    )

    // Find the permanent on the battlefield
    use perm <- result.try(permanent.find(battlefield, attack_pair.attacker))

    // Validate: must be a creature
    use <- bool.guard(
      perm.card.card_type != card.Creature,
      Error(error.InvalidAction("Only creatures can attack")),
    )

    // Validate: must be untapped
    use <- bool.guard(
      perm.tapped,
      Error(error.InvalidAction("Cannot attack with tapped creature")),
    )

    // Validate: must not have summoning sickness
    use <- bool.guard(
      permanent.has_summoning_sickness(perm, current_cycle),
      Error(error.InvalidAction(
        "Cannot attack with creature that has summoning sickness",
      )),
    )

    Ok(perm)
  })
}

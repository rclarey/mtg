import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import mtg_engine/card
import mtg_engine/error
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/util

pub type Action {
  PassPriority(player_id: Int)
  ProduceMana(player_id: Int, mana: mana.Produced)
  PlayLand(player_id: Int, card_id: String)
  TapLandForMana(player_id: Int, card_id: String)
  CastCreature(player_id: Int, card_id: String)
  CastInstant(player_id: Int, card_id: String)
  CastSorcery(player_id: Int, card_id: String)
  DeclareAttackers(player_id: Int, attacks: List(game.AttackPair))
  DeclareBlockers(player_id: Int, blocks: List(game.BlockPair))
  AssignDamage(player_id: Int, assignment: List(game.DamageAssignment))
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
    CastInstant(player_id, card_id) ->
      handle_cast_instant(state, player_id, card_id)
    CastSorcery(player_id, card_id) ->
      handle_cast_sorcery(state, player_id, card_id)
    DeclareAttackers(player_id, attacks) ->
      handle_declare_attackers(state, player_id, attacks)
    DeclareBlockers(player_id, blocks) ->
      handle_declare_blockers(state, player_id, blocks)
    AssignDamage(player_id, assignment) ->
      handle_assign_damage(state, player_id, assignment)
  }
}

/// Make sure the player has priority before doing `action`
fn guard_priority(
  state: game.State,
  player_id: Int,
  action: fn() -> Result(a, error.Error),
) -> Result(a, error.Error) {
  util.guard(
    state.priority_player == Some(player_id) && state.choice_player == None,
    Error(error.DoNotHavePriority),
    action,
  )
}

/// Make sure it's a main phase (either pre or post combat) before doing `action`
fn guard_main(
  state: game.State,
  action: fn() -> Result(a, error.Error),
) -> Result(a, error.Error) {
  util.guard(
    state.step == game.PreCombatMain || state.step == game.PostCombatMain,
    Error(error.WrongStep(expected: "Pre or post-combat main")),
    action,
  )
}

// Handle passing priority
fn handle_pass_priority(
  state: game.State,
  player_id: Int,
) -> Result(game.State, error.Error) {
  use <- guard_priority(state, player_id)

  let consecutive_passes = state.consecutive_passes + 1
  let num_players = list.length(state.players)

  // Check if all players have passed
  case consecutive_passes >= num_players {
    True -> {
      // All players passed - check if there's anything on the stack to resolve
      case state.stack {
        [] -> {
          // Stack is empty, advance to next step
          Ok(game.advance_step(state))
        }
        _ -> {
          // Stack has items, resolve the top one and reset priority
          use state <- result.try(game.resolve_top_of_stack(state))
          // Reset consecutive passes and give priority to active player
          Ok(
            game.State(
              ..state,
              priority_player: Some(state.active_player),
              consecutive_passes: 0,
            ),
          )
        }
      }
    }
    False -> {
      // Not all players passed yet, give priority to next player
      let next_player = game.next_player(state, player_id)

      Ok(
        game.State(
          ..state,
          consecutive_passes: consecutive_passes,
          priority_player: Some(next_player.id),
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
  use <- guard_priority(state, player_id)
  use <- guard_main(state)

  use <- util.guard(
    player_id == state.active_player,
    Error(error.InvalidAction("Only the active player can play a land")),
  )

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Validate: stack must be empty (playing lands is a special action)
  use <- util.guard(
    state.stack == [],
    Error(error.InvalidAction("Cannot play a land while the stack is not empty")),
  )

  // Validate: land-per-turn limit
  use <- util.guard(
    p.lands_played_this_turn == 0,
    Error(error.InvalidAction("Already played a land this turn")),
  )

  use c <- result.try(card.find(p.hand, card_id))
  use <- util.guard(
    c.card_type == card.Land,
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
  use <- guard_priority(state, player_id)

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Find the permanent on the battlefield
  use perm <- result.try(permanent.find(p.battlefield, card_id))

  // Validate: card must be a land
  use <- util.guard(
    perm.card.card_type == card.Land,
    Error(error.InvalidAction("Card is not a land")),
  )

  // Validate: permanent must be untapped
  use <- util.guard(
    !perm.tapped,
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
  use <- guard_priority(state, player_id)

  // Validate: must be active player
  use <- util.guard(
    player_id == state.active_player,
    Error(error.InvalidAction("Only the active player can cast spells")),
  )

  // Validate: must be in a main phase (sorcery-speed for creatures)
  use <- guard_main(state)

  // Validate: stack must be empty (sorcery-speed restriction)
  use <- util.guard(
    state.stack == [],
    Error(error.InvalidAction("Can only cast creatures when the stack is empty")),
  )

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Validate: card must be in hand
  use c <- result.try(card.find(p.hand, card_id))

  // Validate: card must be a creature
  use <- util.guard(
    c.card_type == card.Creature,
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

// Handle casting an instant spell
fn handle_cast_instant(
  state: game.State,
  player_id: Int,
  card_id: String,
) -> Result(game.State, error.Error) {
  use <- guard_priority(state, player_id)

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Validate: card must be in hand
  use c <- result.try(card.find(p.hand, card_id))

  // Validate: card must be an instant
  use <- util.guard(
    c.card_type == card.Instant,
    Error(error.InvalidAction("Card is not an instant")),
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

// Handle casting a sorcery spell
fn handle_cast_sorcery(
  state: game.State,
  player_id: Int,
  card_id: String,
) -> Result(game.State, error.Error) {
  use <- guard_priority(state, player_id)

  // Validate: must be active player
  use <- util.guard(
    player_id == state.active_player,
    Error(error.InvalidAction("Only the active player can cast spells")),
  )

  use <- guard_main(state)

  // Validate: stack must be empty (sorcery-speed restriction)
  use <- util.guard(
    state.stack == [],
    Error(error.InvalidAction("Can only cast sorceries when the stack is empty")),
  )

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Validate: card must be in hand
  use c <- result.try(card.find(p.hand, card_id))

  // Validate: card must be a sorcery
  use <- util.guard(
    c.card_type == card.Sorcery,
    Error(error.InvalidAction("Card is not a sorcery")),
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
  use <- util.guard(
    state.step == game.DeclareAttackers,
    Error(error.InvalidAction(
      "Can only declare attackers during DeclareAttackers step",
    )),
  )

  // Validate: must be active player
  use <- util.guard(
    player_id == state.active_player,
    Error(error.InvalidAction("Only the active player can declare attackers")),
  )

  // Validate: attackers must not already be declared this step
  use <- util.guard(
    option.is_none(state.attacking_creatures),
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
      attacking_creatures: Some(attacks),
      priority_player: Some(player_id),
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
    use <- util.guard(
      attack_pair.target.player_id != attacking_player_id,
      Error(error.InvalidAction("Cannot attack yourself")),
    )

    // Find the permanent on the battlefield
    use perm <- result.try(permanent.find(battlefield, attack_pair.attacker))

    // Validate: must be a creature
    use <- util.guard(
      perm.card.card_type == card.Creature,
      Error(error.InvalidAction("Only creatures can attack")),
    )

    // Validate: must be untapped
    use <- util.guard(
      !perm.tapped,
      Error(error.InvalidAction("Cannot attack with tapped creature")),
    )

    // Validate: must not have summoning sickness
    use <- util.guard(
      !permanent.has_summoning_sickness(perm, current_cycle),
      Error(error.InvalidAction(
        "Cannot attack with creature that has summoning sickness",
      )),
    )

    Ok(perm)
  })
}

// Handle declaring blockers
fn handle_declare_blockers(
  state: game.State,
  player_id: Int,
  blocks: List(game.BlockPair),
) -> Result(game.State, error.Error) {
  // Validate: must be the declare blockers step
  use <- util.guard(
    state.step == game.DeclareBlockers,
    Error(error.InvalidAction(
      "Can only declare blockers in the declare blockers step",
    )),
  )
  // Validate: must be the declaring player's turn
  use <- util.guard(
    state.choice_player == Some(player_id),
    Error(error.InvalidAction("Not your turn to declare blockers")),
  )

  use defending_player <- result.try(player.find(state.players, player_id))

  // Validate: all blocks must be for this defending player
  use <- util.guard(
    list.all(blocks, fn(b) {
      result.is_ok(permanent.find(defending_player.battlefield, b.blocker))
    }),
    Error(error.InvalidAction("Can only declare your own blocks")),
  )

  // Validate: must have attacking creatures
  use attacks <- result.try(case state.attacking_creatures {
    None -> Error(error.InvalidAction("No attackers declared"))
    Some(attack_list) -> Ok(attack_list)
  })

  // Validate each block
  use _ <- result.try(
    list.try_fold(blocks, dict.new(), fn(seen_blockers, block) {
      validate_block_pair(
        defending_player.battlefield,
        block,
        attacks,
        defending_player.id,
        seen_blockers,
      )
    }),
  )

  // Merge this player's blocks with existing blocks
  let blocking_creatures = list.append(state.blocking_creatures, blocks)

  // Determine next defending player
  let next_defender = game.get_next_defending_player(state, player_id)

  // Update step and blocking
  case next_defender {
    Some(next_id) ->
      // More defenders to go
      Ok(game.State(..state, blocking_creatures:, choice_player: Some(next_id)))
    None ->
      // All defenders have declared, give priority to active player
      Ok(
        game.State(
          ..state,
          blocking_creatures:,
          priority_player: Some(state.active_player),
          choice_player: None,
        ),
      )
  }
}

// Validate a single block pair
fn validate_block_pair(
  battlefield: Dict(String, permanent.Permanent),
  block: game.BlockPair,
  attacks: List(game.AttackPair),
  defending_player_id: Int,
  seen_blockers: Dict(String, Int),
) -> Result(Dict(String, Int), error.Error) {
  // For now: each blocker can only block once
  // TODO (Phase 9): Check creature keywords for:
  //   - "can block an additional creature" -> max 2
  //   - "can block any number of creatures" -> unlimited
  use <- util.guard(
    dict.get(seen_blockers, block.blocker) |> result.unwrap(0) == 0,
    Error(error.InvalidAction("A creature cannot block more than once")),
  )

  // Find the blocker on battlefield
  use blocker_perm <- result.try(permanent.find(battlefield, block.blocker))

  // Validate: must be a creature
  use <- util.guard(
    blocker_perm.card.card_type == card.Creature,
    Error(error.InvalidAction("Only creatures can block")),
  )

  // Validate: must be untapped (rule 509.1a)
  use <- util.guard(
    !blocker_perm.tapped,
    Error(error.InvalidAction("Cannot block with tapped creature")),
  )

  // Validate: attacker exists and is attacking this defender
  use <- util.guard(
    is_attacking_defender(attacks, block.attacker, defending_player_id),
    Error(error.InvalidAction("Can only block creatures attacking you")),
  )

  // TODO (Phase 9): Validate evasion abilities (flying, menace, etc.)

  Ok(
    dict.upsert(seen_blockers, block.blocker, fn(c) { option.unwrap(c, 0) + 1 }),
  )
}

// Check if an attacker is attacking a specific defender
fn is_attacking_defender(
  attacks: List(game.AttackPair),
  attacker_id: String,
  defender_id: Int,
) -> Bool {
  list.find(attacks, fn(a) { a.attacker == attacker_id })
  |> result.map(fn(attack) {
    case attack.target {
      game.AttackPlayer(player_id) -> player_id == defender_id
      // TODO: Add planeswalker/battle checks when implemented
    }
  })
  |> result.unwrap(False)
}

fn handle_assign_damage(
  state: game.State,
  player_id: Int,
  assignments: List(game.DamageAssignment),
) -> Result(game.State, error.Error) {
  // Validate: must be the combat damage step
  use <- util.guard(
    state.step == game.CombatDamage,
    Error(error.InvalidAction(
      "Can only assign damage in the combat damage step",
    )),
  )
  // Validate: must be the assigning player's turn
  use <- util.guard(
    state.choice_player == Some(player_id),
    Error(error.InvalidAction("Not your turn to assign damage")),
  )

  use assigning_player <- result.try(player.find(state.players, player_id))

  use damage_per <- result.try(
    list.try_fold(assignments, dict.new(), fn(damage_per, assignment) {
      use _ <- result.try(validate_damage_assignment(
        state,
        assigning_player,
        assignment,
      ))

      Ok(
        dict.upsert(damage_per, assignment.from, fn(entry) {
          case entry {
            Some(n) -> n + assignment.amount
            None -> assignment.amount
          }
        }),
      )
    }),
  )

  // Validate: each creature must assign damage equal to it's power
  use _ <- result.try(
    list.try_each(state.blocking_creatures, fn(block) {
      let assigner_id = case state.active_player == player_id {
        True -> block.attacker
        False -> block.blocker
      }
      case permanent.find(assigning_player.battlefield, assigner_id) {
        // the assigner for this block doesn't belong to the assigning player, so ignore
        Error(_) -> Ok(Nil)
        Ok(creature) -> {
          let damage = dict.get(damage_per, assigner_id)
          let power = option.unwrap(creature.card.power, 0)

          // 0-power creatures should have no damage assignments
          case power {
            0 ->
              case damage {
                Error(_) -> Ok(Nil)
                Ok(_) ->
                  Error(error.InvalidAction(
                    "Cannot assign damage from a creature with 0 power",
                  ))
              }
            _ ->
              case damage == Ok(power) {
                True -> Ok(Nil)
                False ->
                  Error(error.InvalidAction(
                    "Must assign all damage from each creature",
                  ))
              }
          }
        }
      }
    }),
  )

  let state =
    game.State(
      ..state,
      assigned_damage: list.append(assignments, state.assigned_damage),
    )

  // Update step and blocking
  case game.get_next_defending_player(state, player_id) {
    Some(next_id) ->
      // More defenders to go
      Ok(game.State(..state, choice_player: Some(next_id)))
    None -> {
      // All damage assignments collected - apply the damage
      let state = apply_combat_damage(state)

      Ok(
        game.State(
          ..state,
          assigned_damage: [],
          priority_player: Some(state.active_player),
          choice_player: None,
        ),
      )
    }
  }
}

// Apply all combat damage to creatures and players
fn apply_combat_damage(state: game.State) -> game.State {
  // Step 1: Apply assigned damage to creatures
  let state = apply_assigned_damage_to_creatures(state)

  // Step 2: Apply damage from unblocked attackers to defending players
  let state = apply_unblocked_attacker_damage(state)

  // Step 3: Check state-based actions - remove dead creatures
  remove_dead_creatures(state)
}

// Apply damage assignments to creatures on the battlefield
fn apply_assigned_damage_to_creatures(state: game.State) -> game.State {
  // Group damage by player (to update each player's battlefield once)
  let players =
    list.fold(state.assigned_damage, state.players, fn(players, assignment) {
      // Find which player owns the creature receiving damage
      list.fold(players, players, fn(acc_players, p) {
        case permanent.find(p.battlefield, assignment.to) {
          Ok(_) -> {
            // This player owns the creature - apply damage
            player.update(acc_players, p.id, fn(player) {
              let battlefield =
                permanent.update(player.battlefield, assignment.to, fn(perm) {
                  permanent.Permanent(
                    ..perm,
                    damage: perm.damage + assignment.amount,
                  )
                })
              player.Player(..player, battlefield:)
            })
          }
          Error(_) -> acc_players
        }
      })
    })

  game.State(..state, players:)
}

// Apply damage from unblocked attackers to defending players
fn apply_unblocked_attacker_damage(state: game.State) -> game.State {
  // Get list of attackers
  let attackers = case state.attacking_creatures {
    None -> []
    Some(attacks) -> attacks
  }

  // Find unblocked attackers
  let unblocked_attackers =
    list.filter(attackers, fn(attack) {
      !list.any(state.blocking_creatures, fn(block) {
        block.attacker == attack.attacker
      })
    })

  // Deal damage from each unblocked attacker to the defending player
  let players =
    list.fold(unblocked_attackers, state.players, fn(players, attack) {
      // Find the attacker permanent to get its power
      let attacker_owner_id = state.active_player
      case player.find(players, attacker_owner_id) {
        Error(_) -> players
        Ok(attacker_owner) -> {
          case permanent.find(attacker_owner.battlefield, attack.attacker) {
            Error(_) -> players
            Ok(attacker_perm) -> {
              // Get the attacker's power
              let damage = option.unwrap(attacker_perm.card.power, 0)
              // Get the defending player ID from the attack target
              let defender_id = case attack.target {
                game.AttackPlayer(player_id) -> player_id
              }
              // Apply damage to the defending player
              player.update(players, defender_id, fn(defender) {
                player.Player(..defender, life: defender.life - damage)
              })
            }
          }
        }
      }
    })

  game.State(..state, players:)
}

// Remove creatures with lethal damage (state-based action)
fn remove_dead_creatures(state: game.State) -> game.State {
  let players =
    list.map(state.players, fn(p) {
      // Separate living and dead creatures
      let #(battlefield, graveyard) =
        dict.fold(
          p.battlefield,
          #(p.battlefield, p.graveyard),
          fn(acc, card_id, perm) {
            let #(battlefield, graveyard) = acc
            // Check if this is a creature with lethal damage
            case perm.card.card_type, perm.card.toughness {
              card.Creature, Some(toughness) if perm.damage >= toughness -> {
                // Creature is dead - add to graveyard list
                #(dict.delete(battlefield, card_id), [perm.card, ..graveyard])
              }
              _, _ -> {
                // Creature is alive or not a creature - keep on battlefield
                #(battlefield, graveyard)
              }
            }
          },
        )

      // Update player with new battlefield and graveyard
      player.Player(..p, battlefield:, graveyard:)
    })

  game.State(..state, players:)
}

fn validate_damage_assignment(
  state: game.State,
  assigning_player: player.Player,
  assignment: game.DamageAssignment,
) {
  // Validate: there is a corresponding BlockPair for this assignment
  use _ <- result.try(
    list.find(state.blocking_creatures, fn(block) {
      case state.active_player == assigning_player.id {
        True ->
          block.blocker == assignment.to && block.attacker == assignment.from
        False ->
          block.attacker == assignment.to && block.blocker == assignment.from
      }
    })
    |> result.replace_error(error.InvalidAction(
      "Damage assignment doesn't have corresponding declared block",
    )),
  )
  // Validate: creature assigning damage is still on the battlefield
  use from_creature <- result.try(permanent.find(
    assigning_player.battlefield,
    assignment.from,
  ))
  // Validate: creature assigning damage has power
  // Validate: creature getting assigned damage is still on the battlefield
  use _ <- result.try(
    list.filter(state.players, fn(p) { p.id != assigning_player.id })
    |> list.find_map(fn(p) { permanent.find(p.battlefield, assignment.to) })
    |> result.replace_error(error.InvalidAction(
      "Damage cannot be assigned to a creature not on the battlefield",
    )),
  )

  // unwrap to 0 will fail the guard, so don't need a separate check for is_some
  let from_creature_power = option.unwrap(from_creature.card.power, 0)

  // Reject if creature has 0 power - should not assign damage at all
  use <- util.guard(
    from_creature_power != 0,
    Error(error.InvalidAction(
      "Cannot assign damage from a creature with 0 power",
    )),
  )

  // Reject if assignment amount is invalid
  use <- util.guard(
    assignment.amount > 0 && assignment.amount <= from_creature_power,
    Error(error.InvalidAction(
      "Damage assignment must be positive and not exceed the creature's power",
    )),
  )
  Ok(Nil)
}

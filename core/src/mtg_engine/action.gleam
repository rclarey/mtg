import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import mtg_engine/ability
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/color
import mtg_engine/combat
import mtg_engine/effect_resolver
import mtg_engine/effects
import mtg_engine/error
import mtg_engine/extensions
import mtg_engine/filter_matcher
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/stack
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import mtg_engine/util
import mtg_engine/zone

pub type Action {
  PassPriority(player_id: Int)
  ProduceMana(player_id: Int, mana: mana.Produced)
  PlayLand(player_id: Int, card_id: String)
  TapLandForMana(player_id: Int, card_id: String)
  CastCreature(player_id: Int, card_id: String, x_value: Int)
  CastInstant(player_id: Int, card_id: String, x_value: Int)
  CastSorcery(player_id: Int, card_id: String, x_value: Int)
  CastArtifact(player_id: Int, card_id: String, x_value: Int)
  CastEnchantment(player_id: Int, card_id: String, x_value: Int)
  DeclareAttackers(player_id: Int, attacks: List(combat.AttackPair))
  DeclareBlockers(player_id: Int, blocks: List(combat.BlockPair))
  AssignDamage(player_id: Int, assignment: List(combat.DamageAssignment))
  ChooseTargets(
    player_id: Int,
    card_id: String,
    chosen_targets: List(targeting.ChosenTargets),
    chosen_mode: Option(Int),
    damage_division: List(Int),
  )
  ChooseColor(player_id: Int, card_id: String, color: color.Color)
  Scry(player_id: Int, top_to_top: List(Int), top_to_bottom: List(Int))
  ActivateAbility(
    player_id: Int,
    permanent_id: String,
    ability_index: Int,
    x_value: Int,
    chosen_targets: List(targeting.ChosenTargets),
  )
  ChooseTrigger(player_id: Int, card_id: String, put_on_stack: Bool)
}

pub fn dispatch(
  state: state.State,
  action: Action,
) -> Result(state.State, error.Error) {
  case action {
    PassPriority(player_id) -> handle_pass_priority(state, player_id)
    ProduceMana(player_id, mana) ->
      Ok(handle_produce_mana(state, player_id, mana))
    PlayLand(player_id, card_id) -> handle_play_land(state, player_id, card_id)
    TapLandForMana(player_id, card_id) ->
      handle_tap_land_for_mana(state, player_id, card_id)
    CastCreature(player_id, card_id, x_value) ->
      handle_cast_creature(state, player_id, card_id, x_value)
    CastInstant(player_id, card_id, x_value) ->
      handle_cast_instant(state, player_id, card_id, x_value)
    CastSorcery(player_id, card_id, x_value) ->
      handle_cast_sorcery(state, player_id, card_id, x_value)
    CastArtifact(player_id, card_id, x_value) ->
      handle_cast_artifact(state, player_id, card_id, x_value)
    CastEnchantment(player_id, card_id, x_value) ->
      handle_cast_enchantment(state, player_id, card_id, x_value)
    DeclareAttackers(player_id, attacks) ->
      handle_declare_attackers(state, player_id, attacks)
    DeclareBlockers(player_id, blocks) ->
      handle_declare_blockers(state, player_id, blocks)
    AssignDamage(player_id, assignment) ->
      handle_assign_damage(state, player_id, assignment)
    ChooseTargets(
      player_id,
      card_id,
      chosen_targets,
      chosen_mode,
      damage_division,
    ) ->
      handle_choose_targets(
        state,
        player_id,
        card_id,
        chosen_targets,
        chosen_mode,
        damage_division,
      )
    ChooseColor(player_id, card_id, color) ->
      handle_choose_color(state, player_id, card_id, color)
    Scry(player_id, top_to_top, top_to_bottom) ->
      handle_scry(state, player_id, top_to_top, top_to_bottom)
    ActivateAbility(
      player_id,
      permanent_id,
      ability_index,
      x_value,
      chosen_targets,
    ) ->
      handle_activate_ability(
        state,
        player_id,
        permanent_id,
        ability_index,
        x_value,
        chosen_targets,
      )
    ChooseTrigger(player_id, card_id, put_on_stack) ->
      handle_choose_trigger(state, player_id, card_id, put_on_stack)
  }
}

pub fn dispatch_with_ext(
  state: state.State,
  extensions: extensions.GameExtensions,
  action: Action,
) -> Result(#(state.State, extensions.GameExtensions), error.Error) {
  let old_step = state.step

  // Apply static effects before dispatch
  let state = evaluate_static_effects(state, extensions)

  use state <- result.try(dispatch(state, action))

  // Consume any pending delayed triggers created during resolution
  let extensions =
    list.fold(state.pending_delayed_triggers, extensions, fn(ext, dt) {
      extensions.add_delayed_trigger(ext, dt)
    })
  let state = state.State(..state, pending_delayed_triggers: [])

  // Remove static effects for sources that left the battlefield
  let extensions =
    list.fold(state.pending_removed_sources, extensions, fn(ext, source) {
      extensions.remove_static_effects_by_source(ext, source)
    })
  let state = state.State(..state, pending_removed_sources: [])

  let #(state, extensions) = check_delayed_triggers(state, extensions, old_step)
  Ok(#(state, extensions))
}

fn check_delayed_triggers(
  state: state.State,
  extensions: extensions.GameExtensions,
  old_step: step.Step,
) -> #(state.State, extensions.GameExtensions) {
  case state.step == old_step {
    True -> #(state, extensions)
    False -> {
      let #(matching, remaining) =
        list.partition(extensions.delayed_triggers, fn(trigger) {
          case trigger.event {
            effects.AtStep(step:) -> step == state.step
            _ -> False
          }
        })
      let state = list.fold(matching, state, put_delayed_trigger_on_stack)
      let matching_keep =
        list.filter(matching, fn(t) { t.duration == effects.UntilEndOfTurn })
      let new_triggers = list.append(remaining, matching_keep)
      #(
        state,
        extensions.GameExtensions(..extensions, delayed_triggers: new_triggers),
      )
    }
  }
}

fn put_delayed_trigger_on_stack(
  state: state.State,
  trigger: effects.DelayedTrigger,
) -> state.State {
  let dummy_card =
    card.Card(
      id: "delayed_trigger",
      name: "Delayed Trigger",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      abilities: [],
      is_token: False,
    )
  state.State(..state, stack: [
    stack.StackItem(
      card: dummy_card,
      controller_id: trigger.controller,
      chosen_targets: [],
      chosen_mode: None,
      damage_division: [],
      x_value: 0,
      effect_override: Some(trigger.effect),
      trigger_subject: None,
      chosen_color: None,
    ),
    ..state.stack
  ])
}

/// Make sure the player has priority before doing `action`
fn guard_priority(
  state: state.State,
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
  state: state.State,
  action: fn() -> Result(a, error.Error),
) -> Result(a, error.Error) {
  util.guard(
    state.step == step.PreCombatMain || state.step == step.PostCombatMain,
    Error(error.WrongStep(expected: "Pre or post-combat main")),
    action,
  )
}

// Handle passing priority
fn handle_pass_priority(
  state: state.State,
  player_id: Int,
) -> Result(state.State, error.Error) {
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
          Ok(state.advance_step(state))
        }
        _ -> {
          // Stack has items, resolve the top one and reset priority
          use state <- result.try(resolve_top_of_stack(state))
          // Reset consecutive passes and give priority to active player
          Ok(
            state.State(
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
      let next_player = state.next_player(state, player_id)

      Ok(
        state.State(
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
  state: state.State,
  player_id: Int,
  mana: mana.Produced,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, mana_pool: mana.add(p.mana_pool, mana))
    }),
  )
}

// Handle playing a land from hand to battlefield
fn handle_play_land(
  state: state.State,
  player_id: Int,
  card_id: String,
) -> Result(state.State, error.Error) {
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
    c.card_type == card_type.Land,
    Error(error.InvalidAction("Card is not a land")),
  )

  // All validations passed, play the land
  let new_hand = card.remove(p.hand, card_id)
  // Land enters battlefield untapped and record when it entered
  let current_cycle = state.turn_cycle(state)
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
  Ok(state.State(..state, players: new_players))
}

// Handle tapping a land for mana
fn handle_tap_land_for_mana(
  state: state.State,
  player_id: Int,
  card_id: String,
) -> Result(state.State, error.Error) {
  use <- guard_priority(state, player_id)

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Find the permanent on the battlefield
  use perm <- result.try(permanent.find(p.battlefield, card_id))

  // Validate: card must be a land
  use <- util.guard(
    perm.card.card_type == card_type.Land,
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
  use produced <- result.try(mana.from_basic_land(perm.card.name))

  // Add mana to player's pool
  let updated_player =
    player.Player(
      ..p,
      battlefield: new_battlefield,
      mana_pool: mana.add(p.mana_pool, produced),
    )

  let new_players =
    player.update(state.players, player_id, fn(_) { updated_player })

  Ok(state.State(..state, players: new_players))
}

// Handle casting a creature spell
fn handle_cast_creature(
  state: state.State,
  player_id: Int,
  card_id: String,
  x_value: Int,
) -> Result(state.State, error.Error) {
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
    c.card_type == card_type.Creature,
    Error(error.InvalidAction("Card is not a creature")),
  )

  // Find the SpellAbility to check for additional costs
  let additional_costs = case
    list.find(c.abilities, fn(a) {
      case a {
        ability.Spell(_) -> True
        _ -> False
      }
    })
  {
    Ok(ability.Spell(sa)) -> sa.additional_costs
    _ -> []
  }

  // Pay additional costs
  use state <- result.try(pay_additional_costs(
    state,
    player_id,
    card_id,
    additional_costs,
  ))

  // Pay mana cost with X value
  use p <- result.try(player.find(state.players, player_id))
  let actual_cost = mana.Cost(..c.mana_cost, x: x_value)
  use new_mana_pool <- result.try(mana.pay_cost(p.mana_pool, actual_cost))
  let new_hand = card.remove(p.hand, card_id)

  Ok(
    state.State(
      ..state,
      players: player.update(state.players, player_id, fn(_) {
        player.Player(..p, hand: new_hand, mana_pool: new_mana_pool)
      }),
      stack: [stack.make_stack_item(c, player_id, x_value), ..state.stack],
    ),
  )
}

// Handle casting an instant spell
fn handle_cast_instant(
  state: state.State,
  player_id: Int,
  card_id: String,
  x_value: Int,
) -> Result(state.State, error.Error) {
  use <- guard_priority(state, player_id)

  // Find the player
  use p <- result.try(player.find(state.players, player_id))

  // Validate: card must be in hand
  use c <- result.try(card.find(p.hand, card_id))

  // Validate: card must be an instant
  use <- util.guard(
    c.card_type == card_type.Instant,
    Error(error.InvalidAction("Card is not an instant")),
  )

  // Find the SpellAbility to check for additional costs
  let additional_costs = case
    list.find(c.abilities, fn(a) {
      case a {
        ability.Spell(_) -> True
        _ -> False
      }
    })
  {
    Ok(ability.Spell(sa)) -> sa.additional_costs
    _ -> []
  }

  // Pay additional costs
  use state <- result.try(pay_additional_costs(
    state,
    player_id,
    card_id,
    additional_costs,
  ))

  // Pay mana cost with X value
  use p <- result.try(player.find(state.players, player_id))
  let actual_cost = mana.Cost(..c.mana_cost, x: x_value)
  use new_mana_pool <- result.try(mana.pay_cost(p.mana_pool, actual_cost))
  let new_hand = card.remove(p.hand, card_id)

  Ok(
    state.State(
      ..state,
      players: player.update(state.players, player_id, fn(_) {
        player.Player(..p, hand: new_hand, mana_pool: new_mana_pool)
      }),
      stack: [stack.make_stack_item(c, player_id, x_value), ..state.stack],
    ),
  )
}

// Handle casting a sorcery spell
fn handle_cast_sorcery(
  state: state.State,
  player_id: Int,
  card_id: String,
  x_value: Int,
) -> Result(state.State, error.Error) {
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
    c.card_type == card_type.Sorcery,
    Error(error.InvalidAction("Card is not a sorcery")),
  )

  // Find the SpellAbility to check for additional costs
  let additional_costs = case
    list.find(c.abilities, fn(a) {
      case a {
        ability.Spell(_) -> True
        _ -> False
      }
    })
  {
    Ok(ability.Spell(sa)) -> sa.additional_costs
    _ -> []
  }

  // Pay additional costs
  use state <- result.try(pay_additional_costs(
    state,
    player_id,
    card_id,
    additional_costs,
  ))

  // Pay mana cost with X value
  use p <- result.try(player.find(state.players, player_id))
  let actual_cost = mana.Cost(..c.mana_cost, x: x_value)
  use new_mana_pool <- result.try(mana.pay_cost(p.mana_pool, actual_cost))
  let new_hand = card.remove(p.hand, card_id)

  Ok(
    state.State(
      ..state,
      players: player.update(state.players, player_id, fn(_) {
        player.Player(..p, hand: new_hand, mana_pool: new_mana_pool)
      }),
      stack: [stack.make_stack_item(c, player_id, x_value), ..state.stack],
    ),
  )
}

fn handle_cast_artifact(
  state: state.State,
  player_id: Int,
  card_id: String,
  x_value: Int,
) -> Result(state.State, error.Error) {
  use <- guard_priority(state, player_id)
  use <- util.guard(
    player_id == state.active_player,
    Error(error.InvalidAction("Only the active player can cast spells")),
  )
  use <- guard_main(state)
  use <- util.guard(
    state.stack == [],
    Error(error.InvalidAction("Can only cast artifacts when the stack is empty")),
  )
  use p <- result.try(player.find(state.players, player_id))
  use c <- result.try(card.find(p.hand, card_id))
  use <- util.guard(
    c.card_type == card_type.Artifact,
    Error(error.InvalidAction("Card is not an artifact")),
  )

  // Find the SpellAbility to check for additional costs
  let additional_costs = case
    list.find(c.abilities, fn(a) {
      case a {
        ability.Spell(_) -> True
        _ -> False
      }
    })
  {
    Ok(ability.Spell(sa)) -> sa.additional_costs
    _ -> []
  }

  // Pay additional costs
  use state <- result.try(pay_additional_costs(
    state,
    player_id,
    card_id,
    additional_costs,
  ))

  // Pay mana cost with X value
  use p <- result.try(player.find(state.players, player_id))
  let actual_cost = mana.Cost(..c.mana_cost, x: x_value)
  use new_mana_pool <- result.try(mana.pay_cost(p.mana_pool, actual_cost))
  let new_hand = card.remove(p.hand, card_id)
  Ok(
    state.State(
      ..state,
      players: player.update(state.players, player_id, fn(_) {
        player.Player(..p, hand: new_hand, mana_pool: new_mana_pool)
      }),
      stack: [stack.make_stack_item(c, player_id, x_value), ..state.stack],
    ),
  )
}

fn handle_cast_enchantment(
  state: state.State,
  player_id: Int,
  card_id: String,
  x_value: Int,
) -> Result(state.State, error.Error) {
  use <- guard_priority(state, player_id)
  use <- util.guard(
    player_id == state.active_player,
    Error(error.InvalidAction("Only the active player can cast spells")),
  )
  use <- guard_main(state)
  use <- util.guard(
    state.stack == [],
    Error(error.InvalidAction(
      "Can only cast enchantments when the stack is empty",
    )),
  )
  use p <- result.try(player.find(state.players, player_id))
  use c <- result.try(card.find(p.hand, card_id))
  use <- util.guard(
    c.card_type == card_type.Enchantment,
    Error(error.InvalidAction("Card is not an enchantment")),
  )

  // Find the SpellAbility to check for additional costs
  let additional_costs = case
    list.find(c.abilities, fn(a) {
      case a {
        ability.Spell(_) -> True
        _ -> False
      }
    })
  {
    Ok(ability.Spell(sa)) -> sa.additional_costs
    _ -> []
  }

  // Pay additional costs
  use state <- result.try(pay_additional_costs(
    state,
    player_id,
    card_id,
    additional_costs,
  ))

  // Pay mana cost with X value
  use p <- result.try(player.find(state.players, player_id))
  let actual_cost = mana.Cost(..c.mana_cost, x: x_value)
  use new_mana_pool <- result.try(mana.pay_cost(p.mana_pool, actual_cost))
  let new_hand = card.remove(p.hand, card_id)
  Ok(
    state.State(
      ..state,
      players: player.update(state.players, player_id, fn(_) {
        player.Player(..p, hand: new_hand, mana_pool: new_mana_pool)
      }),
      stack: [stack.make_stack_item(c, player_id, x_value), ..state.stack],
    ),
  )
}

// Handle declaring attackers
fn handle_declare_attackers(
  state: state.State,
  player_id: Int,
  attacks: List(combat.AttackPair),
) -> Result(state.State, error.Error) {
  // Validate: must be in DeclareAttackers step
  use <- util.guard(
    state.step == step.DeclareAttackers,
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
  let current_cycle = state.turn_cycle(state)

  // Validate each attacker and collect them
  use validated_attackers <- result.try(validate_attackers(
    p.battlefield,
    attacks,
    current_cycle,
    player_id,
  ))

  // Tap all attacking creatures (skip creatures with vigilance)
  let new_battlefield =
    list.fold(validated_attackers, p.battlefield, fn(battlefield, attacker) {
      case list.contains(attacker.granted_keywords, "Vigilance") {
        True -> battlefield
        False ->
          permanent.update(battlefield, attacker.card.id, fn(perm) {
            permanent.Permanent(..perm, tapped: True)
          })
      }
    })

  // Update player's battlefield
  let updated_player = player.Player(..p, battlefield: new_battlefield)
  let new_players =
    player.update(state.players, player_id, fn(_) { updated_player })

  // Check Attacks triggers for each attacker
  let state_with_triggers =
    list.fold(
      validated_attackers,
      state.State(..state, players: new_players),
      fn(s, perm) {
        effect_resolver.check_attacks_triggers(s, perm.card, player_id)
      },
    )

  // Update state with attacking creatures and give priority to active player
  // Reset consecutive passes since this is an action
  Ok(
    state.State(
      ..state_with_triggers,
      attacking_creatures: Some(attacks),
      priority_player: Some(player_id),
      consecutive_passes: 0,
    ),
  )
}

// Helper function to validate all attackers
fn validate_attackers(
  battlefield: Dict(String, permanent.Permanent),
  attacks: List(combat.AttackPair),
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
      perm.card.card_type == card_type.Creature,
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
  state: state.State,
  player_id: Int,
  blocks: List(combat.BlockPair),
) -> Result(state.State, error.Error) {
  // Validate: must be the declare blockers step
  use <- util.guard(
    state.step == step.DeclareBlockers,
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
        state.players,
        block,
        attacks,
        defending_player.id,
        seen_blockers,
        state.blocking_creatures,
        blocks,
      )
    }),
  )

  // Merge this player's blocks with existing blocks
  let blocking_creatures = list.append(state.blocking_creatures, blocks)

  // Check Blocks triggers for each blocker
  let state =
    list.fold(blocks, state, fn(s, block) {
      case permanent.find(defending_player.battlefield, block.blocker) {
        Ok(perm) ->
          effect_resolver.check_blocks_triggers(s, perm.card, player_id)
        Error(_) -> s
      }
    })

  // Determine next defending player
  let next_defender = state.get_next_defending_player(state, player_id)

  // Update step and blocking
  case next_defender {
    Some(next_id) ->
      // More defenders to go
      Ok(
        state.State(..state, blocking_creatures:, choice_player: Some(next_id)),
      )
    None ->
      // All defenders have declared, give priority to active player
      Ok(
        state.State(
          ..state,
          blocking_creatures:,
          priority_player: Some(state.active_player),
          choice_player: None,
        ),
      )
  }
}

fn find_attacker_permanent(
  players: List(player.Player),
  attacker_id: String,
) -> Result(permanent.Permanent, error.Error) {
  list.find_map(players, fn(p) { permanent.find(p.battlefield, attacker_id) })
  |> result.replace_error(error.InvalidAction("Attacker not found"))
}

// Count how many blockers are assigned to an attacker
fn count_blockers_for_attacker(
  new_blocks: List(combat.BlockPair),
  existing_blocks: List(combat.BlockPair),
  attacker_id: String,
) -> Int {
  let count_new =
    list.length(list.filter(new_blocks, fn(b) { b.attacker == attacker_id }))
  let count_existing =
    list.length(
      list.filter(existing_blocks, fn(b) { b.attacker == attacker_id }),
    )
  count_new + count_existing
}

// Validate a single block pair
fn validate_block_pair(
  players: List(player.Player),
  block: combat.BlockPair,
  attacks: List(combat.AttackPair),
  defending_player_id: Int,
  seen_blockers: Dict(String, Int),
  existing_blocks: List(combat.BlockPair),
  new_blocks: List(combat.BlockPair),
) -> Result(Dict(String, Int), error.Error) {
  // Find the defender to get their battlefield
  use defending_player <- result.try(player.find(players, defending_player_id))

  // Find the blocker on the defender's battlefield
  use blocker_perm <- result.try(permanent.find(
    defending_player.battlefield,
    block.blocker,
  ))

  // Validate: must be a creature
  use <- util.guard(
    blocker_perm.card.card_type == card_type.Creature,
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

  // Can block additional creatures check
  let blocker_block_count =
    dict.get(seen_blockers, block.blocker) |> result.unwrap(0)
  let max_blocks = case
    list.contains(blocker_perm.granted_keywords, "can_block_any_number")
  {
    True -> 999
    False ->
      case
        list.contains(blocker_perm.granted_keywords, "can_block_additional")
      {
        True -> 2
        False -> 1
      }
  }
  use <- util.guard(
    blocker_block_count < max_blocks,
    Error(error.InvalidAction("A creature cannot block more than once")),
  )

  // Evasion: flying check
  use attacker_perm <- result.try(find_attacker_permanent(
    players,
    block.attacker,
  ))
  use <- util.guard(
    !list.contains(attacker_perm.granted_keywords, "Flying")
      || list.contains(blocker_perm.granted_keywords, "Flying")
      || list.contains(blocker_perm.granted_keywords, "Reach"),
    Error(error.InvalidAction(
      "Can't block flying creature without flying or reach",
    )),
  )

  // Evasion: menace check - need at least 2 blockers
  use <- util.guard(
    !list.contains(attacker_perm.granted_keywords, "Menace")
      || count_blockers_for_attacker(
      new_blocks,
      existing_blocks,
      block.attacker,
    )
      >= 2,
    Error(error.InvalidAction(
      "Can't block a creature with menace unless at least two creatures block",
    )),
  )

  Ok(
    dict.upsert(seen_blockers, block.blocker, fn(c) { option.unwrap(c, 0) + 1 }),
  )
}

// Check if an attacker is attacking a specific defender
fn is_attacking_defender(
  attacks: List(combat.AttackPair),
  attacker_id: String,
  defender_id: Int,
) -> Bool {
  list.find(attacks, fn(a) { a.attacker == attacker_id })
  |> result.map(fn(attack) {
    case attack.target {
      combat.AttackPlayer(player_id) -> player_id == defender_id
      combat.AttackPlaneswalker(player_id, _) -> player_id == defender_id
    }
  })
  |> result.unwrap(False)
}

fn handle_assign_damage(
  state: state.State,
  player_id: Int,
  assignments: List(combat.DamageAssignment),
) -> Result(state.State, error.Error) {
  // Validate: must be a combat damage step
  use <- util.guard(
    state.step == step.CombatDamage || state.step == step.FirstStrikeDamage,
    Error(error.InvalidAction("Can only assign damage in a combat damage step")),
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
          // Skip creatures that can't assign damage in the current step (first strike/double strike)
          case creatures_can_assign_damage(state, assigner_id) {
            False -> Ok(Nil)
            True -> {
              let damage = dict.get(damage_per, assigner_id)
              let power = option.unwrap(creature.card.power, 0)
              let has_deathtouch =
                list.contains(creature.granted_keywords, "Deathtouch")
              let has_trample =
                list.contains(creature.granted_keywords, "Trample")

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
                  case damage {
                    Error(_) ->
                      Error(error.InvalidAction(
                        "Must assign damage from each creature",
                      ))
                    Ok(assigned) ->
                      case has_deathtouch || has_trample {
                        True ->
                          // Deathtouch/Trample: can assign less than full power
                          // (at least 1 damage, excess goes to player with trample)
                          case assigned >= 1 && assigned <= power {
                            True -> Ok(Nil)
                            False ->
                              Error(error.InvalidAction(
                                "Must assign at least 1 damage",
                              ))
                          }
                        False ->
                          case assigned == power {
                            True -> Ok(Nil)
                            False ->
                              Error(error.InvalidAction(
                                "Must assign all damage from each creature",
                              ))
                          }
                      }
                  }
              }
            }
          }
        }
      }
    }),
  )

  let state =
    state.State(
      ..state,
      assigned_damage: list.append(assignments, state.assigned_damage),
    )

  // Update step and blocking
  case state.get_next_defending_player(state, player_id) {
    Some(next_id) ->
      // More defenders to go
      Ok(state.State(..state, choice_player: Some(next_id)))
    None -> {
      // All damage assignments collected - apply the damage
      let state = apply_combat_damage(state)

      Ok(
        state.State(
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
fn apply_combat_damage(state: state.State) -> state.State {
  // Step 1: Apply assigned damage to creatures
  let state = apply_assigned_damage_to_creatures(state)

  // Step 2: Check DealsCombatDamage triggers for each damage assignment
  let state = check_combat_damage_triggers(state)

  // Step 3: Apply trample damage (excess damage from blocked attackers with trample)
  let state = apply_trample_damage(state)

  // Step 4: Apply damage from unblocked attackers to defending players
  let state = apply_unblocked_attacker_damage(state)

  // Step 5: Check state-based actions (loop until none are performed)
  effect_resolver.check_state_based_actions(state)
}

/// Check if an attacker can deal combat damage in the current step.
/// Used by trample and unblocked damage functions.
fn attacker_can_deal_damage(state: state.State, attacker_id: String) -> Bool {
  let creature =
    list.find_map(state.players, fn(p) {
      permanent.find(p.battlefield, attacker_id)
    })

  case creature {
    Error(_) -> False
    Ok(perm) -> {
      let has_first_strike =
        list.contains(perm.granted_keywords, "First strike")
      let has_double_strike =
        list.contains(perm.granted_keywords, "Double strike")

      case state.step {
        step.FirstStrikeDamage -> has_first_strike || has_double_strike
        step.CombatDamage -> !has_first_strike || has_double_strike
        _ -> False
      }
    }
  }
}

// Apply damage assignments to creatures on the battlefield
fn apply_assigned_damage_to_creatures(state: state.State) -> state.State {
  // Group damage by player (to update each player's battlefield once)
  let players =
    list.fold(state.assigned_damage, state.players, fn(players, assignment) {
      // Find which player owns the creature receiving damage
      let players =
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
      // Lifelink: find the source creature and check if it has lifelink
      list.find_map(state.players, fn(p) {
        permanent.find(p.battlefield, assignment.from)
        |> result.map(fn(perm) { #(perm, p.id) })
      })
      |> result.map(fn(tup) {
        let #(from_perm, controller_id) = tup
        case list.contains(from_perm.granted_keywords, "Lifelink") {
          True ->
            player.update(players, controller_id, fn(p) {
              player.Player(..p, life: p.life + assignment.amount)
            })
          False -> players
        }
      })
      |> result.unwrap(players)
    })

  state.State(..state, players:)
}

// Check DealsCombatDamage triggers for each damage assignment
fn check_combat_damage_triggers(state: state.State) -> state.State {
  list.fold(state.assigned_damage, state, fn(s, assignment) {
    // Find the source creature
    case
      list.find_map(s.players, fn(p) {
        permanent.find(p.battlefield, assignment.from)
        |> result.map(fn(perm) { #(perm, p.id) })
      })
    {
      Ok(#(perm, controller_id)) ->
        effect_resolver.check_deals_combat_damage_triggers(
          s,
          perm.card,
          controller_id,
          False,
        )
      Error(_) -> s
    }
  })
}

// Apply trample damage: blocked attackers with trample deal excess damage to defending player
fn apply_trample_damage(state: state.State) -> state.State {
  let attackers = case state.attacking_creatures {
    None -> []
    Some(attacks) -> attacks
  }
  // Build a map of assigned damage: attacker_id -> total assigned to creatures
  let assigned_total =
    list.fold(state.assigned_damage, dict.new(), fn(acc, a) {
      dict.upsert(acc, a.from, fn(entry) {
        case entry {
          Some(n) -> n + a.amount
          None -> a.amount
        }
      })
    })
  let #(players, state) =
    list.fold(attackers, #(state.players, state), fn(acc, attack) {
      let #(players, s) = acc
      // Skip attackers that can't deal damage in the current step
      case attacker_can_deal_damage(state, attack.attacker) {
        False -> #(players, s)
        True -> {
          // Only process blocked attackers
          case
            list.any(state.blocking_creatures, fn(b) {
              b.attacker == attack.attacker
            })
          {
            False -> #(players, s)
            True -> {
              // Find the attacker permanent
              case player.find(players, state.active_player) {
                Error(_) -> #(players, s)
                Ok(attacker_owner) -> {
                  case
                    permanent.find(attacker_owner.battlefield, attack.attacker)
                  {
                    Error(_) -> #(players, s)
                    Ok(attacker_perm) -> {
                      case
                        list.contains(attacker_perm.granted_keywords, "Trample")
                      {
                        False -> #(players, s)
                        True -> {
                          let power = option.unwrap(attacker_perm.card.power, 0)
                          let assigned =
                            dict.get(assigned_total, attack.attacker)
                            |> result.unwrap(0)
                          let excess = power - assigned
                          case excess > 0 {
                            False -> #(players, s)
                            True -> {
                              let defender_id = case attack.target {
                                combat.AttackPlayer(player_id) -> player_id
                                combat.AttackPlaneswalker(player_id, _) ->
                                  player_id
                              }
                              let players =
                                player.update(
                                  players,
                                  defender_id,
                                  fn(defender) {
                                    player.Player(
                                      ..defender,
                                      life: defender.life - excess,
                                    )
                                  },
                                )
                              // Check DealsCombatDamage triggers (trample damage to player)
                              let s =
                                effect_resolver.check_deals_combat_damage_triggers(
                                  s,
                                  attacker_perm.card,
                                  state.active_player,
                                  True,
                                )
                              #(players, s)
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    })
  state.State(..state, players:)
}

// Apply damage from unblocked attackers to defending players
fn apply_unblocked_attacker_damage(state: state.State) -> state.State {
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
  let #(players, state) =
    list.fold(unblocked_attackers, #(state.players, state), fn(acc, attack) {
      let #(players, s) = acc
      // Skip attackers that can't deal damage in the current step
      case attacker_can_deal_damage(state, attack.attacker) {
        False -> #(players, s)
        True -> {
          // Find the attacker permanent to get its power
          let attacker_owner_id = state.active_player
          case player.find(players, attacker_owner_id) {
            Error(_) -> #(players, s)
            Ok(attacker_owner) -> {
              case permanent.find(attacker_owner.battlefield, attack.attacker) {
                Error(_) -> #(players, s)
                Ok(attacker_perm) -> {
                  // Get the attacker's power
                  let damage = option.unwrap(attacker_perm.card.power, 0)
                  // Get the defending player ID from the attack target
                  let defender_id = case attack.target {
                    combat.AttackPlayer(player_id) -> player_id
                    combat.AttackPlaneswalker(player_id, _) -> player_id
                  }
                  // Apply damage to the defending player
                  let players =
                    player.update(players, defender_id, fn(defender) {
                      player.Player(..defender, life: defender.life - damage)
                    })
                  // Check DealsCombatDamage triggers (damage to player)
                  let s =
                    effect_resolver.check_deals_combat_damage_triggers(
                      s,
                      attacker_perm.card,
                      attacker_owner_id,
                      True,
                    )
                  // Lifelink: attacker's controller gains life equal to damage dealt
                  let players = case
                    list.contains(attacker_perm.granted_keywords, "Lifelink")
                  {
                    True ->
                      player.update(players, attacker_owner_id, fn(p) {
                        player.Player(..p, life: p.life + damage)
                      })
                    False -> players
                  }
                  #(players, s)
                }
              }
            }
          }
        }
      }
    })

  state.State(..state, players:)
}

fn validate_damage_assignment(
  state: state.State,
  assigning_player: player.Player,
  assignment: combat.DamageAssignment,
) {
  // Validate: creature can assign damage in the current step (first strike / double strike)
  use <- util.guard(
    creatures_can_assign_damage(state, assignment.from),
    Error(error.InvalidAction(
      "Creature cannot assign damage in the current step",
    )),
  )

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

/// Check if a creature can assign damage in the current combat damage step.
/// In FirstStrikeDamage: creature must have "First strike" or "Double strike"
/// In CombatDamage: creature must NOT have only "First strike" (double strike can assign again)
fn creatures_can_assign_damage(
  state: state.State,
  creature_id: String,
) -> Bool {
  // Find the creature on the battlefield
  let creature =
    list.find_map(state.players, fn(p) {
      permanent.find(p.battlefield, creature_id)
    })

  case creature {
    Error(_) -> False
    Ok(perm) -> {
      let has_first_strike =
        list.contains(perm.granted_keywords, "First strike")
      let has_double_strike =
        list.contains(perm.granted_keywords, "Double strike")

      case state.step {
        step.FirstStrikeDamage -> has_first_strike || has_double_strike
        step.CombatDamage -> !has_first_strike || has_double_strike
        _ -> False
      }
    }
  }
}

fn handle_choose_targets(
  state: state.State,
  player_id: Int,
  card_id: String,
  chosen_targets: List(targeting.ChosenTargets),
  chosen_mode: Option(Int),
  damage_division: List(Int),
) -> Result(state.State, error.Error) {
  use <- guard_priority(state, player_id)

  use item <- result.try(
    list.find(state.stack, fn(si) { si.card.id == card_id })
    |> result.replace_error(error.InvalidAction("Spell not found on stack")),
  )

  use <- util.guard(
    item.controller_id == player_id,
    Error(error.InvalidAction("You don't control this spell")),
  )

  // Validate all chosen targets for hexproof/shroud/protection and zone rules
  use _ <- result.try(validate_chosen_targets(state, chosen_targets, item))

  let updated_item =
    stack.StackItem(..item, chosen_targets:, chosen_mode:, damage_division:)

  let new_stack =
    list.map(state.stack, fn(si) {
      case si.card.id == card_id {
        True -> updated_item
        False -> si
      }
    })

  Ok(state.State(..state, stack: new_stack, consecutive_passes: 0))
}

fn handle_choose_color(
  state: state.State,
  player_id: Int,
  card_id: String,
  color: color.Color,
) -> Result(state.State, error.Error) {
  use <- guard_priority(state, player_id)

  use item <- result.try(
    list.find(state.stack, fn(si) { si.card.id == card_id })
    |> result.replace_error(error.InvalidAction("Spell not found on stack")),
  )

  use <- util.guard(
    item.controller_id == player_id,
    Error(error.InvalidAction("You don't control this spell")),
  )

  let updated_item = stack.StackItem(..item, chosen_color: Some(color))
  let new_stack =
    list.map(state.stack, fn(si) {
      case si.card.id == card_id {
        True -> updated_item
        False -> si
      }
    })

  Ok(state.State(..state, stack: new_stack, consecutive_passes: 0))
}

fn handle_scry(
  state: state.State,
  player_id: Int,
  top_to_top: List(Int),
  top_to_bottom: List(Int),
) -> Result(state.State, error.Error) {
  use <- guard_priority(state, player_id)
  use pending <- result.try(case state.pending_scry {
    Some(p) -> Ok(p)
    None -> Error(error.InvalidAction("No pending Scry to resolve"))
  })
  use <- util.guard(
    pending.player_id == player_id,
    Error(error.InvalidAction("Not your Scry to resolve")),
  )
  let n = pending.num
  // Validate that the indices cover exactly 0..n-1.
  let all_indices = list.append(top_to_top, top_to_bottom)
  let expected = list.range(0, n - 1)
  use <- util.guard(
    list.length(all_indices) == n
      && list.all(expected, fn(i) { list.contains(all_indices, i) })
      && !list.any(top_to_top, fn(i) { i < 0 || i >= n })
      && !list.any(top_to_bottom, fn(i) { i < 0 || i >= n }),
    Error(error.InvalidAction(
      "Scry indices must cover exactly the top " <> int.to_string(n) <> " cards",
    )),
  )
  // Apply the reorder: take the top n cards, partition by the indices,
  // put top_to_top back on top (in the specified order), then the rest
  // of the library, then top_to_bottom on the bottom.
  use p <- result.try(player.find(state.players, player_id))
  let top_n = list.take(p.library, n)
  let rest = list.drop(p.library, n)
  let to_top =
    list.filter_map(top_to_top, fn(i) {
      case list.first(list.drop(top_n, i)) {
        Ok(c) -> Ok(c)
        Error(_) -> Error(Nil)
      }
    })
  let to_bottom =
    list.filter_map(top_to_bottom, fn(i) {
      case list.first(list.drop(top_n, i)) {
        Ok(c) -> Ok(c)
        Error(_) -> Error(Nil)
      }
    })
  let new_library = list.append(list.append(to_top, rest), to_bottom)
  let state = state.State(..state, pending_scry: None)
  Ok(
    state.State(
      ..state,
      players: player.update(state.players, player_id, fn(pl) {
        player.Player(..pl, library: new_library)
      }),
    ),
  )
}

fn validate_chosen_targets(
  state: state.State,
  chosen_targets: List(targeting.ChosenTargets),
  item: stack.StackItem,
) -> Result(Nil, error.Error) {
  let target_infos = find_target_infos(item)
  list.try_each(list.zip(chosen_targets, with: target_infos), fn(pair) {
    let #(ct, info) = pair
    list.try_each(ct.targets, fn(target) {
      effect_resolver.validate_target(state, item, info, target)
    })
  })
}

/// Extract the `TargetInfo` list from the ability associated with a stack
/// item. For spells (no effect override) this is the `SpellAbility`'s
/// targets. For triggered/activated abilities, the matching ability's
/// targets. For delayed triggers (no matching ability), returns `[]`.
fn find_target_infos(item: stack.StackItem) -> List(targeting.TargetInfo) {
  let abilities = item.card.abilities
  case item.effect_override {
    None ->
      case
        list.find_map(abilities, fn(a) {
          case a {
            ability.Spell(sa) -> Ok(sa.targets)
            _ -> Error(Nil)
          }
        })
      {
        Ok(targets) -> targets
        Error(_) -> []
      }
    Some(_) ->
      case
        list.find_map(abilities, fn(a) {
          case a {
            ability.Triggered(ta) -> Ok(ta.targets)
            ability.Activated(aa) -> Ok(aa.targets)
            _ -> Error(Nil)
          }
        })
      {
        Ok(targets) -> targets
        Error(_) -> []
      }
  }
}

fn handle_activate_ability(
  state: state.State,
  player_id: Int,
  permanent_id: String,
  ability_index: Int,
  x_value: Int,
  chosen_targets: List(targeting.ChosenTargets),
) -> Result(state.State, error.Error) {
  use <- guard_priority(state, player_id)

  use p <- result.try(player.find(state.players, player_id))
  use perm <- result.try(permanent.find(p.battlefield, permanent_id))

  let abilities = perm.card.abilities
  use ability <- result.try(
    list.drop(abilities, ability_index)
    |> list.first
    |> result.replace_error(error.InvalidAction("No ability at that index")),
  )

  let activated = case ability {
    ability.Activated(aa) -> Ok(aa)
    _ -> Error(error.InvalidAction("Not an activated ability"))
  }
  use aa <- result.try(activated)

  use state <- result.try(pay_activation_costs(
    state,
    player_id,
    permanent_id,
    aa.cost,
  ))

  // Validate chosen targets against the ability's TargetInfo filters.
  let stack_item_for_validation =
    stack.StackItem(
      card: perm.card,
      controller_id: player_id,
      chosen_targets:,
      chosen_mode: None,
      damage_division: [],
      x_value:,
      effect_override: Some(aa.effect),
      trigger_subject: None,
      chosen_color: None,
    )
  use _ <- result.try(validate_chosen_targets(
    state,
    chosen_targets,
    stack_item_for_validation,
  ))

  let stack_item =
    stack.StackItem(
      card: perm.card,
      controller_id: player_id,
      chosen_targets:,
      chosen_mode: None,
      damage_division: [],
      x_value:,
      effect_override: Some(aa.effect),
      trigger_subject: None,
      chosen_color: None,
    )

  Ok(state.State(..state, stack: [stack_item, ..state.stack]))
}

// Handle a player's decision about an optional triggered ability
fn handle_choose_trigger(
  state: state.State,
  player_id: Int,
  card_id: String,
  put_on_stack: Bool,
) -> Result(state.State, error.Error) {
  use pending <- result.try(case state.pending_optional_trigger {
    Some(pending) -> Ok(pending)
    None -> Error(error.InvalidAction("No pending optional trigger to choose"))
  })

  use <- util.guard(
    pending.controller == player_id,
    Error(error.InvalidAction("Not your trigger decision")),
  )

  use <- util.guard(
    pending.source_card.id == card_id,
    Error(error.InvalidAction("Card ID does not match pending trigger")),
  )

  // Clear the pending trigger state
  let state =
    state.State(..state, pending_optional_trigger: None, choice_player: None)

  case put_on_stack {
    True ->
      Ok(effect_resolver.put_trigger_on_stack(
        state,
        pending.controller,
        pending.ability,
        pending.source_card,
        pending.trigger_subject,
      ))
    False -> Ok(state)
  }
}

fn pay_activation_costs(
  state: state.State,
  player_id: Int,
  permanent_id: String,
  cost: ability.ActivationCost,
) -> Result(state.State, error.Error) {
  case cost {
    ability.NoCost -> Ok(state)
    ability.Costs(components) ->
      list.try_fold(components, state, fn(s, component) {
        pay_cost_component(s, player_id, permanent_id, component)
      })
  }
}

fn pay_cost_component(
  state: state.State,
  player_id: Int,
  permanent_id: String,
  component: ability.CostComponent,
) -> Result(state.State, error.Error) {
  case component {
    ability.TapSelf -> {
      let players =
        list.map(state.players, fn(p) {
          case p.id == player_id {
            True -> {
              let battlefield =
                permanent.update(p.battlefield, permanent_id, fn(perm) {
                  permanent.Permanent(..perm, tapped: True)
                })
              player.Player(..p, battlefield:)
            }
            False -> p
          }
        })
      Ok(state.State(..state, players:))
    }
    ability.Mana(cost) -> {
      use p <- result.try(player.find(state.players, player_id))
      use remaining <- result.try(mana.pay_cost(p.mana_pool, cost))
      let players =
        player.update(state.players, player_id, fn(pl) {
          player.Player(..pl, mana_pool: remaining)
        })
      Ok(state.State(..state, players:))
    }
    ability.SacrificeThis -> {
      // Find the permanent being sacrificed and check triggers
      use p <- result.try(player.find(state.players, player_id))
      use perm <- result.try(permanent.find(p.battlefield, permanent_id))
      let state =
        state.State(..state, pending_removed_sources: [
          permanent_id,
          ..state.pending_removed_sources
        ])
      let state =
        effect_resolver.check_leaves_battlefield_triggers(
          state,
          perm.card,
          player_id,
        )
      let state = case perm.card.card_type {
        card_type.Creature ->
          effect_resolver.check_dies_triggers(state, perm.card, player_id)
        _ -> state
      }
      // Remove from battlefield and add to graveyard
      let players =
        list.map(state.players, fn(pl) {
          case pl.id == player_id {
            True ->
              player.Player(
                ..pl,
                battlefield: dict.delete(pl.battlefield, permanent_id),
                graveyard: [perm.card, ..pl.graveyard],
              )
            False -> pl
          }
        })
      Ok(state.State(..state, players:))
    }
    ability.Sacrifice(filter) -> {
      use p <- result.try(player.find(state.players, player_id))
      let matching =
        dict.fold(p.battlefield, [], fn(acc, id, perm) {
          let ctx = permanent_context(state, player_id, player_id, perm)
          case filter_matcher.matches(perm.card, filter, ctx) {
            True -> [#(id, perm.card), ..acc]
            False -> acc
          }
        })
      case matching {
        [#(sac_id, sac_card), ..] -> {
          let state =
            state.State(..state, pending_removed_sources: [
              sac_id,
              ..state.pending_removed_sources
            ])
          let state =
            effect_resolver.check_leaves_battlefield_triggers(
              state,
              sac_card,
              player_id,
            )
          let state = case sac_card.card_type {
            card_type.Creature ->
              effect_resolver.check_dies_triggers(state, sac_card, player_id)
            _ -> state
          }
          let players =
            list.map(state.players, fn(pl) {
              case pl.id == player_id {
                True ->
                  player.Player(
                    ..pl,
                    battlefield: dict.delete(pl.battlefield, sac_id),
                    graveyard: [sac_card, ..pl.graveyard],
                  )
                False -> pl
              }
            })
          Ok(state.State(..state, players:))
        }
        [] -> Error(error.InvalidAction("No matching permanent to sacrifice"))
      }
    }
    ability.SacrificeAny(filter) -> {
      use p <- result.try(player.find(state.players, player_id))
      let matching =
        dict.fold(p.battlefield, [], fn(acc, id, perm) {
          let ctx = permanent_context(state, player_id, player_id, perm)
          case filter_matcher.matches(perm.card, filter, ctx) {
            True -> [#(id, perm.card), ..acc]
            False -> acc
          }
        })
      case matching {
        [#(sac_id, sac_card), ..] -> {
          let state =
            state.State(..state, pending_removed_sources: [
              sac_id,
              ..state.pending_removed_sources
            ])
          let state =
            effect_resolver.check_leaves_battlefield_triggers(
              state,
              sac_card,
              player_id,
            )
          let state = case sac_card.card_type {
            card_type.Creature ->
              effect_resolver.check_dies_triggers(state, sac_card, player_id)
            _ -> state
          }
          let players =
            list.map(state.players, fn(pl) {
              case pl.id == player_id {
                True ->
                  player.Player(
                    ..pl,
                    battlefield: dict.delete(pl.battlefield, sac_id),
                    graveyard: [sac_card, ..pl.graveyard],
                  )
                False -> pl
              }
            })
          Ok(state.State(..state, players:))
        }
        [] -> Error(error.InvalidAction("No matching permanent to sacrifice"))
      }
    }
    ability.PayLife(amount) -> {
      let life_amount = resolve_life_cost(amount)
      let players =
        player.update(state.players, player_id, fn(pl) {
          player.Player(..pl, life: pl.life - life_amount)
        })
      Ok(state.State(..state, players:))
    }
  }
}

fn resolve_life_cost(amount: effects.Amount) -> Int {
  case amount {
    effects.Fixed(n) -> n
    _ -> 0
  }
}

fn pay_additional_costs(
  state: state.State,
  player_id: Int,
  card_id: String,
  costs: List(ability.CostComponent),
) -> Result(state.State, error.Error) {
  list.try_fold(costs, state, fn(s, component) {
    pay_cost_component(s, player_id, card_id, component)
  })
}

// ── Filter Context Helpers ───────────────────────────────────────

fn player_ids(state: state.State) -> List(Int) {
  list.map(state.players, fn(p) { p.id })
}

/// Find the controller of a permanent on the battlefield by card id.
fn find_controller(state: state.State, card_id: String) -> Option(Int) {
  case
    list.find_map(state.players, fn(p) {
      case dict.has_key(p.battlefield, card_id) {
        True -> Ok(p.id)
        False -> Error(Nil)
      }
    })
  {
    Ok(id) -> Some(id)
    Error(_) -> None
  }
}

/// Build a FilterContext for a permanent on the battlefield, evaluated
/// from the perspective of the given active player ("you").
fn permanent_context(
  state: state.State,
  controller_id: Int,
  active_player: Int,
  perm: permanent.Permanent,
) -> filter_matcher.FilterContext {
  filter_matcher.FilterContext(
    controller_id:,
    active_player:,
    target_player: None,
    opponent_ids: list.filter(player_ids(state), fn(id) { id != active_player }),
    is_tapped: Some(perm.tapped),
    zone: zone.Battlefield,
    chosen_color: None,
  )
}

// ── Static Effects Evaluation ─────────────────────────────────────

/// Evaluate all static effects from extensions and apply them to the state.
/// First resets any previously applied static bonuses, then re-applies all
/// current static effects in MTG layer order (rule 613) and timestamp order
/// within each layer. This ensures effects don't compound across multiple
/// dispatch calls.
fn evaluate_static_effects(
  state: state.State,
  extensions: extensions.GameExtensions,
) -> state.State {
  // Step 1: Reset all previous static bonuses on battlefield permanents
  let players =
    list.map(state.players, fn(p) {
      let battlefield =
        dict.map_values(p.battlefield, fn(_, perm) {
          // Revert card power/toughness to pre-static-effect values
          let card =
            card.Card(
              ..perm.card,
              power: option.map(perm.card.power, fn(p) {
                p - perm.static_bonus_power
              }),
              toughness: option.map(perm.card.toughness, fn(t) {
                t - perm.static_bonus_toughness
              }),
            )
          // Remove previously granted static keywords from granted_keywords
          let granted_keywords =
            list.filter(perm.granted_keywords, fn(k) {
              !list.contains(perm.static_bonus_keywords, k)
            })
          permanent.Permanent(
            ..perm,
            card:,
            granted_keywords:,
            static_bonus_power: 0,
            static_bonus_toughness: 0,
            static_bonus_keywords: [],
          )
        })
      player.Player(..p, battlefield:)
    })
  let state = state.State(..state, players:)

  // Step 2: Sort effects by layer (rule 613) then by timestamp (older first)
  let sorted_effects =
    list.sort(extensions.static_effects, fn(a, b) {
      let layer_a = effects.layer_priority(effects.effect_layer(a.effect))
      let layer_b = effects.layer_priority(effects.effect_layer(b.effect))
      case layer_a == layer_b {
        True ->
          case a.timestamp < b.timestamp {
            True -> order.Lt
            False ->
              case a.timestamp == b.timestamp {
                True -> order.Eq
                False -> order.Gt
              }
          }
        False ->
          case layer_a < layer_b {
            True -> order.Lt
            False -> order.Gt
          }
      }
    })

  // Step 3: Re-apply all static effects in sorted order
  list.fold(sorted_effects, state, fn(s, timestamped) {
    // The "you" reference for a static effect is the controller of the
    // source permanent. Look it up on the battlefield.
    let active_player = case find_controller(s, timestamped.source) {
      Some(controller_id) -> controller_id
      None -> 0
    }
    case timestamped.effect {
      effects.PumpAll(filter:, power:, toughness:, keywords:) ->
        apply_pump_all(s, filter, power, toughness, keywords, active_player)
      effects.GrantKeyword(filter:, keyword:) ->
        apply_grant_keyword(s, filter, keyword, active_player)
    }
  })
}

/// Apply a PumpAll static effect: give +power/+toughness and keywords to
/// all permanents matching the filter.
fn apply_pump_all(
  state: state.State,
  filter: filters.CardFilter,
  power: Int,
  toughness: Int,
  keywords: List(effects.Keyword),
  active_player: Int,
) -> state.State {
  let keyword_strings = list.map(keywords, effects.keyword_to_string)
  let players =
    list.map(state.players, fn(p) {
      let battlefield =
        dict.map_values(p.battlefield, fn(_, perm) {
          let ctx = permanent_context(state, p.id, active_player, perm)
          case filter_matcher.matches(perm.card, filter, ctx) {
            True -> {
              let card =
                card.Card(
                  ..perm.card,
                  power: option.map(perm.card.power, fn(pw) { pw + power }),
                  toughness: option.map(perm.card.toughness, fn(t) {
                    t + toughness
                  }),
                )
              permanent.Permanent(
                ..perm,
                card:,
                granted_keywords: list.append(
                  perm.granted_keywords,
                  keyword_strings,
                ),
                static_bonus_power: perm.static_bonus_power + power,
                static_bonus_toughness: perm.static_bonus_toughness + toughness,
                static_bonus_keywords: list.append(
                  perm.static_bonus_keywords,
                  keyword_strings,
                ),
              )
            }
            False -> perm
          }
        })
      player.Player(..p, battlefield:)
    })
  state.State(..state, players:)
}

/// Apply a GrantKeyword static effect: grant a keyword to all permanents
/// matching the filter.
fn apply_grant_keyword(
  state: state.State,
  filter: filters.CardFilter,
  keyword: effects.Keyword,
  active_player: Int,
) -> state.State {
  let keyword_str = effects.keyword_to_string(keyword)
  let players =
    list.map(state.players, fn(p) {
      let battlefield =
        dict.map_values(p.battlefield, fn(_, perm) {
          let ctx = permanent_context(state, p.id, active_player, perm)
          case filter_matcher.matches(perm.card, filter, ctx) {
            True ->
              permanent.Permanent(
                ..perm,
                granted_keywords: [keyword_str, ..perm.granted_keywords],
                static_bonus_keywords: [
                  keyword_str,
                  ..perm.static_bonus_keywords
                ],
              )
            False -> perm
          }
        })
      player.Player(..p, battlefield:)
    })
  state.State(..state, players:)
}

fn resolve_top_of_stack(
  state: state.State,
) -> Result(state.State, error.Error) {
  effect_resolver.resolve_stack_item(state)
}

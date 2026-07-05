import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import mtg_engine/ability
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/color
import mtg_engine/effects
import mtg_engine/error
import mtg_engine/filter_matcher
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/stack
import mtg_engine/state
import mtg_engine/supertype
import mtg_engine/targeting
import mtg_engine/trigger
import mtg_engine/util
import mtg_engine/zone
import prng/random

pub fn resolve_stack_item(
  state: state.State,
) -> Result(state.State, error.Error) {
  use <- util.guard(
    state.stack != [],
    Error(error.InvalidAction("Cannot resolve spell from empty stack")),
  )

  let assert [item, ..remaining_stack] = state.stack
  let state = state.State(..state, stack: remaining_stack)

  use state <- result.try(resolve_spell_effect(state, item))
  let state = move_card_to_destination(state, item)

  let state = case item.effect_override {
    None -> {
      case item.card.card_type {
        card_type.Creature
        | card_type.Artifact
        | card_type.Enchantment
        | card_type.Land -> check_enters_battlefield_triggers(state, item)
        _ -> state
      }
    }
    Some(_) -> state
  }

  Ok(check_state_based_actions(state))
}

fn find_spell_effect(
  item: stack.StackItem,
  abilities: List(ability.Ability),
) -> Option(effects.Effect) {
  case item.effect_override {
    Some(effect) -> Some(effect)
    None -> {
      case abilities {
        [] -> None
        [ability.Spell(sa), ..] -> Some(sa.effect)
        [ability.Activated(aa), ..] -> Some(aa.effect)
        [_, ..rest] -> find_spell_effect(item, rest)
      }
    }
  }
}

fn resolve_spell_effect(
  state: state.State,
  item: stack.StackItem,
) -> Result(state.State, error.Error) {
  case find_spell_effect(item, item.card.abilities) {
    None -> Ok(state)
    Some(effect) -> {
      use #(new_state, _) <- result.try(resolve_effect(state, item, effect))
      Ok(new_state)
    }
  }
}

fn resolve_effect(
  state: state.State,
  item: stack.StackItem,
  effect: effects.Effect,
) -> Result(#(state.State, Int), error.Error) {
  case effect {
    effects.Single(step) -> resolve_step(state, item, step, 0)
    effects.Sequence(steps) ->
      list.try_fold(steps, #(state, 0), fn(acc, step) {
        let #(state, prev) = acc
        resolve_step(state, item, step, prev)
      })
  }
}

fn resolve_amount(
  state: state.State,
  item: stack.StackItem,
  amount: effects.Amount,
  previous_step_result: Int,
) -> Int {
  case amount {
    effects.Fixed(n) -> n
    effects.X -> item.x_value
    effects.Count(filter) -> count_matching(state, item, filter)
    effects.Multiply(a, n) ->
      resolve_amount(state, item, a, previous_step_result) * n
    effects.PreviousStep -> previous_step_result
  }
}

fn resolve_ref_as_player(
  _state: state.State,
  item: stack.StackItem,
  target_ref: targeting.TargetRef,
) -> Result(Int, error.Error) {
  case target_ref {
    targeting.Controller -> Ok(item.controller_id)
    targeting.Source -> Ok(item.controller_id)
    targeting.PrimaryTarget -> {
      case item.chosen_targets {
        [first, ..] -> {
          case list.first(first.targets) {
            Ok(targeting.TargetPlayer(player_id)) -> Ok(player_id)
            _ -> Error(error.InvalidAction("Primary target is not a player"))
          }
        }
        [] -> Error(error.InvalidAction("No targets chosen for PrimaryTarget"))
      }
    }
    targeting.SecondaryTarget -> {
      case item.chosen_targets {
        [_, second, ..] -> {
          case list.first(second.targets) {
            Ok(targeting.TargetPlayer(player_id)) -> Ok(player_id)
            _ -> Error(error.InvalidAction("Secondary target is not a player"))
          }
        }
        _ -> Error(error.InvalidAction("No secondary target chosen"))
      }
    }
    targeting.TriggerSubject -> {
      case item.trigger_subject {
        Some(targeting.TargetPlayer(player_id)) -> Ok(player_id)
        Some(targeting.TargetCard(_)) ->
          Error(error.InvalidAction("Trigger subject is a card, not a player"))
        None -> Error(error.InvalidAction("No trigger subject available"))
      }
    }
    targeting.AllOf(_) ->
      Error(error.InvalidAction("AllOf cannot be resolved as a single player"))
  }
}

fn resolve_ref_as_card(
  state: state.State,
  item: stack.StackItem,
  target_ref: targeting.TargetRef,
) -> Result(String, error.Error) {
  let card_id = case target_ref {
    targeting.Source -> Ok(item.card.id)
    targeting.PrimaryTarget -> {
      case item.chosen_targets {
        [first, ..] -> {
          case list.first(first.targets) {
            Ok(targeting.TargetCard(card_id)) -> Ok(card_id)
            _ -> Error(error.InvalidAction("Primary target is not a card"))
          }
        }
        [] -> Error(error.InvalidAction("No targets chosen for PrimaryTarget"))
      }
    }
    targeting.SecondaryTarget -> {
      case item.chosen_targets {
        [_, second, ..] -> {
          case list.first(second.targets) {
            Ok(targeting.TargetCard(card_id)) -> Ok(card_id)
            _ -> Error(error.InvalidAction("Secondary target is not a card"))
          }
        }
        _ -> Error(error.InvalidAction("No secondary target chosen"))
      }
    }
    targeting.Controller ->
      Error(error.InvalidAction("Controller cannot be resolved as a card"))
    targeting.TriggerSubject -> {
      case item.trigger_subject {
        Some(targeting.TargetCard(card_id)) -> Ok(card_id)
        Some(targeting.TargetPlayer(_)) ->
          Error(error.InvalidAction("Trigger subject is a player, not a card"))
        None -> Error(error.InvalidAction("No trigger subject available"))
      }
    }
    targeting.AllOf(_) ->
      Error(error.InvalidAction("AllOf cannot be resolved as a single card"))
  }
  use card_id <- result.try(card_id)
  use _ <- result.try(check_target_legality(
    state,
    card_id,
    item.card,
    item.controller_id,
  ))
  Ok(card_id)
}

/// Check that a target card is a legal target for a spell or ability.
/// Returns Ok(Nil) if the target is legal or not on the battlefield.
/// Returns an Error if the target has hexproof (and is controlled by an opponent),
/// shroud, or protection from the source's qualities.
pub fn check_target_legality(
  state: state.State,
  target_card_id: String,
  source_card: card.Card,
  source_controller_id: Int,
) -> Result(Nil, error.Error) {
  // Only validate targets that are on the battlefield as permanents
  case find_card_on_battlefield(state, target_card_id) {
    Error(_) -> Ok(Nil)
    Ok(#(perm, permanent_controller_id)) -> {
      // Check shroud: can't be targeted at all
      use <- util.guard(
        !list.contains(perm.granted_keywords, "Shroud"),
        Error(error.InvalidAction("Can't target a permanent with shroud")),
      )

      // Check hexproof: can't be targeted by opponents
      use <- util.guard(
        !list.contains(perm.granted_keywords, "Hexproof")
          || source_controller_id == permanent_controller_id,
        Error(error.InvalidAction(
          "Can't target opponent's permanent with hexproof",
        )),
      )

      // Check protection from colors
      let source_colors = get_card_colors(source_card.mana_cost)
      use _ <- result.try(
        list.try_each(source_colors, fn(c) {
          let prot_str = "Protection from " <> color_to_string(c)
          use <- util.guard(
            !list.contains(perm.granted_keywords, prot_str),
            Error(error.InvalidAction(
              "Target has protection from source's colors",
            )),
          )
          Ok(Nil)
        }),
      )

      // Check protection from card types
      let type_prot_str =
        "Protection from "
        <> card_type_to_protection_string(source_card.card_type)
      use <- util.guard(
        !list.contains(perm.granted_keywords, type_prot_str),
        Error(error.InvalidAction(
          "Target has protection from source's card type",
        )),
      )

      Ok(Nil)
    }
  }
}

fn get_card_colors(cost: mana.Cost) -> List(color.Color) {
  filter_matcher.get_card_colors(cost)
}

fn player_ids(state: state.State) -> List(Int) {
  list.map(state.players, fn(p) { p.id })
}

fn opponents_of(state: state.State, player_id: Int) -> List(Int) {
  list.filter(player_ids(state), fn(id) { id != player_id })
}

/// Resolve the primary target as a player id, if the spell/ability has one.
fn resolve_target_player(item: stack.StackItem) -> Option(Int) {
  case item.chosen_targets {
    [first, ..] ->
      case list.first(first.targets) {
        Ok(targeting.TargetPlayer(player_id)) -> Some(player_id)
        _ -> None
      }
    [] -> None
  }
}

/// Build a FilterContext for a card controlled by `controller_id`, evaluated
/// from the perspective of `item.controller_id` (the "you" reference).
fn filter_context_for_item(
  state: state.State,
  item: stack.StackItem,
  controller_id: Int,
  is_tapped: Option(Bool),
  zone: zone.Zone,
) -> filter_matcher.FilterContext {
  filter_matcher.FilterContext(
    controller_id:,
    active_player: item.controller_id,
    target_player: resolve_target_player(item),
    opponent_ids: opponents_of(state, item.controller_id),
    is_tapped:,
    zone:,
    chosen_color: None,
  )
}

/// Build a FilterContext where the active player ("you") is `controller_id`
/// itself — used by trigger checks where the trigger controller is the
/// reference point and there is no separate spell controller.
fn filter_context_for_controller(
  state: state.State,
  controller_id: Int,
  is_tapped: Option(Bool),
  zone: zone.Zone,
) -> filter_matcher.FilterContext {
  filter_matcher.FilterContext(
    controller_id:,
    active_player: controller_id,
    target_player: None,
    opponent_ids: opponents_of(state, controller_id),
    is_tapped:,
    zone:,
    chosen_color: None,
  )
}

/// Look up a permanent's tapped state on the battlefield by card id.
fn find_tapped_option(state: state.State, card_id: String) -> Option(Bool) {
  case find_permanent_on_battlefield(state, card_id) {
    Ok(#(perm, _)) -> Some(perm.tapped)
    Error(_) -> None
  }
}

fn find_card_on_battlefield(
  state: state.State,
  card_id: String,
) -> Result(#(permanent.Permanent, Int), error.Error) {
  list.find_map(state.players, fn(p) {
    case permanent.find(p.battlefield, card_id) {
      Ok(perm) -> Ok(#(perm, p.id))
      Error(_) -> Error(Nil)
    }
  })
  |> result.replace_error(error.InvalidAction("Card not found on battlefield"))
}

fn resolve_prevention_target_key(
  state: state.State,
  item: stack.StackItem,
  target: targeting.TargetRef,
) -> String {
  case resolve_ref_as_player(state, item, target) {
    Ok(player_id) -> "player_" <> int.to_string(player_id)
    Error(_) -> {
      case resolve_ref_as_card(state, item, target) {
        Ok(card_id) -> card_id
        Error(_) -> "none"
      }
    }
  }
}

fn deal_damage_to_player(
  state: state.State,
  player_id: Int,
  amount: Int,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, life: p.life - amount)
    }),
  )
}

fn deal_damage_to_creature(
  state: state.State,
  card_id: String,
  amount: Int,
) -> state.State {
  list.fold(state.players, state, fn(acc_state, p) {
    case permanent.find(p.battlefield, card_id) {
      Ok(_) ->
        state.State(
          ..acc_state,
          players: player.update(acc_state.players, p.id, fn(player) {
            player.Player(
              ..player,
              battlefield: permanent.update(player.battlefield, card_id, fn(p) {
                permanent.Permanent(..p, damage: p.damage + amount)
              }),
            )
          }),
        )
      Error(_) -> acc_state
    }
  })
}

fn draw_cards(state: state.State, player_id: Int, amount: Int) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      let drawn = list.take(p.library, amount)
      let remaining = list.drop(p.library, amount)
      player.Player(..p, hand: list.append(p.hand, drawn), library: remaining)
    }),
  )
}

fn gain_life(state: state.State, player_id: Int, amount: Int) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, life: p.life + amount)
    }),
  )
}

fn lose_life(state: state.State, player_id: Int, amount: Int) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, life: p.life - amount)
    }),
  )
}

fn produce_mana(
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

fn mill_cards(state: state.State, player_id: Int, amount: Int) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      let milled = list.take(p.library, amount)
      let remaining = list.drop(p.library, amount)
      player.Player(
        ..p,
        graveyard: list.append(p.graveyard, milled),
        library: remaining,
      )
    }),
  )
}

fn find_triggered_abilities(
  abilities: List(ability.Ability),
  trigger_event: trigger.Trigger,
) -> List(ability.TriggeredAbility) {
  list.filter_map(abilities, fn(a) {
    case a {
      ability.Triggered(ta) if ta.trigger == trigger_event -> Ok(ta)
      _ -> Error(Nil)
    }
  })
}

pub fn put_trigger_on_stack(
  state: state.State,
  controller_id: Int,
  ta: ability.TriggeredAbility,
  source_card: card.Card,
  trigger_subject: Option(targeting.TargetIdentifier),
) -> state.State {
  state.State(..state, stack: [
    stack.StackItem(
      card: source_card,
      controller_id:,
      chosen_targets: [],
      chosen_mode: None,
      damage_division: [],
      x_value: 0,
      effect_override: Some(ta.effect),
      trigger_subject:,
      chosen_color: None,
    ),
    ..state.stack
  ])
}

fn put_triggers_on_stack(
  state: state.State,
  triggered: List(ability.TriggeredAbility),
  controller_id: Int,
  source_card: card.Card,
  trigger_subject: Option(targeting.TargetIdentifier),
) -> state.State {
  // Separate optional and non-optional triggers
  let #(optional, non_optional) =
    list.partition(triggered, fn(ta) { ta.optional })

  // Non-optional triggers go on the stack immediately
  let state =
    list.fold(non_optional, state, fn(s, ta) {
      case ta.intervening_if {
        Some(filter) -> {
          let is_tapped = find_tapped_option(s, source_card.id)
          let ctx =
            filter_context_for_controller(
              s,
              controller_id,
              is_tapped,
              zone.Battlefield,
            )
          case filter_matcher.matches(source_card, filter, ctx) {
            True ->
              put_trigger_on_stack(
                s,
                controller_id,
                ta,
                source_card,
                trigger_subject,
              )
            False -> s
          }
        }
        None ->
          put_trigger_on_stack(
            s,
            controller_id,
            ta,
            source_card,
            trigger_subject,
          )
      }
    })

  // Handle the first optional trigger by setting a pending trigger
  case optional {
    [] -> state
    [first_optional, ..] -> {
      // Check intervening_if for the optional trigger
      case first_optional.intervening_if {
        Some(filter) -> {
          let is_tapped = find_tapped_option(state, source_card.id)
          let ctx =
            filter_context_for_controller(
              state,
              controller_id,
              is_tapped,
              zone.Battlefield,
            )
          case filter_matcher.matches(source_card, filter, ctx) {
            True ->
              state.State(
                ..state,
                pending_optional_trigger: Some(state.PendingTrigger(
                  source_card:,
                  controller: controller_id,
                  ability: first_optional,
                  trigger_subject:,
                )),
                choice_player: Some(controller_id),
              )
            False -> state
          }
        }
        None ->
          state.State(
            ..state,
            pending_optional_trigger: Some(state.PendingTrigger(
              source_card:,
              controller: controller_id,
              ability: first_optional,
              trigger_subject:,
            )),
            choice_player: Some(controller_id),
          )
      }
    }
  }
}

fn check_enters_battlefield_triggers(
  state: state.State,
  resolved_item: stack.StackItem,
) -> state.State {
  let triggered =
    find_triggered_abilities(
      resolved_item.card.abilities,
      trigger.EntersBattlefield,
    )
  put_triggers_on_stack(
    state,
    triggered,
    resolved_item.controller_id,
    resolved_item.card,
    Some(targeting.TargetCard(resolved_item.card.id)),
  )
}

pub fn check_leaves_battlefield_triggers(
  state: state.State,
  card: card.Card,
  controller_id: Int,
) -> state.State {
  let triggered =
    find_triggered_abilities(card.abilities, trigger.LeavesBattlefield)
  put_triggers_on_stack(
    state,
    triggered,
    controller_id,
    card,
    Some(targeting.TargetCard(card.id)),
  )
}

pub fn check_dies_triggers(
  state: state.State,
  card: card.Card,
  controller_id: Int,
) -> state.State {
  case card.card_type {
    card_type.Creature -> {
      let triggered = find_triggered_abilities(card.abilities, trigger.Dies)
      put_triggers_on_stack(
        state,
        triggered,
        controller_id,
        card,
        Some(targeting.TargetCard(card.id)),
      )
    }
    _ -> state
  }
}

pub fn check_attacks_triggers(
  state: state.State,
  card: card.Card,
  controller_id: Int,
) -> state.State {
  let triggered = find_triggered_abilities(card.abilities, trigger.Attacks)
  put_triggers_on_stack(
    state,
    triggered,
    controller_id,
    card,
    Some(targeting.TargetCard(card.id)),
  )
}

pub fn check_blocks_triggers(
  state: state.State,
  card: card.Card,
  controller_id: Int,
) -> state.State {
  let triggered = find_triggered_abilities(card.abilities, trigger.Blocks)
  put_triggers_on_stack(
    state,
    triggered,
    controller_id,
    card,
    Some(targeting.TargetCard(card.id)),
  )
}

/// Information about a candidate target card, used to evaluate `Color` and
/// `Zone` target filters precisely. When `None`, the coarse fallback
/// (`!target_is_player`) is used for `Color`/`Zone`.
pub type TargetCandidate {
  TargetCandidate(card: card.Card, controller_id: Int, zone: zone.Zone)
}

fn target_filter_matches(
  filter: targeting.TargetFilter,
  target_is_player: Bool,
  candidate: Option(TargetCandidate),
) -> Bool {
  case filter {
    targeting.Any -> True
    targeting.Single(targeting.Player) -> target_is_player
    targeting.Single(targeting.Creature) ->
      single_card_type(candidate, card_type.Creature, target_is_player)
    targeting.Single(targeting.Artifact) ->
      single_card_type(candidate, card_type.Artifact, target_is_player)
    targeting.Single(targeting.Enchantment) ->
      single_card_type(candidate, card_type.Enchantment, target_is_player)
    targeting.Single(targeting.Spell) ->
      // Spells live on the stack; without a candidate we fall back to
      // "any non-player".
      case candidate {
        Some(c) -> c.zone == zone.Stack
        None -> !target_is_player
      }
    targeting.Single(targeting.Land) ->
      single_card_type(candidate, card_type.Land, target_is_player)
    targeting.Color(ref) ->
      case candidate {
        Some(c) -> color_ref_matches(c.card, ref, filter_context_for_color(c))
        None -> !target_is_player
      }
    targeting.Zone(z) ->
      case candidate {
        Some(c) -> c.zone == z
        None -> !target_is_player
      }
    targeting.Not(inner) ->
      !target_filter_matches(inner, target_is_player, candidate)
    targeting.And(a, b) ->
      target_filter_matches(a, target_is_player, candidate)
      && target_filter_matches(b, target_is_player, candidate)
    targeting.Or(a, b) ->
      target_filter_matches(a, target_is_player, candidate)
      || target_filter_matches(b, target_is_player, candidate)
  }
}

/// Evaluate `Single(target_type)` against a candidate card. When a
/// candidate is available, check the card's type precisely; otherwise fall
/// back to the coarse `!target_is_player` heuristic.
fn single_card_type(
  candidate: Option(TargetCandidate),
  expected: card_type.CardType,
  target_is_player: Bool,
) -> Bool {
  case candidate {
    Some(c) -> c.card.card_type == expected
    None -> !target_is_player
  }
}

fn filter_context_for_color(
  c: TargetCandidate,
) -> filter_matcher.FilterContext {
  filter_matcher.FilterContext(
    controller_id: c.controller_id,
    active_player: c.controller_id,
    target_player: None,
    opponent_ids: [],
    is_tapped: None,
    zone: c.zone,
    chosen_color: None,
  )
}

fn color_ref_matches(
  card: card.Card,
  ref: filters.ColorRef,
  context: filter_matcher.FilterContext,
) -> Bool {
  let colors = filter_matcher.get_card_colors(card.mana_cost)
  case ref {
    filters.Literal(c) -> list.contains(colors, c)
    filters.Chosen ->
      case context.chosen_color {
        Some(c) -> list.contains(colors, c)
        None -> False
      }
  }
}

fn check_deals_damage_triggers_inner(
  state: state.State,
  source_card: card.Card,
  controller_id: Int,
  target_is_player: Bool,
) -> state.State {
  let triggered =
    list.filter_map(source_card.abilities, fn(a) {
      case a {
        ability.Triggered(ta) -> {
          case ta.trigger {
            trigger.DealsDamage(filter) -> {
              case filter {
                None -> Ok(ta)
                Some(tf) ->
                  case target_filter_matches(tf, target_is_player, None) {
                    True -> Ok(ta)
                    False -> Error(Nil)
                  }
              }
            }
            _ -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    })
  put_triggers_on_stack(
    state,
    triggered,
    controller_id,
    source_card,
    Some(targeting.TargetCard(source_card.id)),
  )
}

pub fn check_deals_damage_triggers(
  state: state.State,
  source_card: card.Card,
  controller_id: Int,
  target_is_player: Bool,
) -> state.State {
  check_deals_damage_triggers_inner(
    state,
    source_card,
    controller_id,
    target_is_player,
  )
}

fn check_deals_combat_damage_triggers_inner(
  state: state.State,
  source_card: card.Card,
  controller_id: Int,
  target_is_player: Bool,
) -> state.State {
  let triggered =
    list.filter_map(source_card.abilities, fn(a) {
      case a {
        ability.Triggered(ta) -> {
          case ta.trigger {
            trigger.DealsCombatDamage(filter) -> {
              case filter {
                None -> Ok(ta)
                Some(tf) ->
                  case target_filter_matches(tf, target_is_player, None) {
                    True -> Ok(ta)
                    False -> Error(Nil)
                  }
              }
            }
            _ -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    })
  put_triggers_on_stack(
    state,
    triggered,
    controller_id,
    source_card,
    Some(targeting.TargetCard(source_card.id)),
  )
}

pub fn check_deals_combat_damage_triggers(
  state: state.State,
  source_card: card.Card,
  controller_id: Int,
  target_is_player: Bool,
) -> state.State {
  check_deals_combat_damage_triggers_inner(
    state,
    source_card,
    controller_id,
    target_is_player,
  )
}

pub fn check_discarded_triggers(
  state: state.State,
  card: card.Card,
  controller_id: Int,
) -> state.State {
  let ctx = filter_context_for_controller(state, controller_id, None, zone.Hand)
  let triggered =
    list.filter_map(card.abilities, fn(a) {
      case a {
        ability.Triggered(ta) -> {
          case ta.trigger {
            trigger.Discarded(filter) -> {
              case filter_matcher.matches(card, filter, ctx) {
                True -> Ok(ta)
                False -> Error(Nil)
              }
            }
            _ -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    })
  put_triggers_on_stack(
    state,
    triggered,
    controller_id,
    card,
    Some(targeting.TargetPlayer(controller_id)),
  )
}

fn resolve_all_of(
  state: state.State,
  item: stack.StackItem,
  filter: filters.CardFilter,
) -> List(String) {
  list.flat_map(state.players, fn(p) {
    dict.fold(p.battlefield, [], fn(acc, card_id, perm) {
      let ctx =
        filter_context_for_item(
          state,
          item,
          p.id,
          Some(perm.tapped),
          zone.Battlefield,
        )
      case filter_matcher.matches(perm.card, filter, ctx) {
        True -> [card_id, ..acc]
        False -> acc
      }
    })
  })
}

fn count_matching(
  state: state.State,
  item: stack.StackItem,
  filter: filters.CardFilter,
) -> Int {
  list.fold(state.players, 0, fn(total, p) {
    total
    + list.fold(dict.values(p.battlefield), 0, fn(sub, perm) {
      let ctx =
        filter_context_for_item(
          state,
          item,
          p.id,
          Some(perm.tapped),
          zone.Battlefield,
        )
      sub
      + case filter_matcher.matches(perm.card, filter, ctx) {
        True -> 1
        False -> 0
      }
    })
  })
}

fn discard_cards(
  state: state.State,
  item: stack.StackItem,
  player_id: Int,
  filter: filters.CardFilter,
) -> #(state.State, Int, List(card.Card)) {
  case list.find(state.players, fn(p) { p.id == player_id }) {
    Ok(p) -> {
      let ctx = filter_context_for_item(state, item, player_id, None, zone.Hand)
      let to_discard =
        list.filter(p.hand, fn(c) { filter_matcher.matches(c, filter, ctx) })
      let count = list.length(to_discard)

      let new_state =
        state.State(
          ..state,
          players: player.update(state.players, player_id, fn(pl) {
            player.Player(
              ..pl,
              hand: list.filter(pl.hand, fn(c) {
                !filter_matcher.matches(c, filter, ctx)
              }),
              graveyard: list.append(pl.graveyard, to_discard),
            )
          }),
        )
      #(new_state, count, to_discard)
    }
    Error(_) -> #(state, 0, [])
  }
}

fn search_library(
  state: state.State,
  item: stack.StackItem,
  player_id: Int,
  filter: filters.CardFilter,
  destination: effects.SearchDestination,
  reveal: Bool,
  tapped: Bool,
) -> #(state.State, Int) {
  // reveal is currently a no-op (rule 701.15 — the engine has no
  // observer/UI channel). The matched card is found and moved to its
  // destination; the library is shuffled afterward per rule 701.18a.
  let _ = reveal
  case list.find(state.players, fn(p) { p.id == player_id }) {
    Ok(p) -> {
      let ctx =
        filter_context_for_item(state, item, player_id, None, zone.Library)
      case
        list.find(p.library, fn(c) { filter_matcher.matches(c, filter, ctx) })
      {
        Ok(card) -> {
          let state = remove_from_zone(state, player_id, card.id, zone.Library)
          let state = case destination {
            effects.Hand -> add_to_zone(state, player_id, card, zone.Hand)
            effects.Battlefield -> {
              let state = add_to_zone(state, player_id, card, zone.Battlefield)
              case tapped {
                True -> {
                  state.State(
                    ..state,
                    players: player.update(state.players, player_id, fn(p) {
                      player.Player(
                        ..p,
                        battlefield: permanent.update(
                          p.battlefield,
                          card.id,
                          fn(perm) { permanent.Permanent(..perm, tapped: True) },
                        ),
                      )
                    }),
                  )
                }
                False -> state
              }
            }
          }
          // Shuffle the remaining library per rule 701.18a.
          let state = shuffle_library(state, player_id)
          #(state, 1)
        }
        Error(_) -> {
          // No card found — still shuffle per rule 701.18a.
          let state = shuffle_library(state, player_id)
          #(state, 0)
        }
      }
    }
    Error(_) -> #(state, 0)
  }
}

/// Shuffle a player's library using the PRNG seed threaded through state
/// (rule 701.18a). The seed is advanced so subsequent random effects are
/// independent.
fn shuffle_library(state: state.State, player_id: Int) -> state.State {
  case player.find(state.players, player_id) {
    Ok(p) -> {
      let #(shuffled, new_seed) =
        random.step(random.shuffle(p.library), state.seed)
      let state = state.State(..state, seed: new_seed)
      state.State(
        ..state,
        players: player.update(state.players, player_id, fn(_) {
          player.Player(..p, library: shuffled)
        }),
      )
    }
    Error(_) -> state
  }
}

fn check_player_loss_sba(state: state.State) -> #(state.State, Bool) {
  let #(state, changed) =
    list.fold(state.players, #(state, False), fn(acc, p) {
      let #(s, _) = acc
      case p.life <= 0 {
        True -> #(lose_game(s, p.id), True)
        False -> acc
      }
    })
  #(state, changed)
}

fn check_state_based_actions_loop(
  state: state.State,
  depth: Int,
) -> state.State {
  case depth >= 20 {
    True -> state
    False -> {
      let #(state, changed1) = check_player_loss_sba(state)
      let #(state, changed2) = remove_dead_creatures(state)
      let #(state, changed3) = check_legend_rule(state)
      let #(state, changed4) = check_aura_illegal_attachment(state)
      let #(state, changed5) = check_equipment_illegal_attachment(state)
      let #(state, changed6) = check_tokens_in_non_battlefield_zones(state)

      case
        changed1 || changed2 || changed3 || changed4 || changed5 || changed6
      {
        True -> check_state_based_actions_loop(state, depth + 1)
        False -> state
      }
    }
  }
}

pub fn check_state_based_actions(state: state.State) -> state.State {
  check_state_based_actions_loop(state, 0)
}

/// Check that tokens in non-battlefield zones cease to exist (rule 704.5d).
/// A token that is in a zone other than the battlefield is removed from that zone.
fn check_tokens_in_non_battlefield_zones(
  state: state.State,
) -> #(state.State, Bool) {
  // Count tokens in non-battlefield zones before removal
  let token_count =
    list.fold(state.players, 0, fn(total, p) {
      total
      + list.length(list.filter(p.hand, fn(c) { c.is_token }))
      + list.length(list.filter(p.graveyard, fn(c) { c.is_token }))
      + list.length(list.filter(p.library, fn(c) { c.is_token }))
      + list.length(list.filter(p.exile, fn(c) { c.is_token }))
    })
  let players =
    list.map(state.players, fn(p) {
      player.Player(
        ..p,
        hand: list.filter(p.hand, fn(c) { !c.is_token }),
        graveyard: list.filter(p.graveyard, fn(c) { !c.is_token }),
        library: list.filter(p.library, fn(c) { !c.is_token }),
        exile: list.filter(p.exile, fn(c) { !c.is_token }),
      )
    })
  #(state.State(..state, players:), token_count > 0)
}

fn remove_dead_creatures(state: state.State) -> #(state.State, Bool) {
  // Collect IDs of creatures that will die (for static effect removal tracking)
  let dead_ids =
    list.flat_map(state.players, fn(p) {
      dict.fold(p.battlefield, [], fn(acc, card_id, perm) {
        case perm.card.card_type, perm.card.toughness {
          card_type.Creature, Some(toughness)
            if perm.damage >= toughness || toughness <= 0
          -> [card_id, ..acc]
          _, _ -> acc
        }
      })
    })
  let has_dead = dead_ids != []
  let state =
    state.State(
      ..state,
      pending_removed_sources: list.append(
        state.pending_removed_sources,
        dead_ids,
      ),
    )

  // First collect the dead creatures and add their triggers
  let state =
    list.fold(state.players, state, fn(s, p) {
      dict.fold(p.battlefield, s, fn(s, _card_id, perm) {
        case perm.card.card_type, perm.card.toughness {
          card_type.Creature, Some(toughness)
            if perm.damage >= toughness || toughness <= 0
          -> {
            let s = check_leaves_battlefield_triggers(s, perm.card, p.id)
            check_dies_triggers(s, perm.card, p.id)
          }
          _, _ -> s
        }
      })
    })
  // Then remove the dead creatures from the battlefield
  let players =
    list.map(state.players, fn(p) {
      let #(battlefield, graveyard) =
        dict.fold(
          p.battlefield,
          #(p.battlefield, p.graveyard),
          fn(acc, card_id, perm) {
            let #(battlefield, graveyard) = acc
            case perm.card.card_type, perm.card.toughness {
              card_type.Creature, Some(toughness)
                if perm.damage >= toughness || toughness <= 0
              -> {
                #(dict.delete(battlefield, card_id), [perm.card, ..graveyard])
              }
              _, _ -> #(battlefield, graveyard)
            }
          },
        )
      player.Player(..p, battlefield:, graveyard:)
    })
  #(state.State(..state, players:), has_dead)
}

fn check_legend_rule(state: state.State) -> #(state.State, Bool) {
  // Rule 704.5j: If a player controls two or more legendary permanents
  // with the same name, that player chooses one to keep and puts the others
  // into their owner's graveyard.
  let #(state, changed) =
    list.fold(state.players, #(state, False), fn(acc, p) {
      let #(s, any) = acc
      // Collect legendary permanent IDs grouped by name
      let legendaries_by_name =
        dict.fold(p.battlefield, dict.new(), fn(acc, card_id, perm) {
          case list.contains(perm.card.supertypes, supertype.Legendary) {
            True -> {
              let name = perm.card.name
              let existing = dict.get(acc, name) |> result.unwrap([])
              dict.insert(acc, name, [card_id, ..existing])
            }
            False -> acc
          }
        })

      // For each group with 2+ permanents, keep one, destroy rest
      dict.fold(legendaries_by_name, #(s, any), fn(inner_acc, _name, card_ids) {
        let #(s, any) = inner_acc
        case list.length(card_ids) >= 2 {
          True -> {
            // Keep the first one, destroy the rest
            let to_destroy = list.drop(card_ids, 1)
            #(list.fold(to_destroy, s, destroy_card), True)
          }
          False -> #(s, any)
        }
      })
    })
  #(state, changed)
}

/// Check if a permanent is an Aura
fn is_aura(perm: permanent.Permanent) -> Bool {
  list.contains(perm.card.subtypes, "Aura")
}

/// Check if a permanent is an Equipment
fn is_equipment(perm: permanent.Permanent) -> Bool {
  list.contains(perm.card.subtypes, "Equipment")
}

/// Find a permanent on any player's battlefield by card ID
fn find_permanent_on_battlefield(
  state: state.State,
  card_id: String,
) -> Result(#(permanent.Permanent, Int), Nil) {
  list.find_map(state.players, fn(p) {
    case permanent.find(p.battlefield, card_id) {
      Ok(perm) -> Ok(#(perm, p.id))
      Error(_) -> Error(Nil)
    }
  })
}

/// Find a card in any zone (battlefield, hand, graveyard, library, exile,
/// stack), returning the card, its zone, and the owning player's id.
/// For battlefield, the owner is the permanent's controller. For the stack,
/// the owner is the spell's controller.
pub fn find_card_in_any_zone(
  state: state.State,
  card_id: String,
) -> Option(#(card.Card, zone.Zone, Int)) {
  // Check battlefield
  case find_permanent_on_battlefield(state, card_id) {
    Ok(#(perm, owner_id)) -> Some(#(perm.card, zone.Battlefield, owner_id))
    Error(_) -> {
      // Check each player's hand, graveyard, library, exile
      case
        list.find_map(state.players, fn(p) {
          case find_in_player_zone(p, card_id) {
            Some(#(c, z)) -> Ok(#(c, z, p.id))
            None -> Error(Nil)
          }
        })
      {
        Ok(result) -> Some(result)
        Error(_) -> {
          // Check stack
          case
            list.find_map(state.stack, fn(si) {
              case si.card.id == card_id {
                True -> Ok(#(si.card, zone.Stack, si.controller_id))
                False -> Error(Nil)
              }
            })
          {
            Ok(result) -> Some(result)
            Error(_) -> None
          }
        }
      }
    }
  }
}

fn find_in_player_zone(
  p: player.Player,
  card_id: String,
) -> Option(#(card.Card, zone.Zone)) {
  case list.find(p.hand, fn(c) { c.id == card_id }) {
    Ok(c) -> Some(#(c, zone.Hand))
    Error(_) ->
      case list.find(p.graveyard, fn(c) { c.id == card_id }) {
        Ok(c) -> Some(#(c, zone.Graveyard))
        Error(_) ->
          case list.find(p.library, fn(c) { c.id == card_id }) {
            Ok(c) -> Some(#(c, zone.Library))
            Error(_) ->
              case list.find(p.exile, fn(c) { c.id == card_id }) {
                Ok(c) -> Some(#(c, zone.Exile))
                Error(_) -> None
              }
          }
      }
  }
}

/// Check that a card in a non-battlefield, non-stack zone is in the spell
/// controller's corresponding zone (the "your" implicit rule, plan §Target
/// Filter). Battlefield and Stack are shared zones with no implicit
/// controller restriction.
fn check_zone_controller(
  item: stack.StackItem,
  card_zone: zone.Zone,
  owner_id: Int,
) -> Bool {
  case card_zone {
    zone.Battlefield | zone.Stack -> True
    zone.Graveyard | zone.Hand | zone.Library | zone.Exile ->
      owner_id == item.controller_id
  }
}

/// Validate a chosen target against a `TargetInfo` filter and zone rules.
/// Called from `action.validate_chosen_targets` during `ChooseTargets`.
pub fn validate_target(
  state: state.State,
  item: stack.StackItem,
  target_info: targeting.TargetInfo,
  target: targeting.TargetIdentifier,
) -> Result(Nil, error.Error) {
  case target {
    targeting.TargetCard(card_id) -> {
      case find_card_in_any_zone(state, card_id) {
        Some(#(c, card_zone, owner_id)) -> {
          // Enforce the "your" implicit rule for personal zones.
          use <- util.guard(
            check_zone_controller(item, card_zone, owner_id),
            Error(error.InvalidAction(
              "Target is not in your " <> zone_to_string(card_zone),
            )),
          )
          // Validate the target filter against the candidate card.
          let candidate =
            Some(TargetCandidate(
              card: c,
              controller_id: owner_id,
              zone: card_zone,
            ))
          use <- util.guard(
            target_filter_matches(target_info.filter, False, candidate),
            Error(error.InvalidAction("Target does not match filter")),
          )
          // Also check hexproof/shroud/protection for battlefield targets.
          use _ <- result.try(check_target_legality(
            state,
            card_id,
            item.card,
            item.controller_id,
          ))
          Ok(Nil)
        }
        None -> Error(error.InvalidAction("Target card not found in any zone"))
      }
    }
    targeting.TargetPlayer(_) -> {
      use <- util.guard(
        target_filter_matches(target_info.filter, True, None),
        Error(error.InvalidAction("Target does not match filter")),
      )
      Ok(Nil)
    }
  }
}

fn zone_to_string(z: zone.Zone) -> String {
  case z {
    zone.Battlefield -> "battlefield"
    zone.Graveyard -> "graveyard"
    zone.Hand -> "hand"
    zone.Library -> "library"
    zone.Exile -> "exile"
    zone.Stack -> "stack"
  }
}

/// Check Aura illegal attachment (rule 704.5m):
/// If an Aura is attached to an illegal object or player, or is not attached
/// to anything, put it into its owner's graveyard.
fn check_aura_illegal_attachment(state: state.State) -> #(state.State, Bool) {
  list.fold(state.players, #(state, False), fn(acc, p) {
    let #(s, any) = acc
    dict.fold(p.battlefield, #(s, any), fn(inner_acc, card_id, perm) {
      let #(s, any) = inner_acc
      case is_aura(perm) {
        False -> #(s, any)
        True -> {
          case perm.attached_to {
            // Aura not attached to anything -> put in graveyard
            None -> #(destroy_card(s, card_id), True)
            Some(attached_id) -> {
              // Aura attached to something - check if target is still on battlefield
              case find_permanent_on_battlefield(s, attached_id) {
                Ok(_) -> #(s, any)
                // Target still exists, aura stays
                Error(_) -> #(destroy_card(s, card_id), True)
                // Target gone, destroy aura
              }
            }
          }
        }
      }
    })
  })
}

/// Check Equipment illegal attachment (rule 704.5n):
/// If an Equipment is attached to an illegal permanent, it becomes unattached
/// (remains on battlefield but unattached).
fn check_equipment_illegal_attachment(
  state: state.State,
) -> #(state.State, Bool) {
  list.fold(state.players, #(state, False), fn(acc, p) {
    let #(s, any) = acc
    dict.fold(p.battlefield, #(s, any), fn(inner_acc, card_id, perm) {
      let #(s, any) = inner_acc
      case is_equipment(perm) {
        False -> #(s, any)
        True -> {
          case perm.attached_to {
            // Equipment not attached to anything - fine, stays
            None -> #(s, any)
            Some(attached_id) -> {
              // Equipment attached to something - check if target is still on battlefield
              case find_permanent_on_battlefield(s, attached_id) {
                Ok(_) -> #(s, any)
                // Target still exists, equipment stays attached
                Error(_) -> {
                  // Target gone - unattach the equipment
                  #(
                    state.State(
                      ..s,
                      players: player.update(s.players, p.id, fn(pl) {
                        player.Player(
                          ..pl,
                          battlefield: permanent.update(
                            pl.battlefield,
                            card_id,
                            fn(eq_perm) {
                              permanent.Permanent(..eq_perm, attached_to: None)
                            },
                          ),
                        )
                      }),
                    ),
                    True,
                  )
                }
              }
            }
          }
        }
      }
    })
  })
}

pub fn lose_game(state: state.State, player_id: Int) -> state.State {
  // Rule 104.5: When a player loses, they leave the game.
  // - Remove all permanents from their battlefield
  // - Remove all spells/abilities they own from the stack
  // - Clear their hand, library, graveyard, and exile
  // Collect battlefield card IDs to remove their static effects
  let battlefield_ids =
    list.fold(state.players, [], fn(ids, p) {
      case p.id == player_id {
        True -> dict.keys(p.battlefield)
        False -> ids
      }
    })
  let state =
    state.State(
      ..state,
      pending_removed_sources: list.append(
        state.pending_removed_sources,
        battlefield_ids,
      ),
    )
  state.State(
    ..state,
    stack: list.filter(state.stack, fn(item) { item.controller_id != player_id }),
    players: player.update(state.players, player_id, fn(p) {
      player.Player(
        ..p,
        life: 0,
        battlefield: dict.new(),
        hand: [],
        library: [],
        graveyard: [],
        exile: [],
      )
    }),
  )
}

fn create_token(
  state: state.State,
  player_id: Int,
  token: effects.TokenDefinition,
) -> state.State {
  let token_id =
    "token_" <> token.name <> "_" <> int.to_string(state.turn_index)
  let token_card =
    card.Card(
      id: token_id,
      name: token.name,
      supertypes: [],
      subtypes: [],
      card_type: list.first(token.types)
        |> result.unwrap(card_type.Creature),
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
      power: Some(token.power),
      toughness: Some(token.toughness),
      abilities: [],
      is_token: True,
    )
  let current_cycle = state.turn_cycle(state)
  let token_perm = permanent.from_card(token_card, player_id, current_cycle)

  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(p.battlefield, token_id, token_perm),
      )
    }),
  )
}

fn destroy_card(state: state.State, card_id: String) -> state.State {
  case find_card_on_battlefield(state, card_id) {
    Ok(#(perm, owner_id)) -> {
      let state =
        state.State(..state, pending_removed_sources: [
          card_id,
          ..state.pending_removed_sources
        ])
      let state = check_leaves_battlefield_triggers(state, perm.card, owner_id)
      let state = case perm.card.card_type {
        card_type.Creature -> check_dies_triggers(state, perm.card, owner_id)
        _ -> state
      }
      state.State(
        ..state,
        players: player.update(state.players, owner_id, fn(p) {
          player.Player(
            ..p,
            battlefield: dict.delete(p.battlefield, card_id),
            graveyard: [perm.card, ..p.graveyard],
          )
        }),
      )
    }
    Error(_) -> state
  }
}

/// Try to destroy a card, consulting regeneration shields if
/// `cant_regenerate` is False. If a shield is available, the permanent
/// survives: remove one shield, tap it, remove all marked damage, and
/// remove it from combat (rule 701.9).
fn try_destroy_card(
  state: state.State,
  card_id: String,
  cant_regenerate: Bool,
) -> state.State {
  case cant_regenerate {
    True -> destroy_card(state, card_id)
    False -> {
      let shields =
        dict.get(state.regeneration_shields, card_id) |> result.unwrap(0)
      case shields > 0 {
        True -> {
          // Consume one shield and regenerate the permanent.
          let new_shields = case shields - 1 {
            0 -> dict.delete(state.regeneration_shields, card_id)
            n -> dict.insert(state.regeneration_shields, card_id, n)
          }
          state.State(..state, regeneration_shields: new_shields)
          |> regenerate_permanent(card_id)
        }
        False -> destroy_card(state, card_id)
      }
    }
  }
}

/// Apply regeneration to a permanent: tap it, remove marked damage, and
/// remove it from combat (rule 701.9).
fn regenerate_permanent(state: state.State, card_id: String) -> state.State {
  state.State(
    ..state,
    players: list.map(state.players, fn(p) {
      player.Player(
        ..p,
        battlefield: permanent.update(p.battlefield, card_id, fn(perm) {
          permanent.Permanent(..perm, tapped: True, damage: 0)
        }),
      )
    }),
    // Remove from combat if applicable
    attacking_creatures: option.map(state.attacking_creatures, fn(attacks) {
      list.filter(attacks, fn(a) { a.attacker != card_id })
    }),
    blocking_creatures: list.filter(state.blocking_creatures, fn(b) {
      b.blocker != card_id
    }),
  )
}

fn bounce_card(state: state.State, card_id: String) -> state.State {
  case find_card_on_battlefield(state, card_id) {
    Ok(#(perm, owner_id)) -> {
      let state =
        state.State(..state, pending_removed_sources: [
          card_id,
          ..state.pending_removed_sources
        ])
      let state = check_leaves_battlefield_triggers(state, perm.card, owner_id)
      state.State(
        ..state,
        players: player.update(state.players, owner_id, fn(p) {
          player.Player(
            ..p,
            battlefield: dict.delete(p.battlefield, card_id),
            hand: [perm.card, ..p.hand],
          )
        }),
      )
    }
    Error(_) -> state
  }
}

fn move_card_to_destination(
  state: state.State,
  item: stack.StackItem,
) -> state.State {
  case item.effect_override {
    Some(_) -> state
    None -> {
      case item.card.card_type {
        card_type.Creature | card_type.Artifact | card_type.Enchantment ->
          put_on_battlefield(state, item)
        card_type.Instant | card_type.Sorcery -> put_in_graveyard(state, item)
        card_type.Land -> put_on_battlefield(state, item)
      }
    }
  }
}

fn put_on_battlefield(
  state: state.State,
  item: stack.StackItem,
) -> state.State {
  let current_cycle = state.turn_cycle(state)
  let new_perm =
    permanent.from_card(item.card, item.controller_id, current_cycle)

  state.State(
    ..state,
    players: player.update(state.players, item.controller_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(p.battlefield, item.card.id, new_perm),
      )
    }),
  )
}

fn put_in_graveyard(state: state.State, item: stack.StackItem) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, item.controller_id, fn(p) {
      player.Player(..p, graveyard: [item.card, ..p.graveyard])
    }),
  )
}

fn resolve_step(
  state: state.State,
  item: stack.StackItem,
  step: effects.EffectStep,
  previous_step_result: Int,
) -> Result(#(state.State, Int), error.Error) {
  case step {
    effects.DealDamage(amount:, target:, source_is_combat: _) -> {
      let amount = resolve_amount(state, item, amount, previous_step_result)
      // Check AllFromSource prevention: if this source is on the
      // source_prevention list, prevent all damage from it.
      let source_prevented =
        list.contains(state.source_prevention, item.card.id)
      let key = resolve_prevention_target_key(state, item, target)
      let shield_amount =
        dict.get(state.prevention_shields, key)
        |> result.unwrap(0)
      let prevented = case source_prevented {
        True -> amount
        False ->
          case shield_amount >= amount {
            True -> amount
            False -> shield_amount
          }
      }
      let remaining = amount - prevented
      let new_shields = case source_prevented {
        True -> state.prevention_shields
        False ->
          case shield_amount - prevented {
            0 -> dict.delete(state.prevention_shields, key)
            n -> dict.insert(state.prevention_shields, key, n)
          }
      }
      let state = state.State(..state, prevention_shields: new_shields)
      case resolve_ref_as_player(state, item, target) {
        Ok(player_id) -> {
          let state = deal_damage_to_player(state, player_id, remaining)
          let state =
            check_deals_damage_triggers(
              state,
              item.card,
              item.controller_id,
              True,
            )
          Ok(#(state, remaining))
        }
        Error(_) -> {
          use card_id <- result.try(resolve_ref_as_card(state, item, target))
          let state = deal_damage_to_creature(state, card_id, remaining)
          let state =
            check_deals_damage_triggers(
              state,
              item.card,
              item.controller_id,
              False,
            )
          Ok(#(state, remaining))
        }
      }
    }
    effects.DrawCards(num:, target:) -> {
      let amount = resolve_amount(state, item, num, previous_step_result)
      use player_id <- result.try(resolve_ref_as_player(state, item, target))
      Ok(#(draw_cards(state, player_id, amount), amount))
    }
    effects.GainLife(amount:, target:) -> {
      let amount = resolve_amount(state, item, amount, previous_step_result)
      use player_id <- result.try(resolve_ref_as_player(state, item, target))
      Ok(#(gain_life(state, player_id, amount), amount))
    }
    effects.LoseLife(amount:, target:) -> {
      let amount = resolve_amount(state, item, amount, previous_step_result)
      use player_id <- result.try(resolve_ref_as_player(state, item, target))
      Ok(#(lose_life(state, player_id, amount), amount))
    }
    effects.ProduceMana(mana:) ->
      Ok(#(produce_mana(state, item.controller_id, mana), 0))
    effects.Mill(num:, target:) -> {
      let amount = resolve_amount(state, item, num, previous_step_result)
      use player_id <- result.try(resolve_ref_as_player(state, item, target))
      Ok(#(mill_cards(state, player_id, amount), amount))
    }
    effects.LoseGame(target:) -> {
      use player_id <- result.try(resolve_ref_as_player(state, item, target))
      Ok(#(lose_game(state, player_id), 0))
    }
    effects.CreateToken(token:) ->
      Ok(#(create_token(state, item.controller_id, token), 0))
    effects.Destroy(target:, cant_regenerate:) -> {
      let state = case target {
        targeting.AllOf(filter) ->
          list.fold(resolve_all_of(state, item, filter), state, fn(s, card_id) {
            try_destroy_card(s, card_id, cant_regenerate)
          })
        _ -> {
          case resolve_ref_as_card(state, item, target) {
            Ok(card_id) -> try_destroy_card(state, card_id, cant_regenerate)
            Error(_) -> state
          }
        }
      }
      Ok(#(state, 0))
    }
    effects.Bounce(target:) -> {
      let state = case target {
        targeting.AllOf(filter) ->
          list.fold(resolve_all_of(state, item, filter), state, bounce_card)
        _ -> {
          case resolve_ref_as_card(state, item, target) {
            Ok(card_id) -> bounce_card(state, card_id)
            Error(_) -> state
          }
        }
      }
      Ok(#(state, 0))
    }
    effects.TapOrUntap(target:, mode:) -> {
      let tapped = mode == effects.Tap
      let state = case target {
        targeting.AllOf(filter) ->
          list.fold(resolve_all_of(state, item, filter), state, fn(s, card_id) {
            state.State(
              ..s,
              players: list.map(s.players, fn(p) {
                player.Player(
                  ..p,
                  battlefield: permanent.update(
                    p.battlefield,
                    card_id,
                    fn(perm) { permanent.Permanent(..perm, tapped:) },
                  ),
                )
              }),
            )
          })
        _ -> {
          case resolve_ref_as_card(state, item, target) {
            Ok(card_id) ->
              state.State(
                ..state,
                players: list.map(state.players, fn(p) {
                  player.Player(
                    ..p,
                    battlefield: permanent.update(
                      p.battlefield,
                      card_id,
                      fn(perm) { permanent.Permanent(..perm, tapped:) },
                    ),
                  )
                }),
              )
            Error(_) -> state
          }
        }
      }
      Ok(#(state, 0))
    }
    effects.CounterSpell(target:) -> {
      let state = case target {
        targeting.AllOf(filter) ->
          state.State(
            ..state,
            stack: list.filter(state.stack, fn(si) {
              let ctx =
                filter_context_for_item(
                  state,
                  item,
                  si.controller_id,
                  None,
                  zone.Stack,
                )
              !filter_matcher.matches(si.card, filter, ctx)
            }),
          )
        _ -> {
          case resolve_ref_as_card(state, item, target) {
            Ok(card_id) ->
              state.State(
                ..state,
                stack: list.filter(state.stack, fn(si) { si.card.id != card_id }),
              )
            Error(_) -> state
          }
        }
      }
      Ok(#(state, 0))
    }
    effects.MoveCard(target:, from_zone:, to_zone:) -> {
      let state = case target {
        targeting.AllOf(filter) ->
          list.fold(resolve_all_of(state, item, filter), state, fn(s, card_id) {
            move_card(s, card_id, from_zone, to_zone)
          })
        _ -> {
          case resolve_ref_as_card(state, item, target) {
            Ok(card_id) -> move_card(state, card_id, from_zone, to_zone)
            Error(_) -> state
          }
        }
      }
      Ok(#(state, 0))
    }
    effects.PumpCreature(
      target:,
      power:,
      toughness:,
      add_keywords:,
      duration: _,
    ) -> {
      let state = case resolve_ref_as_card(state, item, target) {
        Ok(card_id) -> {
          let power_bonus = resolve_amount(state, item, power, 0)
          let toughness_bonus = resolve_amount(state, item, toughness, 0)
          pump_creature(
            state,
            card_id,
            power_bonus,
            toughness_bonus,
            add_keywords,
          )
        }
        Error(_) -> state
      }
      Ok(#(state, 0))
    }
    effects.Discard(who:, filter:) -> {
      use player_id <- result.try(resolve_ref_as_player(state, item, who))
      let #(new_state, count, discarded) =
        discard_cards(state, item, player_id, filter)
      let state =
        list.fold(discarded, new_state, fn(s, c) {
          check_discarded_triggers(s, c, player_id)
        })
      Ok(#(state, count))
    }
    effects.SearchLibrary(target:, filter:, destination:, reveal:, tapped:) -> {
      use player_id <- result.try(resolve_ref_as_player(state, item, target))
      let #(new_state, count) =
        search_library(
          state,
          item,
          player_id,
          filter,
          destination,
          reveal,
          tapped,
        )
      Ok(#(new_state, count))
    }
    effects.ChooseOne(modes:) -> {
      let mode_index = option.unwrap(item.chosen_mode, 0)
      case list.drop(modes, mode_index) |> list.first {
        Ok(mode) -> resolve_effect(state, item, mode.effect)
        Error(_) ->
          Error(error.InvalidAction("Invalid mode index for ChooseOne"))
      }
    }
    effects.PreventDamage(target:, mode:) -> {
      case mode {
        effects.Shield(amount:) -> {
          let amount = resolve_amount(state, item, amount, previous_step_result)
          let key = resolve_prevention_target_key(state, item, target)
          let new_shields = dict.insert(state.prevention_shields, key, amount)
          Ok(#(state.State(..state, prevention_shields: new_shields), amount))
        }
        effects.AllFromSource -> {
          // Track the source card whose damage is fully prevented.
          // The target ref identifies the source (e.g. Reverse Damage
          // targets the creature whose damage is prevented).
          case resolve_ref_as_card(state, item, target) {
            Ok(card_id) ->
              Ok(#(
                state.State(..state, source_prevention: [
                  card_id,
                  ..state.source_prevention
                ]),
                0,
              ))
            Error(_) -> Ok(#(state, 0))
          }
        }
        effects.GlobalCombat ->
          Ok(#(state.State(..state, global_combat_prevention: True), 0))
      }
    }
    effects.Scry(num:, target:) -> {
      let amount = resolve_amount(state, item, num, previous_step_result)
      use player_id <- result.try(resolve_ref_as_player(state, item, target))
      // Store the pending scry; the player supplies the reorder via the
      // Scry action (rule 701.22).
      Ok(#(
        state.State(
          ..state,
          pending_scry: Some(state.ScryPending(num: amount, player_id:)),
        ),
        amount,
      ))
    }
    effects.ExtraTurn(target:) -> {
      use player_id <- result.try(resolve_ref_as_player(state, item, target))
      Ok(#(
        state.State(..state, pending_extra_turns: [
          player_id,
          ..state.pending_extra_turns
        ]),
        0,
      ))
    }
    effects.CreateDelayedTrigger(trigger:) -> {
      Ok(#(
        state.State(..state, pending_delayed_triggers: [
          trigger,
          ..state.pending_delayed_triggers
        ]),
        0,
      ))
    }
    effects.FlipCoin(flipper: _) -> {
      // Flip a coin using the PRNG seed threaded through state. The seed
      // is advanced so subsequent random effects are independent.
      let coin = random.choose(effects.Heads, effects.Tails)
      let #(result, new_seed) = random.step(coin, state.seed)
      let state = state.State(..state, seed: new_seed)
      let output = case result {
        effects.Heads -> 1
        effects.Tails -> 0
      }
      Ok(#(state, output))
    }
    effects.ChooseColor -> {
      // The chosen color is stored on the StackItem via the ChooseColor
      // action. This step is a no-op — the color is already available to
      // ColorRef.Chosen via filter_matcher.FilterContext.chosen_color.
      Ok(#(state, 0))
    }
    effects.Regenerate(target:) -> {
      use card_id <- result.try(resolve_ref_as_card(state, item, target))
      let current =
        dict.get(state.regeneration_shields, card_id) |> result.unwrap(0)
      let new_shields =
        dict.insert(state.regeneration_shields, card_id, current + 1)
      Ok(#(state.State(..state, regeneration_shields: new_shields), 0))
    }
    effects.GainControl(target:, duration: _) -> {
      use card_id <- result.try(resolve_ref_as_card(state, item, target))
      use #(perm, old_owner_id) <- result.try(find_card_on_battlefield(
        state,
        card_id,
      ))
      let updated_perm =
        permanent.Permanent(..perm, owner_id: item.controller_id)
      case old_owner_id == item.controller_id {
        True -> {
          let players =
            list.map(state.players, fn(p) {
              case p.id == old_owner_id {
                True ->
                  player.Player(
                    ..p,
                    battlefield: dict.insert(
                      p.battlefield,
                      card_id,
                      updated_perm,
                    ),
                  )
                False -> p
              }
            })
          Ok(#(state.State(..state, players:), 0))
        }
        False -> {
          let remove_from_old = fn(p) {
            player.Player(..p, battlefield: dict.delete(p.battlefield, card_id))
          }
          let add_to_new = fn(p) {
            player.Player(
              ..p,
              battlefield: dict.insert(p.battlefield, card_id, updated_perm),
            )
          }
          let players =
            list.map(state.players, fn(p) {
              case p.id == old_owner_id {
                True -> remove_from_old(p)
                False -> p
              }
            })
          let players =
            list.map(players, fn(p) {
              case p.id == item.controller_id {
                True -> add_to_new(p)
                False -> p
              }
            })
          Ok(#(state.State(..state, players:), 0))
        }
      }
    }
    effects.DealDividedDamage(total_amount:) -> {
      let total =
        resolve_amount(state, item, total_amount, previous_step_result)
      // Gather all chosen target identifiers (flattened).
      let all_targets =
        list.flat_map(item.chosen_targets, fn(ct) { ct.targets })
      // Validate: allocations must sum to total and be non-negative.
      let allocations = item.damage_division
      let sum = list.fold(allocations, 0, fn(a, b) { a + b })
      use <- util.guard(
        list.length(allocations) == list.length(all_targets)
          && sum == total
          && !list.any(allocations, fn(a) { a < 0 }),
        Error(error.InvalidAction(
          "DealDividedDamage: allocations must sum to total, be non-negative, and match the number of targets",
        )),
      )
      // Deal each allocation to the corresponding target.
      let state =
        list.fold(list.zip(allocations, with: all_targets), state, fn(s, pair) {
          let #(alloc, target) = pair
          deal_divided_damage_to_target(s, item, alloc, target)
        })
      Ok(#(state, total))
    }
    effects.RevealHand(of: _, to: _) -> {
      // Rule 701.15: revealing is informational. The engine has no
      // observer/UI channel, so this is a no-op.
      Ok(#(state, 0))
    }
    effects.ManaClash(target:) -> {
      // Mana Clash: repeat coin flips for the target player and the
      // controller until both flip heads simultaneously. Each player
      // deals 1 damage to the other per tails. Coin flips use the PRNG
      // seed threaded through state.
      use target_player_id <- result.try(resolve_ref_as_player(
        state,
        item,
        target,
      ))
      let state = mana_clash_loop(state, item.controller_id, target_player_id)
      Ok(#(state, 0))
    }
  }
}

/// Deal a single divided-damage allocation to a target (player or creature).
fn deal_divided_damage_to_target(
  state: state.State,
  _item: stack.StackItem,
  amount: Int,
  target: targeting.TargetIdentifier,
) -> state.State {
  case target {
    targeting.TargetPlayer(player_id) ->
      deal_damage_to_player(state, player_id, amount)
    targeting.TargetCard(card_id) ->
      deal_damage_to_creature(state, card_id, amount)
  }
}

/// Mana Clash loop: flip coins for both players until both get heads.
/// Each tails result deals 1 damage from that player to the other. Coin
/// flips advance the PRNG seed threaded through state.
fn mana_clash_loop(
  state: state.State,
  controller_id: Int,
  target_player_id: Int,
) -> state.State {
  let coin = random.choose(effects.Heads, effects.Tails)
  let #(controller_flip, seed1) = random.step(coin, state.seed)
  let #(target_flip, seed2) = random.step(coin, seed1)
  let state = state.State(..state, seed: seed2)
  let state = case controller_flip {
    effects.Tails -> deal_damage_to_player(state, target_player_id, 1)
    effects.Heads -> state
  }
  let state = case target_flip {
    effects.Tails -> deal_damage_to_player(state, controller_id, 1)
    effects.Heads -> state
  }
  case controller_flip == effects.Heads && target_flip == effects.Heads {
    True -> state
    False -> mana_clash_loop(state, controller_id, target_player_id)
  }
}

fn keyword_to_string(keyword: effects.Keyword) -> String {
  case keyword {
    effects.Flying -> "Flying"
    effects.Trample -> "Trample"
    effects.FirstStrike -> "First strike"
    effects.DoubleStrike -> "Double strike"
    effects.Haste -> "Haste"
    effects.Vigilance -> "Vigilance"
    effects.Deathtouch -> "Deathtouch"
    effects.Mountainwalk -> "Mountainwalk"
    effects.Hexproof -> "Hexproof"
    effects.Shroud -> "Shroud"
    effects.ProtectionFromColor(c) -> "Protection from " <> color_to_string(c)
    effects.ProtectionFromType(ct) ->
      "Protection from " <> card_type_to_protection_string(ct)
  }
}

fn color_to_string(c: color.Color) -> String {
  case c {
    color.White -> "White"
    color.Blue -> "Blue"
    color.Black -> "Black"
    color.Red -> "Red"
    color.Green -> "Green"
    color.Colorless -> "Colorless"
  }
}

fn card_type_to_protection_string(ct: card_type.CardType) -> String {
  case ct {
    card_type.Land -> "lands"
    card_type.Creature -> "creatures"
    card_type.Instant -> "instants"
    card_type.Sorcery -> "sorceries"
    card_type.Artifact -> "artifacts"
    card_type.Enchantment -> "enchantments"
  }
}

fn pump_creature(
  state: state.State,
  card_id: String,
  power_bonus: Int,
  toughness_bonus: Int,
  keywords: List(effects.Keyword),
) -> state.State {
  let keyword_strings = list.map(keywords, keyword_to_string)
  list.fold(state.players, state, fn(acc_state, p) {
    case permanent.find(p.battlefield, card_id) {
      Ok(_) ->
        state.State(
          ..acc_state,
          players: player.update(acc_state.players, p.id, fn(player) {
            player.Player(
              ..player,
              battlefield: permanent.update(
                player.battlefield,
                card_id,
                fn(perm) {
                  permanent.Permanent(
                    ..perm,
                    granted_keywords: list.append(
                      perm.granted_keywords,
                      keyword_strings,
                    ),
                    card: card.Card(
                      ..perm.card,
                      power: Some(
                        option.unwrap(perm.card.power, 0) + power_bonus,
                      ),
                      toughness: Some(
                        option.unwrap(perm.card.toughness, 0) + toughness_bonus,
                      ),
                      supertypes: perm.card.supertypes,
                    ),
                  )
                },
              ),
            )
          }),
        )
      Error(_) -> acc_state
    }
  })
}

fn move_card(
  state: state.State,
  card_id: String,
  from_zone: zone.Zone,
  to_zone: zone.Zone,
) -> state.State {
  case from_zone, to_zone {
    // Already implemented
    zone.Battlefield, zone.Graveyard -> destroy_card(state, card_id)
    zone.Battlefield, zone.Hand -> bounce_card(state, card_id)

    // New: Battlefield to other zones
    zone.Battlefield, zone.Library ->
      move_from_battlefield_to_library(state, card_id)
    zone.Battlefield, zone.Exile ->
      move_from_battlefield_to_exile(state, card_id)

    // New: Graveyard to other zones
    zone.Graveyard, zone.Hand ->
      move_card_between_players(state, card_id, zone.Graveyard, zone.Hand)
    zone.Graveyard, zone.Battlefield ->
      move_from_graveyard_to_battlefield(state, card_id)
    zone.Graveyard, zone.Library ->
      move_card_between_players(state, card_id, zone.Graveyard, zone.Library)
    zone.Graveyard, zone.Exile ->
      move_card_between_players(state, card_id, zone.Graveyard, zone.Exile)

    // New: Hand to other zones
    zone.Hand, zone.Battlefield -> move_from_hand_to_battlefield(state, card_id)
    zone.Hand, zone.Graveyard ->
      move_card_between_players(state, card_id, zone.Hand, zone.Graveyard)
    zone.Hand, zone.Library ->
      move_card_between_players(state, card_id, zone.Hand, zone.Library)
    zone.Hand, zone.Exile ->
      move_card_between_players(state, card_id, zone.Hand, zone.Exile)

    // New: Library to other zones
    zone.Library, zone.Hand ->
      move_card_between_players(state, card_id, zone.Library, zone.Hand)
    zone.Library, zone.Battlefield ->
      move_card_between_players(state, card_id, zone.Library, zone.Battlefield)
    zone.Library, zone.Graveyard ->
      move_card_between_players(state, card_id, zone.Library, zone.Graveyard)
    zone.Library, zone.Exile ->
      move_card_between_players(state, card_id, zone.Library, zone.Exile)

    // New: Exile to other zones
    zone.Exile, zone.Hand ->
      move_card_between_players(state, card_id, zone.Exile, zone.Hand)
    zone.Exile, zone.Battlefield ->
      move_from_exile_to_battlefield(state, card_id)
    zone.Exile, zone.Graveyard ->
      move_card_between_players(state, card_id, zone.Exile, zone.Graveyard)
    zone.Exile, zone.Library ->
      move_card_between_players(state, card_id, zone.Exile, zone.Library)

    // Stack zone (not stored per-player, skip for now)
    zone.Stack, _ -> state
    _, zone.Stack -> state

    // Same zone — no-op
    zone.Hand, zone.Hand -> state
    zone.Battlefield, zone.Battlefield -> state
    zone.Graveyard, zone.Graveyard -> state
    zone.Library, zone.Library -> state
    zone.Exile, zone.Exile -> state
  }
}

fn move_from_battlefield_to_library(
  state: state.State,
  card_id: String,
) -> state.State {
  case find_card_on_battlefield(state, card_id) {
    Ok(#(perm, owner_id)) -> {
      let state =
        state.State(..state, pending_removed_sources: [
          card_id,
          ..state.pending_removed_sources
        ])
      let state = check_leaves_battlefield_triggers(state, perm.card, owner_id)
      state.State(
        ..state,
        players: player.update(state.players, owner_id, fn(p) {
          player.Player(
            ..p,
            battlefield: dict.delete(p.battlefield, card_id),
            library: [perm.card, ..p.library],
          )
        }),
      )
    }
    Error(_) -> state
  }
}

fn move_from_battlefield_to_exile(
  state: state.State,
  card_id: String,
) -> state.State {
  case find_card_on_battlefield(state, card_id) {
    Ok(#(perm, owner_id)) -> {
      let state =
        state.State(..state, pending_removed_sources: [
          card_id,
          ..state.pending_removed_sources
        ])
      let state = check_leaves_battlefield_triggers(state, perm.card, owner_id)
      state.State(
        ..state,
        players: player.update(state.players, owner_id, fn(p) {
          player.Player(
            ..p,
            battlefield: dict.delete(p.battlefield, card_id),
            exile: [perm.card, ..p.exile],
          )
        }),
      )
    }
    Error(_) -> state
  }
}

fn move_from_graveyard_to_battlefield(
  state: state.State,
  card_id: String,
) -> state.State {
  move_card_between_players(state, card_id, zone.Graveyard, zone.Battlefield)
}

fn move_from_hand_to_battlefield(
  state: state.State,
  card_id: String,
) -> state.State {
  move_card_between_players(state, card_id, zone.Hand, zone.Battlefield)
}

fn move_from_exile_to_battlefield(
  state: state.State,
  card_id: String,
) -> state.State {
  move_card_between_players(state, card_id, zone.Exile, zone.Battlefield)
}

fn move_card_between_players(
  state: state.State,
  card_id: String,
  from_zone: zone.Zone,
  to_zone: zone.Zone,
) -> state.State {
  // Find which player has this card in from_zone
  let result =
    list.find_map(state.players, fn(p) {
      let cards = get_zone_cards(p, from_zone)
      case list.find(cards, fn(c) { c.id == card_id }) {
        Ok(card) -> Ok(#(card, p.id))
        Error(_) -> Error(Nil)
      }
    })

  case result {
    Ok(#(card, owner_id)) -> {
      // Remove from source zone
      let state = remove_from_zone(state, owner_id, card_id, from_zone)
      // Add to destination zone
      add_to_zone(state, owner_id, card, to_zone)
    }
    Error(_) -> state
  }
}

fn get_zone_cards(player: player.Player, z: zone.Zone) -> List(card.Card) {
  case z {
    zone.Hand -> player.hand
    zone.Graveyard -> player.graveyard
    zone.Library -> player.library
    zone.Exile -> player.exile
    zone.Battlefield ->
      dict.values(player.battlefield)
      |> list.map(fn(perm) { perm.card })
    zone.Stack -> []
  }
}

fn remove_from_zone(
  state: state.State,
  player_id: Int,
  card_id: String,
  z: zone.Zone,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      case z {
        zone.Hand -> player.Player(..p, hand: card.remove(p.hand, card_id))
        zone.Graveyard ->
          player.Player(..p, graveyard: card.remove(p.graveyard, card_id))
        zone.Library ->
          player.Player(..p, library: card.remove(p.library, card_id))
        zone.Exile -> player.Player(..p, exile: card.remove(p.exile, card_id))
        zone.Battlefield ->
          player.Player(..p, battlefield: dict.delete(p.battlefield, card_id))
        zone.Stack -> p
      }
    }),
  )
}

fn add_to_zone(
  state: state.State,
  player_id: Int,
  c: card.Card,
  z: zone.Zone,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      case z {
        zone.Hand -> player.Player(..p, hand: [c, ..p.hand])
        zone.Graveyard -> player.Player(..p, graveyard: [c, ..p.graveyard])
        zone.Library -> player.Player(..p, library: [c, ..p.library])
        zone.Exile -> player.Player(..p, exile: [c, ..p.exile])
        zone.Battlefield -> {
          let current_cycle = state.turn_cycle(state)
          let new_perm = permanent.from_card(c, player_id, current_cycle)
          player.Player(
            ..p,
            battlefield: dict.insert(p.battlefield, c.id, new_perm),
          )
        }
        zone.Stack -> p
      }
    }),
  )
}

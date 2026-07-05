import gleam/list
import gleam/option.{None, Some}
import mtg_engine/action
import mtg_engine/effects
import mtg_engine/extensions
import mtg_engine/mana
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import test_helpers.{pass_until}

fn make_at_step_trigger(
  step: step.Step,
  controller: Int,
  duration: effects.TriggerDuration,
) -> effects.DelayedTrigger {
  effects.DelayedTrigger(
    event: effects.AtStep(step:),
    effect: effects.Single(effects.GainLife(
      amount: effects.Fixed(3),
      target: targeting.Controller,
    )),
    controller:,
    duration:,
  )
}

fn pass_with_ext(
  state: state.State,
  extensions: extensions.GameExtensions,
) -> #(state.State, extensions.GameExtensions) {
  case state.priority_player {
    None ->
      pass_with_ext(
        state.State(..state, priority_player: Some(state.active_player)),
        extensions,
      )
    Some(_pp) ->
      list.fold(state.players, #(state, extensions), fn(acc, p) {
        let #(s, ext) = acc
        let assert Ok(#(s2, ext2)) =
          action.dispatch_with_ext(s, ext, action.PassPriority(p.id))
        #(s2, ext2)
      })
  }
}

pub fn at_step_once_trigger_fires_when_step_advances_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let extensions = extensions.new()
  let trigger = make_at_step_trigger(step.BeginCombat, 1, effects.Once)
  let extensions = extensions.add_delayed_trigger(extensions, trigger)

  let #(state, extensions) = pass_with_ext(state, extensions)

  assert state.step == step.BeginCombat
  assert list.length(state.stack) == 1
  let assert Ok(item) = list.first(state.stack)
  assert item.controller_id == 1
  assert item.effect_override
    == Some(
      effects.Single(effects.GainLife(
        amount: effects.Fixed(3),
        target: targeting.Controller,
      )),
    )
  assert extensions.delayed_triggers == []
}

pub fn at_step_once_trigger_removed_after_firing_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let extensions = extensions.new()
  let trigger_begin = make_at_step_trigger(step.BeginCombat, 1, effects.Once)
  let trigger_declare =
    make_at_step_trigger(step.DeclareAttackers, 1, effects.Once)
  let extensions = extensions.add_delayed_trigger(extensions, trigger_begin)
  let extensions = extensions.add_delayed_trigger(extensions, trigger_declare)

  let #(state, extensions) = pass_with_ext(state, extensions)

  assert state.step == step.BeginCombat
  assert list.length(extensions.delayed_triggers) == 1
  let assert Ok(remaining) = list.first(extensions.delayed_triggers)
  assert remaining.event == effects.AtStep(step.DeclareAttackers)
}

pub fn at_step_untileofturn_trigger_kept_after_firing_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let extensions = extensions.new()
  let trigger =
    make_at_step_trigger(step.BeginCombat, 1, effects.UntilEndOfTurn)
  let extensions = extensions.add_delayed_trigger(extensions, trigger)

  let #(state, extensions) = pass_with_ext(state, extensions)

  assert state.step == step.BeginCombat
  assert list.length(state.stack) == 1
  assert list.length(extensions.delayed_triggers) == 1
}

pub fn no_trigger_when_step_does_not_change_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let extensions = extensions.new()
  let trigger = make_at_step_trigger(step.BeginCombat, 1, effects.Once)
  let extensions = extensions.add_delayed_trigger(extensions, trigger)

  let #(state, extensions) = case
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(
        1,
        mana.Produced(
          white: 0,
          blue: 0,
          black: 0,
          red: 0,
          green: 1,
          colorless: 0,
        ),
      ),
    )
  {
    Ok(result) -> result
    Error(_) -> panic as "unexpected error"
  }

  assert state.step == step.PreCombatMain
  assert state.stack == []
  assert list.length(extensions.delayed_triggers) == 1
}

pub fn at_step_trigger_does_not_fire_for_non_matching_step_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let extensions = extensions.new()
  let trigger = make_at_step_trigger(step.EndCombat, 1, effects.Once)
  let extensions = extensions.add_delayed_trigger(extensions, trigger)

  let #(state, extensions) = pass_with_ext(state, extensions)

  assert state.step == step.BeginCombat
  assert state.stack == []
  assert list.length(extensions.delayed_triggers) == 1
}

pub fn trigger_effect_resolves_normally_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let extensions = extensions.new()
  let trigger = make_at_step_trigger(step.BeginCombat, 1, effects.Once)
  let extensions = extensions.add_delayed_trigger(extensions, trigger)

  let #(state, _) = pass_with_ext(state, extensions)

  assert list.length(state.stack) == 1
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.life == 20

  let #(state, _) = pass_with_ext(state, extensions)

  assert state.stack == []
  let assert Ok(p1_after) = player.find(state.players, 1)
  assert p1_after.life == 23
}

pub fn multiple_triggers_same_step_all_fire_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let extensions = extensions.new()
  let trigger1 = make_at_step_trigger(step.BeginCombat, 1, effects.Once)
  let trigger2 =
    effects.DelayedTrigger(
      event: effects.AtStep(step.BeginCombat),
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(5),
        target: targeting.Controller,
      )),
      controller: 1,
      duration: effects.Once,
    )
  let extensions = extensions.add_delayed_trigger(extensions, trigger1)
  let extensions = extensions.add_delayed_trigger(extensions, trigger2)

  let #(state, extensions) = pass_with_ext(state, extensions)

  assert state.step == step.BeginCombat
  assert list.length(state.stack) == 2
  assert extensions.delayed_triggers == []
}

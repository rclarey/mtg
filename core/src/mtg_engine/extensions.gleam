import gleam/list
import mtg_engine/effects

pub type GameExtensions {
  GameExtensions(
    delayed_triggers: List(effects.DelayedTrigger),
    static_effects: List(effects.TimestampedEffect),
    next_timestamp: Int,
  )
}

pub fn new() -> GameExtensions {
  GameExtensions(delayed_triggers: [], static_effects: [], next_timestamp: 0)
}

pub fn add_delayed_trigger(
  extensions: GameExtensions,
  trigger: effects.DelayedTrigger,
) -> GameExtensions {
  GameExtensions(..extensions, delayed_triggers: [
    trigger,
    ..extensions.delayed_triggers
  ])
}

/// Remove all static effects contributed by a given source (card ID).
/// When a permanent with a static ability leaves the battlefield, this function
/// should be called to stop its effect from applying on future dispatches.
pub fn remove_static_effects_by_source(
  extensions: GameExtensions,
  source: String,
) -> GameExtensions {
  GameExtensions(
    ..extensions,
    static_effects: list.filter(extensions.static_effects, fn(e) {
      e.source != source
    }),
  )
}

/// Add a static effect with an auto-assigned timestamp and source tracking.
/// Effects are applied in layer order (rule 613) and within each layer by
/// timestamp ascending (older first).
pub fn add_static_effect(
  extensions: GameExtensions,
  effect: effects.StaticEffect,
  source: String,
) -> GameExtensions {
  let timestamped =
    effects.TimestampedEffect(
      effect:,
      timestamp: extensions.next_timestamp,
      source:,
    )
  GameExtensions(
    ..extensions,
    static_effects: [timestamped, ..extensions.static_effects],
    next_timestamp: extensions.next_timestamp + 1,
  )
}

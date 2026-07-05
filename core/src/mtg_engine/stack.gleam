import gleam/option.{type Option, None}
import mtg_engine/card
import mtg_engine/color
import mtg_engine/effects
import mtg_engine/targeting

pub type StackItem {
  StackItem(
    card: card.Card,
    controller_id: Int,
    chosen_targets: List(targeting.ChosenTargets),
    chosen_mode: Option(Int),
    damage_division: List(Int),
    x_value: Int,
    effect_override: Option(effects.Effect),
    trigger_subject: Option(targeting.TargetIdentifier),
    // Task 5: color chosen by a preceding ChooseColor step.
    chosen_color: Option(color.Color),
  )
}

pub fn make_stack_item(
  card: card.Card,
  controller_id: Int,
  x_value: Int,
) -> StackItem {
  StackItem(
    card:,
    controller_id:,
    chosen_targets: [],
    chosen_mode: None,
    damage_division: [],
    x_value:,
    effect_override: None,
    trigger_subject: None,
    chosen_color: None,
  )
}

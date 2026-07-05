import gleam/list
import gleam/option.{type Option, None, Some}
import mtg_engine/card
import mtg_engine/color
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/zone

/// Context required to evaluate a `CardFilter` against a card. Carries the
/// information that is not available on `card.Card` itself.
///
/// `FilterContext` and `matches` live in `filter_matcher` (rather than
/// `filters`) because `matches` needs `card.Card`, and `filters.gleam`
/// cannot import `card.gleam` without creating an import cycle
/// (`filters → card → ability → effects → filters`). The filter *types*
/// stay in `filters.gleam` so that `ability`, `effects`, `targeting`, and
/// `trigger` can reference `CardFilter` without depending on `card`.
pub type FilterContext {
  FilterContext(
    // The player who controls/owns the card being evaluated.
    controller_id: Int,
    // The "you" reference: the spell/ability controller, or the source
    // permanent's controller for static effects.
    active_player: Int,
    // The player targeted by the spell/ability, if any. Used by
    // `WithController(TargetPlayer)`.
    target_player: Option(Int),
    // All players who are opponents of `active_player`.
    opponent_ids: List(Int),
    // The tapped state of the card if it is a permanent on the battlefield:
    // `Some(True)` for tapped, `Some(False)` for untapped, `None` for
    // non-battlefield zones. Required by `WithRestriction`.
    is_tapped: Option(Bool),
    // The zone the card is being evaluated in. Required by `Zone`.
    zone: zone.Zone,
    // The color chosen by a preceding `ChooseColor` step, if any. Used by
    // `Color(Chosen)`. `None` outside the resolution path.
    chosen_color: Option(color.Color),
  )
}

/// Match a card against a filter using the given context.
/// This is the single shared filter matcher used by effect resolution,
/// static-effect application, cost payment, search, and discard.
pub fn matches(
  card: card.Card,
  filter: filters.CardFilter,
  context: FilterContext,
) -> Bool {
  case filter {
    filters.AnyCard -> True
    filters.Name(name) -> card.name == name
    filters.Types(types) -> list.contains(types, card.card_type)
    filters.Color(ref) -> color_matches(card, ref, context)
    filters.Subtype(subtype) -> list.contains(card.subtypes, subtype)
    filters.Supertype(supertype) -> list.contains(card.supertypes, supertype)
    filters.Not(inner) -> !matches(card, inner, context)
    filters.And(a, b) -> matches(card, a, context) && matches(card, b, context)
    filters.Or(a, b) -> matches(card, a, context) || matches(card, b, context)
    filters.WithController(cf) ->
      controller_matches(context.controller_id, cf, context)
    filters.WithRestriction(r) -> restriction_matches(context.is_tapped, r)
    filters.Zone(z) -> context.zone == z
  }
}

fn color_matches(
  card: card.Card,
  ref: filters.ColorRef,
  context: FilterContext,
) -> Bool {
  let colors = get_card_colors(card.mana_cost)
  case ref {
    filters.Literal(c) -> list.contains(colors, c)
    filters.Chosen ->
      case context.chosen_color {
        Some(c) -> list.contains(colors, c)
        None -> False
      }
  }
}

fn controller_matches(
  controller_id: Int,
  cf: filters.ControllerFilter,
  context: FilterContext,
) -> Bool {
  case cf {
    filters.Any -> True
    filters.You -> controller_id == context.active_player
    filters.Opponent -> list.contains(context.opponent_ids, controller_id)
    filters.TargetPlayer ->
      case context.target_player {
        Some(tp) -> controller_id == tp
        None -> False
      }
  }
}

fn restriction_matches(
  is_tapped: Option(Bool),
  r: filters.CardRestriction,
) -> Bool {
  case is_tapped {
    Some(tapped) ->
      case r {
        filters.Tapped -> tapped
        filters.Untapped -> !tapped
      }
    None -> False
  }
}

/// Compute the colors of a card from its mana cost (rule 202.2).
/// A card is a color if its mana cost has a colored mana symbol of that color.
pub fn get_card_colors(cost: mana.Cost) -> List(color.Color) {
  let colors = []
  let colors = case cost.white > 0 {
    True -> [color.White, ..colors]
    False -> colors
  }
  let colors = case cost.blue > 0 {
    True -> [color.Blue, ..colors]
    False -> colors
  }
  let colors = case cost.black > 0 {
    True -> [color.Black, ..colors]
    False -> colors
  }
  let colors = case cost.red > 0 {
    True -> [color.Red, ..colors]
    False -> colors
  }
  let colors = case cost.green > 0 {
    True -> [color.Green, ..colors]
    False -> colors
  }
  colors
}

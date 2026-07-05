import gleam/option.{None, Some}
import mtg_engine/ability
import mtg_engine/card_type
import mtg_engine/color
import mtg_engine/effects
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/step
import mtg_engine/supertype
import mtg_engine/targeting
import mtg_engine/trigger
import mtg_engine/zone

// ── Simple Targeted Spells ──────────────────────────────────────
// Shock — "2 damage to any target"
pub fn test_shock() {
  let shock =
    ability.Spell(ability.SpellAbility(
      targets: [targeting.any_target()],
      additional_costs: [],
      effect: effects.Single(effects.DealDamage(
        amount: effects.Fixed(2),
        target: targeting.PrimaryTarget,
        source_is_combat: False,
      )),
    ))
  let _ = shock
}

// Giant Growth — "Target creature gets +3/+3 until end of turn"
pub fn test_giant_growth() {
  let growth =
    ability.Spell(ability.SpellAbility(
      targets: [targeting.creature_target()],
      additional_costs: [],
      effect: effects.Single(effects.PumpCreature(
        target: targeting.PrimaryTarget,
        power: effects.Fixed(3),
        toughness: effects.Fixed(3),
        add_keywords: [],
        duration: effects.EndOfTurn,
      )),
    ))
  let _ = growth
}

// Counterspell — "Counter target spell"
pub fn test_counterspell() {
  let counterspell =
    ability.Spell(ability.SpellAbility(
      targets: [targeting.target_info(targeting.Single(targeting.Spell))],
      additional_costs: [],
      effect: effects.Single(effects.CounterSpell(
        target: targeting.PrimaryTarget,
      )),
    ))
  let _ = counterspell
}

// Inspiration — "Target player draws two cards"
pub fn test_inspiration() {
  let inspiration =
    ability.Spell(ability.SpellAbility(
      targets: [targeting.player_target()],
      additional_costs: [],
      effect: effects.Single(effects.DrawCards(
        num: effects.Fixed(2),
        target: targeting.PrimaryTarget,
      )),
    ))
  let _ = inspiration
}

// ── Activated Abilities ─────────────────────────────────────────
// Llanowar Elves — "{T}: Add {G}"
pub fn test_llanowar_elves() {
  let elves =
    ability.Activated(ability.ActivatedAbility(
      cost: ability.tap_cost(),
      targets: [],
      effect: effects.Single(
        effects.ProduceMana(mana: mana.Produced(
          white: 0,
          blue: 0,
          black: 0,
          red: 0,
          green: 1,
          colorless: 0,
        )),
      ),
    ))
  let _ = elves
}

// Prodigal Sorcerer — "{T}: Deal 1 damage to any target"
pub fn test_prodigal_sorcerer() {
  let prodigal =
    ability.Activated(ability.ActivatedAbility(
      cost: ability.tap_cost(),
      targets: [targeting.any_target()],
      effect: effects.Single(effects.DealDamage(
        amount: effects.Fixed(1),
        target: targeting.PrimaryTarget,
        source_is_combat: False,
      )),
    ))
  let _ = prodigal
}

// Seeker of Skybreak — "{T}: Untap target creature"
pub fn test_seeker_of_skybreak() {
  let seeker =
    ability.Activated(ability.ActivatedAbility(
      cost: ability.tap_cost(),
      targets: [targeting.creature_target()],
      effect: effects.Single(effects.TapOrUntap(
        target: targeting.PrimaryTarget,
        mode: effects.Untap,
      )),
    ))
  let _ = seeker
}

// ── Destroy Effects ─────────────────────────────────────────────
// Disenchant — "Destroy target artifact or enchantment"
pub fn test_disenchant() {
  let disenchant =
    ability.Spell(ability.SpellAbility(
      targets: [
        targeting.target_info(targeting.Or(
          targeting.Single(targeting.Artifact),
          targeting.Single(targeting.Enchantment),
        )),
      ],
      additional_costs: [],
      effect: effects.Single(effects.Destroy(
        target: targeting.PrimaryTarget,
        cant_regenerate: False,
      )),
    ))
  let _ = disenchant
}

// Wrath of God — "Destroy all creatures. They can't be regenerated."
pub fn test_wrath_of_god() {
  let wrath =
    ability.Spell(ability.SpellAbility(
      targets: [],
      additional_costs: [],
      effect: effects.Single(effects.Destroy(
        target: targeting.AllOf(filters.creature()),
        cant_regenerate: True,
      )),
    ))
  let _ = wrath
}

// Dark Banishing — "Destroy target nonblack creature. It can't be regenerated."
pub fn test_dark_banishing() {
  let dark_banishing =
    ability.Spell(ability.SpellAbility(
      targets: [
        targeting.target_info(targeting.And(
          targeting.Single(targeting.Creature),
          targeting.Not(targeting.Color(filters.Literal(color.Black))),
        )),
      ],
      additional_costs: [],
      effect: effects.Single(effects.Destroy(
        target: targeting.PrimaryTarget,
        cant_regenerate: True,
      )),
    ))
  let _ = dark_banishing
}

// ── Modal Spells ────────────────────────────────────────────────
// Healing Salve — "Choose one — Target player gains 3 life;
//                   or prevent next 3 damage to any target"
pub fn test_healing_salve() {
  let salve =
    ability.Spell(ability.SpellAbility(
      targets: [],
      additional_costs: [],
      effect: effects.Single(
        effects.ChooseOne(modes: [
          effects.ModalMode(
            targets: [targeting.player_target()],
            effect: effects.Single(effects.GainLife(
              amount: effects.Fixed(3),
              target: targeting.PrimaryTarget,
            )),
          ),
          effects.ModalMode(
            targets: [targeting.any_target()],
            effect: effects.Single(effects.PreventDamage(
              target: targeting.PrimaryTarget,
              mode: effects.Shield(amount: effects.Fixed(3)),
            )),
          ),
        ]),
      ),
    ))
  let _ = salve
}

// ── Compound Effects ────────────────────────────────────────────
// Corrupt — "Deal damage equal to Swamps you control.
//            Gain life equal to damage dealt."
pub fn test_corrupt() {
  let corrupt =
    ability.Spell(ability.SpellAbility(
      targets: [targeting.any_target()],
      additional_costs: [],
      effect: effects.Sequence([
        effects.DealDamage(
          amount: effects.Count(filters.And(
            filters.Types([card_type.Land]),
            filters.And(
              filters.Name("Swamp"),
              filters.WithController(filters.You),
            ),
          )),
          target: targeting.PrimaryTarget,
          source_is_combat: False,
        ),
        effects.GainLife(
          amount: effects.PreviousStep,
          target: targeting.Controller,
        ),
      ]),
    ))
  let _ = corrupt
}

// Tolarian Winds — "Discard your hand, then draw that many cards."
pub fn test_tolarian_winds() {
  let winds =
    ability.Spell(ability.SpellAbility(
      targets: [],
      additional_costs: [],
      effect: effects.Sequence([
        effects.Discard(who: targeting.Controller, filter: filters.AnyCard),
        effects.DrawCards(
          num: effects.PreviousStep,
          target: targeting.Controller,
        ),
      ]),
    ))
  let _ = winds
}

// ── Prevention ──────────────────────────────────────────────────
// Fog — "Prevent all combat damage that would be dealt this turn"
pub fn test_fog() {
  let fog =
    ability.Spell(ability.SpellAbility(
      targets: [],
      additional_costs: [],
      effect: effects.Single(effects.PreventDamage(
        target: targeting.Controller,
        mode: effects.GlobalCombat,
      )),
    ))
  let _ = fog
}

// Samite Healer — "{T}: Prevent next 1 damage to any target"
pub fn test_samite_healer() {
  let healer =
    ability.Activated(ability.ActivatedAbility(
      cost: ability.tap_cost(),
      targets: [targeting.any_target()],
      effect: effects.Single(effects.PreventDamage(
        target: targeting.PrimaryTarget,
        mode: effects.Shield(amount: effects.Fixed(1)),
      )),
    ))
  let _ = healer
}

// ── Extra Turn / Delayed Trigger ────────────────────────────────
// Final Fortune — "Take an extra turn after this one.
//                  You lose the game at the beginning of that turn's end step."
pub fn test_final_fortune() {
  let fortune =
    ability.Spell(ability.SpellAbility(
      targets: [],
      additional_costs: [],
      effect: effects.Sequence([
        effects.ExtraTurn(target: targeting.Controller),
        effects.CreateDelayedTrigger(trigger: effects.DelayedTrigger(
          event: effects.AtStep(step: step.EndStep),
          effect: effects.Single(effects.LoseGame(target: targeting.Controller)),
          controller: 0,
          duration: effects.Once,
        )),
      ]),
    ))
  let _ = fortune
}

// ── Variable Damage ─────────────────────────────────────────────
// Spitting Earth — "Deals damage equal to number of Mountains you control"
pub fn test_spitting_earth() {
  let spitting_earth =
    ability.Spell(ability.SpellAbility(
      targets: [targeting.any_target()],
      additional_costs: [],
      effect: effects.Single(effects.DealDamage(
        amount: effects.Count(filters.And(
          filters.Types([card_type.Land]),
          filters.And(
            filters.Name("Mountain"),
            filters.WithController(filters.You),
          ),
        )),
        target: targeting.PrimaryTarget,
        source_is_combat: False,
      )),
    ))
  let _ = spitting_earth
}

// Starlight — "You gain 3 life for each black creature target opponent controls"
pub fn test_starlight() {
  let starlight =
    ability.Spell(ability.SpellAbility(
      targets: [],
      additional_costs: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Multiply(
          effects.Count(filters.And(
            filters.Types([card_type.Creature]),
            filters.And(
              filters.Color(filters.Literal(color.Black)),
              filters.WithController(filters.TargetPlayer),
            ),
          )),
          3,
        ),
        target: targeting.Controller,
      )),
    ))
  let _ = starlight
}

// ── Sacrifice as Cost ───────────────────────────────────────────
// Ghitu Fire-Eater — "{T}, Sacrifice this: 2 damage to any target"
pub fn test_ghitu_fire_eater() {
  let ghitu =
    ability.Activated(ability.ActivatedAbility(
      cost: ability.tap_sacrifice_this_cost(),
      targets: [targeting.any_target()],
      effect: effects.Single(effects.DealDamage(
        amount: effects.Fixed(2),
        target: targeting.PrimaryTarget,
        source_is_combat: False,
      )),
    ))
  let _ = ghitu
}

// ── Divided Damage ──────────────────────────────────────────────
// Pyrotechnics — "Pyrotechnics deals 4 damage divided as you choose
//                 among any number of target creatures and/or players."
pub fn test_pyrotechnics() {
  let pyro =
    ability.Spell(ability.SpellAbility(
      targets: [
        targeting.TargetInfo(filter: targeting.Any, count: targeting.AnyNumber),
      ],
      additional_costs: [],
      effect: effects.Single(
        effects.DealDividedDamage(total_amount: effects.Fixed(4)),
      ),
    ))
  let _ = pyro
}

// ── Search Library ──────────────────────────────────────────────
// Rampant Growth — "Search your library for a basic land card,
//                   put it onto the battlefield tapped."
pub fn test_rampant_growth() {
  let rampant =
    ability.Spell(ability.SpellAbility(
      targets: [],
      additional_costs: [],
      effect: effects.Single(effects.SearchLibrary(
        target: targeting.Controller,
        filter: filters.And(
          filters.Types([card_type.Land]),
          filters.Supertype(supertype.Basic),
        ),
        destination: effects.Battlefield,
        reveal: False,
        tapped: True,
      )),
    ))
  let _ = rampant
}

// ── Pay Life as Cost ────────────────────────────────────────────
// Greed — "{1}{B}, Pay 2 life: Draw a card"
pub fn test_greed() {
  let greed =
    ability.Activated(ability.ActivatedAbility(
      cost: ability.mana_life_cost(
        mana.Cost(
          generic: 1,
          black: 1,
          white: 0,
          blue: 0,
          red: 0,
          green: 0,
          colorless: 0,
          x: 0,
        ),
        2,
      ),
      targets: [],
      effect: effects.Single(effects.DrawCards(
        num: effects.Fixed(1),
        target: targeting.Controller,
      )),
    ))
  let _ = greed
}

// Necrologia — "As an additional cost, pay X life. You draw X cards."
pub fn test_necrologia() {
  let necrologia =
    ability.Spell(ability.SpellAbility(
      targets: [],
      additional_costs: [ability.PayLife(effects.X)],
      effect: effects.Single(effects.DrawCards(
        num: effects.X,
        target: targeting.Controller,
      )),
    ))
  let _ = necrologia
}

// ── Static Abilities ────────────────────────────────────────────
// Glorious Anthem — "Creatures you control get +1/+1"
pub fn test_glorious_anthem() {
  let anthem =
    ability.Static(
      ability.StaticAbility(
        effect: effects.PumpAll(
          filter: filters.And(
            filters.creature(),
            filters.WithController(filters.You),
          ),
          power: 1,
          toughness: 1,
          keywords: [],
        ),
        zones: [zone.Battlefield],
      ),
    )
  let _ = anthem
}

// Goblin King — "Other Goblins get +1/+1 and have mountainwalk"
pub fn test_goblin_king() {
  let king =
    ability.Static(
      ability.StaticAbility(
        effect: effects.PumpAll(
          filter: filters.And(
            filters.Subtype("Goblin"),
            filters.Not(filters.Name("Goblin King")),
          ),
          power: 1,
          toughness: 1,
          keywords: [effects.Mountainwalk],
        ),
        zones: [zone.Battlefield],
      ),
    )
  let _ = king
}

// ── Triggered Abilities ─────────────────────────────────────────
// Abyssal Specter — "Whenever ~ deals combat damage to a player,
//                     that player discards a card"
pub fn test_abyssal_specter() {
  let specter =
    ability.Triggered(ability.TriggeredAbility(
      trigger: trigger.DealsCombatDamage(
        filter: Some(targeting.Single(targeting.Player)),
      ),
      targets: [],
      effect: effects.Single(effects.Discard(
        who: targeting.TriggerSubject,
        filter: filters.Zone(zone.Hand),
      )),
      optional: False,
      intervening_if: None,
    ))
  let _ = specter
}

// Seasoned Marshal — "Whenever ~ attacks, you may tap target creature"
pub fn test_seasoned_marshal() {
  let marshal =
    ability.Triggered(ability.TriggeredAbility(
      trigger: trigger.Attacks,
      targets: [targeting.creature_target()],
      effect: effects.Single(effects.TapOrUntap(
        target: targeting.PrimaryTarget,
        mode: effects.Tap,
      )),
      optional: True,
      intervening_if: None,
    ))
  let _ = marshal
}

// ── Zone-Based Targeting ────────────────────────────────────────
// Strands of Night — "{1}{B}, Pay 2 life, Sacrifice a Swamp:
//                      Return target creature card from your graveyard
//                      to the battlefield"
pub fn test_strands_of_night() {
  let strands =
    ability.Activated(ability.ActivatedAbility(
      cost: ability.Costs([
        ability.Mana(mana.Cost(
          generic: 1,
          black: 1,
          white: 0,
          blue: 0,
          red: 0,
          green: 0,
          colorless: 0,
          x: 0,
        )),
        ability.PayLife(effects.Fixed(2)),
        ability.Sacrifice(filters.And(
          filters.Types([card_type.Land]),
          filters.Name("Swamp"),
        )),
      ]),
      targets: [
        targeting.target_info(targeting.And(
          targeting.Single(targeting.Creature),
          targeting.Zone(zone.Graveyard),
        )),
      ],
      effect: effects.Single(effects.Bounce(target: targeting.PrimaryTarget)),
    ))
  let _ = strands
}

// Gravedigger — "When Gravedigger enters the battlefield, return target
//                creature card from your graveyard to your hand."
pub fn test_gravedigger() {
  let gravedigger =
    ability.Triggered(ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [
        targeting.target_info(targeting.And(
          targeting.Single(targeting.Creature),
          targeting.Zone(zone.Graveyard),
        )),
      ],
      effect: effects.Single(effects.Bounce(target: targeting.PrimaryTarget)),
      optional: False,
      intervening_if: None,
    ))
  let _ = gravedigger
}

// ── Amount.Multiply with CardFilter ─────────────────────────────
// Verify Multiply composition works correctly
pub fn test_amount_multiply() {
  let amount = effects.Multiply(effects.Fixed(3), 2)
  let _ = amount
}

// ── Activation Cost Helpers ─────────────────────────────────────
pub fn test_activation_cost_helpers() {
  let _ = ability.tap_cost()
  let _ =
    ability.tap_mana_cost(mana.Cost(
      generic: 1,
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
      x: 0,
    ))
  let _ = ability.sacrifice_cost(filters.creature())
  let _ = ability.sacrifice_this_cost()
  let _ = ability.tap_sacrifice_cost(filters.creature())
  let _ = ability.tap_sacrifice_this_cost()
  let _ = ability.life_cost(2)
  let _ =
    ability.mana_life_cost(
      mana.Cost(
        generic: 1,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      2,
    )
  let assert ability.NoCost = ability.tap_cost()
}

// ── NoCost ──────────────────────────────────────────────────────
pub fn test_no_cost() {
  let no_cost = ability.NoCost
  let _ = no_cost
}

// ── Coin Flip Result type ───────────────────────────────────────
pub fn test_coin_flip_result() {
  let heads = effects.Heads
  let tails = effects.Tails
  let _ = heads
  let _ = tails
}

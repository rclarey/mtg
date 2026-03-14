import gleam/uri.{type Uri}
import lustre
import lustre/effect.{type Effect}
import lustre/element
import lustre/element/html as h
import modem
import plinth/browser/document

import global
import pages/game

// MODEL

pub type Model {
  Model(global_model: global.Model, page_model: PageModel)
}

pub type PageModel {
  Game(game.Model)
  NotFound
}

pub type Flags {
  Flags(uri: Uri)
}

fn init(flags: Flags) {
  let #(init_model, init_effect) = init_for_route(flags)
  #(
    init_model,
    effect.batch([
      init_effect,
      modem.init(on_route_change(flags)),
    ]),
  )
}

fn init_for_route(flags: Flags) {
  let Flags(uri:) = flags
  let global_model = global.Model
  case uri.path {
    "/" ->
      game.init(uri)
      |> init_with(global_model, Game, GameMsg)
    _ -> #(Model(global_model:, page_model: NotFound), effect.none())
  }
}

fn init_with(
  result: #(sub_model, Effect(sub_msg)),
  global_model: global.Model,
  to_model: fn(sub_model) -> PageModel,
  to_msg: fn(sub_msg) -> Msg,
) {
  update_with(#(global_model, result.0, result.1), to_model, to_msg)
}

fn on_route_change(flags: Flags) {
  fn(uri: Uri) {
    let #(msg_model, msg_effect) = init_for_route(Flags(uri: uri))
    RouteUpdated(msg_model, msg_effect)
  }
}

// VIEW

fn view(model: Model) {
  case model.page_model {
    Game(page_model) ->
      game.view(page_model)
      |> element.map(GameMsg)
    NotFound -> h.h1([], [h.text("Not Found!")])
  }
}

// UPDATE

pub type Msg {
  RouteUpdated(Model, Effect(Msg))
  GameMsg(game.Msg)
}

fn update(model: Model, msg: Msg) {
  let Model(global_model:, page_model:) = model
  case page_model, msg {
    Game(model), GameMsg(msg) ->
      game.update(global_model, model, msg)
      |> update_with(Game, GameMsg)
    _, RouteUpdated(msg_model, msg_effect) -> #(msg_model, msg_effect)
    _, _ -> #(model, effect.none())
  }
}

fn update_with(
  result: #(global.Model, sub_model, Effect(sub_msg)),
  to_model: fn(sub_model) -> PageModel,
  to_msg: fn(sub_msg) -> Msg,
) {
  let #(global_model, page_model, page_msg) = result
  #(
    Model(global_model:, page_model: to_model(page_model)),
    effect.map(page_msg, to_msg),
  )
}

// MAIN

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(uri) = modem.initial_uri()
  let assert Ok(_) = lustre.start(app, "#app", Flags(uri))
}

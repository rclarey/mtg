import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import gleam/uri
import lustre/attribute as attr
import lustre/effect
import lustre/element
import lustre/element/html as h
import lustre/event as e
import modem

import global

// MODEL

pub type Model {
  Model(cards: List(Card), drag: Option(Drag))
}

pub type Drag {
  Drag(id: Int, x: Int, y: Int)
}

pub type Card {
  Card(id: Int, img: String)
}

pub fn init(cur_uri: uri.Uri) {
  let cards =
    option.unwrap(cur_uri.query, "")
    |> uri.parse_query()
    |> result.unwrap([])
    |> list.key_find("c")
    |> result.unwrap("")
    |> string.split(",")
    |> list.index_map(fn(name, id) { Card(id, "/cards/" <> name <> ".jpg") })

  #(Model(cards, None), effect.none())
}

// VIEW

pub fn view(model: Model) {
  h.main(
    [
      e.on("mousemove", {
        use dx <- decode.field("movementX", decode.int)
        use dy <- decode.field("movementY", decode.int)
        decode.success(MouseMoved(dx, dy))
      }),
      e.on_mouse_up(StopDrag),
      e.on_mouse_leave(StopDrag),
    ],
    list.map(model.cards, card_img(_, model.drag)),
  )
}

fn card_img(card: Card, drag: Option(Drag)) {
  let styles = case drag {
    Some(Drag(id, x, y)) if id == card.id -> {
      [
        attr.style(
          "transform",
          "translate("
            <> int.to_string(x)
            <> "px, "
            <> int.to_string(y)
            <> "px) scale(1.05)",
        ),
      ]
    }
    _ -> {
      echo "NOT A MATCH"
      []
    }
  }
  h.img([
    attr.src(card.img),
    attr.draggable(False),
    e.on_mouse_down(StartDrag(card.id)),
    ..styles
  ])
}

// UPDATE

pub type Msg {
  StartDrag(id: Int)
  StopDrag
  MouseMoved(dx: Int, dy: Int)
}

pub fn update(global_model: global.Model, model: Model, msg: Msg) {
  let model = case msg, model {
    StartDrag(id), _ -> {
      echo id
      Model(..model, drag: Some(Drag(id:, x: 0, y: 0)))
    }
    StopDrag, _ -> Model(..model, drag: None)
    MouseMoved(dx, dy), Model(_, Some(Drag(id, x, y))) ->
      Model(..model, drag: Some(Drag(id, x + dx, y + dy)))
    _, _ -> model
  }
  #(global_model, model, effect.none())
}

import lustre/effect

pub type Model {
  Model
}

pub type Msg(msg) {
  GlobalMsg(GlobalMsg)
  PageMsg(msg)
}

pub type GlobalMsg

pub fn update(model: Model, msg: GlobalMsg) {
  #(model, effect.none())
}

import gleam/result
import mtg_engine/action
import mtg_engine/error
import mtg_engine/extensions
import mtg_engine/state

pub type Engine {
  Engine(state: state.State, extensions: extensions.GameExtensions)
}

pub fn new(state: state.State) -> Engine {
  Engine(state:, extensions: extensions.new())
}

pub fn new_with_extensions(
  state: state.State,
  extensions: extensions.GameExtensions,
) -> Engine {
  Engine(state:, extensions:)
}

pub fn dispatch(
  engine: Engine,
  action: action.Action,
) -> Result(Engine, error.Error) {
  let Engine(state:, extensions:) = engine
  use #(new_state, new_extensions) <- result.try(action.dispatch_with_ext(
    state,
    extensions,
    action,
  ))
  Ok(Engine(state: new_state, extensions: new_extensions))
}

pub fn get_state(engine: Engine) -> state.State {
  engine.state
}

pub fn get_extensions(engine: Engine) -> extensions.GameExtensions {
  engine.extensions
}

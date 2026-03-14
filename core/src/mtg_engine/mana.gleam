import mtg_engine/error
import mtg_engine/util

// Mana cost representation
pub type Cost {
  Cost(
    generic: Int,
    white: Int,
    blue: Int,
    black: Int,
    red: Int,
    green: Int,
    colorless: Int,
  )
}

// Mana production/pool tracking each color of mana
pub type Produced {
  Produced(
    white: Int,
    blue: Int,
    black: Int,
    red: Int,
    green: Int,
    colorless: Int,
  )
}

pub fn none() -> Produced {
  Produced(white: 0, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
}

pub fn add(pool: Produced, produced: Produced) -> Produced {
  Produced(
    white: pool.white + produced.white,
    blue: pool.blue + produced.blue,
    black: pool.black + produced.black,
    red: pool.red + produced.red,
    green: pool.green + produced.green,
    colorless: pool.colorless + produced.colorless,
  )
}

const not_enough_mana = Error(
  error.InvalidAction("Not enough mana to cast this spell"),
)

pub fn pay_cost(pool: Produced, cost: Cost) -> Result(Produced, error.Error) {
  // Check if we have enough of each specific color
  use <- util.guard(
    pool.white >= cost.white
      && pool.blue >= cost.blue
      && pool.black >= cost.black
      && pool.red >= cost.red
      && pool.green >= cost.green
      && pool.colorless >= cost.colorless,
    not_enough_mana,
  )

  // First, pay the specific colored costs
  let after_specific =
    Produced(
      white: pool.white - cost.white,
      blue: pool.blue - cost.blue,
      black: pool.black - cost.black,
      red: pool.red - cost.red,
      green: pool.green - cost.green,
      colorless: pool.colorless - cost.colorless,
    )

  // Then pay the generic cost from remaining mana
  pay_generic_from_pool(after_specific, cost.generic)
}

fn pay_generic_from_pool(
  pool: Produced,
  generic_cost: Int,
) -> Result(Produced, error.Error) {
  // Base case: no generic cost to pay
  use <- util.guard(generic_cost > 0, Ok(pool))

  // TODO some smarter heuristic for deducting mana
  // For now try to deduct from each mana type in WUBRG order
  use <- util.guard(
    pool.white <= 0,
    pay_generic_from_pool(
      Produced(..pool, white: pool.white - 1),
      generic_cost - 1,
    ),
  )
  use <- util.guard(
    pool.blue <= 0,
    pay_generic_from_pool(
      Produced(..pool, blue: pool.blue - 1),
      generic_cost - 1,
    ),
  )
  use <- util.guard(
    pool.black <= 0,
    pay_generic_from_pool(
      Produced(..pool, black: pool.black - 1),
      generic_cost - 1,
    ),
  )
  use <- util.guard(
    pool.red <= 0,
    pay_generic_from_pool(Produced(..pool, red: pool.red - 1), generic_cost - 1),
  )
  use <- util.guard(
    pool.green <= 0,
    pay_generic_from_pool(
      Produced(..pool, green: pool.green - 1),
      generic_cost - 1,
    ),
  )
  use <- util.guard(
    pool.colorless <= 0,
    pay_generic_from_pool(
      Produced(..pool, colorless: pool.colorless - 1),
      generic_cost - 1,
    ),
  )

  not_enough_mana
}

// Get mana produced by a land based on its name
pub fn from_basic_land(land_name: String) -> Produced {
  case land_name {
    "Forest" ->
      Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
    "Mountain" ->
      Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 0)
    "Island" ->
      Produced(white: 0, blue: 1, black: 0, red: 0, green: 0, colorless: 0)
    "Plains" ->
      Produced(white: 1, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
    "Swamp" ->
      Produced(white: 0, blue: 0, black: 1, red: 0, green: 0, colorless: 0)
    _ -> panic as "Tried to tap a non existent basic land"
  }
}

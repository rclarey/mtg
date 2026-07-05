pub type AttackPair {
  AttackPair(attacker: String, target: AttackTarget)
}

pub type AttackTarget {
  AttackPlayer(player_id: Int)
  AttackPlaneswalker(player_id: Int, permanent_id: String)
}

pub type BlockPair {
  BlockPair(blocker: String, attacker: String)
}

pub type DamageAssignment {
  DamageAssignment(amount: Int, from: String, to: String)
}

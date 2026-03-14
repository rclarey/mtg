pub type Error {
  InvalidAction(String)
  DoNotHavePriority
  WrongStep(expected: String)
}

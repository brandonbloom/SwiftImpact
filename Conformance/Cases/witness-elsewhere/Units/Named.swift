protocol Named {
    func name() -> String
}

extension Named {
    func name() -> String { "default" }
}

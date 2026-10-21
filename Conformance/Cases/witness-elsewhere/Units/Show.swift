func show<T: Named>(_ value: T) -> String { value.name() }

func showTag() -> String { show(Tag()) }

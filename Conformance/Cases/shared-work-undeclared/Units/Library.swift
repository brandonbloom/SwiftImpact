func makeLibrary() -> String {
    #if IMPACT_AFTER
        "after"
    #else
        "before"
    #endif
}

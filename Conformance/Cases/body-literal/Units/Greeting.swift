func greeting() -> String {
    #if IMPACT_AFTER
        "hi"
    #else
        "hello"
    #endif
}

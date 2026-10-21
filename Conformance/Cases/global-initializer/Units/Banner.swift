let banner = makeBanner()

func makeBanner() -> String {
    #if IMPACT_AFTER
        "v2"
    #else
        "v1"
    #endif
}

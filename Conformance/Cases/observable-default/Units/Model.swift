import Observation

@Observable final class Model {
    #if IMPACT_AFTER
        var count = 2
    #else
        var count = 1
    #endif
}

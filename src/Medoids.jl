module Medoids

    export
    # Utilities
    loadOrLib, randomInstance, testInstance,
    calculateCost, computeMedoidMap,

    # Implementation from clustering.jl
    parkJun, parkJun!,

    # PAM
    pam, calculateSwapValue, pamMultiswap,

    # Greedy
    forwardGreedy, reverseGreedy, _reverseGreedyOpt,

    # Jain Vazirani
    jv,

    # Linear Programs
    charikar2012Variable, charikar2012,
    
    # algorithms created by Brian 
    forwardGreedyBrian, reverseGreedyBrian,

    # Make PAM terminate after some time
    pam_timing, pamMultiswap_timing
    
    # Source files
    include("utils.jl")
    include("parkJun.jl")
    include("greedy.jl")
    include("charikar2012.jl")
    include("pam.jl")
    include("lp.jl")
    include("jv.jl")
    include("pam_multiswap.jl")
    include("pam_multiswap_timing.jl")
    include("pam_timing.jl")
end

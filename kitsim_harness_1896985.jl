
# include the functions file
include("kitsim_fns_1896985.jl")

function run_harness(seeds::Vector{Int64},allT::Float64)
  
    for seed in seeds
        Ps = Params(seed, 1.05 * 220, 0.96 * 65, 1.1 * 3960, 0.9 * 290)
        # Run simulation
        run_kithome_sim(Ps,allT)
    
    end
end

seeds=collect(201:275)
allT=1000.0
run_harness(seeds,allT)
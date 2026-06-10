# include the functions file
include("kitsim_fns_1896985.jl")


# begin
#     seed = 200
#     p1 = 220
#     p2 = 65 
#     p3 = 3960 
#     p4 = 290   

#     lambda1 = 1.05 * p1
#     lambda2 = 0.96 * p2
#     lambda3 = 1.1 * p3
#     lambda4 = 0.9 * p4   
#     allT=1000.0
# end     
  

# Sample 
seed = 110 #111
lambda1 = 75
lambda2 = 28.749999999999996
lambda3 = 3024.0
lambda4 = 306.0
allT=1000.0

Ps = Params(seed,lambda1,lambda2,lambda3,lambda4)

run_kithome_sim(Ps,allT)
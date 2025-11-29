# runtests.jl - Test runner for BeagleLLM.jl
#
# Usage:
#   julia test/runtests.jl
#   julia --project=. test/runtests.jl
#   BEAGLE_TEST_INTEGRATION=true julia test/runtests.jl

using Test
using Pkg

# Ensure we're in the right directory
cd(dirname(@__DIR__))

# Add test dependencies if needed
if !haskey(Pkg.project().dependencies, "Test")
    Pkg.add("Test")
end

# Include test files
println("🧪 BeagleLLM.jl Test Suite")
println("="^60)
println("Julia Version: $(VERSION)")
println("Test Time: $(Dates.now())")
println("="^60)

# Run tests
@testset "BeagleLLM Tests" begin
    include("test_beagle_llm.jl")
end

println("\n✅ Test suite completed successfully!")

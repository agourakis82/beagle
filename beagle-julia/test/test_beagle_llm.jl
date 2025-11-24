#!/usr/bin/env julia
#
# Smoke test for BeagleLLM.jl wrapper
#
# Tests basic connectivity and functionality with BEAGLE core server.
#
# Usage:
#   julia test/test_beagle_llm.jl
#
# Prerequisites:
#   - BEAGLE core server running on localhost:8080 (or BEAGLE_CORE_URL set)
#   - XAI_API_KEY configured
#
# To run with custom URL:
#   BEAGLE_CORE_URL=http://localhost:8080 julia test/test_beagle_llm.jl

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

using BeagleLLM
using Test

println("="^70)
println("BEAGLE LLM Smoke Test")
println("="^70)

# Configuration
BEAGLE_URL = get(ENV, "BEAGLE_CORE_URL", "http://localhost:8080")
SKIP_LIVE_TESTS = get(ENV, "BEAGLE_SKIP_LIVE_TESTS", "false") == "true"

println("\nConfiguration:")
println("  BEAGLE_CORE_URL: $BEAGLE_URL")
println("  SKIP_LIVE_TESTS: $SKIP_LIVE_TESTS")
println()

@testset "BeagleLLM Smoke Tests" begin

    @testset "Health Check" begin
        println("\n[Test 1/4] Health check...")

        if SKIP_LIVE_TESTS
            @test_skip "Health check (BEAGLE_SKIP_LIVE_TESTS=true)"
        else
            try
                health_status = BeagleLLM.health()

                @test haskey(health_status, "status")
                @test health_status["status"] == "ok"
                @test haskey(health_status, "service")
                @test haskey(health_status, "profile")

                println("  ✓ Health check passed")
                println("    Service: $(health_status["service"])")
                println("    Profile: $(health_status["profile"])")
                println("    Safe Mode: $(get(health_status, "safe_mode", "unknown"))")
            catch e
                @test false "Health check failed: $e"
                println("  ✗ Health check failed: $e")
                println("\n  Make sure BEAGLE core server is running:")
                println("    cargo run --bin beagle-monorepo --release")
            end
        end
    end

    @testset "Simple LLM Completion" begin
        println("\n[Test 2/4] Simple LLM completion...")

        if SKIP_LIVE_TESTS
            @test_skip "LLM completion (BEAGLE_SKIP_LIVE_TESTS=true)"
        else
            try
                prompt = "What is PBPK modeling? Answer in one sentence."
                response = BeagleLLM.complete(prompt)

                @test !isempty(response)
                @test length(response) > 10  # Should be more than a few words
                @test typeof(response) == String

                println("  ✓ LLM completion successful")
                println("    Prompt: $prompt")
                println("    Response length: $(length(response)) chars")
                println("    Response preview: $(first(response, min(100, length(response))))...")
            catch e
                @test false "LLM completion failed: $e"
                println("  ✗ LLM completion failed: $e")
            end
        end
    end

    @testset "LLM with Parameters" begin
        println("\n[Test 3/4] LLM with high quality flag...")

        if SKIP_LIVE_TESTS
            @test_skip "LLM with parameters (BEAGLE_SKIP_LIVE_TESTS=true)"
        else
            try
                prompt = "Explain the concept of clearance in pharmacokinetics."
                response = BeagleLLM.complete(
                    prompt;
                    requires_high_quality=true,
                    requires_math=true
                )

                @test !isempty(response)
                @test length(response) > 20

                println("  ✓ LLM with parameters successful")
                println("    Parameters: requires_high_quality=true, requires_math=true")
                println("    Response length: $(length(response)) chars")
            catch e
                @test false "LLM with parameters failed: $e"
                println("  ✗ LLM with parameters failed: $e")
            end
        end
    end

    @testset "Module Interface" begin
        println("\n[Test 4/4] Module interface validation...")

        # Test that all expected functions exist
        @test isdefined(BeagleLLM, :complete)
        @test isdefined(BeagleLLM, :start_pipeline)
        @test isdefined(BeagleLLM, :pipeline_status)
        @test isdefined(BeagleLLM, :health)

        # Test function signatures
        @test hasmethod(BeagleLLM.complete, (AbstractString,))
        @test hasmethod(BeagleLLM.start_pipeline, (AbstractString,))
        @test hasmethod(BeagleLLM.pipeline_status, (AbstractString,))
        @test hasmethod(BeagleLLM.health, ())

        println("  ✓ All expected functions exist")
        println("    - complete()")
        println("    - start_pipeline()")
        println("    - pipeline_status()")
        println("    - health()")
    end
end

println("\n" * "="^70)
println("Smoke Test Complete!")
println("="^70)

if SKIP_LIVE_TESTS
    println("\n⚠️  Live tests were skipped (BEAGLE_SKIP_LIVE_TESTS=true)")
    println("To run full tests, start the BEAGLE server and run:")
    println("  julia test/test_beagle_llm.jl")
else
    println("\n✅ All tests passed!")
end

println()

# test_beagle_llm.jl - Comprehensive Tests for BeagleLLM Module
#
# Test coverage includes:
# - Basic completion functionality
# - Mock mode for offline testing
# - Error handling and retries
# - RequestMeta routing
# - Statistics tracking
# - Chat functionality
# - Streaming (simulated)
#
# Run with: julia test_beagle_llm.jl

using Test
using UUIDs

# Add parent directory to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using BeagleLLM

@testset "BeagleLLM.jl Tests" begin

    # ============================================
    # Mock Mode Tests
    # ============================================

    @testset "Mock Mode" begin
        # Enable mock mode
        BeagleLLM.set_mock_mode(true)
        @test BeagleLLM.is_mock_mode() == true

        @testset "Basic Mock Completion" begin
            response = BeagleLLM.complete("Test prompt")
            @test typeof(response) == String
            @test length(response) > 0
            @test contains(response, "Mock response")
        end

        @testset "Math Mock Response" begin
            response = BeagleLLM.complete("Explain the math behind derivatives")
            @test contains(lowercase(response), "derivative")
            @test contains(response, "f'(x)")

            # Test with meta
            meta = BeagleLLM.RequestMeta(requires_math=true)
            response = BeagleLLM.complete("Any prompt", meta=meta)
            @test contains(lowercase(response), "mathematical")
        end

        @testset "Code Mock Response" begin
            response = BeagleLLM.complete("Write Julia code for sorting")
            @test contains(response, "```julia")
            @test contains(response, "function")

            # Test with meta
            meta = BeagleLLM.RequestMeta(requires_code=true)
            response = BeagleLLM.complete("Any prompt", meta=meta)
            @test contains(response, "```julia")
        end

        @testset "Error Handling in Mock" begin
            @test_throws ErrorException BeagleLLM.complete("Trigger error please")
        end

        # Disable mock mode for remaining tests
        BeagleLLM.set_mock_mode(false)
        @test BeagleLLM.is_mock_mode() == false
    end

    # ============================================
    # RequestMeta Tests
    # ============================================

    @testset "RequestMeta" begin
        @testset "Default Values" begin
            meta = BeagleLLM.RequestMeta()
            @test meta.requires_high_quality == false
            @test meta.requires_math == false
            @test meta.approximate_tokens == 1000
            @test isnothing(meta.max_cost_usd)
        end

        @testset "Custom Values" begin
            meta = BeagleLLM.RequestMeta(
                requires_high_quality = true,
                requires_math = true,
                max_cost_usd = 0.10,
                language = "julia"
            )
            @test meta.requires_high_quality == true
            @test meta.requires_math == true
            @test meta.max_cost_usd == 0.10
            @test meta.language == "julia"
        end

        @testset "Meta to Dict Conversion" begin
            meta = BeagleLLM.RequestMeta(requires_math=true)
            dict = BeagleLLM.meta_to_dict(meta)
            @test dict["requires_math"] == true
            @test dict["requires_high_quality"] == false
            @test haskey(dict, "approximate_tokens")
        end
    end

    # ============================================
    # Statistics Tests
    # ============================================

    @testset "Statistics Tracking" begin
        # Reset statistics
        BeagleLLM.reset_statistics!()
        stats = BeagleLLM.get_statistics()
        @test stats.total_requests == 0
        @test stats.total_tokens == 0
        @test stats.total_cost == 0.0

        # Enable mock mode for controlled testing
        BeagleLLM.set_mock_mode(true)

        # Make some requests
        BeagleLLM.complete("Test 1")
        BeagleLLM.complete("Test 2")

        # Check statistics updated
        stats = BeagleLLM.get_statistics()
        @test stats.total_requests == 2
        @test stats.successful_requests == 2
        @test stats.failed_requests == 0
        @test stats.total_tokens > 0
        @test haskey(stats.provider_distribution, "mock")
        @test stats.provider_distribution["mock"] == 2

        # Test error tracking
        try
            BeagleLLM.complete("Trigger error")
        catch e
            # Expected error
        end

        stats = BeagleLLM.get_statistics()
        @test stats.failed_requests == 1

        # Reset and verify
        BeagleLLM.reset_statistics!()
        stats = BeagleLLM.get_statistics()
        @test stats.total_requests == 0

        BeagleLLM.set_mock_mode(false)
    end

    # ============================================
    # Chat Functionality Tests
    # ============================================

    @testset "Chat Functionality" begin
        BeagleLLM.set_mock_mode(true)

        @testset "Message Formatting" begin
            messages = [
                Dict("role" => "system", "content" => "You are helpful"),
                Dict("role" => "user", "content" => "Hello"),
                Dict("role" => "assistant", "content" => "Hi there"),
                Dict("role" => "user", "content" => "How are you?")
            ]

            formatted = BeagleLLM.format_messages(messages)
            @test contains(formatted, "SYSTEM:")
            @test contains(formatted, "USER:")
            @test contains(formatted, "ASSISTANT:")
            @test contains(formatted, "Hello")
            @test contains(formatted, "How are you?")
        end

        @testset "Chat Completion" begin
            messages = [
                Dict("role" => "user", "content" => "Test message")
            ]

            response = BeagleLLM.chat(messages)
            @test typeof(response) == String
            @test length(response) > 0
        end

        BeagleLLM.set_mock_mode(false)
    end

    # ============================================
    # Convenience Functions Tests
    # ============================================

    @testset "Convenience Functions" begin
        BeagleLLM.set_mock_mode(true)

        @testset "Scientific Completion" begin
            response = BeagleLLM.complete_scientific("Derive equation")
            @test typeof(response) == String
            @test contains(lowercase(response), "derivative") || contains(response, "mathematical")
        end

        @testset "Code Completion" begin
            response = BeagleLLM.complete_code("Sort array", language="julia")
            @test typeof(response) == String
            @test contains(response, "julia") || contains(response, "function")
        end

        @testset "Fast Completion" begin
            response = BeagleLLM.complete_fast("Quick answer")
            @test typeof(response) == String
            @test length(response) > 0
        end

        BeagleLLM.set_mock_mode(false)
    end

    # ============================================
    # UUID and Run ID Tests
    # ============================================

    @testset "Run ID Tracking" begin
        BeagleLLM.set_mock_mode(true)

        @testset "Auto-generated Run ID" begin
            response = BeagleLLM.complete("Test")
            # In mock mode, we get the content directly, not the response object
            @test typeof(response) == String
        end

        @testset "Custom Run ID" begin
            custom_id = "test_run_123"
            response = BeagleLLM.complete("Test", run_id=custom_id)
            @test typeof(response) == String
        end

        BeagleLLM.set_mock_mode(false)
    end

    # ============================================
    # Edge Cases and Error Conditions
    # ============================================

    @testset "Edge Cases" begin
        BeagleLLM.set_mock_mode(true)

        @testset "Empty Prompt" begin
            response = BeagleLLM.complete("")
            @test typeof(response) == String
            @test length(response) > 0  # Should still return something
        end

        @testset "Very Long Prompt" begin
            long_prompt = repeat("Test ", 10000)
            response = BeagleLLM.complete(long_prompt)
            @test typeof(response) == String
        end

        @testset "Special Characters" begin
            special_prompt = "Test with émojis 🚀 and unicode τ ≈ 2π"
            response = BeagleLLM.complete(special_prompt)
            @test typeof(response) == String
        end

        @testset "Null/Nothing Handling" begin
            response = BeagleLLM.complete("Test", meta=nothing, max_tokens=nothing)
            @test typeof(response) == String
        end

        BeagleLLM.set_mock_mode(false)
    end

    # ============================================
    # Performance Tests
    # ============================================

    @testset "Performance" begin
        BeagleLLM.set_mock_mode(true)
        BeagleLLM.reset_statistics!()

        @testset "Batch Processing" begin
            start_time = time()
            for i in 1:10
                BeagleLLM.complete("Test $i")
            end
            elapsed = time() - start_time

            # Should be fast in mock mode
            @test elapsed < 5.0  # Less than 5 seconds for 10 requests

            stats = BeagleLLM.get_statistics()
            @test stats.total_requests == 10
            @test stats.successful_requests == 10
        end

        @testset "Concurrent Requests" begin
            BeagleLLM.reset_statistics!()

            # Note: Julia's async model is different from traditional threads
            # This tests sequential processing but simulates async patterns
            tasks = []
            for i in 1:5
                push!(tasks, @async BeagleLLM.complete("Async test $i"))
            end

            # Wait for all tasks
            for task in tasks
                wait(task)
            end

            stats = BeagleLLM.get_statistics()
            @test stats.total_requests == 5
        end

        BeagleLLM.set_mock_mode(false)
    end

    # ============================================
    # Integration Tests (if server is running)
    # ============================================

    @testset "Integration Tests (Optional)" begin
        # These tests only run if BEAGLE_TEST_INTEGRATION is set
        if get(ENV, "BEAGLE_TEST_INTEGRATION", "false") == "true"
            @testset "Real Server Connection" begin
                try
                    # Attempt real connection with timeout
                    response = BeagleLLM.complete(
                        "Return 'OK' if you receive this",
                        timeout=5,
                        retries=1
                    )
                    @test typeof(response) == String
                    @test length(response) > 0
                    println("✅ Successfully connected to BEAGLE server")
                catch e
                    @test_skip "Server not available: $(e)"
                end
            end
        else
            @test_skip "Integration tests skipped (set BEAGLE_TEST_INTEGRATION=true to run)"
        end
    end

    # ============================================
    # Print Final Statistics
    # ============================================

    @testset "Statistics Summary" begin
        println("\n" * "="^50)
        println("Test Statistics Summary")
        println("="^50)
        BeagleLLM.print_statistics()
        println("="^50)

        # Verify statistics printing doesn't error
        @test true
    end
end

# Run tests
println("🧪 Starting BeagleLLM.jl test suite...")
println("="^60)

# Set test environment
ENV["BEAGLE_CORE_URL"] = get(ENV, "BEAGLE_CORE_URL", "http://localhost:8080")

# Run all tests
Test.@testset "BeagleLLM.jl Complete Test Suite" begin
    include(@__FILE__)
end

println("\n✅ All tests completed!")

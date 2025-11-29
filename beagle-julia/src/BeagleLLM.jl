# BeagleLLM.jl - Production-Ready Julia Client for BEAGLE LLM API
#
# Features:
# - Multi-provider support via TieredRouter
# - Comprehensive error handling and retries
# - Mock support for testing
# - Async/streaming capabilities
# - Full RequestMeta support
# - Statistics tracking
#
# References:
# - Bezanson, J., et al. (2017). "Julia: A fresh approach to numerical computing."
# - Wickham, H. (2014). "Advanced R." Chapman and Hall/CRC.

module BeagleLLM

using HTTP
using JSON3
using Dates
using UUIDs
using Statistics
using Base: @kwdef
using Logging

# Export main functions and types
export complete, chat, stream_complete
export LLMClient, MockClient, RequestMeta, LLMResponse
export get_statistics, reset_statistics
export set_mock_mode, is_mock_mode

# Configuration
const BEAGLE_CORE_URL = get(ENV, "BEAGLE_CORE_URL", "http://localhost:8080")
const DEFAULT_TIMEOUT = 300  # seconds
const MAX_RETRIES = 3
const RETRY_DELAY = 1.0  # seconds

# Mock mode for testing
const MOCK_MODE = Ref(false)

"""
    RequestMeta

Metadata for intelligent LLM routing.
Mirrors the Rust RequestMeta structure.
"""
@kwdef mutable struct RequestMeta
    requires_high_quality::Bool = false
    requires_phd_level_reasoning::Bool = false
    high_bias_risk::Bool = false
    critical_section::Bool = false
    requires_math::Bool = false
    requires_vision::Bool = false
    requires_code::Bool = false
    requires_realtime::Bool = false
    offline_required::Bool = false
    approximate_tokens::Int = 1000
    max_cost_usd::Union{Nothing, Float64} = nothing
    language::Union{Nothing, String} = nothing
    requires_tools::Bool = false
    requires_long_context::Bool = false
    requires_deterministic::Bool = false
    custom_metadata::Dict{String, String} = Dict()
end

"""
    LLMResponse

Response from LLM API including metadata.
"""
@kwdef struct LLMResponse
    content::String
    run_id::String
    provider::String
    tier::String
    tokens_used::Int
    latency_ms::Int
    cost_usd::Float64
    cache_hit::Bool = false
    metadata::Dict{String, Any} = Dict()
end

"""
    LLMStatistics

Statistics tracking for LLM usage.
"""
mutable struct LLMStatistics
    total_requests::Int
    successful_requests::Int
    failed_requests::Int
    total_tokens::Int
    total_cost::Float64
    total_latency_ms::Int
    provider_distribution::Dict{String, Int}
    error_types::Dict{String, Int}
end

# Global statistics
const GLOBAL_STATS = LLMStatistics(0, 0, 0, 0, 0.0, 0, Dict(), Dict())

"""
Abstract type for LLM clients.
"""
abstract type LLMClient end

"""
    HTTPClient <: LLMClient

Standard HTTP-based LLM client.
"""
struct HTTPClient <: LLMClient
    base_url::String
    timeout::Int
    headers::Dict{String, String}
end

"""
    MockClient <: LLMClient

Mock client for testing.
"""
struct MockClient <: LLMClient
    responses::Vector{String}
    response_index::Ref{Int}
    delay_ms::Int
end

"""
    complete(prompt::String; kwargs...) -> String

Complete a prompt using BEAGLE LLM API.

# Arguments
- `prompt::String`: The prompt to complete
- `run_id::String`: Optional run ID for tracking
- `meta::RequestMeta`: Request metadata for routing
- `max_tokens::Int`: Maximum tokens to generate
- `temperature::Float64`: Temperature for sampling
- `timeout::Int`: Request timeout in seconds
- `retries::Int`: Number of retries on failure

# Returns
- `String`: The LLM response content

# Examples
```julia
# Simple completion
response = complete("Explain PBPK modeling")

# With metadata for routing
meta = RequestMeta(requires_math=true, requires_high_quality=true)
response = complete("Derive the clearance equation", meta=meta)

# With custom run tracking
response = complete("Question", run_id="experiment_001")
```
"""
function complete(prompt::String;
                 run_id::String = string(uuid4()),
                 meta::Union{Nothing, RequestMeta} = nothing,
                 max_tokens::Union{Nothing, Int} = nothing,
                 temperature::Union{Nothing, Float64} = nothing,
                 timeout::Int = DEFAULT_TIMEOUT,
                 retries::Int = MAX_RETRIES,
                 client::Union{Nothing, LLMClient} = nothing)

    # Use mock if in mock mode
    if MOCK_MODE[]
        return complete_mock(prompt, run_id, meta)
    end

    # Use provided client or create default
    if isnothing(client)
        client = HTTPClient(BEAGLE_CORE_URL, timeout, Dict("Content-Type" => "application/json"))
    end

    # Prepare request
    meta = isnothing(meta) ? RequestMeta() : meta
    response = complete_with_retries(client, prompt, run_id, meta, max_tokens, temperature, retries)

    # Update statistics
    update_statistics!(response)

    return response.content
end

"""
    complete_with_retries(client, prompt, run_id, meta, max_tokens, temperature, retries)

Internal function to handle retries.
"""
function complete_with_retries(client::HTTPClient, prompt::String, run_id::String,
                               meta::RequestMeta, max_tokens, temperature, retries::Int)
    last_error = nothing

    for attempt in 1:retries
        try
            return execute_request(client, prompt, run_id, meta, max_tokens, temperature)
        catch e
            last_error = e
            if attempt < retries
                @warn "LLM request failed, retrying..." attempt=attempt error=e
                sleep(RETRY_DELAY * attempt)  # Exponential backoff
            end
        end
    end

    # All retries failed
    GLOBAL_STATS.failed_requests += 1
    push!(get!(GLOBAL_STATS.error_types, string(typeof(last_error)), 0), 1)
    throw(last_error)
end

"""
    execute_request(client, prompt, run_id, meta, max_tokens, temperature)

Execute the actual HTTP request.
"""
function execute_request(client::HTTPClient, prompt::String, run_id::String,
                        meta::RequestMeta, max_tokens, temperature)

    # Build request body
    body = Dict{String, Any}(
        "prompt" => prompt,
        "run_id" => run_id,
        "meta" => meta_to_dict(meta)
    )

    if !isnothing(max_tokens)
        body["max_tokens"] = max_tokens
    end

    if !isnothing(temperature)
        body["temperature"] = temperature
    end

    # Make request
    start_time = time_ns()

    response = HTTP.post(
        "$(client.base_url)/v1/llm/complete/$(run_id)";
        headers = client.headers,
        body = JSON3.write(body),
        readtimeout = client.timeout,
        retry = false  # We handle retries ourselves
    )

    latency_ms = Int((time_ns() - start_time) ÷ 1_000_000)

    # Check status
    if response.status != 200
        error("LLM API error: $(response.status) - $(String(response.body))")
    end

    # Parse response
    json = JSON3.read(String(response.body))

    return LLMResponse(
        content = json["content"],
        run_id = get(json, "run_id", run_id),
        provider = get(json, "provider", "unknown"),
        tier = get(json, "tier", "unknown"),
        tokens_used = get(json, "tokens_used", 0),
        latency_ms = get(json, "latency_ms", latency_ms),
        cost_usd = get(json, "cost_usd", 0.0),
        cache_hit = get(json, "cache_hit", false),
        metadata = get(json, "metadata", Dict())
    )
end

"""
    chat(messages; kwargs...) -> String

Chat with multiple messages.

# Arguments
- `messages::Vector{Dict{String, String}}`: List of messages with "role" and "content"
- Other arguments same as `complete`

# Examples
```julia
messages = [
    Dict("role" => "system", "content" => "You are a scientific assistant"),
    Dict("role" => "user", "content" => "Explain PBPK modeling")
]
response = chat(messages, meta=RequestMeta(requires_math=true))
```
"""
function chat(messages::Vector{Dict{String, String}};
             run_id::String = string(uuid4()),
             meta::Union{Nothing, RequestMeta} = nothing,
             kwargs...)

    # Convert messages to single prompt
    prompt = format_messages(messages)

    # Use complete with formatted prompt
    return complete(prompt; run_id=run_id, meta=meta, kwargs...)
end

"""
    stream_complete(prompt::String; callback::Function, kwargs...) -> Nothing

Stream completion with callback for each chunk.

# Arguments
- `prompt::String`: The prompt to complete
- `callback::Function`: Function called with each chunk
- Other arguments same as `complete`

# Examples
```julia
stream_complete("Long explanation", callback = chunk -> print(chunk))
```
"""
function stream_complete(prompt::String;
                        callback::Function,
                        run_id::String = string(uuid4()),
                        meta::Union{Nothing, RequestMeta} = nothing,
                        kwargs...)

    # For now, just get complete response and simulate streaming
    # In production, would use SSE or WebSockets
    response = complete(prompt; run_id=run_id, meta=meta, kwargs...)

    # Simulate streaming by chunking response
    words = split(response, " ")
    for i in 1:length(words)
        chunk = join(words[1:min(i*10, length(words))], " ")
        callback(chunk)
        if i*10 < length(words)
            sleep(0.1)  # Simulate streaming delay
        end
    end

    return nothing
end

# ============================================
# Mock Support for Testing
# ============================================

"""
    set_mock_mode(enabled::Bool)

Enable or disable mock mode for testing.
"""
function set_mock_mode(enabled::Bool)
    MOCK_MODE[] = enabled
end

"""
    is_mock_mode() -> Bool

Check if mock mode is enabled.
"""
function is_mock_mode()
    return MOCK_MODE[]
end

"""
    complete_mock(prompt, run_id, meta) -> String

Mock completion for testing.
"""
function complete_mock(prompt::String, run_id::String, meta::Union{Nothing, RequestMeta})
    # Generate deterministic mock response based on prompt
    if contains(lowercase(prompt), "math") || (!isnothing(meta) && meta.requires_math)
        content = "Mock mathematical response: The derivative of f(x) = x² is f'(x) = 2x"
    elseif contains(lowercase(prompt), "code") || (!isnothing(meta) && meta.requires_code)
        content = "Mock code response:\n```julia\nfunction example(x)\n    return x^2\nend\n```"
    elseif contains(lowercase(prompt), "error")
        error("Mock error for testing")
    else
        content = "Mock response for: $(first(prompt, min(50, length(prompt))))"
    end

    # Create mock response
    response = LLMResponse(
        content = content,
        run_id = run_id,
        provider = "mock",
        tier = "mock",
        tokens_used = length(split(content)),
        latency_ms = 100,
        cost_usd = 0.0,
        cache_hit = false
    )

    # Update statistics even for mock
    update_statistics!(response)

    return content
end

# ============================================
# Statistics and Monitoring
# ============================================

"""
    update_statistics!(response::LLMResponse)

Update global statistics with response data.
"""
function update_statistics!(response::LLMResponse)
    GLOBAL_STATS.total_requests += 1
    GLOBAL_STATS.successful_requests += 1
    GLOBAL_STATS.total_tokens += response.tokens_used
    GLOBAL_STATS.total_cost += response.cost_usd
    GLOBAL_STATS.total_latency_ms += response.latency_ms

    # Update provider distribution
    if haskey(GLOBAL_STATS.provider_distribution, response.provider)
        GLOBAL_STATS.provider_distribution[response.provider] += 1
    else
        GLOBAL_STATS.provider_distribution[response.provider] = 1
    end
end

"""
    get_statistics() -> LLMStatistics

Get current usage statistics.
"""
function get_statistics()
    return deepcopy(GLOBAL_STATS)
end

"""
    reset_statistics!()

Reset all statistics to zero.
"""
function reset_statistics!()
    GLOBAL_STATS.total_requests = 0
    GLOBAL_STATS.successful_requests = 0
    GLOBAL_STATS.failed_requests = 0
    GLOBAL_STATS.total_tokens = 0
    GLOBAL_STATS.total_cost = 0.0
    GLOBAL_STATS.total_latency_ms = 0
    empty!(GLOBAL_STATS.provider_distribution)
    empty!(GLOBAL_STATS.error_types)
end

"""
    print_statistics()

Print formatted statistics to stdout.
"""
function print_statistics()
    stats = get_statistics()
    println("=== BeagleLLM Statistics ===")
    println("Total Requests: $(stats.total_requests)")
    println("Successful: $(stats.successful_requests)")
    println("Failed: $(stats.failed_requests)")
    println("Total Tokens: $(stats.total_tokens)")
    println("Total Cost: \$$(round(stats.total_cost, digits=4))")
    if stats.successful_requests > 0
        avg_latency = stats.total_latency_ms / stats.successful_requests
        println("Avg Latency: $(round(avg_latency, digits=1))ms")
    end
    println("\nProvider Distribution:")
    for (provider, count) in stats.provider_distribution
        println("  $provider: $count")
    end
    if !isempty(stats.error_types)
        println("\nError Types:")
        for (error_type, count) in stats.error_types
            println("  $error_type: $count")
        end
    end
end

# ============================================
# Helper Functions
# ============================================

"""
    meta_to_dict(meta::RequestMeta) -> Dict

Convert RequestMeta to dictionary for JSON serialization.
"""
function meta_to_dict(meta::RequestMeta)
    return Dict(
        "requires_high_quality" => meta.requires_high_quality,
        "requires_phd_level_reasoning" => meta.requires_phd_level_reasoning,
        "high_bias_risk" => meta.high_bias_risk,
        "critical_section" => meta.critical_section,
        "requires_math" => meta.requires_math,
        "requires_vision" => meta.requires_vision,
        "requires_code" => meta.requires_code,
        "requires_realtime" => meta.requires_realtime,
        "offline_required" => meta.offline_required,
        "approximate_tokens" => meta.approximate_tokens,
        "max_cost_usd" => meta.max_cost_usd,
        "language" => meta.language,
        "requires_tools" => meta.requires_tools,
        "requires_long_context" => meta.requires_long_context,
        "requires_deterministic" => meta.requires_deterministic,
        "custom_metadata" => meta.custom_metadata
    )
end

"""
    format_messages(messages) -> String

Format chat messages into a single prompt.
"""
function format_messages(messages::Vector{Dict{String, String}})
    formatted = String[]
    for msg in messages
        role = get(msg, "role", "user")
        content = get(msg, "content", "")
        push!(formatted, "$(uppercase(role)): $content")
    end
    return join(formatted, "\n\n")
end

# ============================================
# Convenience Functions
# ============================================

"""
    complete_scientific(prompt::String; kwargs...) -> String

Complete with scientific/mathematical settings.
"""
function complete_scientific(prompt::String; kwargs...)
    meta = RequestMeta(
        requires_math = true,
        requires_high_quality = true,
        requires_phd_level_reasoning = true
    )
    return complete(prompt; meta=meta, kwargs...)
end

"""
    complete_code(prompt::String; language::String="julia", kwargs...) -> String

Complete with code generation settings.
"""
function complete_code(prompt::String; language::String="julia", kwargs...)
    meta = RequestMeta(
        requires_code = true,
        requires_deterministic = true,
        language = language
    )
    return complete(prompt; meta=meta, kwargs...)
end

"""
    complete_fast(prompt::String; kwargs...) -> String

Complete with fast/realtime settings.
"""
function complete_fast(prompt::String; kwargs...)
    meta = RequestMeta(
        requires_realtime = true,
        max_cost_usd = 0.01
    )
    return complete(prompt; meta=meta, kwargs...)
end

end # module

#!/usr/bin/env julia

"""
HRV Mood Pipeline - 100% Julia
Análise de HRV para predição de humor
"""

module HRVMoodPipeline

using Flux
using Optimisers
using Zygote
using Statistics
using FFTW

export HRVMoodPipeline, predict_mood, train_pipeline

struct HRVMoodPipeline
    model::Chain
end

function HRVMoodPipeline(;
    input_dim::Int=6,
    hidden_dims::Vector{Int}=[64, 32],
    output_dim::Int=3
)
    layers = []
    prev_dim = input_dim
    
    for hidden in hidden_dims
        push!(layers, Dense(prev_dim => hidden, relu))
        prev_dim = hidden
    end
    
    push!(layers, Dense(prev_dim => output_dim, softmax))
    
    HRVMoodPipeline(Chain(layers...))
end

function compute_hrv_features(rr_intervals::Vector{Float32})::Vector{Float32}
    # RMSSD
    diffs = diff(rr_intervals)
    rmssd = sqrt(mean(diffs .^ 2))
    
    # SDNN
    sdnn = std(rr_intervals)
    
    # pNN50
    pnn50 = sum(abs.(diffs) .> 50.0f0) / length(diffs) * 100.0f0
    
    # Frequency domain (FFT)
    fft_result = fft(rr_intervals)
    power = abs2.(fft_result)
    
    # LF power (0.04-0.15 Hz)
    lf_idx = [i for i in 1:length(power) if 0.04 <= i/length(power) <= 0.15]
    lf_power = sum(power[lf_idx])
    
    # HF power (0.15-0.4 Hz)
    hf_idx = [i for i in 1:length(power) if 0.15 < i/length(power) <= 0.4]
    hf_power = sum(power[hf_idx])
    
    # LF/HF ratio
    lf_hf_ratio = lf_power / (hf_power + 1e-6f0)
    
    [rmssd, sdnn, pnn50, lf_power, hf_power, lf_hf_ratio]
end

function predict_mood(pipeline::HRVMoodPipeline, rr_intervals::Vector{Float32})::Vector{Float32}
    features = compute_hrv_features(rr_intervals)
    pipeline.model(features)
end

function train_pipeline(
    pipeline::HRVMoodPipeline,
    X_train::Matrix{Float32},
    y_train::Matrix{Float32},
    epochs::Int=100,
    lr::Float32=1e-3f0
)::Dict{String,Any}
    @info "😊 Treinando HRV Mood Pipeline"
    
    opt = Optimisers.ADAM(lr)
    opt_state = Optimisers.setup(opt, Flux.params(pipeline.model))
    
    losses = Float32[]
    
    for epoch in 1:epochs
        loss, grads = Zygote.withgradient(Flux.params(pipeline.model)) do
            pred = pipeline.model(X_train)
            mean((pred .- y_train) .^ 2)
        end
        
        opt_state, _ = Optimisers.update(opt_state, Flux.params(pipeline.model), grads)
        push!(losses, loss)
        
        if epoch % 10 == 0
            @info "Epoch $epoch: Loss = $(round(loss, sigdigits=4))"
        end
    end
    
    @info "✅ HRV Mood Pipeline treinado"
    
    Dict("losses" => losses, "final_loss" => losses[end])
end

end # module


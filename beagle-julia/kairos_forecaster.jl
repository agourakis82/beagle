#!/usr/bin/env julia

"""
Kairos Forecaster - 100% Julia
Previsão temporal de eventos heliobiológicos
"""

module KairosForecaster

using Dates
using Statistics
using FFTW
using Flux
using Optimisers
using Zygote

export KairosForecaster, forecast, train_forecaster

struct KairosForecaster
    model::Chain
    lookback::Int
    horizon::Int
end

function KairosForecaster(;
    input_dim::Int=3,
    hidden_dim::Int=64,
    lookback::Int=24,
    horizon::Int=6
)
    model = Chain(
        Dense(input_dim * lookback => hidden_dim, relu),
        Dense(hidden_dim => hidden_dim, relu),
        Dense(hidden_dim => input_dim * horizon)
    )
    
    KairosForecaster(model, lookback, horizon)
end

function forecast(forecaster::KairosForecaster, history::Matrix{Float32})::Matrix{Float32}
    # Flatten lookback window
    input = reshape(history[:, end-forecaster.lookback+1:end], :)
    
    # Predict
    pred = forecaster.model(input)
    
    # Reshape to (features, horizon)
    reshape(pred, 3, forecaster.horizon)
end

function train_forecaster(
    forecaster::KairosForecaster,
    X_train::Array{Float32,3},
    y_train::Array{Float32,3},
    epochs::Int=50,
    lr::Float32=1e-3f0
)::Dict{String,Any}
    @info "🔮 Treinando Kairos Forecaster"
    
    opt = Optimisers.ADAM(lr)
    opt_state = Optimisers.setup(opt, Flux.params(forecaster.model))
    
    losses = Float32[]
    
    for epoch in 1:epochs
        epoch_loss = 0.0f0
        n_batches = 0
        
        for i in 1:size(X_train, 3)
            X_batch = X_train[:, :, i]
            y_batch = y_train[:, :, i]
            
            loss, grads = Zygote.withgradient(Flux.params(forecaster.model)) do
                pred = forecast(forecaster, X_batch)
                mean((pred .- y_batch) .^ 2)
            end
            
            opt_state, _ = Optimisers.update(opt_state, Flux.params(forecaster.model), grads)
            epoch_loss += loss
            n_batches += 1
        end
        
        avg_loss = epoch_loss / n_batches
        push!(losses, avg_loss)
        
        if epoch % 10 == 0
            @info "Epoch $epoch: Loss = $(round(avg_loss, sigdigits=4))"
        end
    end
    
    @info "✅ Kairos Forecaster treinado"
    
    Dict("losses" => losses, "final_loss" => losses[end])
end

end # module


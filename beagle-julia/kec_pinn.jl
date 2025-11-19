#!/usr/bin/env julia

"""
KEC-PINN Model - 100% Julia
Combina KEC features com Physics-Informed Neural Network
"""

module KECPINN

using Flux
using Optimisers
using Zygote
using Dates

export KECPINNModel, train_kec_pinn

struct KECPINNModel
    shared_encoder::Chain
    kec_head::Chain
    pk_head::Chain
end

function KECPINNModel(;
    input_dim::Int=976,
    shared_hidden::Vector{Int}=[512, 256],
    kec_dim::Int=15,
    pk_dim::Int=3
)
    # Shared encoder
    shared_layers = []
    prev_dim = input_dim
    for hidden in shared_hidden
        push!(shared_layers, Dense(prev_dim => hidden, relu))
        prev_dim = hidden
    end
    
    shared_encoder = Chain(shared_layers...)
    
    # KEC head (prediz métricas KEC)
    kec_head = Chain(
        Dense(prev_dim => 128, relu),
        Dense(128 => kec_dim)
    )
    
    # PK head (prediz fu, vd, cl)
    pk_head = Chain(
        Dense(prev_dim => 128, relu),
        Dense(128 => pk_dim, sigmoid)
    )
    
    KECPINNModel(shared_encoder, kec_head, pk_head)
end

function kec_loss(pred_kec::Matrix{Float32}, target_kec::Matrix{Float32})::Float32
    mean((pred_kec .- target_kec) .^ 2)
end

function train_kec_pinn(
    model::KECPINNModel,
    X::Matrix{Float32},
    y_kec::Matrix{Float32},
    y_pk::Matrix{Float32},
    epochs::Int=100,
    lr::Float32=1e-4f0
)::Dict{String,Any}
    @info "🔬 Treinando KEC-PINN"
    
    opt = Optimisers.ADAM(lr)
    opt_state = Optimisers.setup(opt, Flux.params(model))
    
    losses = Float32[]
    
    for epoch in 1:epochs
        loss, grads = Zygote.withgradient(Flux.params(model)) do
            shared = model.shared_encoder(X)
            pred_kec = model.kec_head(shared)
            pred_pk = model.pk_head(shared)
            
            kec_l = kec_loss(pred_kec, y_kec)
            pk_l = mean((pred_pk .- y_pk) .^ 2)
            
            kec_l + pk_l
        end
        
        opt_state, _ = Optimisers.update(opt_state, Flux.params(model), grads)
        push!(losses, loss)
        
        if epoch % 10 == 0
            @info "Epoch $epoch: Loss = $(round(loss, sigdigits=4))"
        end
    end
    
    @info "✅ KEC-PINN treinado"
    
    Dict("losses" => losses, "final_loss" => losses[end])
end

end # module


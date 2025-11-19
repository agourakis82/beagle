#!/usr/bin/env julia

"""
Evidential Deep Learning - 100% Julia
Uncertainty quantification para PBPK predictions
"""

module Evidential

using Flux
using Zygote

export EvidentialHead, evidential_loss, predict_with_uncertainty

struct EvidentialHead
    network::Chain
end

function EvidentialHead(input_dim::Int, output_dim::Int, hidden_dims::Vector{Int}=[128, 64])
    layers = []
    prev_dim = input_dim
    
    for hidden in hidden_dims
        push!(layers, Dense(prev_dim => hidden, relu))
        prev_dim = hidden
    end
    
    # Output: 4 * output_dim (alpha, beta, gamma, nu para cada saída)
    push!(layers, Dense(prev_dim => 4 * output_dim))
    
    EvidentialHead(Chain(layers...))
end

function evidential_loss(pred::Matrix{Float32}, target::Matrix{Float32}, lambda_reg::Float32=0.01f0)::Float32
    # Evidential loss (normal-inverse-gamma)
    # pred tem shape (4*output_dim, batch_size) - [alpha, beta, gamma, nu] para cada saída
    
    n_outputs = size(target, 1)
    batch_size = size(target, 2)
    
    total_loss = 0.0f0
    
    for i in 1:n_outputs
        alpha_idx = (i - 1) * 4 + 1
        beta_idx = (i - 1) * 4 + 2
        gamma_idx = (i - 1) * 4 + 3
        nu_idx = i * 4
        
        alpha = pred[alpha_idx, :] .+ 1.0f0  # alpha > 1
        beta = pred[beta_idx, :] .+ 1e-6f0   # beta > 0
        gamma = pred[gamma_idx, :]
        nu = pred[nu_idx, :] .+ 1e-6f0        # nu > 0
        
        target_i = target[i, :]
        
        # Evidential loss
        loss_i = sum(log.(beta) .+ (alpha .- 1.0f0) .* log.(nu) .- 
                       lgamma.(alpha) .+ alpha .* log.(beta .+ nu .* (target_i .- gamma) .^ 2))
        
        # Regularization (penaliza alta incerteza)
        reg = lambda_reg * sum((alpha .- 1.0f0) ./ beta)
        
        total_loss += loss_i + reg
    end
    
    total_loss / (n_outputs * batch_size)
end

function predict_with_uncertainty(head::EvidentialHead, X::Matrix{Float32})::Tuple{Matrix{Float32}, Matrix{Float32}}
    pred = head.network(X)
    n_outputs = size(pred, 1) ÷ 4
    
    means = zeros(Float32, n_outputs, size(X, 2))
    uncertainties = zeros(Float32, n_outputs, size(X, 2))
    
    for i in 1:n_outputs
        alpha_idx = (i - 1) * 4 + 1
        beta_idx = (i - 1) * 4 + 2
        gamma_idx = (i - 1) * 4 + 3
        nu_idx = i * 4
        
        alpha = pred[alpha_idx, :] .+ 1.0f0
        beta = pred[beta_idx, :] .+ 1e-6f0
        gamma = pred[gamma_idx, :]
        nu = pred[nu_idx, :] .+ 1e-6f0
        
        # Mean prediction
        means[i, :] = gamma
        
        # Uncertainty (aleatoric + epistemic)
        aleatoric = beta ./ (alpha .- 1.0f0)
        epistemic = beta ./ (nu .* (alpha .- 1.0f0))
        uncertainties[i, :] = sqrt.(aleatoric .+ epistemic)
    end
    
    (means, uncertainties)
end

end # module


#!/usr/bin/env julia

"""
WESAD Dataset Loader - 100% Julia
Wearable Stress and Affect Detection dataset
"""

module WESADDataset

using CSV
using DataFrames
using Dates

export WESADDataset, load_wesad, extract_features

struct WESADDataset
    timestamps::Vector{DateTime}
    accel::Matrix{Float32}
    ecg::Matrix{Float32}
    emg::Matrix{Float32}
    eda::Matrix{Float32}
    temp::Matrix{Float32}
    labels::Vector{Int}
end

function load_wesad(data_path::String)::WESADDataset
    @info "📊 Carregando dataset WESAD: $data_path"
    
    # Carrega CSV (formato simplificado)
    df = CSV.read(data_path, DataFrame)
    
    timestamps = [DateTime(row.timestamp) for row in eachrow(df)]
    accel = Matrix{Float32}(df[:, [:accel_x, :accel_y, :accel_z]])
    ecg = Matrix{Float32}(df[:, :ecg])
    emg = Matrix{Float32}(df[:, :emg])
    eda = Matrix{Float32}(df[:, :eda])
    temp = Matrix{Float32}(df[:, :temp])
    labels = Int.(df[:, :label])
    
    @info "✅ WESAD carregado: $(length(timestamps)) amostras"
    
    WESADDataset(timestamps, accel, ecg, emg, eda, temp, labels)
end

function extract_features(dataset::WESADDataset, window_size::Int=60)::Matrix{Float32}
    @info "🔬 Extraindo features WESAD (window: $window_size)"
    
    n_windows = div(length(dataset.timestamps), window_size)
    features = Float32[]
    
    for i in 1:n_windows
        start_idx = (i - 1) * window_size + 1
        end_idx = min(i * window_size, length(dataset.timestamps))
        
        # ECG features
        ecg_window = dataset.ecg[start_idx:end_idx]
        push!(features, mean(ecg_window))
        push!(features, std(ecg_window))
        push!(features, maximum(ecg_window) - minimum(ecg_window))
        
        # EDA features
        eda_window = dataset.eda[start_idx:end_idx]
        push!(features, mean(eda_window))
        push!(features, std(eda_window))
        
        # Temp features
        temp_window = dataset.temp[start_idx:end_idx]
        push!(features, mean(temp_window))
        push!(features, std(temp_window))
        
        # Accel features
        accel_window = dataset.accel[start_idx:end_idx, :]
        push!(features, mean(accel_window))
        push!(features, std(accel_window))
    end
    
    n_features = 10
    reshape(features, n_features, n_windows)
end

end # module


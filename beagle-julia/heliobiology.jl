#!/usr/bin/env julia

module Heliobiology

using Dates
using Statistics
using FFTW
using CSV
using DataFrames

export SolarAtlas, analyze_solar_activity, correlate_with_physiology

struct SolarAtlas
    timestamps::Vector{DateTime}
    solar_flux::Vector{Float64}
    geomagnetic_index::Vector{Float64}
    cosmic_rays::Vector{Float64}
end

function SolarAtlas(data_file::String)
    df = CSV.read(data_file, DataFrame)
    
    timestamps = [DateTime(row[:timestamp]) for row in eachrow(df)]
    solar_flux = df[:, :solar_flux]
    geomagnetic_index = df[:, :geomagnetic_index]
    cosmic_rays = df[:, :cosmic_rays]
    
    SolarAtlas(timestamps, solar_flux, geomagnetic_index, cosmic_rays)
end

function analyze_solar_activity(atlas::SolarAtlas, start_date::DateTime, end_date::DateTime)::Dict{String,Float64}
    @info "☀️  Analisando atividade solar"
    
    mask = [d >= start_date && d <= end_date for d in atlas.timestamps]
    flux_period = atlas.solar_flux[mask]
    geomag_period = atlas.geomagnetic_index[mask]
    
    Dict(
        "mean_flux" => mean(flux_period),
        "max_flux" => maximum(flux_period),
        "mean_geomag" => mean(geomag_period),
        "max_geomag" => maximum(geomag_period),
        "flux_variance" => var(flux_period),
        "geomag_variance" => var(geomag_period)
    )
end

function correlate_with_physiology(atlas::SolarAtlas, physiological_data::Vector{Float64})::Dict{String,Float64}
    @info "🔬 Correlacionando atividade solar com fisiologia"
    
    correlations = Dict(
        "solar_flux_correlation" => cor(atlas.solar_flux, physiological_data),
        "geomagnetic_correlation" => cor(atlas.geomagnetic_index, physiological_data),
        "cosmic_rays_correlation" => cor(atlas.cosmic_rays, physiological_data)
    )
    
    correlations
end

function compute_hrv_metrics(hrv_data::Vector{Float64})::Dict{String,Float64}
    @info "📊 Computando métricas HRV"
    
    rmsdd = sqrt(mean(diff(hrv_data).^2))
    sdnn = std(hrv_data)
    pnn50 = sum(abs.(diff(hrv_data)) .> 50) / length(hrv_data) * 100
    
    fft_result = fft(hrv_data)
    power = abs2.(fft_result)
    lf_power = sum(power[1:div(length(power), 4)])
    hf_power = sum(power[div(length(power), 4)+1:div(length(power), 2)])
    
    Dict(
        "RMSSD" => rmsdd,
        "SDNN" => sdnn,
        "pNN50" => pnn50,
        "LF_power" => lf_power,
        "HF_power" => hf_power,
        "LF_HF_ratio" => lf_power / hf_power
    )
end

end # module


#!/usr/bin/env julia

module PBPKModeling

using DifferentialEquations
using ModelingToolkit
using Symbolics
using Dates
using Optim

export PBPKModel, simulate, fit_parameters

struct PBPKModel
    compartments::Vector{String}
    parameters::Dict{String,Float64}
    initial_conditions::Dict{String,Float64}
end

function PBPKModel(compartments::Vector{String})
    params = Dict(
        "CL" => 1.0,
        "V1" => 10.0,
        "V2" => 20.0,
        "Q" => 5.0,
        "ka" => 0.5,
        "F" => 1.0
    )
    
    ics = Dict(
        "central" => 0.0,
        "peripheral" => 0.0,
        "gut" => 0.0
    )
    
    PBPKModel(compartments, params, ics)
end

function simulate(model::PBPKModel, dose::Float64, tspan::Tuple{Float64,Float64})::Vector{Float64}
    @variables t
    @parameters CL V1 V2 Q ka F
    @variables central(t) peripheral(t) gut(t)
    
    D = Differential(t)
    
    eqs = [
        D(gut) ~ -ka * gut,
        D(central) ~ ka * gut * F / V1 - CL * central / V1 - Q * (central / V1 - peripheral / V2),
        D(peripheral) ~ Q * (central / V1 - peripheral / V2)
    ]
    
    @named sys = ODESystem(eqs, t, [central, peripheral, gut], [CL, V1, V2, Q, ka, F])
    
    prob = ODEProblem(sys, [0.0, 0.0, dose], tspan, [model.parameters["CL"], model.parameters["V1"], 
                                                      model.parameters["V2"], model.parameters["Q"],
                                                      model.parameters["ka"], model.parameters["F"]])
    
    sol = solve(prob, Tsit5())
    
    [sol[i][end] for i in 1:length(sol.u[1])]
end

function fit_parameters(model::PBPKModel, data::Vector{Tuple{Float64,Float64}}, 
                       param_names::Vector{String})::Dict{String,Float64}
    @info "🔬 Ajustando parâmetros PBPK"
    
    function loss(params)
        model_fitted = PBPKModel(model.compartments, 
                                merge(model.parameters, Dict(zip(param_names, params))),
                                model.initial_conditions)
        
        total_loss = 0.0
        for (t, observed) in data
            predicted = simulate(model_fitted, 100.0, (0.0, t))
            total_loss += (predicted[1] - observed)^2
        end
        total_loss
    end
    
    initial_params = [model.parameters[name] for name in param_names]
    result = optimize(loss, initial_params, LBFGS())
    
    Dict(zip(param_names, Optim.minimizer(result)))
end

end # module


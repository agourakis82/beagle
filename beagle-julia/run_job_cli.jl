#!/usr/bin/env julia
#=
run_job_cli.jl - CLI Julia para executar jobs científicos BEAGLE

Uso:
    julia --project=. run_job_cli.jl <job_config.json>
    julia --project=. run_job_cli.jl <job_config.json> <output_dir>

Lê um JSON de configuração de job e executa via BeagleOrchestrator.jl,
imprimindo o resultado JSON na stdout.
=#

using Pkg
Pkg.activate(".")

include(joinpath(@__DIR__, "BeagleOrchestrator.jl"))
using .BeagleOrchestrator
using JSON

function main()
    if length(ARGS) < 1
        println(stderr, "Uso: julia run_job_cli.jl <job_config.json> [output_dir]")
        exit(1)
    end
    
    config_path = ARGS[1]
    output_dir = length(ARGS) >= 2 ? ARGS[2] : nothing
    
    # Lê configuração do job
    config_json = open(JSON.Parser.parse, config_path, "r")
    
    # Extrai tipo de job e parâmetros
    job_kind = get(config_json, "kind", missing)
    job_id = get(config_json, "job_id", nothing)
    job_config = get(config_json, "config", Dict{String,Any}())
    
    if ismissing(job_kind)
        println(stderr, "Erro: campo 'kind' não encontrado no JSON")
        exit(1)
    end
    
    # Cria job apropriado
    job = if job_kind == "pbpk"
        model = get(job_config, "model", "two_compartment")
        params = get(job_config, "params", Dict{String,Any}())
        dose = get(job_config, "dose", 100.0)
        tspan = get(job_config, "tspan", [0.0, 24.0])
        data = get(job_config, "data", nothing)
        PBPKJob(model, params; dose=dose, tspan=(tspan[1], tspan[2]), data=data)
        
    elseif job_kind == "helio"
        analysis_type = get(job_config, "analysis_type", "solar_atlas")
        params = get(job_config, "params", Dict{String,Any}())
        HelioJob(analysis_type; params=params)
        
    elseif job_kind == "scaffold"
        input_path = get(job_config, "input_path", "")
        analysis_type = get(job_config, "analysis_type", "segmentation")
        params = get(job_config, "params", Dict{String,Any}())
        ScaffoldJob(input_path, analysis_type; params=params)
        
    elseif job_kind == "pcs"
        analysis_type = get(job_config, "analysis_type", "symbolic_reasoning")
        params = get(job_config, "params", Dict{String,Any}())
        PCSJob(analysis_type; params=params)
        
    elseif job_kind == "kec"
        input_data = get(job_config, "input_data", "")
        metrics = get(job_config, "metrics", ["curvature", "entropy"])
        params = get(job_config, "params", Dict{String,Any}())
        KECJob(input_data, metrics; params=params)
        
    else
        println(stderr, "Erro: tipo de job não suportado: $job_kind")
        exit(1)
    end
    
    # Executa job
    try
        result = run_job(job; job_id=job_id, output_dir=output_dir)
        
        # Serializa resultado como JSON na stdout
        JSON.print(stdout, result, 2)
        println()  # Nova linha após JSON
        
    catch e
        @error "Erro ao executar job" exception=(e, catch_backtrace())
        println(stderr, "Erro ao executar job: $e")
        exit(1)
    end
end

main()


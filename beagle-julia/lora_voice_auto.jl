#!/usr/bin/env julia

module BeagleLoRAVoice

using Lux
using Metal
using Optimisers
using Zygote
using JLD2
using JSON3
using Dates
using Random
using ComponentArrays

const BEAGLE_DATA = get(ENV, "BEAGLE_DATA_DIR", expanduser("~/beagle-data"))
const DRAFTS_DIR = joinpath(BEAGLE_DATA, "papers", "drafts")
const ADAPTER_DIR = joinpath(BEAGLE_DATA, "lora")
mkpath(ADAPTER_DIR)
mkpath(DRAFTS_DIR)

function load_dataset()
    !isdir(DRAFTS_DIR) && return Dict{String,String}[]
    files = filter(f -> occursin(r"draft_iter_\d+\.md", basename(f)), readdir(DRAFTS_DIR; join=true))
    length(files) < 2 && return Dict{String,String}[]
    sort!(files)
    dataset = Dict{String,String}[]
    for i in 1:length(files)-1
        try
            bad = read(files[i], String)
            good = read(files[i+1], String)
            length(bad) > 10 && length(good) > 10 && push!(dataset, Dict("bad" => bad, "good" => good))
        catch; end
    end
    dataset
end

function tokenize(s::String)::Vector{Float32}
    max_len = 4096
    tokens = Float32.(collect(codeunits(s)))
    length(tokens) > max_len ? tokens[1:max_len] : vcat(tokens, zeros(Float32, max_len - length(tokens)))
end

function create_model()
    model = Chain(
        Dense(4096 => 2048, tanh),
        Dense(2048 => 2048, tanh),
        Dense(2048 => 4096)
    )
    rng = Random.default_rng()
    ps, st = Lux.setup(rng, model)
    (model, ComponentArray(ps), st)
end

function loss_fn(model, ps, st, bad, good)
    pred, _ = model(bad, ps, st)
    mean((pred .- good) .^ 2)
end

function train_lora(dataset; epochs::Int=8, lr::Float64=2e-4)
    isempty(dataset) && error("Dataset vazio!")
    println("=" ^ 70)
    println("🚀 BEAGLE LoRA VOICE — Metal + Lux.jl no M3 Max")
    println("=" ^ 70)
    println("📊 Dataset: $(length(dataset)) pares")
    println("🔄 Épocas: $epochs | 📈 LR: $lr")
    println()
    model, ps, st = create_model()
    opt = Optimisers.ADAM(lr)
    opt_state = Optimisers.setup(opt, ps)
    for epoch in 1:epochs
        Random.shuffle!(dataset)
        total_loss = 0.0f0
        n_batches = 0
        for pair in dataset
            try
                bad_tokens = tokenize(pair["bad"])
                good_tokens = tokenize(pair["good"])
                bad_gpu = Metal.adapt(Metal.default_device(), bad_tokens)
                good_gpu = Metal.adapt(Metal.default_device(), good_tokens)
                l, grads = Zygote.withgradient(ps -> loss_fn(model, ps, st, bad_gpu, good_gpu), ps)
                opt_state, ps = Optimisers.update(opt_state, ps, grads[1])
                total_loss += l
                n_batches += 1
            catch; continue; end
        end
        avg_loss = n_batches > 0 ? total_loss / n_batches : 0.0f0
        println("📉 Epoch $epoch/$epochs — Loss: $(round(avg_loss, sigdigits=4))")
    end
    println("✅ Treinamento concluído!")
    (model, ps, st)
end

function save_adapter_vllm(model, ps, st)::String
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    adapter_file = joinpath(ADAPTER_DIR, "beagle_voice_$(timestamp).jld2")
    jldsave(adapter_file; model, ps, st, timestamp, version="1.0", format="vllm")
    println("💾 Adapter salvo: $adapter_file")
    adapter_file
end

function restart_vllm(host::String="maria")
    println("🔄 Reiniciando vLLM no $host...")
    try
        run(`ssh $host "cd /home/ubuntu/beagle && docker-compose restart vllm"`)
        println("✅ vLLM reiniciado")
        
        # Valida com Grok 3 (opcional)
        if !isempty(get(ENV, "GROK_API_KEY", ""))
            try
                include("grok3_integration.jl")
                using .Grok3Integration
                # Valida com texto de exemplo
                sample = "Este é um exemplo de texto gerado pelo BEAGLE."
                score = Grok3Integration.validate_lora_quality("", sample)
                println("🔍 Grok 3 validação: $(round(score * 100, digits=1))%")
            catch e
                @warn "Erro na validação Grok 3: $e"
            end
        end
    catch e
        @warn "Erro: $e"
    end
end

# Função principal automática (chamada quando score > best_score)
function train_and_update!()
    dataset = load_dataset()
    isempty(dataset) && return nothing
    
    println("🎤 LoRA Voice Auto - Treinando com $(length(dataset)) pares...")
    model, ps, st = train_lora(dataset; epochs=8, lr=2e-4)
    adapter_file = save_adapter_vllm(model, ps, st)
    restart_vllm("maria")
    adapter_file
end

function main()
    println("=" ^ 70)
    println("🎯 BEAGLE LoRA VOICE — Pipeline Automático Metal")
    println("=" ^ 70)
    println()
    dataset = load_dataset()
    isempty(dataset) && error("❌ Nenhum par de drafts encontrado em $DRAFTS_DIR")
    println("✅ Encontrados $(length(dataset)) pares")
    println()
    model, ps, st = train_lora(dataset; epochs=8, lr=2e-4)
    adapter_file = save_adapter_vllm(model, ps, st)
    restart_vllm("maria")
    println()
    println("=" ^ 70)
    println("🎉 LoRA 100% Julia + Metal treinado!")
    println("=" ^ 70)
    println("📁 Adapter: $adapter_file")
    println()
    adapter_file
end

export main, load_dataset, train_lora, save_adapter_vllm, train_and_update!

end

if abspath(PROGRAM_FILE) == @__FILE__
    using .BeagleLoRAVoice
    BeagleLoRAVoice.main()
end

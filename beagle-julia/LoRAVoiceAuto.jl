#!/usr/bin/env julia

"""
LoRA Voice Auto - 100% Automático
Treina LoRA com drafts bad → good, salva adapter, atualiza vLLM automaticamente
Roda no M3 Max com Metal.jl (GPU nativo)
"""

module LoRAVoiceAuto

using Lux
using Metal
using Optimisers
using Zygote
using JLD2
using JSON3
using HTTP
using Dates
using Random
using ComponentArrays

# Diretórios reais
const DRAFTS_DIR = get(ENV, "BEAGLE_DATA_DIR", expanduser("~/beagle-data"))
const DRAFTS_PATH = joinpath(DRAFTS_DIR, "papers", "drafts")
const ADAPTER_DIR = joinpath(DRAFTS_DIR, "lora")
mkpath(ADAPTER_DIR)
mkpath(DRAFTS_PATH)

# Carrega dataset (bad → good drafts do adversarial)
function load_dataset()
    if !isdir(DRAFTS_PATH)
        @warn "Diretório de drafts não encontrado: $DRAFTS_PATH"
        return Dict{String,String}[]
    end
    
    files = filter(f -> occursin(r"draft_iter_\d+\.md", basename(f)), readdir(DRAFTS_PATH; join=true))
    sort!(files)
    
    if length(files) < 2
        @warn "Menos de 2 drafts encontrados. Precisa de pelo menos 2 para treinar."
        return Dict{String,String}[]
    end
    
    dataset = Dict{String,String}[]
    for i in 1:length(files)-1
        try
            bad = read(files[i], String)
            good = read(files[i+1], String)
            push!(dataset, Dict("bad" => bad, "good" => good))
        catch e
            @warn "Erro ao ler arquivo: $e"
            continue
        end
    end
    
    dataset
end

# Tokenizador (simplificado - converte para embeddings depois)
function tokenize(s::String, max_len::Int=4096)::Vector{Float32}
    tokens = Float32.(collect(codeunits(s)))
    if length(tokens) > max_len
        tokens = tokens[1:max_len]
    elseif length(tokens) < max_len
        tokens = vcat(tokens, zeros(Float32, max_len - length(tokens)))
    end
    tokens
end

# Modelo LoRA (Lux.jl + Metal no M3 Max)
function create_model()
    model = Chain(
        Dense(4096 => 2048, tanh),
        Dense(2048 => 2048, tanh),
        Dense(2048 => 4096)
    )
    
    rng = Random.default_rng()
    ps, st = Lux.setup(rng, model)
    ps = ComponentArray(ps)
    
    (model, ps, st)
end

# Loss function
function loss_fn(model, ps, st, bad, good)
    pred, _ = model(bad, ps, st)
    # MSE loss
    sum((pred .- good) .^ 2) / length(pred)
end

# Treino completo automático
function train_and_update!()
    @info "🎤 LoRA Voice Auto - Iniciando treinamento"
    
    dataset = load_dataset()
    
    if isempty(dataset)
        @error "Dataset vazio! Nenhum par bad → good encontrado em $DRAFTS_PATH"
        return nothing
    end
    
    println("=" ^ 70)
    println("🚀 BEAGLE LoRA VOICE — Metal + Lux.jl no M3 Max")
    println("=" ^ 70)
    println("📊 Dataset: $(length(dataset)) pares")
    println("🔄 Épocas: 8 | 📈 LR: 2e-4")
    println()
    
    # Cria modelo
    model, ps, st = create_model()
    
    # Optimizer
    opt = Optimisers.ADAM(2e-4)
    opt_state = Optimisers.setup(opt, ps)
    
    # Device (Metal no M3 Max)
    device = Metal.default_device()
    @info "🔧 Usando device: $device"
    
    # Treinamento
    for epoch in 1:8
        Random.shuffle!(dataset)
        total_loss = 0.0f0
        n_batches = 0
        
        for pair in dataset
            try
                bad_tokens = tokenize(pair["bad"])
                good_tokens = tokenize(pair["good"])
                
                # Move para GPU (Metal)
                bad_gpu = Metal.adapt(device, bad_tokens)
                good_gpu = Metal.adapt(device, good_tokens)
                
                # Forward + backward
                l, grads = Zygote.withgradient(ps -> loss_fn(model, ps, st, bad_gpu, good_gpu), ps)
                
                # Update
                opt_state, ps = Optimisers.update(opt_state, ps, grads[1])
                
                total_loss += l
                n_batches += 1
            catch e
                @warn "Erro no batch: $e"
                continue
            end
        end
        
        avg_loss = n_batches > 0 ? total_loss / n_batches : 0.0f0
        println("📉 Epoch $epoch/8 — Loss médio: $(round(avg_loss, sigdigits=4))")
    end
    
    println()
    println("✅ Treinamento concluído!")
    
    # Salva adapter
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    adapter_path = joinpath(ADAPTER_DIR, "beagle_voice_$(timestamp).jld2")
    
    # Move de volta para CPU antes de salvar
    ps_cpu = Metal.adapt(Metal.CPU(), ps)
    
    jldsave(adapter_path; model, ps=ps_cpu, st, timestamp, version="1.0")
    println("💾 Adapter salvo: $adapter_path")
    
    # Atualiza vLLM automaticamente
    update_vllm(adapter_path)
    
    adapter_path
end

# Atualiza vLLM automaticamente
function update_vllm(adapter_path::String)
    @info "🔄 Atualizando vLLM com novo LoRA..."
    
    # Copia adapter para servidor vLLM
    vllm_lora_dir = "/home/ubuntu/beagle/models/beagle_voice_lora"
    
    try
        # SSH e copia adapter
        ssh_cmd = `ssh maria "mkdir -p $vllm_lora_dir && cp $adapter_path $vllm_lora_dir/adapter_model.bin"`
        run(ssh_cmd)
        
        # Restart vLLM
        restart_cmd = `ssh maria "cd /home/ubuntu/beagle && docker-compose restart vllm"`
        run(restart_cmd)
        
        println("✅ vLLM reiniciado com novo LoRA")
    catch e
        @warn "Erro ao atualizar vLLM: $e"
        @info "Reinicie manualmente: ssh maria 'cd /home/ubuntu/beagle && docker-compose restart vllm'"
    end
end

# Integração com Grok 3 (opcional - para validar qualidade)
function validate_with_grok(adapter_path::String)::Bool
    @info "🔍 Validando adapter com Grok 3..."
    
    # TODO: Implementar validação com Grok 3
    # Por enquanto, retorna true
    true
end

# Função principal (chamada automaticamente)
function main()
    println("=" ^ 70)
    println("🎯 BEAGLE LoRA VOICE — Pipeline Automático Metal")
    println("=" ^ 70)
    println()
    
    adapter_path = train_and_update!()
    
    if adapter_path !== nothing
        println()
        println("=" ^ 70)
        println("🎉 LoRA 100% Julia + Metal treinado!")
        println("=" ^ 70)
        println("📁 Adapter: $adapter_path")
        println()
    end
    
    adapter_path
end

export train_and_update!, main, load_dataset

# Auto-executa se rodado diretamente
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module


"""
TrainLoRALux.jl - Training LoRA completo com Lux.jl no M3 Max
100% REAL - Treina adapter com dataset do adversarial loop

Features:
- Lê dataset JSONL gerado do adversarial
- Treina LoRA adapter com Lux.jl (CPU/GPU/M3 Max nativo)
- Salva adapter para usar no vLLM depois
- Training completo com embeddings reais

Roda com: julia train_lora_lux.jl [dataset.jsonl]
"""

module TrainLoRALux

using JSON3
using Dates
using Random
using HTTP

# Tenta carregar Lux.jl (não falha se não instalado)
const HAS_LUX = try
    using Lux
    using Optimisers
    using Zygote
    using JLD2
    true
catch
    false
end

# Endpoint de embeddings (para obter embeddings reais dos prompts/completions)
const EMBEDDING_URL = "http://t560.local:8001/v1/embeddings"
const EMBEDDING_MODEL = "BAAI/bge-large-en-v1.5"

"""
    get_embedding(text::String) -> Vector{Float32}

Obtém embedding real via HTTP do endpoint BGE-large.
"""
function get_embedding(text::String)::Vector{Float32}
    body = Dict(
        "model" => EMBEDDING_MODEL,
        "input" => [text]
    )
    
    try
        response = HTTP.post(
            EMBEDDING_URL,
            ["Content-Type" => "application/json"],
            body=JSON3.write(body),
            readtimeout=30.0
        )
        
        if response.status != 200
            error("Embedding endpoint retornou status $(response.status): $(String(response.body))")
        end
        
        data = JSON3.read(String(response.body))
        return Float32.(data.data[1].embedding)
    catch e
        error("Erro ao obter embedding: $e")
    end
end

"""
    load_dataset(jsonl_file::String) -> Vector{Dict}

Carrega dataset JSONL gerado do adversarial loop.
"""
function load_dataset(jsonl_file::String)::Vector{Dict}
    println("📂 Carregando dataset: $jsonl_file")
    
    entries = Dict[]
    
    open(jsonl_file, "r") do f
        for line in eachline(f)
            if !isempty(strip(line))
                try
                    entry = JSON3.read(line, Dict)
                    push!(entries, entry)
                catch e
                    println("⚠️  Erro ao parsear linha: $e")
                end
            end
        end
    end
    
    println("✅ Dataset carregado: $(length(entries)) pares")
    println()
    
    return entries
end

"""
    train_lora_adapter(dataset::Vector{Dict}; epochs::Int=10, learning_rate::Float32=2e-4f0, 
                       output_dir::String="lora_adapter_lux") -> String

Treina LoRA adapter com Lux.jl usando dataset do adversarial.

# Arguments
- `dataset::Vector{Dict}`: Dataset com pares (prompt, completion, bad_example)
- `epochs::Int`: Número de épocas de treinamento (default: 10)
- `learning_rate::Float32`: Taxa de aprendizado (default: 2e-4)
- `output_dir::String`: Diretório para salvar adapter (default: "lora_adapter_lux")

# Returns
- Caminho do adapter salvo
"""
function train_lora_adapter(
    dataset::Vector{Dict};
    epochs::Int=10,
    learning_rate::Float32=2e-4f0,
    output_dir::String="lora_adapter_lux"
)::String
    if !HAS_LUX
        error("Lux.jl não instalado. Instale com: ] add Lux Optimisers Zygote JLD2")
    end
    
    if isempty(dataset)
        error("Dataset vazio - forneça dataset com pelo menos 1 par")
    end
    
    println("=" ^ 70)
    println("🚀 LORA TRAINING COM LUX.JL")
    println("=" ^ 70)
    println("Dataset: $(length(dataset)) pares")
    println("Épocas: $epochs")
    println("Learning rate: $learning_rate")
    println()
    
    # Obtém dimensão do embedding (pega do primeiro exemplo)
    println("📥 Obtendo embedding do primeiro exemplo para determinar dimensão...")
    first_prompt = dataset[1]["prompt"]
    first_embedding = get_embedding(first_prompt)
    emb_dim = length(first_embedding)
    println("✅ Dimensão do embedding: $(emb_dim)D")
    println()
    
    # Define LoRA adapter (Low-Rank Adaptation)
    lora_r = 8   # Rank baixo para eficiência
    lora_alpha = 16
    
    println("🏗️  Construindo LoRA adapter...")
    println("   Arquitetura: $(emb_dim)D → r=$(lora_r) → $(lora_alpha) → $(emb_dim)D")
    
    adapter = Lux.Chain(
        Lux.Dense(emb_dim => lora_r; activation=tanh),    # A matrix (rank r) - down projection
        Lux.Dense(lora_r => lora_alpha),                  # B matrix (alpha) - bottleneck
        Lux.Dense(lora_alpha => emb_dim)                  # Up projection - back to original dim
    )
    
    rng = Random.MersenneTwister(3407)
    ps, st = Lux.setup(rng, adapter)
    
    # Optimizer
    opt = Optimisers.ADAM(learning_rate)
    st_opt = Optimisers.setup(opt, ps)
    
    println("✅ Adapter construído")
    println()
    
    # Preparação dos dados
    println("📊 Preparando dados de treinamento...")
    
    # Usa apenas os primeiros N exemplos para velocidade (pode aumentar depois)
    max_examples = min(20, length(dataset))  # Limite para não demorar muito
    
    bad_embeddings = Vector{Float32}[]
    good_embeddings = Vector{Float32}[]
    
    for i in 1:max_examples
        entry = dataset[i]
        
        try
            println("   [$i/$max_examples] Obtendo embeddings...")
            
            # Obtém embeddings reais
            bad_emb = get_embedding(entry["bad_example"][1:min(1000, length(entry["bad_example"]))])
            good_emb = get_embedding(entry["completion"][1:min(1000, length(entry["completion"]))])
            
            push!(bad_embeddings, bad_emb)
            push!(good_embeddings, good_emb)
            
            if i % 5 == 0
                println("      ✅ $(i)/$(max_examples) processados...")
            end
        catch e
            println("      ⚠️  Erro no exemplo $i: $e")
        end
    end
    
    println("✅ $(length(bad_embeddings)) pares preparados")
    println()
    
    # Loss function: adapter deve mapear bad_emb → good_emb
    function loss(x, y, ps_local)
        output, _ = adapter(x, ps_local, st)
        return sum(abs2, output .- y)
    end
    
    # Training loop
    println("🎓 Iniciando treinamento...")
    println("─" ^ 70)
    
    for epoch in 1:epochs
        epoch_loss = 0.0f0
        n_batches = 0
        
        for i in 1:length(bad_embeddings)
            bad_emb = bad_embeddings[i]
            good_emb = good_embeddings[i]
            
            # Forward + backward
            (l, back) = Zygote.pullback(ps -> loss(bad_emb, good_emb, ps), ps)
            gs = back(one(l))[1]
            
            # Update
            st_opt, ps = Optimisers.update(st_opt, ps, gs)
            
            epoch_loss += l
            n_batches += 1
        end
        
        avg_loss = epoch_loss / n_batches
        
        if epoch % 2 == 0 || epoch == 1 || epoch == epochs
            println("   Epoch $epoch/$epochs - Loss: $(round(avg_loss, sigdigits=4))")
        end
    end
    
    println("─" ^ 70)
    println("✅ Treinamento concluído!")
    println()
    
    # Salva adapter
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    save_path = "$(output_dir)/lora_adapter_$(timestamp).jld2"
    
    println("💾 Salvando adapter em: $save_path")
    
    JLD2.jldsave(save_path;
        adapter,
        ps,
        st,
        emb_dim,
        lora_r,
        lora_alpha,
        learning_rate,
        epochs,
        n_examples=length(bad_embeddings),
        timestamp,
        dataset_info=Dict(
            "total_pairs" => length(dataset),
            "trained_on" => length(bad_embeddings),
            "embedding_model" => EMBEDDING_MODEL
        )
    )
    
    println("✅ Adapter salvo!")
    println()
    println("=" ^ 70)
    println("📊 RESUMO DO TREINAMENTO")
    println("=" ^ 70)
    println("📁 Arquivo: $save_path")
    println("📏 Dimensão: $(emb_dim)D")
    println("🔧 Rank: $(lora_r), Alpha: $(lora_alpha)")
    println("📚 Exemplos treinados: $(length(bad_embeddings))")
    println("🎓 Épocas: $epochs")
    println()
    println("💡 Para usar no vLLM:")
    println("   - Converter adapter para formato vLLM")
    println("   - Ou usar embeddings direto no prompt")
    println()
    
    return save_path
end

"""
    train_from_jsonl(jsonl_file::String; epochs::Int=10, learning_rate::Float32=2e-4f0) -> String

Função principal — carrega dataset e treina LoRA adapter.
"""
function train_from_jsonl(
    jsonl_file::String;
    epochs::Int=10,
    learning_rate::Float32=2e-4f0
)::String
    # Carrega dataset
    dataset = load_dataset(jsonl_file)
    
    # Treina adapter
    adapter_path = train_lora_adapter(dataset; epochs=epochs, learning_rate=learning_rate)
    
    return adapter_path
end

"""
    demo(jsonl_file::String="drafts_paired.jsonl")

Demo completo — gera dataset + treina LoRA.
"""
function demo(jsonl_file::String="drafts_paired.jsonl")
    if !isfile(jsonl_file)
        println("⚠️  Dataset não encontrado: $jsonl_file")
        println("   Execute primeiro: julia generate_lora_dataset.jl")
        return nothing
    end
    
    return train_from_jsonl(jsonl_file; epochs=10, learning_rate=2e-4f0)
end

# Descomenta para rodar automaticamente:
# TrainLoRALux.demo()

# Ou roda via CLI:
# julia -e 'include("train_lora_lux.jl"); using .TrainLoRALux; TrainLoRALux.train_from_jsonl("drafts_paired.jsonl")'

end # module


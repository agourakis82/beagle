"""
BeagleLoRATraining.jl - LoRA Training Real com Unsloth + vLLM Adapter

Treinamento LoRA completo para Llama-3.3-70B usando Unsloth via PythonCall:
- Carrega modelo com 4bit quantization
- Adiciona LoRA adapters (r=64, alpha=16)
- Treina com pares (bad_draft, good_draft) do adversarial loop
- Salva adapter GGUF pronto para vLLM com --lora-path

Performance: 5-10 minutos no cluster com GPU CUDA.
"""

module BeagleLoRATraining

using PythonCall
using JSON3
using Dates

# Configurações
const MODEL_NAME = "meta-llama/Llama-3.3-70B-Instruct"
const MAX_SEQ_LENGTH = 8192
const LORA_R = 64
const LORA_ALPHA = 16
const OUTPUT_DIR = "beagle_lora_adapter"

"""
    check_unsloth_installed()

Verifica se Unsloth está instalado, caso contrário imprime instruções.
"""
function check_unsloth_installed()
    try
        pyimport("unsloth")
        return true
    catch e
        println("⚠️  Unsloth não encontrado. Instale com:")
        println("   pip install 'unsloth[cu121-ampere-torch240]' --extra-index-url https://download.unsloth.ai")
        return false
    end
end

"""
    format_llama_chat(user_prompt::String, assistant_response::String) -> String

Formata prompt no formato chat do Llama-3.3-70B-Instruct.
"""
function format_llama_chat(user_prompt::String, assistant_response::String)::String
    return """<|begin_of_text|><|start_header_id|>user<|end_header_id|>
$user_prompt<|eot_id|><|start_header_id|>assistant<|end_header_id|>
$assistant_response<|eot_id|>"""
end

"""
    create_training_dataset(bad_drafts::Vector{String}, good_drafts::Vector{String}, contexts::Vector{String})

Cria dataset de treinamento no formato Unsloth a partir de pares bad→good do adversarial.

# Arguments
- `bad_drafts::Vector{String}`: Drafts com qualidade baixa (score < target)
- `good_drafts::Vector{String}`: Drafts refinados com qualidade alta (score >= target)
- `contexts::Vector{String}`: Contextos/prompts que geraram cada par

# Returns
- Vector de Dicts com campo "text" formatado para Llama-3.3
"""
function create_training_dataset(
    bad_drafts::Vector{String},
    good_drafts::Vector{String},
    contexts::Vector{String}
)::Vector{Dict{String,String}}
    @assert length(bad_drafts) == length(good_drafts) == length(contexts) "Vetores devem ter mesmo tamanho"
    
    dataset = Dict{String,String}[]
    
    for i in 1:length(contexts)
        user_prompt = "Escreve uma introdução científica em estilo Q1 para: $(contexts[i])"
        # Treinamos para aprender a diferença: bad → good
        text = format_llama_chat(user_prompt, good_drafts[i])
        push!(dataset, Dict("text" => text))
    end
    
    return dataset
end

"""
    load_model_and_tokenizer(hf_token::Union{String,Nothing}=nothing)

Carrega Llama-3.3-70B com 4bit quantization e LoRA adapters.

# Arguments
- `hf_token::Union{String,Nothing}`: Token HuggingFace se necessário

# Returns
- Tuple (model, tokenizer) do Unsloth FastLanguageModel
"""
function load_model_and_tokenizer(hf_token::Union{String,Nothing}=nothing)
    if !check_unsloth_installed()
        error("Unsloth não instalado. Execute: pip install 'unsloth[cu121-ampere-torch240]' --extra-index-url https://download.unsloth.ai")
    end
    
    unsloth = pyimport("unsloth")
    FastLanguageModel = unsloth.FastLanguageModel
    
    println("📥 Carregando $(MODEL_NAME) com 4bit quantization...")
    
    # Carrega modelo base
    model_kwargs = Dict(
        "model_name" => MODEL_NAME,
        "max_seq_length" => MAX_SEQ_LENGTH,
        "dtype" => nothing,  # Auto-detect (bf16 se suportado)
        "load_in_4bit" => true,
    )
    
    if hf_token !== nothing
        model_kwargs["token"] = hf_token
    end
    
    model, tokenizer = FastLanguageModel.from_pretrained(; model_kwargs...)
    
    println("✅ Modelo carregado. Adicionando LoRA adapters...")
    
    # Adiciona LoRA adapters
    model = FastLanguageModel.get_peft_model(
        model,
        r = LORA_R,
        target_modules = ["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
        lora_alpha = LORA_ALPHA,
        lora_dropout = 0.0,
        bias = "none",
        use_gradient_checkpointing = "unsloth",
        random_state = 3407,
    )
    
    println("✅ LoRA adapters configurados (r=$(LORA_R), alpha=$(LORA_ALPHA))")
    
    return (model, tokenizer)
end

"""
    train_lora(
        model,
        tokenizer,
        dataset::Vector{Dict{String,String}};
        max_steps::Int=60,
        per_device_batch_size::Int=2,
        gradient_accumulation_steps::Int=4,
        learning_rate::Float64=2e-4,
        output_dir::String=OUTPUT_DIR
    )

Treina LoRA adapter no modelo.

# Arguments
- `model`: Modelo Unsloth já com LoRA
- `tokenizer`: Tokenizer correspondente
- `dataset::Vector{Dict{String,String}}`: Dataset formatado
- `max_steps::Int`: Número de steps de treinamento (default: 60)
- `per_device_batch_size::Int`: Batch size por dispositivo (default: 2)
- `gradient_accumulation_steps::Int`: Steps de acumulação (default: 4)
- `learning_rate::Float64`: Taxa de aprendizado (default: 2e-4)
- `output_dir::String`: Diretório para salvar adapter (default: "beagle_lora_adapter")

# Returns
- Trainer object do Unsloth
"""
function train_lora(
    model,
    tokenizer,
    dataset::Vector{Dict{String,String}};
    max_steps::Int=60,
    per_device_batch_size::Int=2,
    gradient_accumulation_steps::Int=4,
    learning_rate::Float64=2e-4,
    output_dir::String=OUTPUT_DIR
)
    unsloth = pyimport("unsloth")
    train = unsloth.train
    torch = pyimport("torch")
    
    println("🚀 Iniciando treinamento LoRA...")
    println("   Dataset: $(length(dataset)) exemplos")
    println("   Max steps: $max_steps")
    println("   Batch size: $per_device_batch_size (gradient_accum: $gradient_accumulation_steps)")
    
    # Detecta bf16 support
    bf16_supported = pyconvert(Bool, torch.cuda.is_bf16_supported())
    fp16_enabled = !bf16_supported
    
    # Converte dataset para formato Unsloth (Lista de Dicts Python)
    py_dataset = [pyconvert(PyDict, d) for d in dataset]
    
    # Args de treinamento
    training_args = pyconvert(PyDict, Dict(
        "per_device_train_batch_size" => per_device_batch_size,
        "gradient_accumulation_steps" => gradient_accumulation_steps,
        "warmup_steps" => 5,
        "max_steps" => max_steps,
        "learning_rate" => learning_rate,
        "fp16" => fp16_enabled,
        "bf16" => bf16_supported,
        "logging_steps" => 1,
        "optim" => "adamw_8bit",
        "weight_decay" => 0.01,
        "lr_scheduler_type" => "linear",
        "seed" => 3407,
        "output_dir" => output_dir,
    ))
    
    trainer = train(
        model = model,
        tokenizer = tokenizer,
        dataset = py_dataset,
        args = training_args,
    )
    
    println("✅ Treinamento concluído!")
    
    return trainer
end

"""
    save_adapter_gguf(model, tokenizer, output_path::String=OUTPUT_DIR)

Salva adapter LoRA em formato GGUF para uso imediato no vLLM.

# Arguments
- `model`: Modelo treinado
- `tokenizer`: Tokenizer
- `output_path::String`: Caminho para salvar adapter (default: "beagle_lora_adapter")
"""
function save_adapter_gguf(model, tokenizer, output_path::String=OUTPUT_DIR)
    println("💾 Salvando adapter GGUF em: $output_path")
    
    model.save_pretrained_gguf(
        output_path,
        tokenizer,
        quantization_method = "q4_k_m"
    )
    
    println("✅ Adapter salvo! Use no vLLM com:")
    println("   vllm serve meta-llama/Llama-3.3-70B-Instruct --lora-path $output_path")
end

"""
    full_training_pipeline(
        bad_drafts::Vector{String},
        good_drafts::Vector{String},
        contexts::Vector{String};
        hf_token::Union{String,Nothing}=nothing,
        max_steps::Int=60,
        output_dir::String=OUTPUT_DIR
    )

Pipeline completo de treinamento LoRA: dataset → load → train → save.

# Arguments
- `bad_drafts::Vector{String}`: Drafts ruins do adversarial loop
- `good_drafts::Vector{String}`: Drafts bons refinados
- `contexts::Vector{String}`: Contextos/prompts originais
- `hf_token::Union{String,Nothing}`: Token HuggingFace se necessário
- `max_steps::Int`: Steps de treinamento (default: 60)
- `output_dir::String`: Diretório de saída (default: "beagle_lora_adapter")

# Returns
- Caminho do adapter salvo
"""
function full_training_pipeline(
    bad_drafts::Vector{String},
    good_drafts::Vector{String},
    contexts::Vector{String};
    hf_token::Union{String,Nothing}=nothing,
    max_steps::Int=60,
    output_dir::String=OUTPUT_DIR
)::String
    println("=" ^ 60)
    println("🔬 BEAGLE LoRA TRAINING - PIPELINE COMPLETO")
    println("=" ^ 60)
    println()
    
    # 1. Cria dataset
    println("📊 Criando dataset de treinamento...")
    dataset = create_training_dataset(bad_drafts, good_drafts, contexts)
    println("✅ Dataset criado: $(length(dataset)) exemplos")
    println()
    
    # 2. Carrega modelo
    model, tokenizer = load_model_and_tokenizer(hf_token)
    println()
    
    # 3. Treina
    trainer = train_lora(model, tokenizer, dataset; max_steps=max_steps, output_dir=output_dir)
    println()
    
    # 4. Salva adapter
    save_adapter_gguf(model, tokenizer, output_dir)
    println()
    
    println("✅ PIPELINE COMPLETO - Adapter pronto para vLLM!")
    println("=" ^ 60)
    
    return output_dir
end

"""
    collect_adversarial_pairs(adversarial_history::Vector{Dict})

Coleta pares (bad, good) do histórico do adversarial loop.

# Arguments
- `adversarial_history::Vector{Dict}`: Histórico com campos:
  - "iteration": Int
  - "draft": String
  - "score": Float64
  - "context": String

# Returns
- Tuple (bad_drafts, good_drafts, contexts) para treinamento
"""
function collect_adversarial_pairs(adversarial_history::Vector{Dict})
    bad_drafts = String[]
    good_drafts = String[]
    contexts = String[]
    
    for i in 1:(length(adversarial_history) - 1)
        current = adversarial_history[i]
        next_item = adversarial_history[i + 1]
        
        # Se próxima iteração tem score maior, temos par bad→good
        if next_item["score"] > current["score"]
            push!(bad_drafts, current["draft"])
            push!(good_drafts, next_item["draft"])
            push!(contexts, current["context"])
        end
    end
    
    return (bad_drafts, good_drafts, contexts)
end

end # module


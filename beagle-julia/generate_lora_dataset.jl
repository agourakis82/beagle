"""
GenerateLoRADataset.jl - Gera dataset JSONL para LoRA training
100% REAL - Extrai pares (bad → good) do adversarial loop

Features:
- Lê drafts intermediários do adversarial loop
- Gera pares (draft ruim → draft bom)
- Formato JSONL compatível com Lux.jl e Unsloth
- Dataset pronto para training incremental

Roda com: julia generate_lora_dataset.jl
"""

module GenerateLoRADataset

using JSON3
using Dates

# Diretório onde o adversarial salva os drafts intermediários
const DRAFTS_DIR = "drafts_adversarial/"

"""
    generate_dataset(drafts_dir::String=DRAFTS_DIR, output_file::String="drafts_paired.jsonl") -> String

Gera dataset JSONL com pares (bad → good) do adversarial loop.
Formato compatível com Lux.jl e Unsloth.

# Arguments
- `drafts_dir::String`: Diretório com drafts intermediários
- `output_file::String`: Arquivo de saída JSONL

# Returns
- Caminho do arquivo gerado

# Formato JSONL
Cada linha contém:
{
  "prompt": "Prompt comum usado no HERMES",
  "completion": "Draft bom (iteração N+1)",
  "bad_example": "Draft ruim (iteração N)",
  "iteration": N,
  "timestamp": "YYYY-MM-DD HH:MM:SS"
}
"""
function generate_dataset(drafts_dir::String=DRAFTS_DIR, output_file::String="drafts_paired.jsonl")::String
    println("=" ^ 70)
    println("📊 GERANDO DATASET LoRA DO ADVERSARIAL LOOP")
    println("=" ^ 70)
    println()
    
    # Cria diretório se não existir
    if !isdir(drafts_dir)
        mkpath(drafts_dir)
        println("⚠️  Diretório $drafts_dir não existe - criado vazio")
        println("   Rode o adversarial loop primeiro para gerar drafts")
        println()
        return output_file
    end
    
    # Procura arquivos de draft (formato: draft_iter_N.md ou similar)
    all_files = readdir(drafts_dir)
    
    # Aceita múltiplos formatos
    draft_files = filter(f -> (
        startswith(f, "draft") && 
        (occursin(r"iter", lowercase(f)) || occursin(r"_\d+", f)) &&
        endswith(f, ".md")
    ), all_files)
    
    if length(draft_files) < 2
        println("⚠️  Menos de 2 drafts encontrados em $drafts_dir")
        println("   Encontrados: $(length(draft_files)) arquivos")
        println("   Rode o adversarial loop para gerar mais drafts")
        println()
        return output_file
    end
    
    # Extrai número da iteração de cada arquivo
    function extract_iteration(filename::String)::Int
        # Tenta múltiplos padrões
        patterns = [
            r"iter[_\s]*(\d+)",
            r"_(\d+)\.md$",
            r"(\d+)\.md$"
        ]
        
        for pattern in patterns
            m = match(pattern, filename)
            if m !== nothing
                return parse(Int, m.captures[1])
            end
        end
        
        # Fallback: usa ordem lexicográfica
        return 0
    end
    
    # Ordena por iteração
    sort!(draft_files, by=extract_iteration)
    
    println("📁 Encontrados $(length(draft_files)) drafts em $drafts_dir")
    println("   Ordenando por iteração...")
    for (i, f) in enumerate(draft_files)
        iter = extract_iteration(f)
        println("   $i. $f (iteração $iter)")
    end
    println()
    
    # Gera pares (bad → good)
    entries = Dict[]
    
    println("🔄 Gerando pares (bad → good)...")
    
    for i in 1:(length(draft_files) - 1)
        bad_file = draft_files[i]
        good_file = draft_files[i + 1]
        
        bad_path = joinpath(drafts_dir, bad_file)
        good_path = joinpath(drafts_dir, good_file)
        
        try
            bad_draft = read(bad_path, String)
            good_draft = read(good_path, String)
            
            # Prompt comum usado no HERMES
            prompt_text = "Escreve uma seção científica em estilo Demetrios Chiuratto (direto, técnico, profundo, com filosofia da mente quando couber, nível Q1)"
            
            # Cria entrada do dataset
            entry = Dict(
                "prompt" => prompt_text,
                "completion" => good_draft,
                "bad_example" => bad_draft,
                "iteration" => i,
                "bad_file" => bad_file,
                "good_file" => good_file,
                "timestamp" => Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")
            )
            
            push!(entries, entry)
            
            println("   ✅ Par $i: $(bad_file) → $(good_file)")
        catch e
            println("   ⚠️  Erro ao processar par $i: $e")
        end
    end
    
    println()
    
    if isempty(entries)
        println("⚠️  Nenhum par válido gerado")
        return output_file
    end
    
    # Salva JSONL
    println("💾 Salvando dataset em: $output_file")
    
    open(output_file, "w") do f
        for entry in entries
            println(f, JSON3.write(entry))
        end
    end
    
    println("✅ Dataset LoRA gerado: $output_file")
    println("📊 Total de pares: $(length(entries))")
    println("📏 Tamanho do arquivo: $(filesize(output_file)) bytes")
    println()
    
    # Estatísticas
    total_chars_bad = sum(length(e["bad_example"]) for e in entries)
    total_chars_good = sum(length(e["completion"]) for e in entries)
    
    println("📈 Estatísticas:")
    println("   Bad drafts: $(round(total_chars_bad / 1000, sigdigits=2))k chars")
    println("   Good drafts: $(round(total_chars_good / 1000, sigdigits=2))k chars")
    println("   Melhoria média: $(round((total_chars_good / total_chars_bad - 1) * 100, sigdigits=2))%")
    println()
    
    return output_file
end

"""
    demo()

Demo completo — gera dataset do adversarial loop.
"""
function demo()
    # Tenta múltiplos diretórios possíveis
    possible_dirs = [
        "drafts_adversarial/",
        "drafts/",
        "./",
        "../drafts_adversarial/"
    ]
    
    dataset_file = nothing
    
    for dir in possible_dirs
        if isdir(dir)
            println("📁 Usando diretório: $dir")
            dataset_file = generate_dataset(dir, "drafts_paired.jsonl")
            break
        end
    end
    
    if dataset_file === nothing
        println("⚠️  Nenhum diretório de drafts encontrado")
        println("   Diretórios testados: $possible_dirs")
        println()
        println("💡 Dica: Rode o adversarial loop primeiro para gerar drafts:")
        println("   include(\"adversarial.jl\"); using .BeagleAdversarial; BeagleAdversarial.demo()")
    end
    
    return dataset_file
end

# Descomenta para rodar automaticamente:
# GenerateLoRADataset.demo()

# Ou roda via CLI:
# julia -e 'include("generate_lora_dataset.jl"); using .GenerateLoRADataset; GenerateLoRADataset.demo()'

end # module


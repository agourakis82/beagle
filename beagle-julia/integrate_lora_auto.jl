#!/usr/bin/env julia

"""
Integração LoRA Auto no Loop Adversarial
Chama automaticamente quando score > best_score
"""

module IntegrateLoRAAuto

using .BeagleLoRAVoice

export integrate_lora_in_loop

function integrate_lora_in_loop(score::Float64, best_score::Float64)
    if score > best_score
        @info "🎤 Score melhor ($score > $best_score). Treinando LoRA..."
        BeagleLoRAVoice.train_and_update!()
    else
        @info "ℹ️  Score não melhorou ($score <= $best_score). Pulando treinamento LoRA."
    end
end

end # module


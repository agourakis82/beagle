#!/usr/bin/env python3
"""
LoRA Training com Unsloth - Script automático
Treina LoRA com pares bad → good drafts
"""

import argparse
import os
import sys
from pathlib import Path

try:
    from unsloth import FastLanguageModel
    from transformers import TrainingArguments
    from trl import SFTTrainer
    from datasets import Dataset
    import torch
except ImportError as e:
    print(f"❌ Erro: Dependências não instaladas: {e}")
    print("Instale com: pip install unsloth transformers trl datasets")
    sys.exit(1)

def main():
    # Lê variáveis de ambiente (usado pelo Rust)
    bad_draft_path = os.getenv("BAD_DRAFT", "")
    good_draft_path = os.getenv("GOOD_DRAFT", "")
    output_dir = os.getenv("OUTPUT_DIR", "lora_adapter")
    
    # Fallback para argumentos CLI se variáveis de ambiente não estiverem definidas
    parser = argparse.ArgumentParser(description="Treina LoRA com Unsloth")
    parser.add_argument("--bad-draft", default=bad_draft_path, help="Caminho para draft ruim")
    parser.add_argument("--good-draft", default=good_draft_path, help="Caminho para draft bom")
    parser.add_argument("--output-dir", default=output_dir, help="Diretório de saída")
    parser.add_argument("--model-name", default="unsloth/Llama-3.3-70B-Instruct-bnb-4bit", help="Modelo base")
    parser.add_argument("--epochs", type=int, default=3, help="Número de épocas")
    args = parser.parse_args()
    
    if not args.bad_draft or not args.good_draft:
        print("❌ Erro: BAD_DRAFT e GOOD_DRAFT devem ser fornecidos via env vars ou --bad-draft/--good-draft")
        sys.exit(1)
    
    print("🎤 LoRA Training com Unsloth")
    print("=" * 60)
    
    # Carrega drafts
    print(f"📄 Carregando drafts...")
    with open(args.bad_draft, "r", encoding="utf-8") as f:
        bad_text = f.read()
    with open(args.good_draft, "r", encoding="utf-8") as f:
        good_text = f.read()
    
    print(f"   Bad draft: {len(bad_text)} chars")
    print(f"   Good draft: {len(good_text)} chars")
    
    # Verifica suporte bfloat16
    def is_bfloat16_supported():
        try:
            return torch.cuda.is_available() and torch.cuda.get_device_capability()[0] >= 8
        except:
            return False
    
    # Carrega modelo base
    print(f"\n🤖 Carregando modelo: {args.model_name}")
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.model_name,
        max_seq_length=4096,
        dtype=None,
        load_in_4bit=True,
    )
    
    # Adapter LoRA
    print("🔧 Configurando LoRA adapter...")
    model = FastLanguageModel.get_peft_model(
        model,
        r=16,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
        lora_alpha=16,
        lora_dropout=0,
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=3407,
    )
    
    # Dataset
    print("📊 Criando dataset...")
    dataset = Dataset.from_dict({
        "instruction": [bad_text],
        "input": [""],
        "output": [good_text],
    })
    
    # Training arguments
    training_args = TrainingArguments(
        per_device_train_batch_size=2,
        gradient_accumulation_steps=4,
        warmup_steps=5,
        num_train_epochs=args.epochs,
        learning_rate=2e-4,
        fp16=not is_bfloat16_supported(),
        bf16=is_bfloat16_supported(),
        logging_steps=1,
        output_dir=args.output_dir,
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="linear",
        seed=3407,
    )
    
    # Trainer
    print("🚀 Iniciando treinamento...")
    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=4096,
        packing=False,
        args=training_args,
    )
    
    trainer.train()
    
    # Salva adapter
    print(f"\n💾 Salvando adapter em {args.output_dir}...")
    os.makedirs(args.output_dir, exist_ok=True)
    model.save_pretrained(args.output_dir)
    tokenizer.save_pretrained(args.output_dir)
    
    print(f"✅ LoRA salvo em {args.output_dir}")
    print("=" * 60)
    print("🎉 Treinamento concluído!")

if __name__ == "__main__":
    main()


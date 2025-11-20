# Instalação Julia e Whisper.cpp - LOCAL (Sem Sudo)

**Status:** ✅ **Script de instalação local criado**

---

## 🚀 Instalação Rápida (Sem Sudo)

```bash
cd /mnt/e/workspace/beagle-remote
bash scripts/install_julia_whisper_local.sh
```

Este script instala tudo em `~/.local/bin` (não precisa de sudo).

## 📋 O Que o Script Faz

1. **Instala Julia 1.10.0 localmente**
   - Baixa do site oficial
   - Instala em `~/.local/julia`
   - Cria symlink em `~/.local/bin/julia`

2. **Instala Whisper.cpp localmente**
   - Clona repositório do GitHub
   - Compila com CMake
   - Instala em `~/.local/bin/whisper-cpp`

3. **Atualiza PATH**
   - Adiciona `~/.local/bin` ao PATH no `.bashrc`

4. **Instala Dependências Julia**
   - Executa `Pkg.instantiate()` no projeto `beagle-julia`

## ✅ Verificação

```bash
# Ativar PATH (ou reiniciar terminal)
export PATH="$HOME/.local/bin:$PATH"

# Verificar Julia
julia --version

# Verificar Whisper
whisper-cpp --help
```

## 🔧 Instalação Manual (se necessário)

### Julia Local

```bash
mkdir -p ~/.local/bin
cd /tmp
wget https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.0-linux-x86_64.tar.gz
tar -xzf julia-1.10.0-linux-x86_64.tar.gz
cp -r julia-1.10.0 ~/.local/julia
ln -sf ~/.local/julia/bin/julia ~/.local/bin/julia
export PATH="$HOME/.local/bin:$PATH"
```

### Whisper.cpp Local

```bash
mkdir -p ~/.local/bin
cd /tmp
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
cmake -B build
cmake --build build --config Release
cp bin/whisper-cli ~/.local/bin/whisper-cpp
chmod +x ~/.local/bin/whisper-cpp
export PATH="$HOME/.local/bin:$PATH"
```

## 📍 Localizações

- **Julia**: `~/.local/julia/bin/julia`
- **Whisper**: `~/.local/bin/whisper-cpp`
- **PATH**: Adicionado ao `~/.bashrc`

---

**Instalação local completa!** 🎉

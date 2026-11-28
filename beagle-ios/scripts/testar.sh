#!/usr/bin/env bash
#
# testar.sh — roda os testes do BeagleCore.
#
# Por que `swift test` e não `xcodebuild test`: BeagleCore é um produto de Swift
# Package, não um target do Xcode. O scheme do app tinha <TestAction> SEM
# <Testables> — a ação de teste apontava para lugar nenhum, e por isso 145
# testes existiam e NUNCA rodavam. Mesmo com a Testables declarada, xcodebuild
# recusa ("not configured for the test action") porque não resolve o alvo de
# teste do pacote local por linha de comando.
#
# `swift test` compila para macOS. Isso só funciona porque as dependências que
# não compilam para macOS (swift-transformers, MLX, WhisperKit) foram tiradas da
# oferta de macOS no Package.swift — o app é iOS e LocalLLMEngine já se protege
# com #if canImport. No macOS ele simplesmente não tem runtime local.
#
set -euo pipefail
cd "$(dirname "$0")/../BeagleSuite"
exec swift test "$@"

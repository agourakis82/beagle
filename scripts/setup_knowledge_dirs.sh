#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${1:-$HOME/knowledge}"

mkdir -p "$BASE_DIR/papers" "$BASE_DIR/docs" "$BASE_DIR/books"

echo "Created:"
echo "  $BASE_DIR/papers"
echo "  $BASE_DIR/docs"
echo "  $BASE_DIR/books"

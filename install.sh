#!/usr/bin/env bash
# install.sh — instala dependências, baixa o servidor e (opcional) inicia.
# Uso: bash install.sh [--no-start]
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

START=1
for a in "$@"; do
  case "$a" in
    --no-start) START=0 ;;
    *) echo "Opção desconhecida: $a (use --no-start)"; exit 1 ;;
  esac
done

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) echo "[erro] CPU $(uname -m) não suportada: o BDS e o PHP da PMMP para Linux só existem em x86_64."; exit 1 ;;
esac

# Só instala o que está faltando.
MISSING=""
for p in curl tar unzip tmux jq; do
  command -v "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"
done

if [ -n "$MISSING" ]; then
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; elif command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else SUDO="none"; fi
  if [ "$SUDO" = "none" ]; then
    echo "[erro] Faltam:$MISSING e não sou root nem tenho sudo. Instale-os e rode de novo."
    exit 1
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "[erro] Faltam:$MISSING e não achei apt-get. Instale-os manualmente."
    exit 1
  fi
  echo "[install] Instalando:$MISSING"
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -y
  # shellcheck disable=SC2086
  $SUDO apt-get install -y --no-install-recommends ca-certificates$MISSING
else
  echo "[install] Dependências já presentes."
fi

chmod +x "$ROOT/mc" "$ROOT/install.sh"

echo "[install] Checando a rede do sandbox..."
"$ROOT/mc" preflight || true

"$ROOT/mc" setup

if [ "$START" -eq 1 ]; then
  "$ROOT/mc" start
  echo
  echo "Pronto. Comandos: ./mc help   |   console: ./mc console"
else
  echo
  echo "Pronto. Inicie com: ./mc start"
fi

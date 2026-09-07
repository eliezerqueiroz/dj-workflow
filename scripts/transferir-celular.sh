#!/usr/bin/env bash
# ============================================================
# DJ Workflow — transferir-celular.sh
# ============================================================
# Transfere batches selecionados de música para o celular ou pendrive:
# 1. Da pasta especial '_Para Celular/' (padrão)
# 2. De uma playlist .m3u (--playlist ARQUIVO.m3u)
# 3. De um gênero específico com limite (--genero NOME --limite N)
#
# Uso:
#   ./scripts/transferir-celular.sh --destino "/Volumes/PENDRIVE" [--dry-run]
#   ./scripts/transferir-celular.sh --destino "/Volumes/PENDRIVE" --executar
#   ./scripts/transferir-celular.sh --playlist listas/playlists/PL-Festa.m3u --destino "/Volumes/PENDRIVE"
#   ./scripts/transferir-celular.sh --genero "Pagodão" --limite 50 --destino "/Volumes/PENDRIVE"
#
# Padrão: DRY-RUN (apenas simulação)
# ============================================================
set -euo pipefail

# --- Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Caminhos ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/config.yml"
LOGS_DIR="$PROJECT_DIR/logs"

DESTINO=""
PLAYLIST=""
GENERO=""
LIMITE=0
EXECUTAR=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      echo "Uso: transferir-celular.sh --destino PASTA [OPÇÕES]"
      echo ""
      echo "Opções:"
      echo "  --destino PASTA     Caminho de destino (ex: pendrive ou pasta do celular)"
      echo "  --playlist ARQ.m3u  Copia músicas listadas no arquivo M3U"
      echo "  --genero NOME       Copia músicas de um gênero específico"
      echo "  --limite N          Limita quantidade de faixas (ex: 50)"
      echo "  --dry-run           Apenas simula a cópia (padrão)"
      echo "  --executar          Copia os arquivos de fato"
      echo "  --help              Mostra esta ajuda"
      exit 0
      ;;
    --destino)
      DESTINO="$2"
      shift 2
      ;;
    --playlist)
      PLAYLIST="$2"
      shift 2
      ;;
    --genero)
      GENERO="$2"
      shift 2
      ;;
    --limite)
      LIMITE="$2"
      shift 2
      ;;
    --executar)
      EXECUTAR=true
      shift
      ;;
    --dry-run)
      EXECUTAR=false
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Ler raiz da biblioteca
LIBRARY_ROOT=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(os.path.expanduser(cfg.get('caminhos', {}).get('pc', '')))
")

LIBRARY_ROOT="${LIBRARY_ROOT/#\~/$HOME}"

if [[ -z "$DESTINO" ]]; then
  # Destino padrão: pasta no Desktop para enviar fácil ao celular
  DESTINO="$HOME/Desktop/Músicas-Celular"
fi

DESTINO="${DESTINO/#\~/$HOME}"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          📱 TRANSFERIDOR DE MÚSICAS (CELULAR)           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📁 Biblioteca: ${LIBRARY_ROOT}${NC}"
echo -e "${DIM}📲 Destino:    ${DESTINO}${NC}"
if [[ -n "$PLAYLIST" ]]; then
  echo -e "${DIM}📜 Playlist:   ${PLAYLIST}${NC}"
elif [[ -n "$GENERO" ]]; then
  echo -e "${DIM}🎵 Gênero:     ${GENERO} (Limite: ${LIMITE:-'sem limite'})${NC}"
else
  echo -e "${DIM}📦 Modo:       Pasta especial '_Para Celular/'${NC}"
fi

if $EXECUTAR; then
  echo -e "${BOLD}${RED}⚡ MODO: EXECUTAR (arquivos serão copiados)${NC}"
else
  echo -e "${BOLD}${YELLOW}🧪 MODO: DRY-RUN (simulação — nenhum arquivo será copiado)${NC}"
fi
echo ""

mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOGS_DIR/transferir-celular-${TIMESTAMP}.log"

python3 << PYEOF
import os
import sys
import shutil

library = "$LIBRARY_ROOT"
destino = "$DESTINO"
playlist_path = "$PLAYLIST"
genero = "$GENERO"
limite = int("$LIMITE") if "$LIMITE" else 0
executar = "$EXECUTAR" == "true"
log_file = "$LOG_FILE"

extensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg', '.wma', '.opus'}
arquivos_selecionados = []

if playlist_path and os.path.isfile(playlist_path):
    # Modo Playlist M3U
    with open(playlist_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            # Procurar arquivo na biblioteca
            found = False
            for root, dirs, files in os.walk(library):
                if line in files:
                    arquivos_selecionados.append(os.path.join(root, line))
                    found = True
                    break
elif genero:
    # Modo Gênero
    g_dir = os.path.join(library, genero)
    if os.path.isdir(g_dir):
        for root, dirs, files in os.walk(g_dir):
            for f in sorted(files):
                ext = os.path.splitext(f)[1].lower()
                if ext in extensions:
                    arquivos_selecionados.append(os.path.join(root, f))
    if limite > 0:
        arquivos_selecionados = arquivos_selecionados[:limite]
else:
    # Modo padrão: _Para Celular
    celular_dir = os.path.join(library, '_Para Celular')
    if os.path.isdir(celular_dir):
        for root, dirs, files in os.walk(celular_dir):
            for f in files:
                ext = os.path.splitext(f)[1].lower()
                if ext in extensions:
                    arquivos_selecionados.append(os.path.join(root, f))

total_bytes = sum(os.path.getsize(p) for p in arquivos_selecionados if os.path.isfile(p))
mb = total_bytes / (1024**2)

print("\033[1m━━━ 📊 SELEÇÃO DE FAIXAS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n")
print(f"  📦 Total de faixas selecionadas: \033[1;32m{len(arquivos_selecionados)}\033[0m")
print(f"  💾 Tamanho total estimado:       \033[1;34m{mb:.1f} MB\033[0m\n")

if arquivos_selecionados:
    print("  Exemplos de faixas na seleção:")
    for p in arquivos_selecionados[:10]:
        print(f"    • {os.path.basename(p)}")
    if len(arquivos_selecionados) > 10:
        print(f"    ... e mais {len(arquivos_selecionados)-10} faixas")
    print()

if executar and arquivos_selecionados:
    print("\033[1;36m━━━ 🚀 COPIANDO FAIXAS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n")
    os.makedirs(destino, exist_ok=True)
    copiados = 0
    for p in arquivos_selecionados:
        fname = os.path.basename(p)
        dest_file = os.path.join(destino, fname)
        try:
            shutil.copy2(p, dest_file)
            copiados += 1
        except Exception as e:
            print(f"  ❌ Erro ao copiar {fname}: {e}")
    print(f"  ✅ {copiados} faixas copiadas com sucesso para:\n     \033[1m{destino}\033[0m\n")
elif not executar and arquivos_selecionados:
    print("  ℹ️  Modo dry-run concluído. Nenhum arquivo foi copiado.")
    print("  Para copiar de fato, execute com \033[1m--executar\033[0m\n")
else:
    print("  ℹ️  Nenhuma faixa selecionada. Dica: adicione músicas na pasta")
    print(f"      \033[1m{os.path.join(library, '_Para Celular')}\033[0m ou use --playlist / --genero.\n")

# Log
with open(log_file, 'w', encoding='utf-8') as f:
    f.write(f"TRANSFERIR CELULAR — Destino: {destino}\n")
    f.write(f"Modo: {'EXECUTAR' if executar else 'DRY-RUN'}\n")
    f.write(f"Total faixas: {len(arquivos_selecionados)}\n")
    f.write(f"Total MB: {mb:.1f}\n\n")
    for p in arquivos_selecionados:
        f.write(f"{p}\n")

print(f"  💾 Log salvo em: {log_file}")
print()
PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

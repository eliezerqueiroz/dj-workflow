#!/usr/bin/env bash
# ============================================================
# DJ Workflow — padronizar-tags.sh
# ============================================================
# Padroniza e completa tags ID3 dos arquivos de áudio:
# 1. Preenche a tag 'Gênero' baseado na pasta onde o arquivo está
# 2. Preenche 'Artista' e 'Título' se estiverem vazios a partir do nome
# 3. Limpa tags com caracteres corrompidos ou lixo
#
# Uso:
#   ./scripts/padronizar-tags.sh [PASTA] [--dry-run]
#   ./scripts/padronizar-tags.sh [PASTA] --executar
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

# --- Argumentos ---
TARGET_PATH=""
EXECUTAR=false

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: padronizar-tags.sh [PASTA] [--executar] [--dry-run]"
      echo ""
      echo "Opções:"
      echo "  PASTA       Pasta para processar (padrão: PC em config.yml)"
      echo "  --dry-run   Apenas simula a padronização (padrão)"
      echo "  --executar  Aplica as tags diretamente nos arquivos"
      echo "  --help      Mostra esta ajuda"
      exit 0
      ;;
    --executar)
      EXECUTAR=true
      ;;
    --dry-run)
      EXECUTAR=false
      ;;
    *)
      TARGET_PATH="$arg"
      ;;
  esac
done

if [[ -z "$TARGET_PATH" ]]; then
  if [[ -f "$CONFIG_FILE" ]]; then
    TARGET_PATH=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(os.path.expanduser(cfg.get('caminhos', {}).get('pc', '')))
")
  fi
fi

TARGET_PATH="${TARGET_PATH/#\~/$HOME}"

if [[ -z "$TARGET_PATH" ]] || [[ ! -d "$TARGET_PATH" ]]; then
  echo -e "${RED}❌ Pasta não encontrada: ${TARGET_PATH:-'(nenhuma)'}${NC}"
  exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          🏷️  PADRONIZADOR DE TAGS ID3                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Pasta alvo: ${TARGET_PATH}${NC}"
if $EXECUTAR; then
  echo -e "${BOLD}${RED}⚡ MODO: EXECUTAR (tags serão gravadas nos arquivos)${NC}"
else
  echo -e "${BOLD}${YELLOW}🧪 MODO: DRY-RUN (simulação — nenhum arquivo será modificado)${NC}"
fi
echo ""

mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOGS_DIR/padronizar-tags-${TIMESTAMP}.log"

python3 << PYEOF
import os
import sys
import re

try:
    from mutagen.easyid3 import EasyID3
    from mutagen.mp3 import MP3
    from mutagen import File as MutagenFile
except ImportError:
    print("  ❌ mutagen não instalado. Rode: pip3 install mutagen")
    sys.exit(1)

target = "$TARGET_PATH"
executar = "$EXECUTAR" == "true"
log_file = "$LOG_FILE"
extensions = {'.mp3', '.m4a', '.flac'}

alteracoes = [] # (fpath, fname, mudancas_str, dict_novas_tags)
total_analisado = 0

for root, dirs, files in os.walk(target):
    # Pasta imediata define o gênero canônico se for gênero
    folder_name = os.path.basename(root)
    
    for f in files:
        ext = os.path.splitext(f)[1].lower()
        if ext not in extensions:
            continue

        fpath = os.path.join(root, f)
        total_analisado += 1

        mudancas = []
        updates = {}

        try:
            audio = MutagenFile(fpath, easy=True)
            if audio is None:
                continue

            # 1. Artista e Título
            curr_artist = audio.get('artist', [''])[0].strip()
            curr_title = audio.get('title', [''])[0].strip()
            curr_genre = audio.get('genre', [''])[0].strip()

            base_name = os.path.splitext(f)[0]

            if not curr_artist or not curr_title:
                # Tentar extrair de "Artista - Titulo"
                if " - " in base_name:
                    parts = base_name.split(" - ", 1)
                    sug_artist = parts[0].strip()
                    sug_title = parts[1].strip()
                    # Limpar numeração no artista
                    sug_artist = re.sub(r'^\d+[\.\s_-]*', '', sug_artist)

                    if not curr_artist and sug_artist:
                        mudancas.append(f"Artista: '{sug_artist}'")
                        updates['artist'] = sug_artist
                    if not curr_title and sug_title:
                        mudancas.append(f"Título: '{sug_title}'")
                        updates['title'] = sug_title
                else:
                    if not curr_title:
                        sug_title = re.sub(r'^\d+[\.\s_-]*', '', base_name)
                        mudancas.append(f"Título: '{sug_title}'")
                        updates['title'] = sug_title

            # 2. Gênero baseado na pasta (se a pasta for um gênero e a tag estiver vazia ou for genérica)
            if folder_name and not folder_name.startswith(('_', '.')):
                if not curr_genre or curr_genre.lower() in {'other', 'unknown', 'genre', 'none'}:
                    mudancas.append(f"Gênero: '{folder_name}'")
                    updates['genre'] = folder_name

            if mudancas:
                alteracoes.append((fpath, f, ", ".join(mudancas), updates))

        except Exception as e:
            pass

print(f"  📊 Total de faixas analisadas: {total_analisado}")
print(f"  📝 Faixas com tags a atualizar: {len(alteracoes)}\n")

if alteracoes:
    print("━━━ 📝 AMOSTRA DE ATUALIZAÇÕES ━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    for fpath, fname, mudancas_str, _ in alteracoes[:15]:
        print(f"  🏷️  {fname[:45]}")
        print(f"     ➔ {mudancas_str}\n")
    if len(alteracoes) > 15:
        print(f"  ... e mais {len(alteracoes)-15} faixas detalhadas no log\n")

if executar:
    print("\033[1;36m━━━ 🚀 GRAVANDO TAGS NOS ARQUIVOS ━━━━━━━━━━━━━━━━━━━━━━\033[0m\n")
    gravadas = 0
    for fpath, fname, _, updates in alteracoes:
        try:
            audio = MutagenFile(fpath, easy=True)
            if audio is not None:
                for k, v in updates.items():
                    audio[k] = [v]
                audio.save()
                gravadas += 1
        except Exception as e:
            print(f"  ❌ Erro ao gravar tags em {fname}: {e}")
    print(f"  ✅ {gravadas} faixas atualizadas com sucesso!\n")
else:
    print("  ℹ️  Modo dry-run concluído. Nenhuma tag foi alterada no disco.")
    print("  Use \033[1m--executar\033[0m para aplicar as gravações.\n")

# Log
with open(log_file, 'w', encoding='utf-8') as f:
    f.write(f"PADRONIZAR TAGS — {target}\n")
    f.write(f"Modo: {'EXECUTAR' if executar else 'DRY-RUN'}\n")
    f.write(f"Total analisado: {total_analisado}\n")
    f.write(f"Total a atualizar: {len(alteracoes)}\n\n")
    for fpath, fname, mudancas_str, _ in alteracoes:
        f.write(f"[UPDATE] {fpath}\n         {mudancas_str}\n")

print(f"  💾 Log salvo em: {log_file}")
print()
PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

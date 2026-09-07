#!/usr/bin/env bash
# ============================================================
# DJ Workflow — coletar-downloads.sh
# ============================================================
# Coleta faixas e pastas musicais baixadas em ~/Downloads:
# 1. Pastas de Sets (ex: Set Salvador) -> _Sets/
# 2. Pastas de Intros/SFX (ex: DJ Deuzbenza Intros) -> _Samples-Vinhetas/
# 3. Faixas e pastas de downloads soltas -> _Inbox/YYYY-MM-DD/
# 4. Remove prefixos de downloaders (ex: 'SpotiDownloader.com - ')
#
# Uso:
#   ./scripts/coletar-downloads.sh [--dry-run]
#   ./scripts/coletar-downloads.sh --executar
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

EXECUTAR=false

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: coletar-downloads.sh [--executar] [--dry-run]"
      echo ""
      echo "Opções:"
      echo "  --dry-run   Apenas simula a coleta (padrão)"
      echo "  --executar  Move os arquivos para a biblioteca"
      echo "  --help      Mostra esta ajuda"
      exit 0
      ;;
    --executar)
      EXECUTAR=true
      ;;
    --dry-run)
      EXECUTAR=false
      ;;
  esac
done

DOWNLOADS_DIR="$HOME/Downloads"
LIBRARY_ROOT=""

if [[ -f "$CONFIG_FILE" ]]; then
  LIBRARY_ROOT=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(os.path.expanduser(cfg.get('caminhos', {}).get('pc', '')))
")
fi

LIBRARY_ROOT="${LIBRARY_ROOT/#\~/$HOME}"

if [[ -z "$LIBRARY_ROOT" ]] || [[ ! -d "$LIBRARY_ROOT" ]]; then
  echo -e "${RED}❌ Pasta da biblioteca não encontrada: ${LIBRARY_ROOT}${NC}"
  exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          📥 COLETOR DE DOWNLOADS MUSICAIS              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Origem:  ${DOWNLOADS_DIR}${NC}"
echo -e "${DIM}📁 Destino: ${LIBRARY_ROOT}/_Inbox/ (ou _Sets, _Samples-Vinhetas)${NC}"
if $EXECUTAR; then
  echo -e "${BOLD}${RED}⚡ MODO: EXECUTAR (arquivos serão movidos)${NC}"
else
  echo -e "${BOLD}${YELLOW}🧪 MODO: DRY-RUN (simulação — nenhum arquivo será movido)${NC}"
fi
echo ""

mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
DATE_TAG=$(date '+%Y-%m-%d')
LOG_FILE="$LOGS_DIR/coletar-downloads-${TIMESTAMP}.log"

python3 << PYEOF
import os
import sys
import shutil
import re

downloads = "$DOWNLOADS_DIR"
library = "$LIBRARY_ROOT"
executar = "$EXECUTAR" == "true"
date_tag = "$DATE_TAG"
log_file = "$LOG_FILE"

extensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg', '.wma', '.opus'}

def clean_downloader_name(name):
    base, ext = os.path.splitext(name)
    # Tirar prefixos de downloaders
    base = re.sub(r'^SpotiDownloader\.com\s*-\s*', '', base, flags=re.IGNORECASE)
    base = re.sub(r'^SnapInsta\.io\s*-\s*', '', base, flags=re.IGNORECASE)
    base = re.sub(r'\(youtube\)', '', base, flags=re.IGNORECASE)
    base = re.sub(r'\s+', ' ', base).strip()
    return base + ext

inbox_batch_dir = os.path.join(library, '_Inbox', date_tag)
sets_dir = os.path.join(library, '_Sets')
samples_dir = os.path.join(library, '_Samples-Vinhetas')

tarefas = [] # (origem, destino, descricao)

# 1. Pastas específicas
for item in os.listdir(downloads):
    item_path = os.path.join(downloads, item)
    if not os.path.isdir(item_path):
        continue

    item_lower = item.lower()
    if 'set ' in item_lower or item_lower.endswith('set') or 'sets' in item_lower:
        dest = os.path.join(sets_dir, item)
        tarefas.append((item_path, dest, f"Pasta de Set -> _Sets/{item}"))
    elif 'intro' in item_lower or 'vinheta' in item_lower or 'sfx' in item_lower:
        dest = os.path.join(samples_dir, item)
        tarefas.append((item_path, dest, f"Pasta de Vinhetas -> _Samples-Vinhetas/{item}"))
    elif 'fordownload' in item_lower:
        # Varrer áudios dentro da pasta forDownload
        for root, dirs, files in os.walk(item_path):
            for f in files:
                ext = os.path.splitext(f)[1].lower()
                if ext in extensions:
                    orig_f = os.path.join(root, f)
                    new_name = clean_downloader_name(f)
                    dest_f = os.path.join(inbox_batch_dir, new_name)
                    tarefas.append((orig_f, dest_f, f"Faixa de {item} -> _Inbox/{date_tag}/{new_name}"))

# 2. Arquivos de áudio soltos na raiz de Downloads
for item in os.listdir(downloads):
    item_path = os.path.join(downloads, item)
    if os.path.isfile(item_path):
        ext = os.path.splitext(item)[1].lower()
        if ext in extensions:
            new_name = clean_downloader_name(item)
            dest_f = os.path.join(inbox_batch_dir, new_name)
            tarefas.append((item_path, dest_f, f"Faixa solta -> _Inbox/{date_tag}/{new_name}"))

print(f"  📊 Total de itens encontrados para coleta: {len(tarefas)}\n")

if tarefas:
    print("━━━ 📝 ITENS ENCONTRADOS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    for orig, dest, desc in tarefas[:15]:
        orig_name = os.path.basename(orig)
        print(f"  📦 {orig_name[:45]}")
        print(f"     ➔ {desc}\n")
    if len(tarefas) > 15:
        print(f"  ... e mais {len(tarefas)-15} itens detalhados no log\n")

if executar:
    print("\033[1;36m━━━ 🚀 COLETANDO ARQUIVOS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n")
    sucesso = 0
    for orig, dest, desc in tarefas:
        try:
            if os.path.isdir(orig):
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.move(orig, dest)
            else:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                if os.path.exists(dest):
                    b, e = os.path.splitext(dest)
                    dest = f"{b}_dl{e}"
                shutil.move(orig, dest)
            sucesso += 1
        except Exception as e:
            print(f"  ❌ Erro ao mover {orig}: {e}")
    print(f"  ✅ {sucesso} itens coletados com sucesso!\n")
else:
    print("  ℹ️  Modo dry-run concluído. Nenhum arquivo foi movido de Downloads.")
    print("  Use \033[1m--executar\033[0m para aplicar a coleta.\n")

# Log
with open(log_file, 'w', encoding='utf-8') as f:
    f.write(f"COLETOR DE DOWNLOADS — {downloads}\n")
    f.write(f"Modo: {'EXECUTAR' if executar else 'DRY-RUN'}\n")
    f.write(f"Data batch: {date_tag}\n")
    f.write(f"Total: {len(tarefas)}\n\n")
    for orig, dest, desc in tarefas:
        f.write(f"[COLETAR] {orig} -> {dest} ({desc})\n")

print(f"  💾 Log salvo em: {log_file}")
print()
PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

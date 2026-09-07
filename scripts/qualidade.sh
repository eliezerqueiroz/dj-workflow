#!/usr/bin/env bash
# ============================================================
# DJ Workflow — qualidade.sh
# ============================================================
# Lista faixas MP3 abaixo de 320kbps.
# Gera relatório com bitrate, arquivo e sugestão de ação.
#
# Uso:
#   ./scripts/qualidade.sh [PASTA]
#   ./scripts/qualidade.sh --salvar
#   ./scripts/qualidade.sh --min 256   # Mínimo customizado
#
# Dependências: python3, mutagen
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

# --- Configuração ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/config.yml"
LISTAS_DIR="$PROJECT_DIR/listas"

# --- Parse de argumentos ---
TARGET_PATH=""
SALVAR=false
MIN_BITRATE=320

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: qualidade.sh [PASTA] [--salvar] [--min BITRATE]"
      echo ""
      echo "Opções:"
      echo "  PASTA       Pasta para analisar (padrão: config.yml)"
      echo "  --salvar    Salva relatório em listas/"
      echo "  --min N     Bitrate mínimo aceitável (padrão: 320)"
      echo "  --help      Mostra esta ajuda"
      exit 0
      ;;
    --salvar)
      SALVAR=true
      ;;
    --min)
      shift_next=true
      ;;
    *)
      if [[ "${shift_next:-false}" == "true" ]]; then
        MIN_BITRATE="$arg"
        shift_next=false
      else
        TARGET_PATH="$arg"
      fi
      ;;
  esac
done

# --- Resolver caminho ---
if [[ -z "$TARGET_PATH" ]]; then
  if [[ -f "$CONFIG_FILE" ]]; then
    TARGET_PATH=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
hd = os.path.expanduser(cfg.get('caminhos', {}).get('hd', ''))
pc = os.path.expanduser(cfg.get('caminhos', {}).get('pc', ''))
print(hd if os.path.isdir(hd) else (pc if os.path.isdir(pc) else ''))
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
echo "║       🔍 ANÁLISE DE QUALIDADE DE ÁUDIO                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Pasta: ${TARGET_PATH}${NC}"
echo -e "${DIM}📏 Mínimo: ${MIN_BITRATE}kbps${NC}"
echo ""

REPORT_FILE=""
if $SALVAR; then
  mkdir -p "$LISTAS_DIR"
  REPORT_FILE="$LISTAS_DIR/qualidade-$(date '+%Y%m%d-%H%M%S').txt"
fi

python3 << PYEOF
import os
import sys

try:
    from mutagen import File as MutagenFile
except ImportError:
    print("  ❌ mutagen não instalado. Rode: pip3 install mutagen")
    sys.exit(1)

target = "$TARGET_PATH"
min_br = int("$MIN_BITRATE")
report_file = "$REPORT_FILE" if "$SALVAR" == "true" else ""
extensions = {'.mp3', '.m4a', '.aac', '.ogg', '.wma', '.opus'}

total = 0
low = []
ok = 0

for root, dirs, files in os.walk(target):
    for fname in files:
        ext = os.path.splitext(fname)[1].lower()
        if ext not in extensions:
            continue

        fpath = os.path.join(root, fname)
        total += 1

        try:
            audio = MutagenFile(fpath)
            if audio and hasattr(audio.info, 'bitrate'):
                br = audio.info.bitrate // 1000
                if br < min_br:
                    rel = os.path.relpath(fpath, target)
                    low.append((br, rel, fpath))
                else:
                    ok += 1
            else:
                ok += 1
        except Exception:
            pass

    if total % 500 == 0 and total > 0:
        print(f"\r  🔍 Analisando... {total} arquivos", end="", flush=True)

if total > 500:
    print(f"\r  🔍 Concluído: {total} arquivos analisados    ")
print()

# Resultados
pct_ok = ok * 100 // total if total > 0 else 0
print(f"  ✅ Acima de {min_br}kbps: \033[1;32m{ok}\033[0m ({pct_ok}%)")
print(f"  ⚠️  Abaixo de {min_br}kbps: \033[1;33m{len(low)}\033[0m ({100-pct_ok}%)")
print()

if low:
    low.sort(key=lambda x: x[0])
    print(f"  \033[1m{'#':>4}  {'kbps':>6}  Arquivo\033[0m")
    print(f"  {'─'*4}  {'─'*6}  {'─'*50}")
    for i, (br, rel, _) in enumerate(low[:100], 1):
        icon = "❌" if br < 128 else "⚠️"
        print(f"  {i:>4}  {icon} {br:>3}   {rel}")

    if len(low) > 100:
        print(f"\n  ... e mais {len(low)-100} arquivos")
    print()

# Salvar
if report_file:
    with open(report_file, 'w') as f:
        f.write(f"QUALIDADE — {target}\n")
        f.write(f"Mínimo: {min_br}kbps\n")
        f.write(f"Total: {total} | OK: {ok} | Low: {len(low)}\n\n")
        for br, rel, full in sorted(low):
            f.write(f"[{br}kbps] {full}\n")
    print(f"  💾 Relatório salvo: {report_file}")
    print()

PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

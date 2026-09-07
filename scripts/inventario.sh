#!/usr/bin/env bash
# ============================================================
# DJ Workflow — inventario.sh
# ============================================================
# Gera um relatório completo da biblioteca musical:
#   - Total de arquivos por formato
#   - Total por pasta/gênero
#   - Faixas sem tags (artista/título/gênero)
#   - Distribuição de qualidade (bitrate)
#   - Arquivos maiores e menores
#
# Uso:
#   ./scripts/inventario.sh [PASTA]
#   ./scripts/inventario.sh                    # Usa config padrão
#   ./scripts/inventario.sh /caminho/pasta     # Pasta específica
#   ./scripts/inventario.sh --salvar           # Salva em listas/
#
# Dependências: ffprobe (ffmpeg), python3, mutagen
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
NC='\033[0m' # No Color

# --- Configuração ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/config.yml"
LOGS_DIR="$PROJECT_DIR/logs"
LISTAS_DIR="$PROJECT_DIR/listas"

# --- Parse de argumentos ---
TARGET_PATH=""
SALVAR=false

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: inventario.sh [PASTA] [--salvar]"
      echo ""
      echo "Opções:"
      echo "  PASTA       Pasta para inventariar (padrão: config.yml)"
      echo "  --salvar    Salva relatório em listas/"
      echo "  --help      Mostra esta ajuda"
      exit 0
      ;;
    --salvar)
      SALVAR=true
      ;;
    *)
      TARGET_PATH="$arg"
      ;;
  esac
done

# --- Resolver caminho da biblioteca ---
if [[ -z "$TARGET_PATH" ]]; then
  # Tentar ler do config.yml
  if [[ -f "$CONFIG_FILE" ]]; then
    TARGET_PATH=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
hd = cfg.get('caminhos', {}).get('hd', '')
pc = cfg.get('caminhos', {}).get('pc', '')
# Prefere HD se conectado
import os
hd_expanded = os.path.expanduser(hd)
pc_expanded = os.path.expanduser(pc)
if os.path.isdir(hd_expanded):
    print(hd_expanded)
elif os.path.isdir(pc_expanded):
    print(pc_expanded)
else:
    print('')
")
  fi
fi

if [[ -z "$TARGET_PATH" ]] || [[ ! -d "$TARGET_PATH" ]]; then
  echo -e "${RED}❌ Pasta não encontrada: ${TARGET_PATH:-'(nenhuma especificada)'}${NC}"
  echo "Uso: inventario.sh /caminho/para/biblioteca"
  exit 1
fi

# --- Expandir ~ ---
TARGET_PATH="${TARGET_PATH/#\~/$HOME}"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║         🎧 INVENTÁRIO DA BIBLIOTECA MUSICAL             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Pasta: ${TARGET_PATH}${NC}"
echo -e "${DIM}📅 Data:  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

# --- Extensões de áudio ---
AUDIO_EXTENSIONS=("mp3" "m4a" "flac" "wav" "aac" "ogg" "wma" "opus")

# --- 1. Contagem total e por formato ---
echo -e "${BOLD}━━━ 📊 RESUMO GERAL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TOTAL=0

for ext in "${AUDIO_EXTENSIONS[@]}"; do
  count=$(find "$TARGET_PATH" -type f -iname "*.${ext}" 2>/dev/null | wc -l | tr -d ' ')
  if [[ $count -gt 0 ]]; then
    TOTAL=$((TOTAL + count))
  fi
done

echo -e "  ${BOLD}Total de arquivos de áudio: ${GREEN}${TOTAL}${NC}"
echo ""

if [[ $TOTAL -eq 0 ]]; then
  echo -e "  ${YELLOW}⚠️  Nenhum arquivo de áudio encontrado.${NC}"
  exit 0
fi

echo -e "  ${BOLD}Por formato:${NC}"
for ext in "${AUDIO_EXTENSIONS[@]}"; do
  count=$(find "$TARGET_PATH" -type f -iname "*.${ext}" 2>/dev/null | wc -l | tr -d ' ')
  if [[ $count -gt 0 ]]; then
    pct=$((count * 100 / TOTAL))
    bar=""
    bar_len=$((pct / 2))
    for ((i=0; i<bar_len; i++)); do bar+="█"; done
    printf "    %-6s %5d  %3d%%  ${BLUE}%s${NC}\n" ".${ext}" "$count" "$pct" "$bar"
  fi
done

echo ""

# --- 2. Contagem por pasta (gênero) ---
echo -e "${BOLD}━━━ 📂 POR PASTA ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Construir find args para extensões
FIND_ARGS=""
first=true
for ext in "${AUDIO_EXTENSIONS[@]}"; do
  if $first; then
    FIND_ARGS="-iname \"*.${ext}\""
    first=false
  else
    FIND_ARGS="$FIND_ARGS -o -iname \"*.${ext}\""
  fi
done

while IFS= read -r dir; do
  name=$(basename "$dir")
  count=$(eval "find \"$dir\" -maxdepth 1 -type f \( $FIND_ARGS \)" 2>/dev/null | wc -l | tr -d ' ')
  sub_count=$(eval "find \"$dir\" -mindepth 2 -type f \( $FIND_ARGS \)" 2>/dev/null | wc -l | tr -d ' ')
  total_dir=$((count + sub_count))
  if [[ $total_dir -gt 0 ]]; then
    if [[ $sub_count -gt 0 ]]; then
      printf "  ${GREEN}%-30s${NC} %5d  ${DIM}(+%d em subpastas)${NC}\n" "$name/" "$count" "$sub_count"
    else
      printf "  ${GREEN}%-30s${NC} %5d\n" "$name/" "$total_dir"
    fi
  fi
done < <(find "$TARGET_PATH" -maxdepth 1 -type d ! -path "$TARGET_PATH" | sort)

echo ""

# --- 3. Análise de tags e qualidade via Python ---
echo -e "${BOLD}━━━ 🏷️  TAGS E QUALIDADE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

REPORT_FILE=""
if $SALVAR; then
  mkdir -p "$LISTAS_DIR"
  REPORT_FILE="$LISTAS_DIR/inventario-$(date '+%Y%m%d-%H%M%S').txt"
fi

python3 << PYEOF
import os
import sys

try:
    from mutagen import File as MutagenFile
    from mutagen.mp3 import MP3
    from mutagen.easyid3 import EasyID3
    HAS_MUTAGEN = True
except ImportError:
    HAS_MUTAGEN = False
    print("  ⚠️  mutagen não instalado — pulando análise de tags")
    sys.exit(0)

target = "$TARGET_PATH"
report_file = "$REPORT_FILE" if "$SALVAR" == "true" else ""
extensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg', '.wma', '.opus'}

# Contadores
total = 0
sem_artista = []
sem_titulo = []
sem_genero = []
bitrates = {}
low_quality = []
tamanhos = []

for root, dirs, files in os.walk(target):
    for fname in files:
        ext = os.path.splitext(fname)[1].lower()
        if ext not in extensions:
            continue

        fpath = os.path.join(root, fname)
        total += 1
        tamanhos.append((os.path.getsize(fpath), fpath))

        try:
            audio = MutagenFile(fpath, easy=True)
            if audio is None:
                sem_artista.append(fpath)
                sem_titulo.append(fpath)
                sem_genero.append(fpath)
                continue

            # Tags
            artist = audio.get('artist', [''])[0] if audio.get('artist') else ''
            title = audio.get('title', [''])[0] if audio.get('title') else ''
            genre = audio.get('genre', [''])[0] if audio.get('genre') else ''

            if not artist.strip():
                sem_artista.append(fpath)
            if not title.strip():
                sem_titulo.append(fpath)
            if not genre.strip():
                sem_genero.append(fpath)

            # Bitrate
            raw = MutagenFile(fpath)
            if raw and hasattr(raw.info, 'bitrate'):
                br = raw.info.bitrate // 1000
                bitrates[br] = bitrates.get(br, 0) + 1
                if br < 320 and ext == '.mp3':
                    low_quality.append((br, fpath))

        except Exception:
            pass

    # Progresso
    if total % 500 == 0:
        print(f"\r  🔍 Analisando... {total} arquivos", end="", flush=True)

if total > 500:
    print(f"\r  🔍 Análise concluída: {total} arquivos    ")
print()

# Tags faltando
print(f"  🏷️  Sem artista:  \033[1;33m{len(sem_artista)}\033[0m de {total}")
print(f"  🏷️  Sem título:   \033[1;33m{len(sem_titulo)}\033[0m de {total}")
print(f"  🏷️  Sem gênero:   \033[1;33m{len(sem_genero)}\033[0m de {total}")
print()

# Distribuição de bitrate
if bitrates:
    print("  \033[1m━━━ 📈 DISTRIBUIÇÃO DE BITRATE ━━━━━━━━━━━━━━━━━━━━━━━━\033[0m")
    print()
    for br in sorted(bitrates.keys(), reverse=True):
        count = bitrates[br]
        pct = count * 100 // total
        bar = "█" * (pct // 2)
        quality = "✅" if br >= 320 else ("⚠️" if br >= 192 else "❌")
        print(f"    {quality} {br:>4}kbps  {count:>5}  {pct:>3}%  \033[0;34m{bar}\033[0m")
    print()

# Low quality
if low_quality:
    print(f"  \033[1;31m⚠️  {len(low_quality)} faixas MP3 abaixo de 320kbps\033[0m")
    print()

# Tamanho total
total_size = sum(s for s, _ in tamanhos)
gb = total_size / (1024**3)
print(f"  💾 Tamanho total: \033[1m{gb:.2f} GB\033[0m")

# Maiores
tamanhos.sort(reverse=True)
print(f"  📦 Maior arquivo: {tamanhos[0][1].split('/')[-1]} ({tamanhos[0][0] / (1024**2):.1f} MB)")
print()

# Salvar relatório
if report_file:
    with open(report_file, 'w') as f:
        f.write(f"INVENTÁRIO — {target}\n")
        f.write(f"Data: $(date '+%Y-%m-%d %H:%M:%S')\n")
        f.write(f"Total: {total} arquivos\n")
        f.write(f"Tamanho: {gb:.2f} GB\n\n")

        f.write(f"SEM ARTISTA ({len(sem_artista)}):\n")
        for p in sem_artista[:50]:
            f.write(f"  {p}\n")
        if len(sem_artista) > 50:
            f.write(f"  ... e mais {len(sem_artista)-50}\n")

        f.write(f"\nSEM TÍTULO ({len(sem_titulo)}):\n")
        for p in sem_titulo[:50]:
            f.write(f"  {p}\n")
        if len(sem_titulo) > 50:
            f.write(f"  ... e mais {len(sem_titulo)-50}\n")

        f.write(f"\nSEM GÊNERO ({len(sem_genero)}):\n")
        for p in sem_genero[:50]:
            f.write(f"  {p}\n")
        if len(sem_genero) > 50:
            f.write(f"  ... e mais {len(sem_genero)-50}\n")

        f.write(f"\nLOW QUALITY ({len(low_quality)}):\n")
        for br, p in sorted(low_quality):
            f.write(f"  [{br}kbps] {p}\n")

    print(f"  💾 Relatório salvo: {report_file}")
    print()

PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"
echo -e "${DIM}Concluído em $(date '+%H:%M:%S')${NC}"

#!/usr/bin/env bash
# ============================================================
# DJ Workflow — rastrear-artistas.sh
# ============================================================
# Varre todas as pastas de gêneros da biblioteca e mapeia os
# artistas presentes em cada uma delas:
# - Extrai de metadados ID3 quando disponíveis
# - Extrai do nome do arquivo ("Artista - Título") quando sem tag
# - Destaca suspeitas de artistas na pasta errada (cruzando com generos.yml)
# - Gera relatório legível em listas/ para revisão manual do DJ
#
# Uso:
#   ./scripts/rastrear-artistas.sh [PASTA_BIBLIOTECA]
#   ./scripts/rastrear-artistas.sh --salvar
#   ./scripts/rastrear-artistas.sh --pasta "Samba"
# ============================================================
set -euo pipefail

# --- Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Caminhos ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/config.yml"
GENEROS_FILE="$PROJECT_DIR/config/generos.yml"
LISTAS_DIR="$PROJECT_DIR/listas"

TARGET_PATH=""
FILTRO_PASTA=""
SALVAR=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      echo "Uso: rastrear-artistas.sh [OPÇÕES]"
      echo ""
      echo "Opções:"
      echo "  --pasta NOME   Analisa apenas uma pasta específica (ex: Samba)"
      echo "  --salvar       Gera relatório em listas/ (padrão: ativado)"
      echo "  --help         Mostra esta ajuda"
      exit 0
      ;;
    --pasta)
      FILTRO_PASTA="$2"
      shift 2
      ;;
    *)
      TARGET_PATH="$1"
      shift
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
echo "║       🔍 RASTREADOR DE ARTISTAS POR GÊNERO              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Biblioteca: ${TARGET_PATH}${NC}"
if [[ -n "$FILTRO_PASTA" ]]; then
  echo -e "${DIM}🎯 Filtro:     Pasta '${FILTRO_PASTA}'${NC}"
fi
echo ""

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
REPORT_TXT="$LISTAS_DIR/rastreamento-artistas-${TIMESTAMP}.txt"
REPORT_MD="$LISTAS_DIR/rastreamento-artistas-${TIMESTAMP}.md"
mkdir -p "$LISTAS_DIR"

python3 << PYEOF
import os
import sys
import re
import unicodedata
from collections import defaultdict
import yaml

try:
    from mutagen import File as MutagenFile
except ImportError:
    MutagenFile = None

target = "$TARGET_PATH"
filtro_pasta = "$FILTRO_PASTA".strip()
generos_file = "$GENEROS_FILE"
report_txt = "$REPORT_TXT"
report_md = "$REPORT_MD"

def normalizar(txt):
    if not txt:
        return ""
    txt = unicodedata.normalize('NFKD', str(txt)).encode('ASCII', 'ignore').decode('utf-8')
    return txt.lower().strip()

# Carregar mapa de gêneros para cruzar artistas de referência
with open(generos_file) as f:
    cfg = yaml.safe_load(f)

generos_map = cfg.get('generos', {})
artist_expected_genre = {}
for g_name, info in generos_map.items():
    for art in info.get('artistas_referencia', []):
        artist_expected_genre[normalizar(art)] = g_name

extensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg', '.wma', '.opus'}

def extrair_artista_e_titulo(fpath, fname):
    artist = ""
    title = ""

    if MutagenFile:
        try:
            audio = MutagenFile(fpath, easy=True)
            if audio:
                a_list = audio.get('artist', [])
                if a_list and a_list[0].strip():
                    artist = a_list[0].strip()
                t_list = audio.get('title', [])
                if t_list and t_list[0].strip():
                    title = t_list[0].strip()
        except Exception:
            pass

    base, _ = os.path.splitext(fname)
    # Limpar numeração inicial tipo "01 - " ou "1. "
    base_clean = re.sub(r'^\d+[\.\s_-]+', '', base)

    # Se não tinha tag de artista, tentar extrair de "Artista - Titulo"
    if not artist:
        if " - " in base_clean:
            parts = base_clean.split(" - ", 1)
            artist = parts[0].strip()
            if not title:
                title = parts[1].strip()
        elif " _ " in base_clean:
            parts = base_clean.split(" _ ", 1)
            artist = parts[0].strip()
            if not title:
                title = parts[1].strip()
        else:
            artist = "[Sem Artista Identificado]"
            if not title:
                title = base_clean

    if not title:
        title = base_clean

    return artist, title

# Varrer pastas de primeiro nível dentro da biblioteca
pastas_dados = defaultdict(lambda: defaultdict(list)) # pasta -> artista -> lista de faixas

for item in sorted(os.listdir(target)):
    item_path = os.path.join(target, item)
    if not os.path.isdir(item_path):
        continue
    # Ignorar pastas ocultas
    if item.startswith('.'):
        continue
    if filtro_pasta and item.lower() != filtro_pasta.lower():
        continue

    for root, dirs, files in os.walk(item_path):
        for f in sorted(files):
            ext = os.path.splitext(f)[1].lower()
            if ext in extensions:
                fpath = os.path.join(root, f)
                art, tit = extrair_artista_e_titulo(fpath, f)
                pastas_dados[item][art].append((f, tit, fpath))

# Gerar relatórios
txt_lines = []
md_lines = ["# 🎧 Rastreamento de Artistas por Pasta de Gênero\n\n"]
md_lines.append(f"Gerado em: {os.popen('date').read().strip()}\n\n")

print(f"  📊 Pastas analisadas: {len(pastas_dados)}\n")

total_suspeitas = 0

for pasta, artistas in sorted(pastas_dados.items()):
    total_faixas = sum(len(tracks) for tracks in artistas.values())
    
    header_txt = f"\n{'='*60}\n📂 PASTA: {pasta} ({total_faixas} faixas | {len(artistas)} artistas)\n{'='*60}\n"
    txt_lines.append(header_txt)
    md_lines.append(f"## 📂 Pasta: `{pasta}` ({total_faixas} faixas)\n\n")
    md_lines.append("| Artista | Qtd | Faixas / Exemplos | Alerta de Gênero |\n")
    md_lines.append("|---|---|---|---|\n")

    print(f"\033[1;36m━━━ 📂 {pasta} ({total_faixas} faixas, {len(artistas)} artistas) ━━━━━━━━━━━━━━\033[0m")

    # Ordenar artistas por quantidade de faixas
    artistas_ordenados = sorted(artistas.items(), key=lambda x: len(x[1]), reverse=True)

    suspeitas_pasta = []

    for art, tracks in artistas_ordenados[:25]:
        art_norm = normalizar(art)
        
        # Verificar se esse artista é esperado em outro gênero
        alerta = ""
        alerta_md = "-"
        if art_norm in artist_expected_genre:
            gen_esperado = artist_expected_genre[art_norm]
            if normalizar(gen_esperado) != normalizar(pasta):
                alerta = f" ⚠️  [ATENÇÃO: Artista esperado em '{gen_esperado}']"
                alerta_md = f"⚠️ Esperado em `{gen_esperado}`"
                suspeitas_pasta.append((art, gen_esperado, len(tracks)))
                total_suspeitas += 1

        exemplo = tracks[0][0][:40]
        if len(tracks) > 1:
            exemplo += f" (+{len(tracks)-1})"

        print(f"  • \033[1m{art[:30]:<30}\033[0m ({len(tracks):>2} faixas)\033[0;33m{alerta}\033[0m")
        txt_lines.append(f"  • {art} ({len(tracks)} faixas){alerta} -> Ex: {tracks[0][0]}\n")
        md_lines.append(f"| **{art}** | {len(tracks)} | `{exemplo}` | {alerta_md} |\n")

    if len(artistas_ordenados) > 25:
        resto = len(artistas_ordenados) - 25
        print(f"    \033[2m... e mais {resto} artistas detalhados no relatório\033[0m")
        txt_lines.append(f"  ... e mais {resto} artistas com menos faixas\n")

    print()
    md_lines.append("\n")

print(f"\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m")
print(f"  ✅ Rastreamento concluído com sucesso!")
if total_suspeitas > 0:
    print(f"  ⚠️  \033[1;33m{total_suspeitas} possíveis inconsistências de artistas identificadas!\033[0m")
print()

# Salvar relatórios
with open(report_txt, 'w', encoding='utf-8') as f:
    f.writelines(txt_lines)

with open(report_md, 'w', encoding='utf-8') as f:
    f.writelines(md_lines)

print(f"  💾 Relatório TXT salvo em: \033[1m{report_txt}\033[0m")
print(f"  💾 Relatório MD salvo em:  \033[1m{report_md}\033[0m")
print()
PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

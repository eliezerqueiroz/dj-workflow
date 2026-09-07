#!/usr/bin/env bash
# ============================================================
# DJ Workflow — separar-generos.sh
# ============================================================
# Analisa a pasta mista 'Amapiano-afrobeat-kuduro' e separa as
# faixas em suas pastas corretas:
#   - Amapiano/
#   - Afrobeat/
#   - Kuduro/
#
# Uso:
#   ./scripts/separar-generos.sh [PASTA_ORIGEM] [--dry-run]
#   ./scripts/separar-generos.sh [PASTA_ORIGEM] --executar
#
# Padrão: roda em modo DRY-RUN (apenas simulação)
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
LOGS_DIR="$PROJECT_DIR/logs"

# --- Argumentos ---
TARGET_PATH=""
EXECUTAR=false

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: separar-generos.sh [PASTA_ORIGEM] [--executar] [--dry-run]"
      echo ""
      echo "Opções:"
      echo "  PASTA_ORIGEM   Pasta mista (padrão: Amapiano-afrobeat-kuduro no PC)"
      echo "  --dry-run      Apenas simula a separação (padrão)"
      echo "  --executar     Aplica as movimentações de fato"
      echo "  --help         Mostra esta ajuda"
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

# Resolver caminho padrão se não informado
if [[ -z "$TARGET_PATH" ]]; then
  if [[ -f "$CONFIG_FILE" ]]; then
    PC_PATH=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(os.path.expanduser(cfg.get('caminhos', {}).get('pc', '')) + '/Amapiano-afrobeat-kuduro')
")
    TARGET_PATH="$PC_PATH"
  fi
fi

TARGET_PATH="${TARGET_PATH/#\~/$HOME}"

if [[ -z "$TARGET_PATH" ]] || [[ ! -d "$TARGET_PATH" ]]; then
  echo -e "${RED}❌ Pasta não encontrada: ${TARGET_PATH:-'(nenhuma)'}${NC}"
  exit 1
fi

PARENT_DIR="$(dirname "$TARGET_PATH")"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       🌍 SEPARADOR: AMAPIANO / AFROBEAT / KUDURO        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Origem:  ${TARGET_PATH}${NC}"
echo -e "${DIM}📁 Destino: ${PARENT_DIR}/{Amapiano, Afrobeat, Kuduro}/${NC}"
if $EXECUTAR; then
  echo -e "${BOLD}${RED}⚡ MODO: EXECUTAR (arquivos serão movidos)${NC}"
else
  echo -e "${BOLD}${YELLOW}🧪 MODO: DRY-RUN (simulação — nenhum arquivo será movido)${NC}"
fi
echo ""

mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOGS_DIR/separar-generos-${TIMESTAMP}.log"

python3 << PYEOF
import os
import sys
import shutil
import unicodedata
import yaml

try:
    from mutagen import File as MutagenFile
    from mutagen.easyid3 import EasyID3
except ImportError:
    MutagenFile = None

target = "$TARGET_PATH"
parent = "$PARENT_DIR"
executar = "$EXECUTAR" == "true"
log_file = "$LOG_FILE"
generos_file = "$GENEROS_FILE"

def normalizar(txt):
    if not txt:
        return ""
    txt = unicodedata.normalize('NFKD', str(txt)).encode('ASCII', 'ignore').decode('utf-8')
    return txt.lower().strip()

# Artistas e palavras-chave de referência
AMAPIANO_KEYWORDS = {
    'amapiano', 'piano', 'yanos', 'kabza de small', 'dj maphorisa', 'uncle waffles',
    'focalistic', 'mellow & sleazy', 'kelvin momo', 'young stunna', 'ceeka rsa',
    'dbn gogo', 'scotts maphuma', 'leemckrazy', 'tnk musiq', 'mas musiq',
    'de mthuda', 'boohle', 'semi tee', 'tman xpress', 'al xapo', 'snenaah',
    'nkosazana daughter', 'tyler icu', 'myztro', 'vigro deep', 'busta 929',
    'daliwonga', 'sir trill', 'musa keys', 'toss', 'major league djz', 'major league',
    'tshwala bam', 'titom', 'ypaso', 'chley', 'mdoovar', 'visca', 'blxckie',
    'felo le tee', 'mellow', 'sleazy', 'abalele', 'asibe happy', 'imithandazo',
    'mnike', 'chipi ke chipi', 'woza', 'bakwa lah', 'kancane', 'labantwana ama uber',
    'vula vala', 'sethathi', 'shimi', 'barcadi', 'bacardi', 'gqom'
}

KUDURO_KEYWORDS = {
    'kuduro', 'kuduru', 'buraka som sistema', 'dog murras', 'titica', 'cabo snoop',
    'os kuduristas', 'bruno m', 'costa neto', 'noite e dia', 'sebem', 'os do mombaca',
    'dj znobia', 'prophets of da city', 'i love kuduro', 'agasalho', 'kappata'
}

AFROBEAT_KEYWORDS = {
    'afrobeat', 'afrobeats', 'afro-beat', 'afropop', 'afro pop', 'afro house', 'afro fusion',
    'burna boy', 'wizkid', 'davido', 'tems', 'rema', 'asake', 'ckay', 'tiwa savage',
    'yemi alade', 'fireboy dml', 'fireboy', 'ayra starr', 'omah lay', 'kizz daniel',
    'joeboy', 'oxlade', 'tekno', 'magic system', '1er gaou', 'joe dwet file',
    'fally ipupa', 'koffi olomide', 'diamond platnumz', 'innoss b', 'adekunle gold',
    'shallipopi', 'seyi vibez', 'flavour', 'p-square', 'psquare', 'd banj', 'd\'banj',
    'ruger', 'buju', 'bwx', 'victony', 'zinoleesky', 'pheelz', 'spyro', 'king promise',
    'kuami eugene', 'stonebwoy', 'sarkodie', 'black sherif', 'lazzo matumbi',
    'marimbas', 'fuji', 'ijo fuji', 'highlife', 'makossa', 'soukous', 'azonto'
}

# Pastas de destino
dest_dirs = {
    'Amapiano': os.path.join(parent, 'Amapiano'),
    'Afrobeat': os.path.join(parent, 'Afrobeat'),
    'Kuduro': os.path.join(parent, 'Kuduro'),
    'Indefinido': os.path.join(parent, '_Outros', 'Amapiano-Afrobeat-Revisar')
}

extensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg', '.wma', '.opus'}

results = {'Amapiano': [], 'Afrobeat': [], 'Kuduro': [], 'Indefinido': []}
log_entries = []

# Listar arquivos
files_to_process = []
for root, dirs, files in os.walk(target):
    for f in files:
        ext = os.path.splitext(f)[1].lower()
        if ext in extensions:
            files_to_process.append(os.path.join(root, f))

files_to_process.sort()
total = len(files_to_process)

for fpath in files_to_process:
    fname = os.path.basename(fpath)
    fn_norm = normalizar(fname)

    artist_tag = ""
    title_tag = ""
    genre_tag = ""

    if MutagenFile:
        try:
            audio = MutagenFile(fpath, easy=True)
            if audio:
                artist_tag = normalizar(" ".join(audio.get('artist', [])))
                title_tag = normalizar(" ".join(audio.get('title', [])))
                genre_tag = normalizar(" ".join(audio.get('genre', [])))
        except Exception:
            pass

    search_text = f"{fn_norm} {artist_tag} {title_tag} {genre_tag}"

    matched_genre = None
    match_reason = ""

    # 1. Kuduro (mais específico)
    for kw in KUDURO_KEYWORDS:
        if kw in search_text:
            matched_genre = 'Kuduro'
            match_reason = f"palavra-chave '{kw}'"
            break

    # 2. Amapiano
    if not matched_genre:
        for kw in AMAPIANO_KEYWORDS:
            if kw in search_text:
                matched_genre = 'Amapiano'
                match_reason = f"palavra-chave '{kw}'"
                break

    # 3. Afrobeat
    if not matched_genre:
        for kw in AFROBEAT_KEYWORDS:
            if kw in search_text:
                matched_genre = 'Afrobeat'
                match_reason = f"palavra-chave '{kw}'"
                break

    # 4. Fallback por heurística de estilo sul-africano vs nigeriano
    if not matched_genre:
        # Se contiver 'feat' e nomes zulu/xhosa típicos ou 'rsa'
        if 'rsa' in search_text or 'feat.' in fn_norm and ('young' in search_text or 'dj' in search_text):
            matched_genre = 'Amapiano'
            match_reason = "heurística sul-africana"
        else:
            matched_genre = 'Indefinido'
            match_reason = "não classificado automaticamente"

    results[matched_genre].append((fpath, fname, match_reason))
    log_entries.append(f"[{matched_genre.upper()}] {fname} -> {match_reason}")

# Exibir resultados na tela
print(f"  📊 Total de faixas analisadas: {total}\n")

colors = {
    'Amapiano': '\033[0;34m',    # Blue
    'Afrobeat': '\033[0;32m',    # Green
    'Kuduro':   '\033[0;35m',    # Magenta
    'Indefinido': '\033[1;33m'   # Yellow
}
icons = {
    'Amapiano': '🎹',
    'Afrobeat': '🥁',
    'Kuduro':   '💃',
    'Indefinido': '❓'
}

for g in ['Amapiano', 'Afrobeat', 'Kuduro', 'Indefinido']:
    qtd = len(results[g])
    pct = qtd * 100 // total if total > 0 else 0
    bar = "█" * (pct // 2)
    print(f"  {icons[g]} {colors[g]}{g:<12}\033[0m: {qtd:>4} faixas ({pct:>2}%) {bar}")

print()

# Amostras do que será movido
for g in ['Amapiano', 'Afrobeat', 'Kuduro']:
    if results[g]:
        print(f"  {icons[g]} \033[1mExemplos para {g}/:\033[0m")
        for _, fname, reason in results[g][:4]:
            print(f"     • {fname[:60]} \033[2m({reason})\033[0m")
        if len(results[g]) > 4:
            print(f"     ... e mais {len(results[g])-4} faixas")
        print()

if results['Indefinido']:
    print(f"  ❓ \033[1mFaixas para revisão manual ({len(results['Indefinido'])}):\033[0m")
    for _, fname, reason in results['Indefinido'][:5]:
        print(f"     • {fname[:65]}")
    if len(results['Indefinido']) > 5:
        print(f"     ... e mais {len(results['Indefinido'])-5} faixas")
    print()

# Executar movimentações se habilitado
moved_count = 0
if executar:
    print("\033[1;36m━━━ 🚀 MOVENDO ARQUIVOS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n")
    for g, items in results.items():
        if not items:
            continue
        dest_dir = dest_dirs[g]
        os.makedirs(dest_dir, exist_ok=True)
        for fpath, fname, reason in items:
            dest_file = os.path.join(dest_dir, fname)
            # Evitar colisão
            if os.path.exists(dest_file):
                base, ext = os.path.splitext(fname)
                dest_file = os.path.join(dest_dir, f"{base}_dup{ext}")
            try:
                shutil.move(fpath, dest_file)
                moved_count += 1
            except Exception as e:
                print(f"  ❌ Erro ao mover {fname}: {e}")
    print(f"  ✅ {moved_count} arquivos movidos com sucesso!\n")
else:
    print("  ℹ️  Nenhum arquivo foi movido. Use \033[1m--executar\033[0m para aplicar as alterações.\n")

# Salvar log
with open(log_file, 'w') as f:
    f.write(f"SEPARADOR DE GÊNEROS — {target}\n")
    f.write(f"Modo: {'EXECUTAR' if executar else 'DRY-RUN'}\n")
    f.write(f"Total: {total}\n")
    for g in ['Amapiano', 'Afrobeat', 'Kuduro', 'Indefinido']:
        f.write(f"{g}: {len(results[g])}\n")
    f.write("\nDETALHES:\n")
    for l in log_entries:
        f.write(f"{l}\n")

print(f"  💾 Log salvo em: {log_file}")
print()
PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

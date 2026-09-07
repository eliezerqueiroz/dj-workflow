#!/usr/bin/env bash
# ============================================================
# DJ Workflow — auditar-genero.sh
# ============================================================
# Escaneia pastas de gênero e identifica faixas que podem
# estar na pasta errada, comparando:
#   1. Tag de gênero do arquivo
#   2. Nome da pasta onde está
#   3. Mapa de gêneros (config/generos.yml)
#   4. Artista (se conhecido no mapa)
#
# Uso:
#   ./scripts/auditar-genero.sh [PASTA]
#   ./scripts/auditar-genero.sh /Volumes/.../Amapiano/
#   ./scripts/auditar-genero.sh --todas
#   ./scripts/auditar-genero.sh --salvar
#
# Dependências: python3, mutagen, pyyaml
# ============================================================
set -euo pipefail

# --- Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Configuração ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/config.yml"
GENEROS_FILE="$PROJECT_DIR/config/generos.yml"
LISTAS_DIR="$PROJECT_DIR/listas"

# --- Parse de argumentos ---
TARGET_PATH=""
SALVAR=false
TODAS=false

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: auditar-genero.sh [PASTA] [--todas] [--salvar]"
      echo ""
      echo "Opções:"
      echo "  PASTA       Pasta de gênero específica"
      echo "  --todas     Audita todas as pastas de gênero"
      echo "  --salvar    Salva relatório em listas/"
      echo "  --help      Mostra esta ajuda"
      exit 0
      ;;
    --salvar)
      SALVAR=true
      ;;
    --todas)
      TODAS=true
      ;;
    *)
      TARGET_PATH="$arg"
      ;;
  esac
done

# --- Resolver raiz da biblioteca ---
LIBRARY_ROOT=""
if [[ -f "$CONFIG_FILE" ]]; then
  LIBRARY_ROOT=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
hd = os.path.expanduser(cfg.get('caminhos', {}).get('hd', ''))
pc = os.path.expanduser(cfg.get('caminhos', {}).get('pc', ''))
print(hd if os.path.isdir(hd) else (pc if os.path.isdir(pc) else ''))
")
fi

if $TODAS && [[ -n "$LIBRARY_ROOT" ]]; then
  TARGET_PATH="$LIBRARY_ROOT"
elif [[ -z "$TARGET_PATH" ]]; then
  TARGET_PATH="$LIBRARY_ROOT"
fi

TARGET_PATH="${TARGET_PATH/#\~/$HOME}"

if [[ -z "$TARGET_PATH" ]] || [[ ! -d "$TARGET_PATH" ]]; then
  echo -e "${RED}❌ Pasta não encontrada: ${TARGET_PATH:-'(nenhuma)'}${NC}"
  exit 1
fi

if [[ ! -f "$GENEROS_FILE" ]]; then
  echo -e "${RED}❌ Mapa de gêneros não encontrado: ${GENEROS_FILE}${NC}"
  exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║         🔍 AUDITORIA DE GÊNEROS                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Pasta: ${TARGET_PATH}${NC}"
echo ""

REPORT_FILE=""
if $SALVAR; then
  mkdir -p "$LISTAS_DIR"
  REPORT_FILE="$LISTAS_DIR/auditoria-genero-$(date '+%Y%m%d-%H%M%S').txt"
fi

python3 << PYEOF
import os
import sys
import yaml
from collections import defaultdict

# Carregar mapa de gêneros
with open("$GENEROS_FILE") as f:
    config = yaml.safe_load(f)

generos_map = config.get('generos', {})

# Construir lookup: alias → nome da pasta
alias_to_genre = {}
artist_to_genre = {}

for genre_name, info in generos_map.items():
    # O próprio nome é um alias
    alias_to_genre[genre_name.lower()] = genre_name
    for alias in info.get('aliases', []):
        alias_to_genre[alias.lower()] = genre_name
    for artist in info.get('artistas_referencia', []):
        artist_to_genre[artist.lower()] = genre_name

target = "$TARGET_PATH"
is_all = "$TODAS" == "true"
report_file = "$REPORT_FILE" if "$SALVAR" == "true" else ""

try:
    from mutagen import File as MutagenFile
except ImportError:
    print("  ❌ mutagen não instalado. Rode: pip3 install mutagen")
    sys.exit(1)

extensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg'}

# Se --todas, iterar pelas subpastas de gênero
if is_all:
    folders = [
        os.path.join(target, d) for d in sorted(os.listdir(target))
        if os.path.isdir(os.path.join(target, d)) and not d.startswith('.')
    ]
else:
    folders = [target]

all_issues = []
total_ok = 0
total_analyzed = 0

for folder in folders:
    folder_name = os.path.basename(folder)

    # Determinar gênero esperado da pasta
    expected_genre = None
    for genre_name in generos_map:
        if genre_name.lower() == folder_name.lower():
            expected_genre = genre_name
            break
    if not expected_genre:
        # Tentar match parcial
        for genre_name in generos_map:
            if genre_name.lower() in folder_name.lower():
                expected_genre = genre_name
                break

    issues = []
    ok_count = 0
    analyzed = 0

    for root, dirs, files in os.walk(folder):
        for fname in files:
            ext = os.path.splitext(fname)[1].lower()
            if ext not in extensions:
                continue

            fpath = os.path.join(root, fname)
            analyzed += 1

            try:
                audio = MutagenFile(fpath, easy=True)
                if audio is None:
                    issues.append({
                        'file': os.path.relpath(fpath, target),
                        'tag_genre': '(sem tag)',
                        'suggested': '_Quarentena',
                        'reason': 'Não foi possível ler tags'
                    })
                    continue

                tag_genre = (audio.get('genre', [''])[0] or '').strip()
                tag_artist = (audio.get('artist', [''])[0] or '').strip()

                # Determinar onde deveria estar
                suggested = None

                # 1. Checar pelo tag de gênero
                if tag_genre:
                    mapped = alias_to_genre.get(tag_genre.lower())
                    if mapped and expected_genre and mapped.lower() != expected_genre.lower():
                        suggested = mapped
                    elif mapped:
                        ok_count += 1
                        continue
                    elif not mapped and expected_genre:
                        # Tag não reconhecida — verificar pelo artista
                        pass

                # 2. Checar pelo artista
                if not suggested and tag_artist:
                    artist_genre = artist_to_genre.get(tag_artist.lower())
                    if artist_genre and expected_genre and artist_genre.lower() != expected_genre.lower():
                        suggested = artist_genre
                    elif artist_genre:
                        ok_count += 1
                        continue

                # 3. Se não tem tag nem artista reconhecido
                if not suggested:
                    if not tag_genre and not tag_artist:
                        suggested = '_Outros'
                        reason = 'Sem tag de gênero e artista'
                    elif expected_genre:
                        # Tem tag mas não reconhecida — pode estar OK
                        ok_count += 1
                        continue
                    else:
                        ok_count += 1
                        continue

                reason = f'Tag: {tag_genre or "(vazio)"}' + (f', Artista: {tag_artist}' if tag_artist else '')

                issues.append({
                    'file': os.path.relpath(fpath, target),
                    'tag_genre': tag_genre or '(vazio)',
                    'suggested': suggested,
                    'reason': reason
                })

            except Exception as e:
                pass

    total_ok += ok_count
    total_analyzed += analyzed
    all_issues.extend(issues)

    # Mostrar resultado da pasta
    if analyzed > 0:
        icon = "✅" if not issues else "⚠️"
        exp = f" (esperado: {expected_genre})" if expected_genre else " (gênero não mapeado)"
        print(f"  {icon} {folder_name}/{exp}")
        print(f"     {ok_count} OK, {len(issues)} inconsistências, {analyzed} analisados")
        print()

# Resumo
print()
print(f"\033[1m━━━ 📊 RESUMO ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m")
print()
print(f"  Total analisado: {total_analyzed}")
print(f"  ✅ Compatíveis:  \033[1;32m{total_ok}\033[0m")
print(f"  ⚠️  Inconsistentes: \033[1;33m{len(all_issues)}\033[0m")
print()

if all_issues:
    # Agrupar por sugestão
    by_suggestion = defaultdict(list)
    for issue in all_issues:
        by_suggestion[issue['suggested']].append(issue)

    print(f"\033[1m━━━ 🔀 SUGESTÕES DE MOVIMENTAÇÃO ━━━━━━━━━━━━━━━━━━━━━━\033[0m")
    print()
    for dest, items in sorted(by_suggestion.items(), key=lambda x: -len(x[1])):
        print(f"  → {dest}/ ({len(items)} faixas)")
        for item in items[:5]:
            print(f"    {item['file']}")
            print(f"      \033[2m{item['reason']}\033[0m")
        if len(items) > 5:
            print(f"    ... e mais {len(items)-5}")
        print()

# Salvar
if report_file:
    with open(report_file, 'w') as f:
        f.write(f"AUDITORIA DE GÊNEROS — {target}\n")
        f.write(f"Total: {total_analyzed} | OK: {total_ok} | Inconsistentes: {len(all_issues)}\n\n")
        for issue in sorted(all_issues, key=lambda x: x['suggested']):
            f.write(f"[{issue['suggested']}] {issue['file']}\n")
            f.write(f"  Tag: {issue['tag_genre']} | {issue['reason']}\n")
    print(f"  💾 Relatório salvo: {report_file}")
    print()

PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

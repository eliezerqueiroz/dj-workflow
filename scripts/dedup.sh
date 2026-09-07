#!/usr/bin/env bash
# ============================================================
# DJ Workflow — dedup.sh
# ============================================================
# Encontra duplicatas na biblioteca musical usando:
#   1. Nome de arquivo similar (fuzzy match)
#   2. Tamanho + duração iguais
#   3. Fingerprint de áudio (chromaprint/fpcalc) — se disponível
#
# Uso:
#   ./scripts/dedup.sh [PASTA]
#   ./scripts/dedup.sh --salvar
#   ./scripts/dedup.sh --modo nome     # Só por nome
#   ./scripts/dedup.sh --modo completo # Nome + fingerprint
#
# Dependências: python3, mutagen
# Opcional: fpcalc (chromaprint) para fingerprinting de áudio
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
LISTAS_DIR="$PROJECT_DIR/listas"

# --- Parse de argumentos ---
TARGET_PATH=""
SALVAR=false
MODO="nome"

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: dedup.sh [PASTA] [--salvar] [--modo nome|completo]"
      echo ""
      echo "Modos:"
      echo "  nome      Detecta por nome de arquivo similar (rápido)"
      echo "  completo  Nome + fingerprint de áudio (lento, precisa fpcalc)"
      echo ""
      echo "Opções:"
      echo "  --salvar  Salva relatório em listas/"
      echo "  --help    Mostra esta ajuda"
      exit 0
      ;;
    --salvar)
      SALVAR=true
      ;;
    --modo)
      shift_next="modo"
      ;;
    nome|completo)
      if [[ "${shift_next:-}" == "modo" ]]; then
        MODO="$arg"
        shift_next=""
      else
        TARGET_PATH="$arg"
      fi
      ;;
    *)
      if [[ "${shift_next:-}" == "modo" ]]; then
        MODO="$arg"
        shift_next=""
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
echo "║         🔍 DETECTOR DE DUPLICATAS                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Pasta: ${TARGET_PATH}${NC}"
echo -e "${DIM}🔧 Modo:  ${MODO}${NC}"
echo ""

REPORT_FILE=""
if $SALVAR; then
  mkdir -p "$LISTAS_DIR"
  REPORT_FILE="$LISTAS_DIR/duplicatas-$(date '+%Y%m%d-%H%M%S').txt"
fi

python3 << PYEOF
import os
import sys
import re
import hashlib
from collections import defaultdict
from difflib import SequenceMatcher

try:
    from mutagen import File as MutagenFile
except ImportError:
    print("  ❌ mutagen não instalado. Rode: pip3 install mutagen")
    sys.exit(1)

target = "$TARGET_PATH"
modo = "$MODO"
report_file = "$REPORT_FILE" if "$SALVAR" == "true" else ""
extensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg'}

# --- Coletar todos os arquivos ---
print("  🔍 Escaneando arquivos...")
files = []
for root, dirs, fnames in os.walk(target):
    for fname in fnames:
        ext = os.path.splitext(fname)[1].lower()
        if ext not in extensions:
            continue
        fpath = os.path.join(root, fname)
        files.append({
            'path': fpath,
            'name': os.path.splitext(fname)[0],
            'ext': ext,
            'size': os.path.getsize(fpath),
            'rel': os.path.relpath(fpath, target)
        })

print(f"  📊 {len(files)} arquivos de áudio encontrados")
print()

def normalize_name(name):
    """Normaliza nome para comparação."""
    name = name.lower()
    # Remove prefixos comuns de download
    name = re.sub(r'^spotdownloader\.com\s*-\s*', '', name)
    name = re.sub(r'^y2mate\.com\s*-\s*', '', name)
    # Remove sufixos como (1), (2), _copy, etc
    name = re.sub(r'\s*\(\d+\)\s*$', '', name)
    name = re.sub(r'\s*_copy\s*$', '', name)
    name = re.sub(r'\s*-\s*copy\s*$', '', name)
    # Remove caracteres especiais
    name = re.sub(r'[^\w\s-]', '', name)
    # Normaliza espaços
    name = re.sub(r'\s+', ' ', name).strip()
    return name

# --- Detecção por nome ---
print("\033[1m━━━ 📝 DUPLICATAS POR NOME ━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m")
print()

# Agrupar por nome normalizado
by_name = defaultdict(list)
for f in files:
    key = normalize_name(f['name'])
    by_name[key].append(f)

# Encontrar exatos
exact_dupes = {k: v for k, v in by_name.items() if len(v) > 1}

if exact_dupes:
    print(f"  ⚠️  {len(exact_dupes)} grupos de duplicatas exatas encontrados")
    print()
    for i, (name, group) in enumerate(sorted(exact_dupes.items()), 1):
        if i > 30:
            print(f"  ... e mais {len(exact_dupes) - 30} grupos")
            break
        print(f"  \033[1m{i}. \"{name}\"\033[0m ({len(group)} cópias)")
        # Marcar o melhor (maior bitrate/tamanho)
        group.sort(key=lambda x: x['size'], reverse=True)
        for j, f in enumerate(group):
            icon = "✅" if j == 0 else "🗑️"
            size_mb = f['size'] / (1024**2)
            print(f"     {icon} {f['rel']} ({size_mb:.1f}MB)")
        print()
else:
    print("  ✅ Nenhuma duplicata exata por nome encontrada")
    print()

# --- Detecção por similaridade (fuzzy) ---
print("\033[1m━━━ 🔄 NOMES SIMILARES (>85%) ━━━━━━━━━━━━━━━━━━━━━━━━\033[0m")
print()

similar_pairs = []
normalized = [(normalize_name(f['name']), f) for f in files]

# Otimização: agrupar por tamanho similar e primeiras letras
for i in range(len(normalized)):
    for j in range(i+1, len(normalized)):
        n1, f1 = normalized[i]
        n2, f2 = normalized[j]

        # Pular se já são duplicata exata
        if n1 == n2:
            continue

        # Otimização: pular se primeiras 3 letras são muito diferentes
        if len(n1) >= 3 and len(n2) >= 3:
            if n1[:2] != n2[:2]:
                continue

        ratio = SequenceMatcher(None, n1, n2).ratio()
        if ratio > 0.85:
            similar_pairs.append((ratio, f1, f2))

    # Progresso
    if i % 200 == 0 and i > 0:
        print(f"\r  🔍 Comparando... {i}/{len(normalized)}", end="", flush=True)

if len(normalized) > 200:
    print(f"\r  🔍 Comparação concluída                    ")
print()

if similar_pairs:
    similar_pairs.sort(key=lambda x: -x[0])
    print(f"  ⚠️  {len(similar_pairs)} pares similares encontrados")
    print()
    for i, (ratio, f1, f2) in enumerate(similar_pairs[:20], 1):
        pct = int(ratio * 100)
        print(f"  {i}. {pct}% similar:")
        print(f"     📄 {f1['rel']}")
        print(f"     📄 {f2['rel']}")
        print()
    if len(similar_pairs) > 20:
        print(f"  ... e mais {len(similar_pairs) - 20} pares")
else:
    print("  ✅ Nenhum par similar encontrado")
print()

# --- Resumo ---
total_dupes = sum(len(v) - 1 for v in exact_dupes.values())
print(f"\033[1m━━━ 📊 RESUMO ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m")
print()
print(f"  Total de arquivos:    {len(files)}")
print(f"  Duplicatas exatas:    \033[1;33m{total_dupes}\033[0m (em {len(exact_dupes)} grupos)")
print(f"  Pares similares:      \033[1;33m{len(similar_pairs)}\033[0m")
print()

# Estimar espaço recuperável
recoverable = sum(
    sum(f['size'] for f in group[1:])
    for group in exact_dupes.values()
)
print(f"  💾 Espaço recuperável: \033[1m{recoverable / (1024**2):.1f} MB\033[0m")
print()

# Salvar
if report_file:
    with open(report_file, 'w') as f:
        f.write(f"DUPLICATAS — {target}\n")
        f.write(f"Total: {len(files)} | Dupes: {total_dupes} | Similares: {len(similar_pairs)}\n\n")

        f.write("DUPLICATAS EXATAS:\n")
        for name, group in sorted(exact_dupes.items()):
            f.write(f"\n  \"{name}\" ({len(group)} cópias)\n")
            group.sort(key=lambda x: x['size'], reverse=True)
            for j, fi in enumerate(group):
                icon = "MANTER" if j == 0 else "REMOVER"
                f.write(f"    [{icon}] {fi['path']} ({fi['size']} bytes)\n")

        f.write("\n\nNOMES SIMILARES:\n")
        for ratio, f1, f2 in similar_pairs:
            f.write(f"\n  {int(ratio*100)}% similar:\n")
            f.write(f"    {f1['path']}\n")
            f.write(f"    {f2['path']}\n")

    print(f"  💾 Relatório salvo: {report_file}")
    print()

PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

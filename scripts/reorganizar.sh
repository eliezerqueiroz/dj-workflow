#!/usr/bin/env bash
# ============================================================
# DJ Workflow — reorganizar.sh
# ============================================================
# Reorganiza a biblioteca musical para o padrão oficial do DJ Zezé:
# 1. Cria a estrutura oficial de pastas de gêneros e pastas especiais
# 2. Unifica pastas legadas (ex: Samba de terreiro + Samba-Partido alto -> Samba/)
# 3. Opcionalmente limpa nomes de arquivos (--limpar-nomes)
#
# Uso:
#   ./scripts/reorganizar.sh [PASTA_RAIZ] [--dry-run]
#   ./scripts/reorganizar.sh [PASTA_RAIZ] --executar
#   ./scripts/reorganizar.sh [PASTA_RAIZ] --limpar-nomes [--executar]
#
# Padrão: DRY-RUN (apenas simulação)
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
LIMPAR_NOMES=false

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: reorganizar.sh [PASTA_RAIZ] [--executar] [--dry-run] [--limpar-nomes]"
      echo ""
      echo "Opções:"
      echo "  PASTA_RAIZ      Pasta raiz da biblioteca (padrão: PC em config.yml)"
      echo "  --dry-run       Apenas simula a reorganização (padrão)"
      echo "  --executar      Aplica as alterações no disco"
      echo "  --limpar-nomes  Remove IDs de download (_XozT..., 128kbps, etc.)"
      echo "  --help          Mostra esta ajuda"
      exit 0
      ;;
    --executar)
      EXECUTAR=true
      ;;
    --dry-run)
      EXECUTAR=false
      ;;
    --limpar-nomes)
      LIMPAR_NOMES=true
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
  echo -e "${RED}❌ Pasta raiz não encontrada: ${TARGET_PATH:-'(nenhuma)'}${NC}"
  exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          📂 REORGANIZADOR DA BIBLIOTECA                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Biblioteca:   ${TARGET_PATH}${NC}"
echo -e "${DIM}🧹 Limpar nomes: ${LIMPAR_NOMES}${NC}"
if $EXECUTAR; then
  echo -e "${BOLD}${RED}⚡ MODO: EXECUTAR (alterações serão aplicadas no disco)${NC}"
else
  echo -e "${BOLD}${YELLOW}🧪 MODO: DRY-RUN (simulação — nenhum arquivo será movido)${NC}"
fi
echo ""

mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOGS_DIR/reorganizar-${TIMESTAMP}.log"

python3 << PYEOF
import os
import sys
import shutil
import re
import unicodedata
import yaml

target = "$TARGET_PATH"
executar = "$EXECUTAR" == "true"
limpar_nomes = "$LIMPAR_NOMES" == "true"
log_file = "$LOG_FILE"
generos_file = "$GENEROS_FILE"

with open(generos_file) as f:
    cfg = yaml.safe_load(f)

generos_oficiais = list(cfg.get('generos', {}).keys())
pastas_especiais = list(cfg.get('pastas_especiais', {}).keys())

extensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg', '.wma', '.opus'}

def clean_filename(name):
    base, ext = os.path.splitext(name)
    orig = base

    # 1. Remover IDs de vídeo do YouTube tipo _RjPqsOGabVc ou _6ACl8s_tBzE
    base = re.sub(r'_[A-Za-z0-9_-]{10,12}$', '', base)
    
    # 2. Remover tags típicas de download
    patterns = [
        r'\s*\(CLIPE OFICIAL\)', r'\s*\[CLIPE OFICIAL\]',
        r'\s*\(Clipe Oficial\)', r'\s*\[Clipe Oficial\]',
        r'\s*\(Official (Music )?Video\)', r'\s*\[Official (Music )?Video\]',
        r'\s*\(Visualizer\)', r'\s*\[Visualizer\]',
        r'\s*\(Official Visualizer\)', r'\s*\[Official Visualizer\]',
        r'\s*\(128\s*kbps\)', r'\s*\(320\s*kbps\)',
        r'\s*\(KondZilla\)', r'\s*\[KondZilla\]',
        r'\s*SnapInsta\.io\s*-\s*',
        r'^\d+\.\s*', # numeração inicial "03. " ou "9. "
    ]
    for pat in patterns:
        base = re.sub(pat, '', base, flags=re.IGNORECASE)

    # Limpar espaços duplos
    base = re.sub(r'\s+', ' ', base).strip()
    if not base:
        base = orig

    return base + ext

print("━━━ 📁 ESTRUTURA OFICIAL DE PASTAS ━━━━━━━━━━━━━━━━━━━━━\n")

# Pastas a criar
todas_pastas = generos_oficiais + pastas_especiais
for p in todas_pastas:
    p_path = os.path.join(target, p)
    existe = os.path.isdir(p_path)
    status = "✅ Existe" if existe else "✨ Será criada"
    print(f"  {status:<14} {p}/")
    if executar and not existe:
        os.makedirs(p_path, exist_ok=True)

print()

# Migrações e Unificações
print("━━━ 🔄 UNIFICAÇÕES PLANEJADAS ━━━━━━━━━━━━━━━━━━━━━━━━━\n")

unificacoes = [
    ("Samba de terreiro", "Samba"),
    ("Samba-Partido alto", "Samba"),
]

tarefas_mover = [] # (origem_arquivo, destino_arquivo, motivo)

for antiga, nova in unificacoes:
    pasta_antiga = os.path.join(target, antiga)
    pasta_nova = os.path.join(target, nova)
    if os.path.isdir(pasta_antiga):
        qtd = 0
        for root, dirs, files in os.walk(pasta_antiga):
            for f in files:
                ext = os.path.splitext(f)[1].lower()
                if ext in extensions:
                    qtd += 1
                    orig = os.path.join(root, f)
                    # Caminho relativo para manter subpastas se houver
                    rel = os.path.relpath(orig, pasta_antiga)
                    dest = os.path.join(pasta_nova, rel)
                    tarefas_mover.append((orig, dest, f"unificar {antiga}/ -> {nova}/"))
        print(f"  🔄 {antiga}/ ➔  {nova}/: {qtd} faixas para unificar")

print()

# Limpeza de nomes se solicitado
renomeacoes = [] # (fpath_origem, fpath_novo, nome_limpo)
if limpar_nomes:
    print("━━━ 🧹 LIMPEZA DE NOMES DE ARQUIVO ━━━━━━━━━━━━━━━━━━━━\n")
    for root, dirs, files in os.walk(target):
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext in extensions:
                novo_nome = clean_filename(f)
                if novo_nome != f:
                    orig_p = os.path.join(root, f)
                    novo_p = os.path.join(root, novo_nome)
                    renomeacoes.append((orig_p, novo_p, f, novo_nome))

    print(f"  📝 Total de arquivos com nomes a padronizar: {len(renomeacoes)}\n")
    for orig_p, novo_p, antigo, novo in renomeacoes[:10]:
        print(f"    • {antigo[:45]} \n      ➔ {novo[:45]}\n")
    if len(renomeacoes) > 10:
        print(f"    ... e mais {len(renomeacoes)-10} arquivos")
    print()

# Execução
if executar:
    print("\033[1;36m━━━ 🚀 APLICANDO ALTERAÇÕES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n")
    # 1. Unificações de pastas
    movidos = 0
    for orig, dest, motivo in tarefas_mover:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.exists(dest):
            b, e = os.path.splitext(dest)
            dest = f"{b}_alt{e}"
        try:
            shutil.move(orig, dest)
            movidos += 1
        except Exception as e:
            print(f"  ❌ Erro ao mover {orig}: {e}")
    print(f"  ✅ {movidos} faixas unificadas com sucesso.")

    # Remover pastas antigas se ficarem vazias
    for antiga, _ in unificacoes:
        p_antiga = os.path.join(target, antiga)
        try:
            shutil.rmtree(p_antiga)
            print(f"  ✨ Pasta legada {antiga}/ removida.")
        except Exception:
            pass

    # 2. Renomeações
    if renomeacoes:
        renomeados = 0
        for orig_p, novo_p, antigo, novo in renomeacoes:
            if os.path.exists(orig_p) and not os.path.exists(novo_p):
                try:
                    os.rename(orig_p, novo_p)
                    renomeados += 1
                except Exception as e:
                    print(f"  ❌ Erro ao renomear {antigo}: {e}")
        print(f"  ✅ {renomeados} nomes de arquivos limpos e padronizados.")
    print()
else:
    print("  ℹ️  Modo dry-run concluído. Nenhuma alteração foi gravada em disco.")
    print("  Use \033[1m--executar\033[0m para aplicar.\n")

# Log
with open(log_file, 'w', encoding='utf-8') as f:
    f.write(f"REORGANIZADOR — {target}\n")
    f.write(f"Modo: {'EXECUTAR' if executar else 'DRY-RUN'}\n")
    f.write(f"Tarefas de unificação: {len(tarefas_mover)}\n")
    f.write(f"Renomeações: {len(renomeacoes)}\n\n")
    for orig, dest, motivo in tarefas_mover:
        f.write(f"[UNIFICAR] {orig} -> {dest} ({motivo})\n")
    for orig_p, novo_p, antigo, novo in renomeacoes:
        f.write(f"[RENOMEAR] {antigo} -> {novo}\n")

print(f"  💾 Log salvo em: {log_file}")
print()
PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

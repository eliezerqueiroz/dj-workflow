#!/usr/bin/env bash
# ============================================================
# DJ Workflow — sync-musica.sh
# ============================================================
# Sincronização inteligente e incremental entre PC e HD Externo.
# Usa rsync com suporte a dry-run e exclusão de arquivos de sistema.
#
# Uso:
#   ./scripts/sync-musica.sh [--dry-run]
#   ./scripts/sync-musica.sh --executar
#   ./scripts/sync-musica.sh --push [--executar]  # PC -> HD (padrão)
#   ./scripts/sync-musica.sh --pull [--executar]  # HD -> PC
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
APAGAR=false
DIRECAO="" # "pc_para_hd" ou "hd_para_pc"

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: sync-musica.sh [--executar] [--dry-run] [--delete] [--push] [--pull]"
      echo ""
      echo "Opções:"
      echo "  --dry-run   Apenas simula a sincronização (padrão)"
      echo "  --executar  Aplica a sincronização no disco"
      echo "  --delete    Remove no destino arquivos apagados na origem (espelho exato)"
      echo "  --push      Sincroniza PC -> HD (envia alterações)"
      echo "  --pull      Sincroniza HD -> PC (recebe alterações)"
      echo "  --help      Mostra esta ajuda"
      exit 0
      ;;
    --executar)
      EXECUTAR=true
      ;;
    --dry-run)
      EXECUTAR=false
      ;;
    --delete)
      APAGAR=true
      ;;
    --push|--pc-para-hd)
      DIRECAO="pc_para_hd"
      ;;
    --pull|--hd-para-pc)
      DIRECAO="hd_para_pc"
      ;;
  esac
done

# Ler configurações do YAML
PC_DIR=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(os.path.expanduser(cfg.get('caminhos', {}).get('pc', '')))
")

HD_DIR=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(os.path.expanduser(cfg.get('caminhos', {}).get('hd', '')))
")

HD_VOLUME=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('caminhos', {}).get('hd_volume', 'DEUZBENZA'))
")

DEFAULT_DIR=$(python3 -c "
import yaml, os
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('sync', {}).get('direcao', 'pc_para_hd'))
")

if [[ -z "$DIRECAO" ]]; then
  # Se acabamos de reorganizar o PC, o padrão mais seguro é enviar pro HD
  DIRECAO="${DEFAULT_DIR:-pc_para_hd}"
fi

# Verificar se HD está montado
if [[ ! -d "/Volumes/$HD_VOLUME" ]]; then
  echo -e "${RED}❌ HD Externo '$HD_VOLUME' não está conectado ou montado!${NC}"
  echo -e "${YELLOW}👉 Conecte o cabo do HD e tente novamente.${NC}"
  exit 1
fi

# Definir Origem e Destino
if [[ "$DIRECAO" == "pc_para_hd" ]]; then
  ORIGEM="$PC_DIR/"
  DESTINO="$HD_DIR/"
  SETA="PC ➔ HD ($HD_VOLUME)"
else
  ORIGEM="$HD_DIR/"
  DESTINO="$PC_DIR/"
  SETA="HD ($HD_VOLUME) ➔ PC"
fi

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          🔄 SINCRONIZADOR DE MÚSICA (RSYNC)             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}🧭 Direção: ${SETA}${NC}"
echo -e "${DIM}📂 Origem:  ${ORIGEM}${NC}"
echo -e "${DIM}📁 Destino: ${DESTINO}${NC}"
if $EXECUTAR; then
  echo -e "${BOLD}${RED}⚡ MODO: EXECUTAR (arquivos serão sincronizados)${NC}"
else
  echo -e "${BOLD}${YELLOW}🧪 MODO: DRY-RUN (simulação — nenhum arquivo será copiado)${NC}"
fi
echo ""

mkdir -p "$LOGS_DIR"
mkdir -p "$DESTINO"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOGS_DIR/sync-${TIMESTAMP}.log"

# Argumentos do rsync
RSYNC_FLAGS=("-avh" "--modify-window=2" "--stats")
RSYNC_EXCLUDE=(
  "--exclude=.DS_Store"
  "--exclude=._*"
  "--exclude=Thumbs.db"
  "--exclude=desktop.ini"
  "--exclude=.Spotlight-V100"
  "--exclude=.Trashes"
)

if ! $EXECUTAR; then
  RSYNC_FLAGS+=("--dry-run")
fi

if $APAGAR; then
  RSYNC_FLAGS+=("--delete")
fi

echo -e "  🔍 Comparando diretórios e calculando alterações..."
echo ""

# Executar rsync
rsync "${RSYNC_FLAGS[@]}" "${RSYNC_EXCLUDE[@]}" "$ORIGEM" "$DESTINO" > "$LOG_FILE" 2>&1

# Analisar saída do log
python3 << PYEOF
import re

log_file = "$LOG_FILE"
executar = "$EXECUTAR" == "true"

with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Extrair estatísticas do rsync
files_transferred = re.search(r'Number of (?:regular )?files transferred:\s*([0-9,]+)', content)
total_size_m = re.search(r'Total (?:transferred )?file size:\s*([0-9\.,]+)\s*([A-Za-z]*)', content)

num_files = files_transferred.group(1) if files_transferred else "0"

if total_size_m:
    val = float(total_size_m.group(1).replace(',', ''))
    unit = total_size_m.group(2).upper()
    if 'G' in unit:
        gb = val
    elif 'M' in unit:
        gb = val / 1024
    elif 'K' in unit:
        gb = val / (1024**2)
    else:
        gb = val / (1024**3)
else:
    gb = 0.0

mb = gb * 1024

print("\033[1m━━━ 📊 ESTATÍSTICAS DA SINCRONIZAÇÃO ━━━━━━━━━━━━━━━━━━━━\033[0m\n")
print(f"  📦 Arquivos a transferir/atualizar: \033[1;32m{num_files}\033[0m")
if gb >= 1.0:
    print(f"  💾 Volume de dados:                 \033[1;34m{gb:.2f} GB\033[0m")
else:
    print(f"  💾 Volume de dados:                 \033[1;34m{mb:.1f} MB\033[0m")

print()

if not executar:
    print("  ℹ️  Modo dry-run concluído. Nenhum byte foi gravado.")
    print("  Para sincronizar de fato, execute:")
    print("  \033[1m./scripts/sync-musica.sh --executar\033[0m\n")
else:
    print("  ✅ Sincronização concluída com sucesso no disco!\n")

print(f"  💾 Log completo disponível em: {log_file}")
print()
PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

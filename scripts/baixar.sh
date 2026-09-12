#!/usr/bin/env bash
# ============================================================
# DJ Workflow — baixar.sh
# ============================================================
# Downloader inteligente para sets de DJ:
# 1. Verifica se as faixas já existem na biblioteca local (~/Documents/DjZeze)
# 2. Baixa as faixas faltantes em alta resolução (320kbps MP3 via Spotify/YouTube)
# 3. Salva em batches datados em ~/Documents/DjZeze/_Inbox/
# 4. Gera automaticamente a playlist .m3u unificada para o djay Pro
#
# Uso:
#   ./scripts/baixar.sh --lista listas/set-samba-salvador.txt
#   ./scripts/baixar.sh --query "Criolo - Menino Mimado"
#   ./scripts/baixar.sh --playlist-name "Set-Samba-Salvador"
# ============================================================
set -euo pipefail

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PYTHON_ENGINE="$SCRIPT_DIR/core_downloader.py"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          🎧 DJ WORKFLOW — DOWNLOADER & SET BUILDER       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ $# -eq 0 ]]; then
    echo -e "${YELLOW}Uso:${NC}"
    echo "  ./scripts/baixar.sh --lista <arquivo.txt>    # Baixa lista/wishlist do set"
    echo "  ./scripts/baixar.sh --query '<faixa>'        # Baixa faixa avulsa"
    echo "  ./scripts/baixar.sh --playlist-name '<nome>' # Nome personalizado da playlist .m3u"
    echo ""
    echo -e "Exemplo padrão para o set de domingo:"
    echo -e "  ${CYAN}./scripts/baixar.sh --lista listas/set-samba-salvador.txt${NC}"
    exit 1
fi

python3 -u "$PYTHON_ENGINE" "$@"

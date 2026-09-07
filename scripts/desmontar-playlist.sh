#!/usr/bin/env bash
# ============================================================
# DJ Workflow — desmontar-playlist.sh
# ============================================================
# Desmonta pastas de playlist (ex: PL-Festa do Lado C, 
# PL-PraFazerCriança) e 'Musicas Soltas':
# 1. Exporta uma playlist .m3u para não perder a seleção original
# 2. Identifica o gênero de cada faixa usando tags e o mapa de gêneros
# 3. Detecta duplicatas já existentes na biblioteca
# 4. Move as faixas para suas pastas de gênero correspondentes
#
# Uso:
#   ./scripts/desmontar-playlist.sh "PASTA_PLAYLIST" [--dry-run]
#   ./scripts/desmontar-playlist.sh "PASTA_PLAYLIST" --executar
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
PLAYLISTS_DIR="$PROJECT_DIR/listas/playlists"

# --- Argumentos ---
TARGET_PATH=""
EXECUTAR=false

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: desmontar-playlist.sh \"PASTA_PLAYLIST\" [--executar] [--dry-run]"
      echo ""
      echo "Opções:"
      echo "  PASTA_PLAYLIST  Caminho da pasta da playlist para desmontar"
      echo "  --dry-run       Apenas simula a operação (padrão)"
      echo "  --executar      Aplica as movimentações de fato"
      echo "  --help          Mostra esta ajuda"
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

if [[ -z "$TARGET_PATH" ]]; then
  echo -e "${YELLOW}⚠️ Nenhuma pasta informada. Exemplo de uso:${NC}"
  echo "  ./scripts/desmontar-playlist.sh ~/Documents/DjZeze/\"PL-Festa do Lado C \""
  exit 1
fi

TARGET_PATH="${TARGET_PATH/#\~/$HOME}"

if [[ ! -d "$TARGET_PATH" ]]; then
  echo -e "${RED}❌ Pasta não encontrada: ${TARGET_PATH}${NC}"
  exit 1
fi

LIBRARY_ROOT="$(dirname "$TARGET_PATH")"
PLAYLIST_NAME="$(basename "$TARGET_PATH")"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║            🎶 DESMONTADOR DE PLAYLISTS                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}📂 Pasta Playlist:  ${TARGET_PATH}${NC}"
echo -e "${DIM}📁 Biblioteca Raiz: ${LIBRARY_ROOT}${NC}"
if $EXECUTAR; then
  echo -e "${BOLD}${RED}⚡ MODO: EXECUTAR (arquivos serão movidos e playlist .m3u criada)${NC}"
else
  echo -e "${BOLD}${YELLOW}🧪 MODO: DRY-RUN (simulação — nenhum arquivo será alterado)${NC}"
fi
echo ""

mkdir -p "$LOGS_DIR" "$PLAYLISTS_DIR"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOGS_DIR/desmontar-playlist-${TIMESTAMP}.log"

python3 << PYEOF
import os
import sys
import shutil
import unicodedata
import yaml

try:
    from mutagen import File as MutagenFile
except ImportError:
    MutagenFile = None

target = "$TARGET_PATH"
library_root = "$LIBRARY_ROOT"
playlist_name = "$PLAYLIST_NAME"
executar = "$EXECUTAR" == "true"
log_file = "$LOG_FILE"
playlists_dir = "$PLAYLISTS_DIR"
generos_file = "$GENEROS_FILE"

def normalizar(txt):
    if not txt:
        return ""
    txt = unicodedata.normalize('NFKD', str(txt)).encode('ASCII', 'ignore').decode('utf-8')
    return txt.lower().strip()

# Carregar mapa de gêneros
with open(generos_file) as f:
    cfg = yaml.safe_load(f)

generos_map = cfg.get('generos', {})
extensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg', '.wma', '.opus'}

# Criar lookup: palavra/artista -> Gênero
alias_to_genre = {}
for g_name, info in generos_map.items():
    alias_to_genre[normalizar(g_name)] = g_name
    for al in info.get('aliases', []):
        alias_to_genre[normalizar(al)] = g_name
    for art in info.get('artistas_referencia', []):
        alias_to_genre[normalizar(art)] = g_name

# Varrer toda a biblioteca para identificar duplicatas já existentes
print("  🔍 Indexando biblioteca para checar duplicatas existentes...")
existing_files = {}
for root, dirs, files in os.walk(library_root):
    # Ignorar a própria pasta da playlist que estamos desmontando
    if os.path.abspath(root).startswith(os.path.abspath(target)):
        continue
    for f in files:
        ext = os.path.splitext(f)[1].lower()
        if ext in extensions:
            fn_clean = normalizar(os.path.splitext(f)[0])
            existing_files[fn_clean] = os.path.join(root, f)

# Analisar faixas da playlist
playlist_files = []
for root, dirs, files in os.walk(target):
    for f in files:
        ext = os.path.splitext(f)[1].lower()
        if ext in extensions:
            playlist_files.append(os.path.join(root, f))

playlist_files.sort()
total = len(playlist_files)
print(f"  📊 Total de faixas na playlist: {total}\n")

# Gerar arquivo M3U
m3u_filename = os.path.join(playlists_dir, f"{playlist_name.strip()}.m3u")
m3u_lines = ["#EXTM3U\n"]

decisoes = [] # (fpath, fname, status, genero_destino, motivo)
dest_counts = {}

for fpath in playlist_files:
    fname = os.path.basename(fpath)
    fn_clean = normalizar(os.path.splitext(fname)[0])

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

    # Linha M3U
    m3u_lines.append(f"#EXTINF:-1,{fname}\n{fname}\n")

    # Checar se já existe em outra pasta da biblioteca
    if fn_clean in existing_files:
        dup_path = existing_files[fn_clean]
        dup_folder = os.path.basename(os.path.dirname(dup_path))
        decisoes.append((fpath, fname, 'DUPLICATA', dup_folder, f"já existe em {dup_folder}/"))
        dest_counts['DUPLICATA'] = dest_counts.get('DUPLICATA', 0) + 1
        continue

    # Classificar gênero
    search_text = f"{fn_clean} {artist_tag} {title_tag} {genre_tag}"
    matched_genre = None
    match_reason = ""

    for kw, target_g in alias_to_genre.items():
        if kw and kw in search_text:
            matched_genre = target_g
            match_reason = f"palavra/artista '{kw}'"
            break

    if not matched_genre:
        matched_genre = "_Outros"
        match_reason = "não identificado automaticamente"

    decisoes.append((fpath, fname, 'MOVER', matched_genre, match_reason))
    dest_counts[matched_genre] = dest_counts.get(matched_genre, 0) + 1

# Exibir resumo na tela
print("━━━ 📊 RESUMO DE DESTINO ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
for dest, count in sorted(dest_counts.items(), key=lambda x: x[1], reverse=True):
    pct = count * 100 // total if total > 0 else 0
    bar = "█" * (pct // 2)
    icon = "🗑️ " if dest == 'DUPLICATA' else "📂 "
    print(f"  {icon}{dest:<20} {count:>3} faixas ({pct:>2}%)  {bar}")

print("\n━━━ 📝 AMOSTRA DE DECISÕES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
for fpath, fname, status, dest, motivo in decisoes[:15]:
    if status == 'DUPLICATA':
        print(f"  🗑️  \033[1;33m[DUPLICATA]\033[0m {fname[:45]} → \033[2m{motivo}\033[0m")
    else:
        print(f"  ➡️  \033[0;32m[{dest}]\033[0m {fname[:45]} → \033[2m({motivo})\033[0m")

if len(decisoes) > 15:
    print(f"\n  ... e mais {len(decisoes)-15} faixas detalhadas no log")

print()

# Salvar M3U
with open(m3u_filename, 'w', encoding='utf-8') as f:
    f.writelines(m3u_lines)
print(f"  💾 Backup da playlist salvo em: \033[1m{m3u_filename}\033[0m\n")

# Executar se habilitado
if executar:
    print("\033[1;36m━━━ 🚀 PROCESSANDO ARQUIVOS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n")
    moved = 0
    dups_handled = 0
    for fpath, fname, status, dest, motivo in decisoes:
        if status == 'DUPLICATA':
            # Remove a cópia redundante da playlist
            os.remove(fpath)
            dups_handled += 1
        else:
            dest_dir = os.path.join(library_root, dest)
            os.makedirs(dest_dir, exist_ok=True)
            dest_file = os.path.join(dest_dir, fname)
            if os.path.exists(dest_file):
                base, ext = os.path.splitext(fname)
                dest_file = os.path.join(dest_dir, f"{base}_pl{ext}")
            shutil.move(fpath, dest_file)
            moved += 1
    
    # Remover pasta se vazia
    try:
        os.rmdir(target)
        print(f"  ✨ Pasta original da playlist removida com sucesso (vazia).")
    except Exception:
        pass

    print(f"  ✅ {moved} faixas movidas para os gêneros correspondentes.")
    print(f"  🗑️  {dups_handled} duplicatas redundantes eliminadas.")
    print()
else:
    print("  ℹ️  Modo dry-run concluído. Nenhuma faixa foi movida ou apagada.")
    print("  Use \033[1m--executar\033[0m para aplicar.\n")

# Salvar log
with open(log_file, 'w', encoding='utf-8') as f:
    f.write(f"DESMONTAR PLAYLIST — {target}\n")
    f.write(f"Playlist M3U: {m3u_filename}\n")
    f.write(f"Modo: {'EXECUTAR' if executar else 'DRY-RUN'}\n\n")
    for fpath, fname, status, dest, motivo in decisoes:
        f.write(f"[{status}] {fname} -> {dest} ({motivo})\n")

print(f"  💾 Log salvo em: {log_file}")
print()
PYEOF

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"

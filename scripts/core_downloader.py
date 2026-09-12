#!/usr/bin/env python3
"""
scripts/core_downloader.py
Mecanismo central para verificação de acervo local, download de estúdio
via Spotify (spotdl) / YouTube (yt-dlp) e geração de playlists para DJ.
"""

import os
import sys
import time
import argparse
import subprocess
import unicodedata
from pathlib import Path
from datetime import datetime
import mutagen
from mutagen.easyid3 import EasyID3
from mutagen.id3 import ID3NoHeaderError

# Garante saída em tempo real no terminal/logs
try:
    sys.stdout.reconfigure(line_buffering=True)
except Exception:
    pass

LOCAL_ROOT = Path(os.path.expanduser('~/Documents/DjZeze'))
WORKFLOW_ROOT = Path('/Users/eliezer/Desktop/dj-workflow')

def norm(s: str) -> str:
    if not s:
        return ''
    return ''.join(
        c for c in unicodedata.normalize('NFD', s.lower())
        if unicodedata.category(c) != 'Mn'
    )

def safe_tag_audio(filepath: Path, artist: str = None, title: str = None, genre: str = "Samba"):
    """Escreve tags ID3 limpas."""
    try:
        try:
            audio = EasyID3(filepath)
        except ID3NoHeaderError:
            audio = mutagen.File(filepath, easy=True)
            if audio is None:
                return
            audio.add_tags()
        if artist:
            audio['artist'] = artist
        if title:
            audio['title'] = title
        if genre:
            audio['genre'] = genre
        audio.save()
    except Exception:
        pass

def index_local_library() -> list:
    """Indexa todo o acervo local lendo tags ID3 e nomes normalizados."""
    print("🔍 Indexando acervo local em ~/Documents/DjZeze...")
    library = []
    if not LOCAL_ROOT.exists():
        return library

    for root, dirs, files in os.walk(LOCAL_ROOT):
        # Pula a pasta _Inbox para não considerar temporários anteriores
        if '_Inbox' in root or '_Quarentena' in root:
            continue
        for f in files:
            if not f.startswith('.') and not f.startswith('._') and f.lower().endswith(('.mp3', '.m4a', '.wav', '.flac')):
                fp = Path(root) / f
                title = ''
                artist = ''
                if f.lower().endswith('.mp3'):
                    try:
                        audio = EasyID3(fp)
                        title = audio.get('title', [''])[0]
                        artist = audio.get('artist', [''])[0]
                    except Exception:
                        pass
                
                rel = fp.relative_to(LOCAL_ROOT)
                blob = norm(f"{f} {title} {artist} {rel}")
                library.append({
                    'path': fp,
                    'relpath': str(rel),
                    'filename': f,
                    'title': title,
                    'artist': artist,
                    'blob': blob
                })
    print(f"✅ Total de {len(library)} faixas indexadas no acervo local.")
    return library

def search_in_library(query: str, library: list) -> Path:
    """Busca inteligente de faixa no acervo local."""
    clean_q = norm(query)
    # Separar artista e título caso haja hífen
    if ' - ' in query:
        parts = query.split(' - ', 1)
        artist_part = norm(parts[0])
        title_part = norm(parts[1])
    else:
        artist_part = ''
        title_part = clean_q

    # Remover parênteses comuns de busca (ex: "ao vivo", "versão")
    title_words = [w for w in title_part.split() if len(w) > 2 and w not in ['com', 'para', 'versao', 'vivo']]
    artist_words = [w for w in artist_part.split() if len(w) > 2 and w not in ['com', 'part', 'feat', 'banda', 'grupo']]

    for item in library:
        blob = item['blob']
        # Se todas as palavras-chave do título baterem
        if title_words and all(w in blob for w in title_words):
            # Se tiver palavras de artista, pelo menos uma deve bater ou o título ser muito específico
            if not artist_words or any(aw in blob for aw in artist_words):
                return item['path']
    return None

def download_track(query: str, out_dir: Path) -> Path:
    """Baixa faixa via spotdl (prioridade estúdio) com fallback para yt-dlp."""
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"\n⬇️  Processando download: '{query}'")

    # Mapeamento de termos para faixas com nomes populares divergentes
    search_query = query
    if "Batatinha - Diploma de Pobre" in query:
        search_query = "Batatinha - Direito de Sambar"
    elif "Marcelo D2 & Arlindo Cruz - Pode Acreditar" in query:
        search_query = "Marcelo D2 - Pode Acreditar Meu Laia Laia"

    # Captura fotos dos arquivos antes da tentativa
    files_before = {p.name for p in out_dir.iterdir() if p.is_file()}

    # Tentativa 1: spotdl (garante estúdio 320kbps + metadados Spotify)
    try:
        print("  -> Buscando catálogo oficial do Spotify (spotdl 320kbps)...")
        cmd_spot = [
            sys.executable, "-m", "spotdl",
            "--output", str(out_dir / "{artist} - {title}.{output-ext}"),
            "--format", "mp3",
            "--bitrate", "320k",
            "download", search_query
        ]
        res = subprocess.run(cmd_spot, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=45)
        new_files = [
            p for p in out_dir.iterdir()
            if p.is_file() and p.name not in files_before and p.suffix.lower() == '.mp3' and not p.name.startswith('.')
        ]
        if new_files:
            newest = max(new_files, key=lambda p: p.stat().st_mtime)
            print(f"  ✅ Baixado com sucesso via Spotify: {newest.name}")
            return newest
    except Exception as e:
        print(f"  [i] spotdl falhou ou timeout ({e}), tentando yt-dlp...")

    # Tentativa 2: yt-dlp oficial com áudio de alta fidelidade
    try:
        print("  -> Buscando áudio de alta fidelidade via yt-dlp...")
        yt_search = f"ytsearch3:{search_query} audio oficial"
        
        # Formata o nome de saída padronizado baseado na query
        if ' - ' in query:
            clean_name = query.replace('/', '-').replace(':', '-')
        else:
            clean_name = "%(title)s"

        cmd_yt = [
            sys.executable, "-m", "yt_dlp",
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", "320K",
            "--ffmpeg-location", "/opt/homebrew/bin/ffmpeg",
            "--match-filter", "duration >= 60 & duration <= 540",
            "--max-downloads", "1",
            "--output", str(out_dir / f"{clean_name}.%(ext)s"),
            "--no-playlist",
            yt_search
        ]
        res_yt = subprocess.run(cmd_yt, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=90)
        new_yt_files = [
            p for p in out_dir.iterdir()
            if p.is_file() and p.name not in files_before and p.suffix.lower() == '.mp3' and not p.name.startswith('.')
        ]
        if new_yt_files:
            newest = max(new_yt_files, key=lambda p: p.stat().st_mtime)
            print(f"  ✅ Baixado com sucesso via yt-dlp: {newest.name}")
            return newest
    except Exception as e:
        print(f"  ❌ Erro ao baixar '{query}' via yt-dlp: {e}")

    return None

def main():
    parser = argparse.ArgumentParser(description="DJ Workflow - Downloader & Set Builder")
    parser.add_argument("--lista", type=str, help="Caminho do arquivo de texto com a lista de faixas")
    parser.add_argument("--query", type=str, help="Busca ou link de faixa única")
    parser.add_argument("--batch-name", type=str, default=None, help="Nome da subpasta em _Inbox")
    parser.add_argument("--playlist-name", type=str, default="Set-Samba-Salvador", help="Nome do arquivo .m3u gerado")
    args = parser.parse_args()

    inbox_root = LOCAL_ROOT / "_Inbox"
    inbox_root.mkdir(parents=True, exist_ok=True)
    existing_inboxes = [d for d in inbox_root.iterdir() if d.is_dir() and 'set-samba-salvador' in d.name]
    if existing_inboxes and not args.batch_name:
        inbox_dir = sorted(existing_inboxes)[-1]
    else:
        date_str = datetime.now().strftime("%Y-%m-%d")
        batch_folder_name = args.batch_name or f"{date_str}-set-samba-salvador"
        inbox_dir = inbox_root / batch_folder_name
    inbox_dir.mkdir(parents=True, exist_ok=True)

    library = index_local_library()

    queries = []
    if args.lista:
        p_lista = Path(args.lista)
        if not p_lista.is_absolute():
            p_lista = WORKFLOW_ROOT / p_lista
        with open(p_lista, 'r', encoding='utf-8') as f:
            for line in f:
                l = line.strip()
                if l and not l.startswith('#'):
                    queries.append(l)
    elif args.query:
        queries.append(args.query.strip())
    else:
        print("Uso: core_downloader.py --lista <arquivo.txt> ou --query '<musica>'")
        sys.exit(1)

    print(f"\n📋 Analisando {len(queries)} faixas solicitadas para o set...")

    already_in_library = []
    already_in_inbox = []
    to_download = []

    for q in queries:
        found_path = search_in_library(q, library)
        if found_path:
            already_in_library.append((q, found_path))
            continue

        # Verifica se a faixa já foi baixada anteriormente no inbox
        inbox_match = None
        q_check = q
        if "Batatinha - Diploma de Pobre" in q:
            q_check = "Batatinha - Direito de Sambar"
        elif "Marcelo D2 & Arlindo Cruz - Pode Acreditar" in q:
            q_check = "Marcelo D2 - Pode Acreditar"
        parts = q_check.split(' - ', 1) if ' - ' in q_check else ['', q_check]
        tit_words = [w for w in norm(parts[1]).split() if len(w) > 2 and w not in ['com', 'para', 'versao', 'vivo']]
        art_words = [w for w in norm(parts[0]).split() if len(w) > 2 and w not in ['com', 'part', 'feat']]
        for f in inbox_dir.iterdir():
            if f.is_file() and f.suffix.lower() == '.mp3' and not f.name.startswith('.'):
                fn = norm(f.name)
                if tit_words and all(w in fn for w in tit_words):
                    if not art_words or any(aw in fn for aw in art_words):
                        inbox_match = f
                        break

        if inbox_match:
            already_in_inbox.append((q, inbox_match))
        else:
            to_download.append(q)

    print(f"\n━━━ 📊 BALANÇO DE ACERVO ━━━━━━━━━━━━━━━━━━━━")
    print(f"  ✅ Já presentes na sua biblioteca: {len(already_in_library)} faixas")
    print(f"  📂 Já baixadas no Inbox:           {len(already_in_inbox)} faixas")
    print(f"  ⬇️  Restantes para download:        {len(to_download)} faixas")
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

    for q, p in already_in_library:
        rel = p.relative_to(LOCAL_ROOT)
        print(f"  [LOCAL] {q} -> {rel}")

    for q, p in already_in_inbox:
        print(f"  [INBOX] {q} -> {p.name}")

    downloaded_paths = []
    if to_download:
        print(f"\nIniciando download de {len(to_download)} faixas faltantes para:")
        print(f"📁 {inbox_dir}\n")

        for idx, q in enumerate(to_download, 1):
            print(f"[{idx}/{len(to_download)}]", end=" ")
            dl_path = download_track(q, inbox_dir)
            if dl_path:
                # Taguear gênero padrão Samba/Brasilidades
                safe_tag_audio(dl_path, genre="Samba")
                downloaded_paths.append((q, dl_path))
            else:
                print(f"  [!] Falha no download de: {q}")

    # Gerar Playlist .m3u
    playlist_dir = WORKFLOW_ROOT / "listas" / "playlists"
    playlist_dir.mkdir(parents=True, exist_ok=True)
    m3u_path = playlist_dir / f"{args.playlist_name}.m3u"

    print(f"\n📝 Gerando playlist unificada para o djay Pro em: {m3u_path}")
    with open(m3u_path, 'w', encoding='utf-8') as f:
        f.write("#EXTM3U\n")
        f.write(f"#PLAYLIST: {args.playlist_name}\n\n")

        # Adicionar as faixas locais
        for q, p in already_in_library:
            f.write(f"#EXTINF:-1,{q}\n")
            f.write(f"{p}\n")

        # Adicionar as faixas já existentes no inbox
        for q, p in already_in_inbox:
            f.write(f"#EXTINF:-1,{q}\n")
            f.write(f"{p}\n")

        # Adicionar as novas faixas baixadas
        for q, p in downloaded_paths:
            f.write(f"#EXTINF:-1,{q}\n")
            f.write(f"{p}\n")

    # Também salvar uma cópia no inbox da gig
    try:
        shutil_dst = inbox_dir / f"{args.playlist_name}.m3u"
        import shutil
        shutil.copy2(m3u_path, shutil_dst)
    except Exception:
        pass

    total_set = len(already_in_library) + len(already_in_inbox) + len(downloaded_paths)
    print(f"\n🎉 SET PRONTO! Total de {total_set} faixas incluídas na playlist.")
    print(f"  • {len(already_in_library)} faixas do seu acervo oficial")
    print(f"  • {len(already_in_inbox) + len(downloaded_paths)} faixas em alta resolução no _Inbox")
    print(f"  • Playlist salva: {m3u_path}")

if __name__ == '__main__':
    main()

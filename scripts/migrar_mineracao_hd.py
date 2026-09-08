#!/usr/bin/env python3
"""
scripts/migrar_mineracao_hd.py
Executa a mineração seletiva das pastas do acervo 'Musicas Eliezer' no HD externo,
organizando na biblioteca oficial (~/Documents/DjZeze) e removendo com segurança
as pastas correspondentes do HD externo conforme aprovado pelo usuário.
"""

import os
import shutil
import unicodedata
from pathlib import Path
import mutagen
from mutagen.easyid3 import EasyID3
from mutagen.id3 import ID3NoHeaderError

HD_ROOT = Path('/Volumes/DEUZBENZA/Music/Musicas Eliezer')
LOCAL_ROOT = Path(os.path.expanduser('~/Documents/DjZeze'))
WORKFLOW_ROOT = Path('/Users/eliezer/Desktop/dj-workflow')

def norm(s: str) -> str:
    """Normaliza texto para comparações insensíveis a acentos e casing."""
    return ''.join(
        c for c in unicodedata.normalize('NFD', s.lower())
        if unicodedata.category(c) != 'Mn'
    )

def safe_tag_genre(filepath: Path, genre: str):
    """Atualiza a tag de gênero ID3 de forma segura."""
    try:
        try:
            audio = EasyID3(filepath)
        except ID3NoHeaderError:
            audio = mutagen.File(filepath, easy=True)
            if audio is None:
                return
            audio.add_tags()
        audio['genre'] = genre
        audio.save()
    except Exception as e:
        # Não falhar caso tags não possam ser escritas
        pass

def safe_copy_file(src: Path, dst: Path):
    """Copia arquivo preservando metadados e tratando erros."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

def step1_sany_pitbull():
    print("\n--- [Passo 1] PENDRIVE DO SANY PITBULL (25 Relíquias) ---")
    src_dir = HD_ROOT / 'PENDRIVE DO SANY PITBULL'
    dst_dir = LOCAL_ROOT / 'Funk' / 'Sany Pitbull - Relíquias'
    dst_dir.mkdir(parents=True, exist_ok=True)

    target_files = [
        "Catra - Bonde do Justo ( ao vivo).mp3",
        "Catra e Sany Pitbull - Cobra Cega-Garotos maneiros (ao vivo) Salgueiro.mp3",
        "Cidinho e Doca - Meus Direitos.mp3",
        "Cidinho - Rap CDD Deus 2003.mp3",
        "Cadu e Dida - Rap do Morro do Macaco ZZ.mp3",
        "AZUL E CEBOLINHA - PAPA TUDO.mp3",
        "Abertura Camila Burana.mp3",
        "Catra - Se vier mandado ( Original).mp3",
        "Catra - Caput Fusca (cruel).mp3",
        "Catra e Dilsinho - Rap do Bateou.mp3",
        "Catra e Duda - Em uma casa na Favela.mp3",
        "Duda e Catra - Liquido do Amor ao vivo.mp3",
        "Duda do Dorel - Rap Fazendinha ao vivo Furmiga.mp3",
        "GARRINCHA E JUNINHO - RAP SANTA CRUZ.mp3",
        "Geleia - Rap Vidigal.mp3",
        "Julaine - Rap Fazenda de Inhauma.mp3",
        "MARCIO E WILLIAN - PANTANAL.mp3",
        "Doctors Mcs - Tik Tak.mp3",
        "Danda e Tafarel - Rap Festival Tambor.mp3",
        "RAP DA MORENA (WILLIAN E DUDA).mp3",
        "Marcio do Cacuia - Rap Guerreiro da Paz ZZ.mp3",
        "Mascote - Rap Daniele Perez ( Ao Vivo ).mp3",
        "Pixote - Cidade Alta.mp3",
        "Nenem - Rap Rocinha 2.mp3",
        "Tati - Cachorra 2000.mp3",
    ]

    copied = 0
    # Iterar sobre o diretório usando scandir para ler os nomes exatos do FS
    entries_map = {}
    for entry in os.scandir(src_dir):
        if entry.is_file() and not entry.name.startswith('.'):
            entries_map[norm(entry.name)] = entry

    for target_name in target_files:
        n_target = norm(target_name)
        if n_target in entries_map:
            entry = entries_map[n_target]
            src_file = Path(entry.path)
            dst_file = dst_dir / target_name
            print(f"  -> Copiando: {target_name}")
            safe_copy_file(src_file, dst_file)
            safe_tag_genre(dst_file, "Funk")
            copied += 1
        else:
            print(f"  [!] Alvo não encontrado: {target_name}")

    print(f"Total copiado Sany Pitbull: {copied}/25 faixas.")
    assert copied >= 23, f"Esperado pelo menos 23 faixas, copiado {copied}"

    print(f"Removendo pasta de backup: {src_dir}")
    shutil.rmtree(src_dir, ignore_errors=True)
    print("Pasta PENDRIVE DO SANY PITBULL removida com sucesso do HD.")

def step2_forro_lucas():
    print("\n--- [Passo 2] Forro Lucas (~110 Maiores Clássicos em Álbuns) ---")
    src_root = HD_ROOT / 'Forro Lucas'
    dst_root = LOCAL_ROOT / 'Brasilidades' / 'Forró'
    dst_root.mkdir(parents=True, exist_ok=True)

    folder_map = {
        'Seleção Flávio José As Melhores': 'Flávio José - As Melhores',
        'Flavio José': 'Flávio José - Seleção de Sucessos',
        'Falamansa - As Sanfonas Do Rei - www.musicasparabaixar.org': 'Falamansa - As Sanfonas Do Rei',
        'Adelmario Coelho - 15 Anos de Puro Forro¦ü': 'Adelmário Coelho - 15 Anos de Puro Forró',
        'LIMÃO COM MEL AS MELHORES - M.A DOWNLOAD': 'Limão com Mel - As Melhores',
        'Magnificos - Cd Super Seleção': 'Banda Magníficos - Super Seleção',
        'Seleção de Calcinha Preta': 'Calcinha Preta - Seleção',
    }

    # Indexar diretórios reais
    actual_dirs = {}
    for entry in os.scandir(src_root):
        if entry.is_dir() and not entry.name.startswith('.'):
            actual_dirs[norm(entry.name)] = entry

    total_copied = 0
    for folder_key, target_folder_name in folder_map.items():
        n_key = norm(folder_key)
        if n_key in actual_dirs:
            entry = actual_dirs[n_key]
            src_folder = Path(entry.path)
            dst_folder = dst_root / target_folder_name
            dst_folder.mkdir(parents=True, exist_ok=True)
            print(f"\n* Processando álbum: {target_folder_name}")
            folder_copied = 0
            for item in os.scandir(src_folder):
                if item.is_file() and not item.name.startswith('.') and item.name.lower().endswith(('.mp3', '.m4a', '.wav', '.flac')):
                    src_file = Path(item.path)
                    dst_file = dst_folder / item.name
                    safe_copy_file(src_file, dst_file)
                    safe_tag_genre(dst_file, "Forró")
                    folder_copied += 1
                elif item.is_file() and not item.name.startswith('.') and item.name.lower().endswith(('.jpg', '.png', '.jpeg')):
                    safe_copy_file(Path(item.path), dst_folder / item.name)
            print(f"  -> {folder_copied} faixas copiadas para {target_folder_name}")
            total_copied += folder_copied
        else:
            print(f"  [!] Pasta não encontrada para a chave: {folder_key}")

    print(f"\nTotal de faixas de Forró migradas: {total_copied}")
    assert total_copied >= 100, f"Esperado pelo menos 100 faixas de forró, copiado {total_copied}"

    print(f"Removendo pasta de backup: {src_root}")
    shutil.rmtree(src_root, ignore_errors=True)
    print("Pasta Forro Lucas removida com sucesso do HD.")

def step3_monster_records():
    print("\n--- [Passo 3] Monster Records (Set de DJ Preservado) ---")
    src_dir = HD_ROOT / 'Monster Records'
    dst_dir = LOCAL_ROOT / '_Sets' / 'Monster Records Set'
    dst_dir.mkdir(parents=True, exist_ok=True)

    playlist_dir = WORKFLOW_ROOT / 'listas' / 'playlists'
    playlist_dir.mkdir(parents=True, exist_ok=True)
    playlist_file = playlist_dir / 'Monster Records.m3u'

    audio_files = []
    for item in sorted(os.scandir(src_dir), key=lambda x: x.name):
        if item.is_file() and not item.name.startswith('.'):
            src_file = Path(item.path)
            dst_file = dst_dir / item.name
            safe_copy_file(src_file, dst_file)
            if item.name.lower().endswith(('.mp3', '.wav', '.m4a', '.flac')):
                audio_files.append(item.name)

    # Gerar a playlist .m3u
    with open(playlist_file, 'w', encoding='utf-8') as f:
        f.write("#EXTM3U\n")
        f.write("#PLAYLIST: Monster Records Set\n\n")
        for audio in audio_files:
            f.write(f"#EXTINF:-1,{audio}\n")
            f.write(f"{audio}\n")

    # Também salvar uma cópia da playlist dentro do próprio diretório do set
    shutil.copy2(playlist_file, dst_dir / 'Monster Records.m3u')

    print(f"Set copiado com {len(audio_files)} faixas de áudio.")
    print(f"Playlist gerada em: {playlist_file}")

    print(f"Removendo pasta de backup: {src_dir}")
    shutil.rmtree(src_dir, ignore_errors=True)
    print("Pasta Monster Records removida com sucesso do HD.")

def step4_musicas_tarta():
    print("\n--- [Passo 4] Musicas Tarta (Autorais e Sets de DJ Tarta) ---")
    src_dir = HD_ROOT / 'Musicas Tarta'
    dst_autorais = LOCAL_ROOT / '_Autorais' / 'DJ Tarta'
    dst_sets = LOCAL_ROOT / '_Sets' / 'DJ Tarta'
    dst_autorais.mkdir(parents=True, exist_ok=True)
    dst_sets.mkdir(parents=True, exist_ok=True)

    # Identificar mixes que vão para _Sets
    mix_keywords = ['tarta mix', 'minimix', 'immortal tsunami']

    count_autorais = 0
    count_sets = 0

    for root, dirs, files in os.walk(src_dir):
        for f in files:
            if f.startswith('.') or f.lower().endswith(('.ini', '.db')):
                continue
            src_file = Path(root) / f
            n_f = norm(f)

            if any(k in n_f for k in mix_keywords):
                dst_file = dst_sets / f
                safe_copy_file(src_file, dst_file)
                count_sets += 1
                print(f"  -> Set gravado: {f} -> _Sets/DJ Tarta/")
            else:
                dst_file = dst_autorais / f
                safe_copy_file(src_file, dst_file)
                count_autorais += 1
                print(f"  -> Autoral/Remix: {f} -> _Autorais/DJ Tarta/")

    print(f"Total Tarta migrado: {count_sets} sets e {count_autorais} autorais/remixes.")
    assert (count_sets + count_autorais) >= 20, "Erro na cópia dos arquivos do Tarta."

    print(f"Removendo pasta de backup: {src_dir}")
    shutil.rmtree(src_dir, ignore_errors=True)
    print("Pasta Musicas Tarta removida com sucesso do HD.")

def step5_bonus_folders():
    print("\n--- [Passo 5] Pastas Bônus (Baile da Santinha, Gallant, Know No Better) ---")

    # 1. BAILE DA SANTINHA
    santinha_candidates = [d for d in os.scandir(HD_ROOT) if 'santinha' in norm(d.name)]
    if santinha_candidates:
        src_santinha = Path(santinha_candidates[0].path)
        dst_santinha = LOCAL_ROOT / 'Pagodão' / 'Léo Santana - Baile da Santinha (Ao Vivo)'
        dst_santinha.mkdir(parents=True, exist_ok=True)
        print(f"* Migrando Baile da Santinha: {src_santinha.name}")
        c = 0
        for item in os.scandir(src_santinha):
            if item.is_file() and not item.name.startswith('.') and item.name.lower().endswith(('.mp3', '.wav', '.m4a')):
                safe_copy_file(Path(item.path), dst_santinha / item.name)
                safe_tag_genre(dst_santinha / item.name, "Pagodão")
                c += 1
        print(f"  -> {c} faixas migradas para Pagodão.")
        shutil.rmtree(src_santinha, ignore_errors=True)
        print("  -> Pasta Baile da Santinha removida do backup.")

    # 2. Gallant - Ology
    gallant_candidates = [d for d in os.scandir(HD_ROOT) if 'gallant' in norm(d.name)]
    if gallant_candidates:
        src_gallant = Path(gallant_candidates[0].path)
        dst_gallant = LOCAL_ROOT / 'Pop-World Music' / 'Gallant - Ology (2016)'
        dst_gallant.mkdir(parents=True, exist_ok=True)
        print(f"* Migrando Gallant - Ology: {src_gallant.name}")
        c = 0
        for root, dirs, files in os.walk(src_gallant):
            for f in files:
                if not f.startswith('.'):
                    src_f = Path(root) / f
                    dst_f = dst_gallant / f
                    safe_copy_file(src_f, dst_f)
                    if f.lower().endswith(('.mp3', '.m4a', '.flac')):
                        safe_tag_genre(dst_f, "Pop-World Music")
                        c += 1
        print(f"  -> {c} faixas migradas para Pop-World Music.")
        shutil.rmtree(src_gallant, ignore_errors=True)
        print("  -> Pasta Gallant removida do backup.")

    # 3. Know No Better Remixes
    know_candidates = [d for d in os.scandir(HD_ROOT) if 'know no better' in norm(d.name)]
    if know_candidates:
        src_know = Path(know_candidates[0].path)
        dst_know = LOCAL_ROOT / 'Pop-World Music' / 'Major Lazer - Know No Better (Full Flex Remixes)'
        dst_know.mkdir(parents=True, exist_ok=True)
        print(f"* Migrando Know No Better Remixes: {src_know.name}")
        c = 0
        for item in os.scandir(src_know):
            if item.is_file() and not item.name.startswith('.') and item.name.lower().endswith(('.mp3', '.wav', '.m4a')):
                safe_copy_file(Path(item.path), dst_know / item.name)
                safe_tag_genre(dst_know / item.name, "Pop-World Music")
                c += 1
        print(f"  -> {c} faixas migradas para Pop-World Music.")
        shutil.rmtree(src_know, ignore_errors=True)
        print("  -> Pasta Know No Better removida do backup.")

def step6_delete_obsolete_folders():
    print("\n--- [Passo 6] Exclusão Total de Pastas Obsoletas no Backup ---")
    obsolete_keywords = ['the best halloween', 'pioneerdj', 'festa claudinha']

    for entry in os.scandir(HD_ROOT):
        if entry.is_dir():
            n_name = norm(entry.name)
            for kw in obsolete_keywords:
                if kw in n_name:
                    print(f"Excluindo pasta obsoleta: {entry.name}")
                    shutil.rmtree(entry.path, ignore_errors=True)
                    print(f"  -> Removida: {entry.name}")
                    break

def main():
    print("Iniciando execução da mineração e limpeza do backup no HD externo...")
    step1_sany_pitbull()
    step2_forro_lucas()
    step3_monster_records()
    step4_musicas_tarta()
    step5_bonus_folders()
    step6_delete_obsolete_folders()
    print("\n=== Todas as migrações e exclusões foram concluídas com sucesso! ===")

if __name__ == '__main__':
    main()

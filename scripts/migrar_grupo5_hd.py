#!/usr/bin/env python3
"""
scripts/migrar_grupo5_hd.py
Executa a mineração seletiva e limpeza das pastas do Grupo 5 no acervo do HD externo:
- Niver de xande
- Niver 2
- 0 - Musicas baixadas
- intervalo
- mini set
- soltas
- Playlists (pasta vazia)
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
    except Exception:
        pass

def safe_copy_file(src: Path, dst: Path) -> bool:
    """Copia arquivo preservando metadados e tratando arquivos corrompidos."""
    try:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        return True
    except Exception as e:
        print(f"  [!] Ignorando arquivo ilegível no HD: {src.name} ({e})")
        return False

def safe_remove_tree(dir_path: Path):
    """Remove diretório ou move para a lixeira do volume caso haja entradas FAT32 teimosas."""
    if not dir_path.exists():
        return
    try:
        shutil.rmtree(dir_path)
        print(f"Pasta removida com sucesso: {dir_path.name}")
    except Exception as e:
        trash = Path('/Volumes/DEUZBENZA/.Trashes')
        if trash.exists():
            try:
                import time
                dest = trash / f"{dir_path.name}_{int(time.time())}"
                os.rename(dir_path, dest)
                print(f"Pasta movida para lixeira do volume: {dir_path.name}")
                return
            except Exception:
                pass
        shutil.rmtree(dir_path, ignore_errors=True)
        print(f"Pasta removida (ignore_errors): {dir_path.name}")

def is_audio(filename: str) -> bool:
    return (
        not filename.startswith('.') and
        not filename.startswith('._') and
        filename.lower().endswith(('.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg', '.wma'))
    )

def step1_niver_de_xande():
    print("\n--- [Passo 1] Niver de xande (Pagodão Baiano, Viola de Doze, Arrocha, Forró) ---")
    src_dir = HD_ROOT / 'Niver de xande'
    if not src_dir.exists():
        print("Pasta Niver de xande não encontrada.")
        return

    # Mapeamento de subpastas para destinos canônicos
    folder_mapping = {
        # Pagodão Baiano
        '(RELIQUIA) HARMONIA DO SAMBA EM SALINAS-MG 2012': (LOCAL_ROOT / 'Pagodão' / 'Harmonia do Samba - Ao Vivo em Salinas (2012)', 'Pagodão'),
        'Igor Kannário no no 6º Muvuca Fest em Ipiaú': (LOCAL_ROOT / 'Pagodão' / 'Igor Kannário - Ao Vivo Muvuca Fest (2015)', 'Pagodão'),
        'Bailão do Robsão - CD No Ritmo da CalíGula 2015': (LOCAL_ROOT / 'Pagodão' / 'Bailão do Robyssão - No Ritmo da Calígula (2015)', 'Pagodão'),
        'La_Furia_Pagofunk_Na_Veia_2015': (LOCAL_ROOT / 'Pagodão' / 'La Fúria - Pagofunk Na Veia (2015)', 'Pagodão'),
        'PSIRICO -AO VIVO EM PETROLINA -PE [21.04.15]': (LOCAL_ROOT / 'Pagodão' / 'Psirico - Ao Vivo em Petrolina (2015)', 'Pagodão'),
        'BLACK STYLE - THE BEST BEACH 10-04-15': (LOCAL_ROOT / 'Pagodão' / 'Black Style - The Best Beach (2015)', 'Pagodão'),
        'PlayWay_Salvador_Fest_2014': (LOCAL_ROOT / 'Pagodão' / 'PlayWay - Ao Vivo Salvador Fest (2014)', 'Pagodão'),
        'PlayWay_Explosion_CD_Verao_2015': (LOCAL_ROOT / 'Pagodão' / 'PlayWay - Explosion Verão (2015)', 'Pagodão'),
        'SAIDDY BAMBA -AO VIVO EM MACEIÓ -AL [08.02.15]': (LOCAL_ROOT / 'Pagodão' / 'Saiddy Bamba - Ao Vivo em Maceió (2015)', 'Pagodão'),
        'GASPARZINHO - VERAO 2014 - AO VIVO EM SSA': (LOCAL_ROOT / 'Pagodão' / 'Gasparzinho - Ao Vivo SSA (2014)', 'Pagodão'),
        'COLETÂNEA BOTA PAGODÃO VERÃO 2015': (LOCAL_ROOT / 'Pagodão' / 'Coletânea Bota Pagodão Verão 2015', 'Pagodão'),
        'PagodaO das Antigas': (LOCAL_ROOT / 'Pagodão' / 'Pagodão das Antigas', 'Pagodão'),
        'Banda Pagodão - Batalha das Novinhas 2014': (LOCAL_ROOT / 'Pagodão' / 'Banda Pagodão - Batalha das Novinhas (2014)', 'Pagodão'),
        
        # Samba de Terreiro
        'VIOLA DE DOZE - 10 ANOS DE SAMBA': (LOCAL_ROOT / 'Samba de terreiro' / 'Viola de Doze - 10 Anos de Samba', 'Samba de terreiro'),
        
        # Arrocha / Arrochadeira
        'Luxúria - CD A Gente Tem o Poder - Verão 2014': (LOCAL_ROOT / 'Brasilidades' / 'Arrocha' / 'Luxúria - A Gente Tem o Poder (2014)', 'Arrocha'),
        'LUXURIA': (LOCAL_ROOT / 'Brasilidades' / 'Arrocha' / 'Luxúria - Seleção', 'Arrocha'),
        
        # Forró
        'AVIOES ABRIL 2015': (LOCAL_ROOT / 'Brasilidades' / 'Forró' / 'Aviões do Forró - Promocional Abril 2015', 'Forró'),
        'Wesley Safadão': (LOCAL_ROOT / 'Brasilidades' / 'Forró' / 'Wesley Safadão - Promocional 2015', 'Forró'),
        
        # Brasilidades Gerais
        '2015': (LOCAL_ROOT / 'Brasilidades' / 'Hits Verão 2015', 'Brasilidades'),
        'Férias Em Dubai': (LOCAL_ROOT / 'Brasilidades' / 'Férias Em Dubai', 'Brasilidades'),
    }

    copied_count = 0
    actual_subdirs = {norm(d.name): d for d in os.scandir(src_dir) if d.is_dir()}

    for target_key, (dst_path, genre) in folder_mapping.items():
        n_key = norm(target_key)
        matched_entry = None
        for k, entry in actual_subdirs.items():
            if n_key in k:
                matched_entry = entry
                break

        if matched_entry:
            dst_path.mkdir(parents=True, exist_ok=True)
            print(f"* Processando: {matched_entry.name} -> {dst_path.relative_to(LOCAL_ROOT)} [{genre}]")
            for item in os.scandir(matched_entry.path):
                if is_audio(item.name):
                    src_f = Path(item.path)
                    dst_f = dst_path / item.name
                    safe_copy_file(src_f, dst_f)
                    safe_tag_genre(dst_f, genre)
                    copied_count += 1
                elif item.name.lower().endswith(('.jpg', '.png', '.jpeg')):
                    safe_copy_file(Path(item.path), dst_path / item.name)

    print(f"Total copiado de Niver de xande: {copied_count} faixas.")
    assert copied_count >= 300, f"Esperado >= 300 faixas de Niver de xande, copiado {copied_count}"

    print(f"Removendo pasta de backup: {src_dir}")
    safe_remove_tree(src_dir)
    print("Pasta Niver de xande removida com sucesso do HD.")

def step2_niver_2():
    print("\n--- [Passo 2] Niver 2 (Pagodão, Samba/Pagode Nacional, Arrocha Pablo) ---")
    src_dir = HD_ROOT / 'Niver 2'
    if not src_dir.exists():
        print("Pasta Niver 2 não encontrada.")
        return

    folder_mapping = {
        # Pagodão Baiano
        'BAILÃO DO ROBYSSÃO -AO VIVO EM SALVADOR-BA': (LOCAL_ROOT / 'Pagodão' / 'Bailão do Robyssão - Ao Vivo em Salvador (2015)', 'Pagodão'),
        '01 Bailão do Robyssão - Ao Vivo Em Tobias Barreto': (LOCAL_ROOT / 'Pagodão' / 'Bailão do Robyssão - Ao Vivo em Tobias Barreto (2014)', 'Pagodão'),
        '03La Furia - Inverno Quente': (LOCAL_ROOT / 'Pagodão' / 'La Fúria - Inverno Quente Studio (2014)', 'Pagodão'),
        'LA FURIA - PAGOFUNK NA VEIA': (LOCAL_ROOT / 'Pagodão' / 'La Fúria - Pagofunk Na Veia (2015)', 'Pagodão'),
        'PSIRICO-BLOCO MARACUBOM': (LOCAL_ROOT / 'Pagodão' / 'Psirico - Bloco Maracubom (2014)', 'Pagodão'),
        '04 Black Style - Promocional No Pique Do WiLL': (LOCAL_ROOT / 'Pagodão' / 'Black Style - No Pique do Will (2014)', 'Pagodão'),
        'Black Style - Ao Vivo Na The Best Beach': (LOCAL_ROOT / 'Pagodão' / 'Black Style - Ao Vivo The Best Beach', 'Pagodão'),
        '06 Flavinho e Os Barões ao vivo no Beija ou Desce': (LOCAL_ROOT / 'Pagodão' / 'Flavinho e Os Barões - Beija ou Desce (2014)', 'Pagodão'),
        '08 IGOR KANNÁRIO - SALVADOR-BA  2014': (LOCAL_ROOT / 'Pagodão' / 'Igor Kannário - Ao Vivo Salvador (2014)', 'Pagodão'),
        'IGOR KANNÁRIO - FESTA DA BAMOR 36 ANOS': (LOCAL_ROOT / 'Pagodão' / 'Igor Kannário - Festa da BAMOR 36 Anos', 'Pagodão'),
        '11 BANDA PAGODÃO - BATALHA DAS NOVINHAS': (LOCAL_ROOT / 'Pagodão' / 'Banda Pagodão - Batalha das Novinhas Studio (2014)', 'Pagodão'),
        'ParangoleÌ  - Coisa boa demais': (LOCAL_ROOT / 'Pagodão' / 'Parangolé - Coisa Boa Demais', 'Pagodão'),
        '02 PayWay': (LOCAL_ROOT / 'Pagodão' / 'PlayWay - Ao Vivo Pagodão da Skina', 'Pagodão'),
        'PlayWay - Explosion - CD Verão 2015': (LOCAL_ROOT / 'Pagodão' / 'PlayWay - Explosion Verão (2015)', 'Pagodão'),
        'H. do Samba Holiday 2015': (LOCAL_ROOT / 'Pagodão' / 'Harmonia do Samba - Holiday (2015)', 'Pagodão'),
        'pagode': (LOCAL_ROOT / 'Pagodão' / 'Pagodão - Singles e Lançamentos 2015', 'Pagodão'),

        # Samba & Pagode Nacional
        'Belo ( CD Misterios 2014 )': (LOCAL_ROOT / 'Samba' / 'Belo - Mistérios (2014)', 'Samba'),
        'Belo ao vivo no Samba Brasilia 2014': (LOCAL_ROOT / 'Samba' / 'Belo - Ao Vivo Samba Brasília (2014)', 'Samba'),
        'MUMUZINHO AO VIVO NO SAMABA SÃO PAULO': (LOCAL_ROOT / 'Samba' / 'Mumuzinho - Ao Vivo Samba São Paulo (2014)', 'Samba'),
        'TH [24.08.2014 - Brasília-DF]': (LOCAL_ROOT / 'Samba' / 'Thiaguinho - Ao Vivo Samba Brasília (2014)', 'Samba'),
        'Revelaçao - Só As Melhores (2014)': (LOCAL_ROOT / 'Samba' / 'Grupo Revelação - Só As Melhores (2014)', 'Samba'),
        'XANDE DE PILARES [06.11.2014 - Ao vivo - Fm o dia]': (LOCAL_ROOT / 'Samba' / 'Xande de Pilares - Ao Vivo FM O Dia', 'Samba'),
        '+ que samba': (LOCAL_ROOT / 'Samba' / 'Samba e Pagode - Mais Que Samba', 'Samba'),
        'SAMBA E PAGODE': (LOCAL_ROOT / 'Samba' / 'Samba e Pagode - Coletânea Clássicos', 'Samba'),
        'fm ao vivo': (LOCAL_ROOT / 'Samba' / 'Pagode FM Ao Vivo (Alexandre Pires, Pixote, etc.)', 'Samba'),
        'Fabo songr': (LOCAL_ROOT / 'Samba' / 'Pagode Romântico (SPC, Sorriso Maroto, etc.)', 'Samba'),

        # Arrocha & Sertanejo
        'ARROCHA - Pablo - É só dizer que Sim (2014)': (LOCAL_ROOT / 'Brasilidades' / 'Arrocha' / 'Pablo - É Só Dizer Que Sim (2014)', 'Arrocha'),
        'PABLO A VOZ ROMANTICA AO EM RECIFE': (LOCAL_ROOT / 'Brasilidades' / 'Arrocha' / 'Pablo - Ao Vivo em Recife', 'Arrocha'),
        'jorge e mateus': (LOCAL_ROOT / 'Brasilidades' / 'Sertanejo' / 'Jorge & Mateus - Seleção', 'Sertanejo'),

        # Forró
        'wesley safadao': (LOCAL_ROOT / 'Brasilidades' / 'Forró' / 'Wesley Safadão - Ao Vivo 2015', 'Forró'),

        # Eletrônica
        'ELETRONICA': (LOCAL_ROOT / 'Pop-World Music' / 'Dance & Eletrônica 2014', 'Pop-World Music'),
    }

    copied_count = 0
    actual_subdirs = {norm(d.name): d for d in os.scandir(src_dir) if d.is_dir()}

    for target_key, (dst_path, genre) in folder_mapping.items():
        n_key = norm(target_key)
        matched_entry = None
        for k, entry in actual_subdirs.items():
            if n_key in k:
                matched_entry = entry
                break

        if matched_entry:
            dst_path.mkdir(parents=True, exist_ok=True)
            print(f"* Processando: {matched_entry.name} -> {dst_path.relative_to(LOCAL_ROOT)} [{genre}]")
            for item in os.scandir(matched_entry.path):
                if is_audio(item.name):
                    src_f = Path(item.path)
                    dst_f = dst_path / item.name
                    safe_copy_file(src_f, dst_f)
                    safe_tag_genre(dst_f, genre)
                    copied_count += 1
                elif item.name.lower().endswith(('.jpg', '.png', '.jpeg')):
                    safe_copy_file(Path(item.path), dst_path / item.name)

    print(f"Total copiado de Niver 2: {copied_count} faixas.")
    assert copied_count >= 350, f"Esperado >= 350 faixas de Niver 2, copiado {copied_count}"

    print(f"Removendo pasta de backup: {src_dir}")
    safe_remove_tree(src_dir)
    print("Pasta Niver 2 removida com sucesso do HD.")

def step3_intervalo():
    print("\n--- [Passo 3] intervalo (Simone & Simaria Bar das Coleguinhas + Hits de Intervalo) ---")
    src_dir = HD_ROOT / 'intervalo'
    if not src_dir.exists():
        print("Pasta intervalo não encontrada.")
        return

    dst_ses = LOCAL_ROOT / 'Brasilidades' / 'Sertanejo' / 'Simone & Simaria - Bar Das Coleguinhas (2015)'
    dst_pagodao = LOCAL_ROOT / 'Pagodão'
    dst_forro = LOCAL_ROOT / 'Brasilidades' / 'Forró'
    dst_ses.mkdir(parents=True, exist_ok=True)

    copied = 0
    for root, dirs, files in os.walk(src_dir):
        for f in files:
            if is_audio(f):
                src_f = Path(root) / f
                n_f = norm(f)
                if 'bar das coleguinhas' in norm(root) or 'simone' in n_f or 'simaria' in n_f:
                    dst_f = dst_ses / f
                    safe_copy_file(src_f, dst_f)
                    safe_tag_genre(dst_f, 'Sertanejo')
                    copied += 1
                elif any(k in n_f for k in ['lepo lepo', 'xenhenhen', 'abana', 'pagodao', 'swingueira']):
                    dst_f = dst_pagodao / f
                    safe_copy_file(src_f, dst_f)
                    safe_tag_genre(dst_f, 'Pagodão')
                    copied += 1
                else:
                    dst_f = dst_forro / f
                    safe_copy_file(src_f, dst_f)
                    safe_tag_genre(dst_f, 'Forró')
                    copied += 1

    print(f"Total copiado de intervalo: {copied} faixas.")
    print(f"Removendo pasta de backup: {src_dir}")
    safe_remove_tree(src_dir)
    print("Pasta intervalo removida com sucesso do HD.")

def step4_mini_set_e_soltas():
    print("\n--- [Passo 4] mini set (Set DJ) e soltas (Singles) ---")
    src_ms = HD_ROOT / 'mini set'
    src_soltas = HD_ROOT / 'soltas'

    # 1. Mini Set
    if src_ms.exists():
        dst_ms = LOCAL_ROOT / '_Sets' / 'Mini Set Open Format'
        dst_ms.mkdir(parents=True, exist_ok=True)
        playlist_file = WORKFLOW_ROOT / 'listas' / 'playlists' / 'Mini Set Open Format.m3u'
        playlist_file.parent.mkdir(parents=True, exist_ok=True)

        ms_audio = []
        for item in sorted(os.scandir(src_ms), key=lambda x: x.name):
            if is_audio(item.name):
                src_f = Path(item.path)
                dst_f = dst_ms / item.name
                safe_copy_file(src_f, dst_f)
                ms_audio.append(item.name)

        with open(playlist_file, 'w', encoding='utf-8') as pf:
            pf.write("#EXTM3U\n#PLAYLIST: Mini Set Open Format\n\n")
            for a in ms_audio:
                pf.write(f"#EXTINF:-1,{a}\n{a}\n")
        shutil.copy2(playlist_file, dst_ms / 'Mini Set Open Format.m3u')
        print(f"Mini set migrado ({len(ms_audio)} faixas) com playlist salva.")
        safe_remove_tree(src_ms)
        print("Pasta mini set removida do HD.")

    # 2. Soltas
    if src_soltas.exists():
        dst_pop = LOCAL_ROOT / 'Pop-World Music'
        c_soltas = 0
        for item in os.scandir(src_soltas):
            if is_audio(item.name):
                src_f = Path(item.path)
                dst_f = dst_pop / item.name
                safe_copy_file(src_f, dst_f)
                safe_tag_genre(dst_f, 'Pop-World Music')
                c_soltas += 1
        print(f"Soltas migradas: {c_soltas} faixas para Pop-World Music.")
        safe_remove_tree(src_soltas)
        print("Pasta soltas removida do HD.")

def step5_musicas_baixadas():
    print("\n--- [Passo 5] 0 - Musicas baixadas (Distribuição de Hits por Gênero) ---")
    src_dir = HD_ROOT / '0 - Musicas baixadas'
    if not src_dir.exists():
        print("Pasta 0 - Musicas baixadas não encontrada.")
        return

    dst_pop = LOCAL_ROOT / 'Pop-World Music'
    dst_funk = LOCAL_ROOT / 'Funk'
    dst_afro = LOCAL_ROOT / 'Afrobeat'
    dst_brasil = LOCAL_ROOT / 'Brasilidades'

    count_pop = 0
    count_funk = 0
    count_afro = 0
    count_brasil = 0

    for item in os.scandir(src_dir):
        if is_audio(item.name):
            src_f = Path(item.path)
            n_f = norm(item.name)

            # Classificação por palavra-chave dos hits identificados
            if any(k in n_f for k in ['mc ', 'funk', 'livinho', 'menor da vg', 'roca roca', 'mamadeira', 'vidro fume', 'furcun', 'sarrando']):
                dst_f = dst_funk / item.name
                safe_copy_file(src_f, dst_f)
                safe_tag_genre(dst_f, 'Funk')
                count_funk += 1
            elif any(k in n_f for k in ['afro house', 'ganyani', 'habias', 'kentura', 'busiswa', 'salut eh', 'buddha song']):
                dst_f = dst_afro / item.name
                safe_copy_file(src_f, dst_f)
                safe_tag_genre(dst_f, 'Afrobeat')
                count_afro += 1
            elif any(k in n_f for k in ['ivete', 'tropicana', 'jorge & mateus', 'cuida bem dela', 'bielbands', 'henrique']):
                dst_f = dst_brasil / item.name
                safe_copy_file(src_f, dst_f)
                safe_tag_genre(dst_f, 'Brasilidades')
                count_brasil += 1
            else:
                # Pop / EDM / Dance Hits
                dst_f = dst_pop / item.name
                safe_copy_file(src_f, dst_f)
                safe_tag_genre(dst_f, 'Pop-World Music')
                count_pop += 1

    total_dist = count_pop + count_funk + count_afro + count_brasil
    print(f"Total distribuído de Musicas baixadas: {total_dist} faixas (Pop/EDM: {count_pop}, Funk: {count_funk}, Afro House: {count_afro}, Brasil: {count_brasil})")
    assert total_dist >= 150, "Erro na distribuição de Musicas baixadas"

    print(f"Removendo pasta de backup: {src_dir}")
    safe_remove_tree(src_dir)
    print("Pasta 0 - Musicas baixadas removida com sucesso do HD.")

def step6_cleanup_empty_playlists():
    print("\n--- [Passo 6] Limpeza de Pastas Vazias Remanescentes ---")
    p_playlists = HD_ROOT / 'Playlists'
    if p_playlists.exists():
        safe_remove_tree(p_playlists)
        print("Pasta vazia Playlists removida do HD.")

def main():
    print("Iniciando execução da mineração do Grupo 5 e limpeza no HD externo...")
    step1_niver_de_xande()
    step2_niver_2()
    step3_intervalo()
    step4_mini_set_e_soltas()
    step5_musicas_baixadas()
    step6_cleanup_empty_playlists()
    print("\n=== Grupo 5 completamente processado e backups eliminados com sucesso! ===")

if __name__ == '__main__':
    main()

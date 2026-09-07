# 🎧 DJ Workflow — DJ Zezé (Deuzbenza)

Automação de organização, deduplicação e sincronização da biblioteca musical.

## 📋 Visão Geral

| Item | Detalhe |
|------|---------|
| **Perfil** | DJ — criação de sets |
| **DJ Software** | djay Pro, VirtualDJ, Engine DJ |
| **Fonte** | Playlists do Spotify → download via site |
| **Formato** | MP3 320kbps |
| **HD Externo** | `DEUZBENZA` → `/Volumes/DEUZBENZA` |
| **PC** | `~/Documents/DjZeze` |
| **Biblioteca HD** | `/Volumes/DEUZBENZA/Music/Biblioteca` |

## 📂 Estrutura do Projeto

```
dj-workflow/
├── scripts/           ← Scripts de automação
├── config/
│   ├── config.yml     ← Caminhos e preferências
│   └── generos.yml    ← Mapa de gêneros (aliases, artistas)
├── logs/              ← Histórico de operações (git-ignored)
├── listas/            ← Relatórios gerados (git-ignored)
├── .gitignore
├── .editorconfig
└── README.md          ← Este arquivo
```

## 🎵 Gêneros

| Gênero | Descrição |
|--------|-----------|
| Afrobeat | Afrobeats, Afropop, Afro House |
| Amapiano | Amapiano House, Piano |
| Brasilidades | Forró, MPB, Axé, Maracatu, Brega |
| DanceHall | Bashment, Ragga |
| Funk | Funk Carioca, Baile Funk |
| Jazz | Jazz Fusion, Acid Jazz, Nu Jazz |
| Kuduro | — |
| Musica Latina | Reggaeton, Salsa, Cumbia |
| Pagodão | Pagode Baiano (ritmo baiano) |
| Rap | Hip Hop, Trap, Boom Bap |
| Reggae-Dub | Reggae, Dub, Roots |
| Samba | Pagode, Partido Alto, Samba de Roda |

> **Nota:** "Pagode" → Samba. "Pagode Baiano" → Pagodão.

## 🛠️ Scripts

### Fase 1 — Auditoria (somente leitura)

| Script | O que faz |
|--------|-----------|
| `inventario.sh` | Relatório completo da biblioteca |
| `dedup.sh` | Encontra duplicatas |
| `auditar-genero.sh` | Identifica faixas na pasta errada |
| `qualidade.sh` | Lista faixas abaixo de 320kbps |

### Fase 2 — Reorganização (dry-run por padrão)

| Script | O que faz |
|--------|-----------|
| `padronizar-tags.sh` | Corrige tags ID3 |
| `reorganizar.sh` | Move arquivos pra estrutura correta |
| `separar-generos.sh` | Desmonta pastas mistas |
| `desmontar-playlist.sh` | Desmonta playlists → gêneros |
| `coletar-downloads.sh` | Coleta áudio de ~/Downloads |

### Fase 3 — Workflow Diário

| Script | O que faz |
|--------|-----------|
| `sync-musica.sh` | Sincroniza HD ↔ PC |
| `transferir-celular.sh` | Copia batch pro celular |

## 🔒 Segurança

Todos os scripts de movimentação:
- Rodam em **dry-run** por padrão (mostram o que fariam)
- Só executam com `--executar`
- Geram log detalhado em `logs/`

## 🚀 Uso Rápido

```bash
# Ver o que tem na biblioteca
./scripts/inventario.sh /Volumes/DEUZBENZA/Music/Biblioteca/

# Auditar gêneros de uma pasta
./scripts/auditar-genero.sh /Volumes/DEUZBENZA/Music/Biblioteca/Amapiano/

# Reorganizar (dry-run primeiro!)
./scripts/reorganizar.sh --dry-run
./scripts/reorganizar.sh --executar

# Sincronizar HD → PC
./scripts/sync-musica.sh
```

## 📝 Versionamento

- **Conventional Commits:** `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`
- **Tags semânticas:** `v0.1.0` (setup) → `v0.2.0` (auditoria) → `v1.0.0` (completo)

## 📄 Licença

Projeto pessoal — uso privado.

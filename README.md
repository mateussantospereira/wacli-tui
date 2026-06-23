# wacli-tui

TUI para [wacli](https://github.com/openclaw/wacli) usando `fzf`.

## Dependências

- [wacli](https://github.com/openclaw/wacli) — CLI do WhatsApp
- `fzf` — navegação e seleção
- `jq` — parsing de JSON
- `chafa`, `catimg` ou `viu` (opcional) — preview de imagens

## Instalação

```bash
chmod +x wacli-tui.sh
./wacli-tui.sh
```

## Uso interativo

```
./wacli-tui.sh
```

## Modo direto (CLI)

```bash
./wacli-tui.sh --recentes              # Conversas recentes
./wacli-tui.sh --chat <jid>            # Ver msgs de um chat
./wacli-tui.sh --send-text "msg" --to <jid>  # Enviar texto
./wacli-tui.sh --sync                  # Sincronizar e sair
./wacli-tui.sh --doctor                # Diagnóstico
./wacli-tui.sh --debug                 # Modo debug
./wacli-tui.sh --no-sync               # Iniciar sem sync
./wacli-tui.sh --help                  # Ajuda
```

## Configuração

Arquivo: `~/.config/wacli-tui/config.sh`

```bash
# Limite padrão de mensagens nas listagens
WACLI_LIMIT=50

# Cache de chats (segundos)
WACLI_CACHE_TTL=15

# Modo debug (mostra erros do wacli)
WACLI_DEBUG=0

# Iniciar sync automaticamente: ask, always, never
WACLI_SYNC_START=ask
```

## Funcionalidades

- Mensagens (listar, buscar, contexto, exportar, editar, apagar)
- Envio (texto, arquivo, figurinha, reação, voz)
- Contatos (buscar, detalhes, alias, tags)
- Chats (navegar, arquivar, mutar, fixar, marcar lido)
- Grupos (info, renomear, participantes, admin, convite, prune)
- Canais
- Sync sob demanda
- Histórico (cobertura, backfill)
- Mídia (download)
- Presença (digitando)
- Perfil (foto)
- Armazenamento (estatísticas, limpeza)
- Autenticação (QR, telefone, logout)
- Doctor (diagnóstico)

#!/bin/bash

e=$(printf '\e')
R="${e}[31m"; G="${e}[32m"; Y="${e}[33m"; B="${e}[34m"; N="${e}[0m"; BOLD="${e}[1m"; DIM="${e}[2m"

for cmd in wacli fzf jq; do
  command -v "$cmd" &>/dev/null || { echo "Erro: $cmd nao instalado" >&2; exit 1; }
done

FZF_O="--height=100% --layout=reverse --border=rounded --ansi --preview-window=border-rounded"
FZF_ITEMS=/tmp/wacli-items
FZF_SEL=/tmp/wacli-sel
FZF_CTRLC=/tmp/wacli-ctrl-c

printf -v LOGO '%s\n' \
  "██╗    ██╗██╗  ██╗ █████╗ ████████╗███████╗ █████╗ ██████╗ ██████╗ " \
  "██║    ██║██║  ██║██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗" \
  "██║ █╗ ██║███████║███████║   ██║   ███████╗███████║██████╔╝██████╔╝" \
  "██║███╗██║██╔══██║██╔══██║   ██║   ╚════██║██╔══██║██╔═══╝ ██╔═══╝ " \
  "╚███╔███╔╝██║  ██║██║  ██║   ██║   ███████║██║  ██║██║     ██║     " \
  " ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝     "

run_fzf() {
  fzf $FZF_O \
    --bind "ctrl-c:execute-silent(touch $FZF_CTRLC)+abort" \
    --color 'fg:#d0d0d0,fg+:#d0d0d0,bg+:#000000' \
    --color 'hl:#5f87af,hl+:#5fd7ff,info:#afaf87,marker:#87ff00' \
    --color 'prompt:#87d700,spinner:#87d700,pointer:#87d700,header:#87d700' \
    --color 'border:#262626,label:#aeaeae,query:#d9d9d9' \
    --marker='>' --pointer='->' --separator='─' --scrollbar='│' \
    --prompt='> ' \
    --header="$LOGO" --header-first \
    "$@" < "$FZF_ITEMS" > "$FZF_SEL"
  sed -i "s/$e\[[0-9;]*m//g" "$FZF_SEL" 2>/dev/null
  if [ -f "$FZF_CTRLC" ]; then
    rm -f "$FZF_CTRLC"
    echo -e "${G}Ate logo!${N}"
    exit 0
  fi
}

die()   { echo -e "${R}Erro: $*${N}" >&2; }
warn()  { echo -e "${Y}Aviso: $*${N}"; }
info()  { echo -e "${B}$*${N}"; }
ok()    { echo -e "${G}$*${N}"; }
hr()    { echo; echo -e "${DIM}────────────────────────────────────${N}"; echo; }
enter() { echo; read -rsn1 -p "${DIM}[Enter]${N} "; }
conf()  { local r; read -r -n 1 -p "$1 (s/N) " r; echo; [[ "$r" =~ ^[SsYy] ]]; }
ask()   { local p="$1" v; read -r -p "$p: " "$2"; }

trap 'echo >&2; echo -e "${G}Ate logo!${N}" >&2; trap - INT; exit 0' INT TERM

SYNC_PID=""
cleanup() {
  if [ -n "$SYNC_PID" ] && kill -0 "$SYNC_PID" 2>/dev/null; then
    kill "$SYNC_PID" 2>/dev/null
    wait "$SYNC_PID" 2>/dev/null
  fi
}
trap cleanup EXIT

# ── Pega campo .data da resposta padrao do wacli ────────────────────────
wdata() { wacli "$@" --json 2>/dev/null | jq '.data'; }

# ── Pickers ──────────────────────────────────────────────────────────────
pick_contact() {
  local d
  d=$(wdata chats list | jq '[.[] | select(.kind == "dm")]')
  if [[ "$d" == "null" || -z "$d" || "$(echo "$d" | jq 'length')" -eq 0 ]]; then
    d=$(wdata contacts search "a") || { warn "Nenhum contato"; return 1; }
  fi
  [[ "$d" == "null" || -z "$d" ]] && warn "Nenhum contato" && return 1
  echo "$d" | jq -r '.[] | "\(.name // .jid) | \(.jid)"' > "$FZF_ITEMS"
  run_fzf --prompt="Contato > " \
    --preview='j=$(echo {} | cut -d"|" -f2 | xargs); wdata contacts show --jid "$j" 2>/dev/null | jq -r '"'"'to_entries | .[] | "\(.key): \(.value)"'"'" \
    --preview-window=right:40%
  local s; s=$(cat "$FZF_SEL" 2>/dev/null)
  [[ -z "$s" ]] && return 1
  echo "$s" | cut -d'|' -f2 | xargs
}

pick_chat() {
  local d
  d=$(wdata chats list) || { warn "Nenhum chat"; return 1; }
  [[ "$d" == "null" || -z "$d" ]] && warn "Nenhum chat" && return 1
  echo "$d" | jq -r '
    sort_by(.last_message_ts // "") | reverse[]
    | "\(.name // .jid)\(
        if .pinned then " 📌" else "" end
      )\(
        if .muted_until and (.muted_until > 0) then " 🔇" else "" end
      )\(
        if .archived then " 📁" else "" end
      )\(
        if .unread and .unread > 0 then " [" + (.unread|tostring) + "]" else "" end
      ) | \(.jid)"' > "$FZF_ITEMS"
  run_fzf --prompt="Chat > " \
    --preview='j=$(echo {} | cut -d"|" -f2 | xargs); [ -n "$j" ] && { echo "--- Ultimas msgs ---"; wacli messages list --chat "$j" --limit 5 2>/dev/null | tail -n +2; }' \
    --preview-window=right:55%
  local s; s=$(cat "$FZF_SEL" 2>/dev/null)
  [[ -z "$s" ]] && return 1
  echo "$s" | cut -d'|' -f2 | xargs
}

pick_group() {
  local d
  d=$(wdata groups list) || { warn "Nenhum grupo"; return 1; }
  [[ "$d" == "null" || -z "$d" ]] && warn "Nenhum grupo" && return 1
  echo "$d" | jq -r '.[] | "\(.Name // .JID) | \(.JID)"' > "$FZF_ITEMS"
  run_fzf --prompt="Grupo > " \
    --preview='j=$(echo {} | cut -d"|" -f2 | xargs); wacli groups info --jid "$j" 2>/dev/null | head -20' \
    --preview-window=right:40%
  local s; s=$(cat "$FZF_SEL" 2>/dev/null)
  [[ -z "$s" ]] && return 1
  echo "$s" | cut -d'|' -f2 | xargs
}

pick_msg() {
  local chat="$1"
  [[ -z "$chat" ]] && return 1
  local d
  d=$(wacli messages list --chat "$chat" --limit 50 --json 2>/dev/null | jq '.data.messages') || return 1
  [[ "$d" == "null" || -z "$d" ]] && warn "Nenhuma msg" && return 1
  echo "$d" | jq -r '.[] | "\(.MsgID[0:20]) | \(.Timestamp) | \(.DisplayText // .MediaType // "[midia]")"' > "$FZF_ITEMS"
  run_fzf --prompt="Mensagem > " \
    --preview='m=$(echo {} | cut -d"|" -f1 | xargs); wacli messages show --chat "'"$chat"'" --id "$m" 2>/dev/null' \
    --preview-window=right:50%
  local s; s=$(cat "$FZF_SEL" 2>/dev/null)
  [[ -z "$s" ]] && return 1
  echo "$s" | cut -d'|' -f1 | xargs
}

# ── Menu helper ──────────────────────────────────────────────────────────
menu() {
  local p="$1"; shift
  printf "%s\n" "$@" > "$FZF_ITEMS"
  run_fzf --prompt="$p > "
}

# ═════════════════════════════════════════════════════════════════════════════
# SUBMENUS
# ═════════════════════════════════════════════════════════════════════════════

msgs() {
  while true; do
    clear
    local c
    menu "📩 MENSAGENS" \
      "Listar msg de um chat" \
      "Buscar" \
      "Contexto" \
      "Exportar" \
      "Estreladas" \
      "Editar" \
      "Apagar" \
      "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Listar msg de um chat")
        local ch; ch=$(pick_chat) || continue
        wdata messages list --chat "$ch" --limit 30 | \
          jq -r '.messages[]? | "[\(.Timestamp)] \(if .FromMe then "Voce" else .SenderName // "?" end): \(.DisplayText // .MediaType // "[midia]")"' 2>/dev/null || warn "Sem msgs"
        enter;;
      "Buscar")
        local q; ask "Buscar" q; [[ -z "$q" ]] && continue
        local co=""
        if conf "Filtrar chat?"; then local ct; ct=$(pick_chat) || continue; co="--chat $ct"; fi
        wdata messages search "$q" $co --limit 30 | \
          jq -r '.messages[]? | "[\(.Timestamp)] [\(.ChatName)] \(.DisplayText // .MediaType // "[midia]")"' 2>/dev/null || warn "Nada"
        enter;;
      "Contexto")
        local ch; ch=$(pick_chat) || continue
        local m; m=$(pick_msg "$ch") || continue
        wdata messages context --chat "$ch" --id "$m" --before 5 --after 5 | \
          jq -r '.[]? | "[\(.Timestamp)] \(if .FromMe then "Voce" else .SenderName end): \(.DisplayText // .MediaType // "[midia]")"' 2>/dev/null || warn "Sem contexto"
        enter;;
      "Exportar")
        local ch; ch=$(pick_chat) || continue
        local f="${ch##*/}"; f="${f%@*}"
        local o="$HOME/wacli-export-$f-$(date +%Y%m%d).json"
        wacli messages export --chat "$ch" --limit 5000 --output "$o" 2>/dev/null && ok "Exportado: $o" || warn "Falha"
        enter;;
      "Estreladas")
        wdata messages starred --limit 50 | \
          jq -r '.messages[]? | "[\(.Timestamp)] [\(.ChatName)] \(.DisplayText // .MediaType // "[midia]")"' 2>/dev/null || warn "Nenhuma"
        enter;;
      "Editar")
        local ch; ch=$(pick_chat) || continue
        local m; m=$(pick_msg "$ch") || continue
        local t; ask "Novo texto" t; [[ -z "$t" ]] && continue
        wacli messages edit --chat "$ch" --id "$m" --message "$t" 2>/dev/null && ok "Editada!" || warn "Falha"
        enter;;
      "Apagar")
        local ch; ch=$(pick_chat) || continue
        local m; m=$(pick_msg "$ch") || continue
        local df="--for-me"
        conf "Apagar p/ todos? (N=só voce)" && df=""
        wacli messages delete --chat "$ch" --id "$m" $df 2>/dev/null && ok "Apagada!" || warn "Falha"
        enter;;
      "Voltar") break;;
    esac
  done
}

enviar() {
  while true; do
    clear
    local c
    menu "✉️ ENVIAR" \
      "Texto" \
      "Arquivo" \
      "Figurinha" \
      "Reagir" \
      "Voz" \
      "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Texto")
        local to; to=$(pick_contact) || continue
        local msg; ask "Mensagem" msg; [[ -z "$msg" ]] && continue
        if conf "Responder?"; then
          local ch; ch=$(pick_chat) || continue
          local ri; ri=$(pick_msg "$ch") || continue
          wacli send text --to "$to" --message "$msg" --reply-to "$ri" 2>/dev/null && ok "Enviada!" || warn "Falha"
        else
          wacli send text --to "$to" --message "$msg" 2>/dev/null && ok "Enviada!" || warn "Falha"
        fi
        enter;;
      "Arquivo")
        local to; to=$(pick_contact) || continue
        local f; ask "Caminho" f; [[ -z "$f" || ! -f "$f" ]] && die "Invalido" && enter && continue
        local cap=""; conf "Legenda?" && ask "Legenda" cap
        wacli send file --to "$to" --file "$f" ${cap:+--caption "$cap"} 2>/dev/null && ok "Enviado!" || warn "Falha"
        enter;;
      "Figurinha")
        local to; to=$(pick_contact) || continue
        local f; ask "Arquivo WebP" f; [[ -z "$f" || ! -f "$f" ]] && die "Invalido" && enter && continue
        wacli send sticker --to "$to" --file "$f" 2>/dev/null && ok "Enviada!" || warn "Falha"
        enter;;
      "Reagir")
        local ch; ch=$(pick_chat) || continue
        local m; m=$(pick_msg "$ch") || continue
        local em; ask "Emoji (vazio=remover)" em
        wacli send react --to "$ch" --id "$m" --reaction "$em" 2>/dev/null && ok "Reagido!" || warn "Falha"
        enter;;
      "Voz")
        local to; to=$(pick_contact) || continue
        local f; ask "Arquivo OGG" f; [[ -z "$f" || ! -f "$f" ]] && die "Invalido" && enter && continue
        wacli send voice --to "$to" --file "$f" 2>/dev/null && ok "Enviada!" || warn "Falha"
        enter;;
      "Voltar") break;;
    esac
  done
}

contatos() {
  while true; do
    clear
    local c
    menu "👤 CONTATOS" \
      "Buscar" \
      "Detalhes" \
      "Definir alias" \
      "Remover alias" \
      "Add tag" \
      "Remover tag" \
      "Refresh" \
      "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Buscar")
        local q; ask "Nome" q; [[ -z "$q" ]] && continue
        wdata contacts search "$q" | \
          jq -r '.[]? | "\(.name // "(sem nome)") | \(.jid) | Alias: \(.alias // "-") | Tags: \(.tags // [])"' 2>/dev/null || warn "Nada"
        enter;;
      "Detalhes")
        local j; j=$(pick_contact) || continue
        wdata contacts show --jid "$j" | jq -r 'to_entries | .[] | "\(.key): \(.value)"' 2>/dev/null || warn "Nao encontrado"
        enter;;
      "Definir alias")
        local j; j=$(pick_contact) || continue; local a; ask "Alias" a; [[ -z "$a" ]] && continue
        wacli contacts alias set --jid "$j" --alias "$a" 2>/dev/null && ok "Alias set!" || warn "Falha"
        enter;;
      "Remover alias")
        local j; j=$(pick_contact) || continue; local a; ask "Alias" a; [[ -z "$a" ]] && continue
        wacli contacts alias rm --jid "$j" --alias "$a" 2>/dev/null && ok "Removido!" || warn "Falha"
        enter;;
      "Add tag")
        local j; j=$(pick_contact) || continue; local t; ask "Tag" t; [[ -z "$t" ]] && continue
        wacli contacts tags add --jid "$j" --tag "$t" 2>/dev/null && ok "Tag add!" || warn "Falha"
        enter;;
      "Remover tag")
        local j; j=$(pick_contact) || continue; local t; ask "Tag" t; [[ -z "$t" ]] && continue
        wacli contacts tags rm --jid "$j" --tag "$t" 2>/dev/null && ok "Removida!" || warn "Falha"
        enter;;
      "Refresh") wacli contacts refresh 2>/dev/null && ok "Contatos atualizados!" || warn "Falha"; enter;;
      "Voltar") break;;
    esac
  done
}

chats() {
  while true; do
    clear
    local c
    menu "💬 CHATS" \
      "🔍 Navegar" \
      "🧹 Limpar chats" \
      "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "🔍 Navegar") navegar_chats;;
      "🧹 Limpar chats")
        local days; ask "Dias (365)" days; days="${days:-365}"
        conf "Dry-run?" && wdata chats cleanup --days "$days" --dry-run 2>/dev/null; echo
        conf "Confirmar?" && wacli chats cleanup --days "$days" --confirm 2>/dev/null && ok "Limpeza OK!" || warn "Falha"
        enter;;
      "Voltar") break;;
    esac
  done
}

navegar_chats() {
  while true; do
    clear
    info "Carregando chats..."
    local d
    d=$(wdata chats list) || { warn "Falha ao carregar"; return; }
    [[ "$d" == "null" || -z "$d" ]] && warn "Nenhum chat" && return

    echo "$d" | jq -r '
      sort_by(.last_message_ts // "") | reverse[]
      | "\(.name // .jid)\(
          if .pinned then " 📌" else "" end
        )\(
          if .muted_until and (.muted_until > 0) then " 🔇" else "" end
        )\(
          if .archived then " 📁" else "" end
        )\(
          if .unread and .unread > 0 then " [" + (.unread|tostring) + "]" else "" end
        ) | \(.jid)"' > "$FZF_ITEMS"
    run_fzf --prompt="Chat > " \
      --header="ENTER=gerenciar  ESC=voltar" \
      --preview='j=$(echo {} | cut -d"|" -f2 | xargs); [ -n "$j" ] && { echo "--- Ultimas msgs ---"; wacli messages list --chat "$j" --limit 5 2>/dev/null | tail -n +2; }' \
      --preview-window=right:55%
    local sel; sel=$(cat "$FZF_SEL" 2>/dev/null)

    [[ -z "$sel" ]] && return

    local jid name
    jid=$(echo "$sel" | cut -d'|' -f2 | xargs)
    name=$(echo "$sel" | cut -d'|' -f1 | xargs)

    while true; do
      clear
      echo -e "${BOLD}${name}${N}  ${DIM}${jid}${N}"
      echo
      local act
      menu "Acao" \
        "📋 Ver mensagens" \
        "📁 Arquivar" \
        "📂 Desarquivar" \
        "🔇 Mutar" \
        "🔊 Desmutar" \
        "📌 Fixar" \
        "🔓 Desfixar" \
        "✅ Marcar lido" \
        "🔄 Marcar nao lido" \
        "⬅ Outro chat"
      act=$(cat "$FZF_SEL")
      [[ -z "$act" ]] && break
      case "$act" in
        "📋 Ver mensagens")
          wacli messages list --chat "$jid" --limit 30 2>/dev/null || warn "Sem msgs"
          enter;;
        "📁 Arquivar")    wacli chats archive --chat "$jid" 2>/dev/null && ok "Arquivado!" || warn "Falha"; enter;;
        "📂 Desarquivar") wacli chats unarchive --chat "$jid" 2>/dev/null && ok "Desarquivado!" || warn "Falha"; enter;;
        "🔇 Mutar")
          echo "0=sempre, 8h=8h, 24h=1d, 168h=1sem"
          local dur; ask "Duracao" dur; dur="${dur:-0}"
          wacli chats mute --chat "$jid" --duration "$dur" 2>/dev/null && ok "Mutado!" || warn "Falha"
          enter;;
        "🔊 Desmutar")    wacli chats unmute --chat "$jid" 2>/dev/null && ok "OK!" || warn "Falha"; enter;;
        "📌 Fixar")       wacli chats pin --chat "$jid" 2>/dev/null && ok "Fixado!" || warn "Falha"; enter;;
        "🔓 Desfixar")    wacli chats unpin --chat "$jid" 2>/dev/null && ok "Desfixado!" || warn "Falha"; enter;;
        "✅ Marcar lido")   wacli chats mark-read --chat "$jid" 2>/dev/null && ok "OK!" || warn "Falha"; enter;;
        "🔄 Marcar nao lido") wacli chats mark-unread --chat "$jid" 2>/dev/null && ok "OK!" || warn "Falha"; enter;;
        "⬅ Outro chat") break;;
      esac
    done
  done
}

grupos() {
  while true; do
    clear
    local c
    menu "👥 GRUPOS" \
      "Listar" \
      "Info" \
      "Renomear" \
      "Atualizar" \
      "Entrar (codigo)" \
      "Sair" \
      "Link convite" \
      "Revogar link" \
      "Add participante" \
      "Remover participante" \
      "Promover admin" \
      "Rebaixar" \
      "Prune" \
      "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Listar") wdata groups list | jq -r '.[]? | "\(.Name // .JID)"' 2>/dev/null || warn "Nenhum"; enter;;
      "Info") local j; j=$(pick_group) || continue; wdata groups info --jid "$j" | jq -r 'to_entries | .[] | "\(.key): \(.value)"' 2>/dev/null || warn "Falha"; enter;;
      "Renomear") local j; j=$(pick_group) || continue; local n; ask "Nome" n; [[ -z "$n" ]] && continue; wacli groups rename --jid "$j" --name "$n" 2>/dev/null && ok "Renomeado!" || warn "Falha"; enter;;
      "Atualizar") wacli groups refresh 2>/dev/null && ok "OK!" || warn "Falha"; enter;;
      "Entrar (codigo)") local c; ask "Codigo" c; [[ -z "$c" ]] && continue; wacli groups join --code "$c" 2>/dev/null && ok "Entrou!" || warn "Falha"; enter;;
      "Sair") local j; j=$(pick_group) || continue; conf "Sair?" || continue; wacli groups leave --jid "$j" 2>/dev/null && ok "Saiu!" || warn "Falha"; enter;;
      "Link convite") local j; j=$(pick_group) || continue; wacli groups invite link get --jid "$j" 2>/dev/null || warn "Falha"; enter;;
      "Revogar link") local j; j=$(pick_group) || continue; conf "Revogar?" || continue; wacli groups invite link revoke --jid "$j" 2>/dev/null && ok "Revogado!" || warn "Falha"; enter;;
      "Add participante"|"Remover participante"|"Promover admin"|"Rebaixar")
        local j; j=$(pick_group) || continue
        local u; ask "Numero (+5511...)" u; [[ -z "$u" ]] && continue
        local sc
        case "$c" in "Add participante") sc="add";; "Remover participante") sc="remove";; "Promover admin") sc="promote";; "Rebaixar") sc="demote";; esac
        wacli groups participants $sc --jid "$j" --user "$u" 2>/dev/null && ok "Feito!" || warn "Falha"
        enter;;
      "Prune")
        local days; ask "Dias (0=todos)" days; days="${days:-0}"
        conf "Dry-run?" && wacli groups prune --days "$days" --dry-run 2>/dev/null; echo
        conf "Confirmar?" && wacli groups prune --days "$days" --confirm 2>/dev/null && ok "Prune OK!" || warn "Falha"
        enter;;
      "Voltar") break;;
    esac
  done
}

canais() {
  while true; do
    clear
    local c
    menu "📢 CANAIS" "Listar" "Info" "Entrar" "Sair" "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Listar") wacli channels list 2>/dev/null || warn "Falha"; enter;;
      "Info") local j; ask "JID (@newsletter)" j; [[ -z "$j" ]] && continue; wdata channels info --jid "$j" | jq -r 'to_entries | .[] | "\(.key): \(.value)"' 2>/dev/null || warn "Falha"; enter;;
      "Entrar") local i; ask "Link" i; [[ -z "$i" ]] && continue; wacli channels join --invite "$i" 2>/dev/null && ok "Inscrito!" || warn "Falha"; enter;;
      "Sair") local j; ask "JID" j; [[ -z "$j" ]] && continue; conf "Sair?" || continue; wacli channels leave --jid "$j" 2>/dev/null && ok "Saiu!" || warn "Falha"; enter;;
      "Voltar") break;;
    esac
  done
}

sync_() {
  while true; do
    clear
    local c
    menu "🔄 SYNC" "Sync unico" "Sync continuo" "Status auth" "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Sync unico") info "Sync (Ctrl+C para parar)..."; wacli sync --once --idle-exit 10s 2>/dev/null && ok "Sync OK!" || warn "Falha"; enter;;
      "Sync continuo") info "Sync continuo (Ctrl+C para parar)"; wacli sync --follow 2>/dev/null || true; enter;;
      "Status auth") wdata auth status | jq -r 'to_entries | .[] | "\(.key): \(.value)"' 2>/dev/null || warn "Nao autenticado"; enter;;
      "Voltar") break;;
    esac
  done
}

hist() {
  while true; do
    clear
    local c
    menu "🕓 HISTORICO" "Cobertura" "Backfill" "Fill" "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Cobertura") wdata history coverage --limit 30 | jq -r '.coverage[]? | "\(.Name // .JID): \(.OldestMessageTime // "?") ate \(.NewestMessageTime // "?") [\(.MessageCount // 0) msgs]"' 2>/dev/null || warn "Falha"; enter;;
      "Backfill")
        local ch; ch=$(pick_chat) || continue
        local n; ask "Qtd (max 500, padrao 50)" n; n="${n:-50}"
        info "Solicitando... (telefone precisa estar online)"; wacli history backfill --chat "$ch" --count "$n" --requests 3 2>/dev/null && ok "Backfill OK!" || warn "Falha"
        enter;;
      "Fill") wdata history fill --limit 30 --dry-run | jq -r '.coverage[]? | "\(.Name // .JID): \(.OldestTime // "?") → \(.NewestTime // "?")"' 2>/dev/null || warn "Falha"; enter;;
      "Voltar") break;;
    esac
  done
}

midia() {
  while true; do
    clear
    local c
    menu "🖼️ MIDIA" "Baixar" "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Baixar")
        local ch; ch=$(pick_chat) || continue
        local m; m=$(pick_msg "$ch") || continue
        local o; ask "Diretorio (Enter=padrao)" o
        wacli media download --chat "$ch" --id "$m" ${o:+--output "$o"} 2>/dev/null && ok "Download OK!" || warn "Falha"
        enter;;
      "Voltar") break;;
    esac
  done
}

presenca() {
  while true; do
    clear
    local c
    menu "🎯 PRESENCA" "Digitando..." "Parou de digitar" "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Digitando...") local to; to=$(pick_contact) || continue; wacli presence typing --to "$to" 2>/dev/null && ok "OK!" || warn "Falha"; enter;;
      "Parou de digitar") local to; to=$(pick_contact) || continue; wacli presence paused --to "$to" 2>/dev/null && ok "OK!" || warn "Falha"; enter;;
      "Voltar") break;;
    esac
  done
}

perfil() {
  while true; do
    clear
    local c
    menu "⚙️ PERFIL" "Alterar foto" "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Alterar foto") local f; ask "Imagem JPEG/PNG" f; [[ -z "$f" || ! -f "$f" ]] && die "Invalido" && enter && continue; wacli profile set-picture "$f" 2>/dev/null && ok "Foto alterada!" || warn "Falha"; enter;;
      "Voltar") break;;
    esac
  done
}

storage() {
  while true; do
    clear
    local c
    menu "🗄️ ARMAZENAMENTO" "Estatisticas" "Limpar dados" "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Estatisticas") wacli store stats 2>/dev/null || warn "Falha"; enter;;
      "Limpar dados")
        local days; ask "Dias (365)" days; days="${days:-365}"
        conf "Dry-run?" && wacli store cleanup --days "$days" --dry-run 2>/dev/null; echo
        conf "Confirmar?" && wacli store cleanup --days "$days" --confirm 2>/dev/null && ok "Limpeza OK!" || warn "Falha"
        enter;;
      "Voltar") break;;
    esac
  done
}

auth_() {
  while true; do
    clear
    local c
    menu "🔐 AUTENTICACAO" "Autenticar QR" "Autenticar telefone" "Status" "Logout" "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Autenticar QR") info "Escaneie o QR code"; wacli auth --follow 2>/dev/null || warn "Falha"; enter;;
      "Autenticar telefone") local p; ask "Numero (+5511...)" p; [[ -z "$p" ]] && continue; wacli auth --phone "$p" 2>/dev/null || warn "Falha"; enter;;
      "Status") wdata auth status 2>/dev/null || warn "Nao autenticado"; enter;;
      "Logout") conf "Logout?" || continue; wacli auth logout 2>/dev/null && ok "Logout OK!" || warn "Falha"; enter;;
      "Voltar") break;;
    esac
  done
}

doctor() {
  while true; do
    clear
    local c
    menu "🔧 DOCTOR" "Basico" "Com conexao" "Voltar"
    c=$(cat "$FZF_SEL")
    [[ -z "$c" ]] && break
    case "$c" in
      "Basico") wacli doctor 2>/dev/null || warn "Falha"; enter;;
      "Com conexao") wacli doctor --connect 2>/dev/null || warn "Falha"; enter;;
      "Voltar") break;;
    esac
  done
}

# ── Recentes (lista contatos/grupos por ultima msg) ───────────────────────
recentes() {
  clear
  info "Carregando conversas recentes..."
  local d
  d=$(wdata chats list) || { warn "Falha ao carregar"; return; }
  [[ "$d" == "null" || -z "$d" ]] && warn "Nenhum chat" && return

  echo "$d" | jq -r '
    sort_by(.last_message_ts) | reverse[]
    | "\(.last_message_ts[0:19]) | \(
        if .kind == "group" then "👥"
        elif .kind == "dm" then "👤"
        else "📢"
      end) | \(.name // .jid)"' > "$FZF_ITEMS"
  run_fzf --prompt="📋 Recentes > " \
    --header="📋 RECENTES | Enter=ver msgs  ESC=voltar" \
    --preview='j=$(echo {} | cut -d"|" -f3 | xargs); [ -n "$j" ] && wacli messages list --chat "$j" --limit 5 2>/dev/null | tail -n +2' \
    --preview-window=right:55%
  local sel; sel=$(cat "$FZF_SEL" 2>/dev/null)

  [[ -z "$sel" ]] && return
  local jid
  jid=$(echo "$sel" | cut -d'|' -f3 | xargs)
  [[ -z "$jid" ]] && return

  # Mostra as mensagens do chat selecionado
  clear
  wacli messages list --chat "$jid" --limit 30 2>/dev/null || warn "Sem mensagens"
  echo
  info "Chat: $jid"
  enter
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════
main() {
  info "Iniciando sync em background..."
  wacli sync --follow >/dev/null 2>&1 &
  SYNC_PID=$!
  disown "$SYNC_PID" 2>/dev/null || true
  info "Sync rodando em background (PID $SYNC_PID)"

  while true; do
    clear
    printf '%s\n' \
      "  Recentes" \
      "  Mensagens" \
      "  Enviar" \
      "  Contatos" \
      "  Chats" \
      "  Grupos" \
      "  Canais" \
      "  Sync" \
      "  Historico" \
      "  Midia" \
      "  Presenca" \
      "  Perfil" \
      "  Armazenamento" \
      "  Autenticacao" \
      "  Doctor" \
      "Sair" > "$FZF_ITEMS"
    run_fzf --prompt="MENU > "
    local c; c=$(cat "$FZF_SEL" 2>/dev/null)
    [[ -z "$c" ]] && continue
    case "$c" in
      *Recentes)     recentes;;
      *Mensagens)    msgs;;
      *Enviar)       enviar;;
      *Contatos)     contatos;;
      *Chats)        chats;;
      *Grupos)       grupos;;
      *Canais)       canais;;
      *Sync)         sync_;;
      *Historico)    hist;;
      *Midia)        midia;;
      *Presenca)     presenca;;
      *Perfil)       perfil;;
      *Armazenamento) storage;;
      *Autenticacao) auth_;;
      *Doctor)       doctor;;
      Sair)          echo; echo -e "${G}Ate logo!${N}"; exit 0;;
    esac
  done
}

main "$@"

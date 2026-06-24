#!/bin/bash

# ═════════════════════════════════════════════════════════════════════════════
# wacli-tui — TUI para wacli (WhatsApp CLI)
# ═════════════════════════════════════════════════════════════════════════════

# ── Config ──────────────────────────────────────────────────────────────────
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wacli-tui"
CONFIG_FILE="$CONFIG_DIR/config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

: "${WACLI_LIMIT:=30}"
: "${WACLI_CACHE_TTL:=30}"
: "${WACLI_DEBUG:=0}"
: "${WACLI_SYNC_START:=ask}"

# ── ANSI ────────────────────────────────────────────────────────────────────
e=$(printf '\e')
R="${e}[31m"; G="${e}[32m"; Y="${e}[33m"; B="${e}[34m"; N="${e}[0m"
BOLD="${e}[1m"; DIM="${e}[2m"
ORANGE="${e}[38;5;214m"
DGREEN="${e}[38;5;28m"

# ── Temp files (PID-safe) ──────────────────────────────────────────────────
FZF_ITEMS="/tmp/wacli-$$-items"
FZF_SEL="/tmp/wacli-$$-sel"
FZF_CTRLC="/tmp/wacli-$$-ctrl-c"
CACHE_D="/tmp/wacli-$$-cache"
SYNC_PID_FILE="/tmp/wacli-$$-sync-pid"
_PREVIEW_HELPER="/tmp/wacli-$$-preview-msgs"
cat > "$_PREVIEW_HELPER" << 'PREVIEWEOF'
#!/bin/bash
jid="$1"
[ -z "$jid" ] && exit
me=$(printf '\033[38;5;28m')
them=$(printf '\033[38;5;214m')
rst=$(printf '\033[0m')
wacli messages list --chat "$jid" --limit 5 --json 2>/dev/null | jq -r --arg me "$me" --arg them "$them" --arg rst "$rst" '.data.messages // .data | reverse[] | "\(if .FromMe then "\($me)Voce\($rst)" else "\($them)\(.SenderName // "?")\($rst)" end): \(.DisplayText // .MediaType // "[midia]")"' 2>/dev/null
PREVIEWEOF
chmod +x "$_PREVIEW_HELPER"

cleanup_all() {
  sync_stop
  rm -rf "/tmp/wacli-$$-"*
}
trap cleanup_all EXIT

trap 'echo >&2; echo -e "${G}Ate logo!${N}" >&2; trap - INT; exit 0' INT TERM

# ── Dependencies ────────────────────────────────────────────────────────────
for cmd in wacli fzf jq; do
  command -v "$cmd" &>/dev/null || { echo "Erro: $cmd nao instalado" >&2; exit 1; }
done

# ── FZF defaults ────────────────────────────────────────────────────────────
FZF_O="--height=100% --layout=reverse --border=rounded --ansi --preview-window=border-rounded"
FZF_C="--color=fg:#d0d0d0,fg+:#d0d0d0,bg+:#000000"
FZF_C="$FZF_C --color=hl:#5f87af,hl+:#5fd7ff,info:#afaf87,marker:#87ff00"
FZF_C="$FZF_C --color=prompt:#87d700,spinner:#87d700,pointer:#87d700,header:#87d700"
FZF_C="$FZF_C --color=border:#262626,label:#aeaeae,query:#d9d9d9"


# ── Helpers ─────────────────────────────────────────────────────────────────
wdata() {
  if [ "$WACLI_DEBUG" = "1" ]; then
    wacli "$@" --json 2>&1 | jq '.data'
  else
    wacli "$@" --json 2>/dev/null | jq '.data'
  fi
}

die()   { echo -e "${R}Erro: $*${N}" >&2; }
warn()  { echo -e "${Y}Aviso: $*${N}"; }
info()  { echo -e "${B}$*${N}"; }
ok()    { echo -e "${G}$*${N}"; }
hr()    { echo; echo -e "${DIM}────────────────────────────────────${N}"; echo; }
enter() { echo; read -rsn1 -p "${DIM}[Enter]${N} "; }
conf()  { local r; read -r -n 1 -p "$1 (s/N) " r; echo; [[ "$r" =~ ^[SsYy] ]]; }
ask() {
  local p="$1"
  read -r -e -p "$p: " "$2"
  case "${!2}" in
    \~)   printf -v "$2" "%s" "$HOME";;
    \~/*) printf -v "$2" "%s" "$HOME/${!2#\~/}";;
  esac
}

# ── Pick helpers ────────────────────────────────────────────────────────────
pick_field() { cut -d'|' -f"$1" "$FZF_SEL" 2>/dev/null | xargs; }
pick_jid()   { pick_field 2; }
pick_name()  { pick_field 1; }
pick_id()    { pick_field 1; }

# ── Cache ───────────────────────────────────────────────────────────────────
cache_get() {
  local key="$1" file="$CACHE_D/$key" now t
  [ -f "$file" ] || return 1
  read -r t < "$file"
  now=$(date +%s)
  [ "$((now - t))" -lt "$WACLI_CACHE_TTL" ] && tail -n +2 "$file" || { rm -f "$file"; return 1; }
}
cache_set() {
  local key="$1"
  mkdir -p "$CACHE_D"
  { date +%s; cat; } > "$CACHE_D/$key"
}
cache_clear() { rm -rf "$CACHE_D"; }

# ── Image preview (optional) ────────────────────────────────────────────────
img_preview() {
  local f="$1"
  [ ! -f "$f" ] && return 1
  command -v chafa &>/dev/null && chafa --symbols solid "$f" && return 0
  command -v catimg &>/dev/null && catimg "$f" && return 0
  command -v viu &>/dev/null && viu "$f" && return 0
  return 1
}

# ── Logo ────────────────────────────────────────────────────────────────────
printf -v LOGO '%s\n' \
  "██╗    ██╗██╗  ██╗ █████╗ ████████╗███████╗ █████╗ ██████╗ ██████╗ " \
  "██║    ██║██║  ██║██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗" \
  "██║ █╗ ██║███████║███████║   ██║   ███████╗███████║██████╔╝██████╔╝" \
  "██║███╗██║██╔══██║██╔══██║   ██║   ╚════██║██╔══██║██╔═══╝ ██╔═══╝ " \
  "╚███╔███╔╝██║  ██║██║  ██║   ██║   ███████║██║  ██║██║     ██║     " \
  " ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝     "

# ── run_fzf ─────────────────────────────────────────────────────────────────
run_fzf() {
  # shellcheck disable=SC2086
  fzf $FZF_O $FZF_C \
    --bind "ctrl-c:execute-silent(touch $FZF_CTRLC)+abort" \
    --marker='>' --pointer='->' --separator='─' --scrollbar='│' \
    "$@" < "$FZF_ITEMS" > "$FZF_SEL"
  sed -i "s/$e\[[0-9;]*m//g" "$FZF_SEL" 2>/dev/null
  if [ -f "$FZF_CTRLC" ]; then
    rm -f "$FZF_CTRLC"
    echo -e "${G}Ate logo!${N}"
    exit 0
  fi
}

# ── text_box ────────────────────────────────────────────────────────────────
text_box() {
  local prompt="${1:-Texto}"
  fzf --print-query --prompt="> " --height=1 --layout=reverse --border=rounded \
    --border-label=" $prompt " --no-separator --info=hidden \
    $FZF_C --color=bg:#000000,label:#87d700,prompt:#87d700 \
    </dev/null 2>/dev/null | head -1
}

# ── Sync management ─────────────────────────────────────────────────────────
sync_ensure() {
  local pid
  if [ -f "$SYNC_PID_FILE" ]; then
    pid=$(cat "$SYNC_PID_FILE")
    kill -0 "$pid" 2>/dev/null && return
    rm -f "$SYNC_PID_FILE"
  fi
  wacli sync --follow --max-reconnect 0 >/dev/null 2>&1 &
  pid=$!
  echo "$pid" > "$SYNC_PID_FILE"
  disown "$pid" 2>/dev/null || true
}

sync_start() {
  local pid
  if [ -f "$SYNC_PID_FILE" ]; then
    pid=$(cat "$SYNC_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      info "Sync ja rodando (PID $pid)"
      return
    fi
    rm -f "$SYNC_PID_FILE"
  fi
  info "Iniciando sync em background..."
  wacli sync --follow >/dev/null 2>&1 &
  pid=$!
  echo "$pid" > "$SYNC_PID_FILE"
  disown "$pid" 2>/dev/null || true
  ok "Sync rodando (PID $pid)"
}

sync_stop() {
  local pid
  [ ! -f "$SYNC_PID_FILE" ] && { warn "Sync nao rodando"; return; }
  pid=$(cat "$SYNC_PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    ok "Sync parado"
  fi
  rm -f "$SYNC_PID_FILE"
}

sync_status() {
  local pid
  [ ! -f "$SYNC_PID_FILE" ] && return 1
  pid=$(cat "$SYNC_PID_FILE")
  kill -0 "$pid" 2>/dev/null
}

# ── Notificacao ─────────────────────────────────────────────────────────────
check_unread() {
  local d n
  d=$(wdata chats list 2>/dev/null) || return
  n=$(echo "$d" | jq '[.[] | select(.unread and .unread > 0) | .unread] | add // 0' 2>/dev/null)
  [ "$n" -gt 0 ] && echo " ${Y}[$n nao lida(s)]${N}" || echo ""
}

# ── Pickers ─────────────────────────────────────────────────────────────────
pick_contact() {
  while true; do
    local q; ask "Nome do contato" q; [[ -z "$q" ]] && return 1
    local r; r=$(wdata contacts search "$q") || { warn "Nenhum contato"; return 1; }
    local n; n=$(echo "$r" | jq 'length' 2>/dev/null)
    if [ "$n" -eq 0 ] 2>/dev/null; then warn "Nenhum contato"; return 1
    elif [ "$n" -eq 1 ] 2>/dev/null; then
      echo "$r" | jq -r '.[] | "\(.name // .jid) | \(.jid)"' >&2
      echo "$r" | jq -r '.[0].jid'; return 0
    else
      echo "$r" | jq -r '.[] | "\(.name // .jid) | \(.jid)"' > "$FZF_ITEMS"
      run_fzf --prompt="Selecione > " --header="$n contatos encontrados" \
        --preview='j=$(echo {} | cut -d"|" -f2 | xargs); wdata contacts show --jid "$j" 2>/dev/null | jq -r '"'"'to_entries | .[] | "\(.key): \(.value)"'"'" \
        --preview-window=right:40%
      local jid; jid=$(pick_jid)
      [ -n "$jid" ] && echo "$jid" && return 0
    fi
  done
}

pick_chat() {
  local d
  d=$(cache_get chats) || {
    d=$(wdata chats list) || { warn "Nenhum chat"; return 1; }
    [[ "$d" == "null" || -z "$d" ]] && warn "Nenhum chat" && return 1
    echo "$d" | cache_set chats
  }
  echo "$d" | jq -r --arg orange "$ORANGE" --arg rst "$N" '
    sort_by(.last_message_ts // "") | reverse[]
    | "\($orange)\(.name // .jid)\($rst)\(
        if .pinned then " 📌" else "" end
      )\(
        if .muted_until and (.muted_until > 0) then " 🔇" else "" end
      )\(
        if .archived then " 📁" else "" end
      )\(
        if .unread and .unread > 0 then " [" + (.unread|tostring) + "]" else "" end
      ) | \(.jid)"' > "$FZF_ITEMS"
  run_fzf --prompt="Chat > " \
    --preview='j=$(echo {} | cut -d"|" -f2 | xargs); [ -n "$j" ] && { echo "--- Ultimas msgs ---"; '"$_PREVIEW_HELPER"' "$j"; }' \
    --preview-window=right:55%
  local jid; jid=$(pick_jid)
  [ -z "$jid" ] && return 1
  echo "$jid"
}

pick_group() {
  local d
  d=$(wdata groups list) || { warn "Nenhum grupo"; return 1; }
  [[ "$d" == "null" || -z "$d" ]] && warn "Nenhum grupo" && return 1
  echo "$d" | jq -r '.[] | "\(.Name // .JID) | \(.JID)"' > "$FZF_ITEMS"
  run_fzf --prompt="Grupo > " \
    --preview='j=$(echo {} | cut -d"|" -f2 | xargs); wacli groups info --jid "$j" 2>/dev/null | head -20' \
    --preview-window=right:40%
  local jid; jid=$(pick_jid)
  [ -z "$jid" ] && return 1
  echo "$jid"
}

pick_msg() {
  local chat="$1"
  [[ -z "$chat" ]] && return 1
  local d
  d=$(wdata messages list --chat "$chat" --limit 50 | jq '.messages') || return 1
  [[ "$d" == "null" || -z "$d" ]] && warn "Nenhuma msg" && return 1
  echo "$d" | jq -r --arg me "$DGREEN" --arg them "$ORANGE" --arg rst "$N" '.[] | "\(.MsgID) | \(.Timestamp | fromdateiso8601 | strflocaltime("%d/%m %H:%M:%S")) | \(if .FromMe then "\($me)Voce\($rst)" else "\($them)\(.SenderName // "?")\($rst)" end): \((.DisplayText | select(length > 0)) // .MediaType // "[midia]")"' > "$FZF_ITEMS"
  run_fzf --prompt="Mensagem > " \
    --preview='m=$(echo {} | cut -d"|" -f1 | xargs); wacli messages show --chat "'"$chat"'" --id "$m" 2>/dev/null' \
    --preview-window=right:50%
  local id; id=$(pick_id)
  [ -z "$id" ] && return 1
  echo "$id"
}

pick_file() {
  local dir="${1:-$HOME}"
  dir=$(realpath "$dir" 2>/dev/null || echo "$dir")
  local sel

  while true; do
    {
      echo "@ .."
      ls -1p "$dir" 2>/dev/null
    } > "$FZF_ITEMS"
    run_fzf --prompt="Arquivo > " \
      --header="$dir" \
      --preview='p="'"$dir"'/{}"; [ -d "$p" ] && ls -1p "$p" | head -30 2>/dev/null || { head -50 "$p" 2>/dev/null || file -b "$p"; }' \
      --preview-window=right:50%:wrap
    sel=$(cat "$FZF_SEL" 2>/dev/null)
    [ -z "$sel" ] && return 1
    [ "$sel" = "@ .." ] && { [ "$dir" = "/" ] && return 1 || dir="$(dirname "$dir")"; continue; }
    [ -d "$dir/$sel" ] && { dir="$dir/$sel"; continue; }
    echo "$dir/$sel"
    return 0
  done
}

# ── Menu helper ─────────────────────────────────────────────────────────────
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
    menu "📩 MENSAGENS" \
      "Listar msg de um chat" \
      "Buscar" \
      "Contexto" \
      "Exportar" \
      "Estreladas" \
      "Editar" \
      "Apagar" \
      "Voltar"
    local c; c=$(pick_name)
    [[ -z "$c" ]] && break
    case "$c" in
      "Listar msg de um chat")
        local ch; ch=$(pick_chat) || continue
        wdata messages list --chat "$ch" --limit "$WACLI_LIMIT" | \
          jq -r --arg me "$DGREEN" --arg them "$ORANGE" --arg rst "$N" '.messages[]? | "[\(.Timestamp | fromdateiso8601 | strflocaltime("%d/%m %H:%M:%S"))] \(if .FromMe then "\($me)Voce\($rst)" else "\($them)\(.SenderName // "?")\($rst)" end): \((.DisplayText | select(length > 0)) // .MediaType // "[midia]")"' 2>/dev/null || warn "Sem msgs"
        enter;;
      "Buscar")
        local q; ask "Buscar" q; [[ -z "$q" ]] && continue
        local co=""
        if conf "Filtrar chat?"; then local ct; ct=$(pick_chat) || continue; co="--chat $ct"; fi
        wdata messages search "$q" $co --limit "$WACLI_LIMIT" | \
          jq -r --arg bld "$BOLD" --arg rst "$N" '.messages[]? | "[\(.Timestamp | fromdateiso8601 | strflocaltime("%d/%m %H:%M:%S"))] \($bld)[\(.ChatName)]\($rst) \((.DisplayText | select(length > 0)) // .MediaType // "[midia]")"' 2>/dev/null || warn "Nada"
        enter;;
      "Contexto")
        local ch; ch=$(pick_chat) || continue
        local m; m=$(pick_msg "$ch") || continue
        wdata messages context --chat "$ch" --id "$m" --before 5 --after 5 | \
          jq -r --arg me "$DGREEN" --arg them "$ORANGE" --arg rst "$N" '.[]? | "[\(.Timestamp | fromdateiso8601 | strflocaltime("%d/%m %H:%M:%S"))] \(if .FromMe then "\($me)Voce\($rst)" else "\($them)\(.SenderName // "?")\($rst)" end): \((.DisplayText | select(length > 0)) // .MediaType // "[midia]")"' 2>/dev/null || warn "Sem contexto"
        enter;;
      "Exportar")
        local ch; ch=$(pick_chat) || continue
        local f="${ch##*/}"; f="${f%@*}"
        local o="$HOME/wacli-export-$f-$(date +%Y%m%d).json"
        wacli messages export --chat "$ch" --limit 5000 --output "$o" 2>/dev/null && ok "Exportado: $o" || warn "Falha"
        enter;;
      "Estreladas")
        wdata messages starred --limit 50 | \
          jq -r --arg bld "$BOLD" --arg rst "$N" '.messages[]? | "[\(.Timestamp | fromdateiso8601 | strflocaltime("%d/%m %H:%M:%S"))] \($bld)[\(.ChatName)]\($rst) \((.DisplayText | select(length > 0)) // .MediaType // "[midia]")"' 2>/dev/null || warn "Nenhuma"
        enter;;
      "Editar")
        local ch; ch=$(pick_chat) || continue
        local m; m=$(pick_msg "$ch") || continue
        local t; t=$(text_box "Novo texto"); [[ -z "$t" ]] && continue
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
    local to; to=$(pick_contact)
    [ -z "$to" ] && break
    local nome; nome=$(wdata contacts show --jid "$to" 2>/dev/null | jq -r '.name // .jid' 2>/dev/null || echo "$to")

    while true; do
      clear
      echo -e "${BOLD}Para:${N} $nome ${DIM}$to${N}"
      echo
      menu "✉️ TIPO" \
        "Texto" \
        "Arquivo" \
        "Figurinha" \
        "Reagir" \
        "Voz" \
        "Outro contato" \
        "Voltar"
      local c; c=$(pick_name)
      [[ -z "$c" ]] && break
      case "$c" in
        "Texto")
          local msg; msg=$(text_box "Mensagem"); [[ -z "$msg" ]] && continue
          if conf "Responder?"; then
            local ri; ri=$(pick_msg "$to") || continue
            wacli send text --to "$to" --message "$msg" --reply-to "$ri" 2>/dev/null && ok "Enviada!" || warn "Falha"
          else
            wacli send text --to "$to" --message "$msg" 2>/dev/null && ok "Enviada!" || warn "Falha"
          fi
          enter;;
        "Arquivo")
          local f; f=$(pick_file) || { die "Nenhum arquivo" && enter && continue; }
          local cap=""; conf "Legenda?" && ask "Legenda" cap
          wacli send file --to "$to" --file "$f" ${cap:+--caption "$cap"} 2>/dev/null && ok "Enviado!" || warn "Falha"
          enter;;
        "Figurinha")
          local f; f=$(pick_file) || { die "Nenhum arquivo" && enter && continue; }
          wacli send sticker --to "$to" --file "$f" 2>/dev/null && ok "Enviada!" || warn "Falha"
          enter;;
        "Reagir")
          local m; m=$(pick_msg "$to") || continue
          local em; ask "Emoji (vazio=remover)" em
          wacli send react --to "$to" --id "$m" --reaction "$em" 2>/dev/null && ok "Reagido!" || warn "Falha"
          enter;;
        "Voz")
          local f; f=$(pick_file) || { die "Nenhum arquivo" && enter && continue; }
          wacli send voice --to "$to" --file "$f" 2>/dev/null && ok "Enviada!" || warn "Falha"
          enter;;
        "Outro contato") break;;
        "Voltar") break 2;;
      esac
    done
  done
}

contatos() {
  while true; do
    clear
    menu "👤 CONTATOS" \
      "Buscar" \
      "Detalhes" \
      "Definir alias" \
      "Remover alias" \
      "Add tag" \
      "Remover tag" \
      "Voltar"
    local c; c=$(pick_name)
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
      "Voltar") break;;
    esac
  done
}

chats() {
  while true; do
    clear
    menu "💬 CHATS" \
      "🔍 Navegar" \
      "🧹 Limpar chats" \
      "Voltar"
    local c; c=$(pick_name)
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

    echo "$d" | jq -r --arg orange "$ORANGE" --arg rst "$N" '
      sort_by(.last_message_ts // "") | reverse[]
      | "\($orange)\(.name // .jid)\($rst)\(
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
      --preview='j=$(echo {} | cut -d"|" -f2 | xargs); [ -n "$j" ] && { echo "--- Ultimas msgs ---"; '"$_PREVIEW_HELPER"' "$j"; }' \
      --preview-window=right:55%
    local sel; sel=$(pick_name)
    [[ -z "$sel" ]] && return
    local jid; jid=$(pick_jid)
    local name="$sel"

    while true; do
      clear
      echo -e "${BOLD}${name}${N}  ${DIM}${jid}${N}"
      echo
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
      local act; act=$(pick_name)
      [[ -z "$act" ]] && break
      case "$act" in
        "📋 Ver mensagens")
          wacli messages list --chat "$jid" --limit "$WACLI_LIMIT" 2>/dev/null || warn "Sem msgs"
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
    local c; c=$(pick_name)
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
    menu "📢 CANAIS" "Listar" "Info" "Entrar" "Sair" "Voltar"
    local c; c=$(pick_name)
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
    local s="Sync desligado"
    sync_status && s="Sync ligado"
    menu "🔄 SYNC [${s}]" "Sync unico" "Sync continuo" "Ligar sync" "Desligar sync" "Status auth" "Voltar"
    local c; c=$(pick_name)
    [[ -z "$c" ]] && break
    case "$c" in
      "Sync unico") info "Sync (Ctrl+C para parar)..."; wacli sync --once --idle-exit 10s 2>/dev/null && ok "Sync OK!" || warn "Falha"; enter;;
      "Sync continuo") info "Sync continuo (Ctrl+C para parar)"; wacli sync --follow 2>/dev/null || true; enter;;
      "Ligar sync") sync_start; enter;;
      "Desligar sync") sync_stop; enter;;
      "Status auth") wdata auth status | jq -r 'to_entries | .[] | "\(.key): \(.value)"' 2>/dev/null || warn "Nao autenticado"; enter;;
      "Voltar") break;;
    esac
  done
}

hist() {
  while true; do
    clear
    menu "🕓 HISTORICO" "Cobertura" "Backfill" "Fill" "Voltar"
    local c; c=$(pick_name)
    [[ -z "$c" ]] && break
    case "$c" in
      "Cobertura") wdata history coverage --limit "$WACLI_LIMIT" | jq -r '.coverage[]? | "\(.Name // .JID): \(.OldestMessageTime // "?") ate \(.NewestMessageTime // "?") [\(.MessageCount // 0) msgs]"' 2>/dev/null || warn "Falha"; enter;;
      "Backfill")
        local ch; ch=$(pick_chat) || continue
        local n; ask "Qtd (max 500, padrao 50)" n; n="${n:-50}"
        info "Solicitando... (telefone precisa estar online)"; wacli history backfill --chat "$ch" --count "$n" --requests 3 2>/dev/null && ok "Backfill OK!" || warn "Falha"
        enter;;
      "Fill") wdata history fill --limit "$WACLI_LIMIT" --dry-run | jq -r '.coverage[]? | "\(.Name // .JID): \(.OldestTime // "?") → \(.NewestTime // "?")"' 2>/dev/null || warn "Falha"; enter;;
      "Voltar") break;;
    esac
  done
}

midia() {
  while true; do
    clear
    menu "🖼️ MIDIA" "Baixar" "Voltar"
    local c; c=$(pick_name)
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


perfil() {
  while true; do
    clear
    menu "⚙️ PERFIL" "Alterar foto" "Voltar"
    local c; c=$(pick_name)
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
    menu "🗄️ ARMAZENAMENTO" "Estatisticas" "Limpar dados" "Voltar"
    local c; c=$(pick_name)
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
    menu "🔐 AUTENTICACAO" "Autenticar QR" "Autenticar telefone" "Status" "Logout" "Voltar"
    local c; c=$(pick_name)
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
    menu "🔧 DOCTOR" "Basico" "Com conexao" "Voltar"
    local c; c=$(pick_name)
    [[ -z "$c" ]] && break
    case "$c" in
      "Basico") wacli doctor 2>/dev/null || warn "Falha"; enter;;
      "Com conexao") wacli doctor --connect 2>/dev/null || warn "Falha"; enter;;
      "Voltar") break;;
    esac
  done
}

# ── Recentes ────────────────────────────────────────────────────────────────
recentes() {
  clear
  info "Carregando conversas recentes..."
  local d
  d=$(wdata chats list) || { warn "Falha ao carregar"; return; }
  [[ "$d" == "null" || -z "$d" ]] && warn "Nenhum chat" && return

  echo "$d" | jq -r '
    sort_by(.last_message_ts) | reverse[]
    | "\(.last_message_ts | fromdateiso8601 | strflocaltime("%d/%m %H:%M")) | \(
        if .kind == "group" then "👥"
        elif .kind == "dm" then "👤"
        else "📢"
      end) | \(.name // .jid)"' > "$FZF_ITEMS"
  run_fzf --prompt="📋 Recentes > " \
    --header="📋 RECENTES | Enter=ver msgs  ESC=voltar" \
    --preview='j=$(echo {} | cut -d"|" -f3 | xargs); [ -n "$j" ] && '"$_PREVIEW_HELPER"' "$j"' \
    --preview-window=right:55%
  local jid; jid=$(pick_field 3)
  [[ -z "$jid" ]] && return

  clear
  wacli messages list --chat "$jid" --limit "$WACLI_LIMIT" 2>/dev/null || warn "Sem mensagens"
  echo
  info "Chat: $jid"
  enter
}

# ═════════════════════════════════════════════════════════════════════════════
# CLI ARGS
# ═════════════════════════════════════════════════════════════════════════════

usage() {
  echo "Uso: $0 [opcoes]"
  echo
  echo "Opcoes:"
  echo "  --recentes              Abrir conversas recentes"
  echo "  --chat <jid>            Ver mensagens de um chat"
  echo "  --send-text <msg>       Enviar texto (requer --to)"
  echo "  --to <jid>              Destinatario (usar com --send-text)"
  echo "  --sync                  Sincronizar uma vez e sair"
  echo "  --doctor                Rodar diagnostico"
  echo "  --debug                 Modo debug (mostra erros do wacli)"
  echo "  --no-sync               Nao iniciar sync automatico"
  echo "  -h, --help              Mostrar esta ajuda"
}

parse_args() {
  local opts
  opts=$(getopt -o h --long help,recentes,chat:,send-text:,to:,sync,doctor,debug,no-sync -n "$0" -- "$@") || { usage >&2; exit 1; }
  eval set -- "$opts"

  local send_text="" to=""
  while true; do
    case "$1" in
      -h|--help) usage; exit 0;;
      --recentes) recentes; exit 0;;
      --chat) shift; local ch="$1"; info "Chat: $ch"; wacli messages list --chat "$ch" --limit "$WACLI_LIMIT" 2>/dev/null; exit $?;;
      --send-text) shift; send_text="$1";;
      --to) shift; to="$1";;
      --sync) wacli sync --once --idle-exit 10s 2>/dev/null; exit $?;;
      --doctor) wacli doctor --connect 2>/dev/null; exit $?;;
      --debug) WACLI_DEBUG=1;;
      --no-sync) WACLI_SYNC_START=never;;
      --) shift; break;;
      *) break;;
    esac
    shift
  done

  if [ -n "$send_text" ]; then
    if [ -z "$to" ]; then
      die "--send-text requer --to"
      exit 1
    fi
    wacli send text --to "$to" --message "$send_text" 2>/dev/null && ok "Enviada!" || die "Falha ao enviar"
    exit $?
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════
main() {
  parse_args "$@"

  # Sync inicial
  case "$WACLI_SYNC_START" in
    always) sync_start;;
    ask)
      if conf "${B}Iniciar sync em background?${N}"; then
        sync_start
      fi
      ;;
  esac

  while true; do
    clear
    local unread; unread=$(check_unread)

    printf '%s\n' \
      "  Mensagens" \
      "  Enviar" \
      "  Contatos" \
      "  Refresh" \
      "  Chats" \
      "  Grupos" \
      "  Canais" \
      "  Sync" \
      "  Historico" \
      "  Midia" \
      "  Perfil" \
      "  Armazenamento" \
      "  Autenticacao" \
      "  Doctor" \
      "Sair" > "$FZF_ITEMS"
    run_fzf --prompt="MENU > " \
      --header="${LOGO}${unread}" --header-first
    local c; c=$(pick_name 2>/dev/null)
    [[ -z "$c" ]] && continue
    case "$c" in
      *Mensagens)
        sync_ensure
        local ch; ch=$(pick_chat) || continue
        local _store_dir; _store_dir=$(wacli doctor --json 2>/dev/null | jq -r '.data.store_dir' 2>/dev/null || echo "$HOME/.wacli")
        local _db="$_store_dir/wacli.db"
        local _last_sent=""
        local _chat_name; _chat_name=$(wdata chats list 2>/dev/null | jq -r --arg jid "$ch" 'map(select(.jid == $jid)) | .[0] | .name // .jid // $jid' 2>/dev/null || echo "$ch")
        while true; do
          clear
          echo -e "${BOLD}${_chat_name}${N}  ${DIM}${ch}${N}"
          echo
          wdata messages list --chat "$ch" --limit "$WACLI_LIMIT" 2>/dev/null | jq -r \
            --arg me "$DGREEN" --arg them "$ORANGE" --arg rst "$N" '
            (.messages // []) | reverse[] |
            "\(
              if .Timestamp then
                (.Timestamp | fromdateiso8601? // "" | strflocaltime("%d/%m/%Y %H:%M"))
              else "" end
            ) \(
              if .FromMe then "\($me)Voce\($rst)" else "\($them)\(.SenderName // "?")\($rst)" end
            ): \(
              .DisplayText // .MediaType // "[midia]"
            )"
          ' 2>/dev/null
          [ -n "$_last_sent" ] && echo -e "${G}$_last_sent${N}"
          echo
          local _db_mtime; _db_mtime=$(stat -c %Y "$_db" 2>/dev/null)
          echo -e "${DIM}[Enter] texto  [f] arquivo  [v] copiar  [q] sair${N}"
          while true; do
            if read -rsn1 -t 1 key 2>/dev/null; then
              case "$key" in
                q|Q) break 2;;
                f|F)
                  local _ff; _ff=$(pick_file) || { warn "Nenhum" && break; }
                  local _cap=""; conf "Legenda?" && ask "Legenda" _cap
                  wacli send file --to "$ch" --file "$_ff" ${_cap:+--caption "$_cap"} 2>/dev/null && {
                    _last_sent="[$(date +%H:%M)] Voce: $(basename "$_ff")"
                    ok "Enviado!"
                  } || warn "Falha"
                  break;;
                v|V)
                  clear
                  wacli messages list --chat "$ch" --limit 200 --json 2>/dev/null | jq -r \
                    --arg me "$DGREEN" --arg them "$ORANGE" --arg rst "$N" '
                    (.data.messages // .data) | reverse[] |
                    "\($rst)[\(.Timestamp | fromdateiso8601? // "" | strflocaltime("%d/%m/%Y %H:%M"))]\($rst) \(if .FromMe then "\($me)Voce\($rst)" else "\($them)\(.SenderName // "?")\($rst)" end): \(.DisplayText // .MediaType // "[midia]")"
                  ' 2>/dev/null | less -R
                  break
                  ;;
                r|R) sync_ensure; break;;
                $'\n'|"")
                  local msg; msg=$(text_box "Mensagem")
                  [[ -z "$msg" ]] && break
                  if wacli send text --to "$ch" --message "$msg" 2>/dev/null; then
                    _last_sent="[$(date +%H:%M)] Voce: $msg"
                  else
                    warn "Falha"
                  fi
                  break
                  ;;
              esac
            fi
            local _new_mtime; _new_mtime=$(stat -c %Y "$_db" 2>/dev/null)
            [ "$_new_mtime" != "$_db_mtime" ] && { _db_mtime=$_new_mtime; break; }
          done
        done
        enter;;
      *Enviar)       enviar;;
      *Contatos)     contatos;;
      *Refresh)      wacli contacts refresh 2>/dev/null && ok "Contatos atualizados!" || warn "Falha"; enter;;
      *Chats)        chats;;
      *Grupos)       grupos;;
      *Canais)       canais;;
      *Sync)         sync_;;
      *Historico)    hist;;
      *Midia)        midia;;
      *Perfil)       perfil;;
      *Armazenamento) storage;;
      *Autenticacao) auth_;;
      *Doctor)       doctor;;
      Sair)          echo; echo -e "${G}Ate logo!${N}"; exit 0;;
    esac
  done
}

main "$@"

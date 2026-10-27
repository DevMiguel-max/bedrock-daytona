#!/usr/bin/env bash
# mc — servidor Minecraft Bedrock em um sandbox Linux x86_64 (ex.: Daytona).
# Dois tipos: "bds" (servidor oficial da Mojang, padrão) e "pocketmine" (fork da comunidade).
# Uso: ./mc help
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT/server"
PLAYIT_DIR="$ROOT/playit"
BACKUP_DIR="$ROOT/backups"
SESSION="mc"
PLAYIT_SESSION="mc-playit"

# ---------- padrões (config.env sobrescreve) ----------
SERVER_TYPE="bds"
SERVER_NAME="Bedrock Daytona"
SERVER_PORT="19132"
MAX_PLAYERS="8"
VIEW_DISTANCE="8"
GAMEMODE="survival"
DIFFICULTY="normal"
ONLINE_MODE="true"
LEVEL_NAME="Bedrock level"
BDS_VERSION="latest"
BDS_URL=""
BDS_ZIP=""
BDS_TRANSPORT_RAKNET="1"
PM_REPO="BetterLite/PocketMine-MP"
PM_VERSION="latest"
PHP_VERSION="8.4"
AUTO_RESTART="1"
USE_PLAYIT="1"
PLAYIT_VERSION="v1.0.10"
BACKUP_KEEP="3"
# shellcheck disable=SC1091
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"

BDS_BIN="$SERVER_DIR/bedrock_server"
PHP_BIN="$SERVER_DIR/bin/php7/bin/php"
PHAR="$SERVER_DIR/PocketMine-MP.phar"
PLAYIT_BIN="$PLAYIT_DIR/playit"
PLAYIT_CLI="$PLAYIT_DIR/playit-cli"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

# ---------- util ----------
if [ -t 1 ]; then
  C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_B=$'\e[36m'; C_0=$'\e[0m'
else
  C_R=""; C_G=""; C_Y=""; C_B=""; C_0=""
fi
log()  { printf '%s\n' "${C_B}[mc]${C_0} $*"; }
ok()   { printf '%s\n' "${C_G}[ok]${C_0} $*"; }
warn() { printf '%s\n' "${C_Y}[aviso]${C_0} $*" >&2; }
die()  { printf '%s\n' "${C_R}[erro]${C_0} $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Falta '$1'. Rode: bash install.sh"; }

require_arch() {
  case "$(uname -m)" in
    x86_64|amd64) ;;
    *) die "Arquitetura $(uname -m) não suportada: o servidor oficial (BDS) e o PHP da PMMP para Linux só existem em x86_64." ;;
  esac
}

dl() { # dl URL DESTINO
  local url="$1" dest="$2" tmp="$2.part"
  rm -f "$tmp"
  log "baixando: $url"
  if ! curl -fL --http1.1 -A "$UA" --retry 4 --retry-delay 3 --connect-timeout 20 -o "$tmp" "$url"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$dest"
}

is_running()     { command -v tmux >/dev/null 2>&1 && tmux has-session -t "$SESSION" 2>/dev/null; }
playit_running() { command -v tmux >/dev/null 2>&1 && tmux has-session -t "$PLAYIT_SESSION" 2>/dev/null; }

# O php.ini do pacote carrega opcache.so de um caminho de CI que não existe aqui; apontamos o extension_dir certo.
php_ext_dir() { find "$SERVER_DIR/bin/php7/lib/php/extensions" -maxdepth 1 -type d -name 'no-debug*' 2>/dev/null | head -n1; }
# Gravamos o extension_dir no php.ini do pacote, para o processo principal E os filhos (ex.: leitor do console).
fix_php_ini() {
  local ini="$SERVER_DIR/bin/php7/bin/php.ini" ed
  ed="$(php_ext_dir)"
  { [ -f "$ini" ] && [ -n "$ed" ]; } || return 0
  sed -i '/^extension_dir=/d' "$ini"
  sed -i "1i extension_dir=\"$ed\"" "$ini"
}
php_run() { PHPRC="" "$PHP_BIN" "$@"; }

installed() {
  case "$SERVER_TYPE" in
    bds)        [ -x "$BDS_BIN" ] ;;
    pocketmine) [ -x "$PHP_BIN" ] && [ -f "$PHAR" ] ;;
    *)          return 1 ;;
  esac
}

set_prop() { # set_prop ARQUIVO CHAVE VALOR
  local f="$1" k="$2" v="$3"
  v="${v//|/ }"; v="${v//&/\\&}"
  if grep -q "^${k}=" "$f" 2>/dev/null; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$f"
  else
    printf '%s=%s\n' "$k" "${v//\\&/&}" >> "$f"
  fi
}

# ---------- checagem de rede (o Daytona restringe a saída nos Tiers 1 e 2) ----------
probe() { # probe NOME URL  -> 0 se o host responde (qualquer código HTTP)
  local code
  code="$(curl -sS -o /dev/null --max-time 8 -w '%{http_code}' "$2" 2>/dev/null)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    printf '  %s[ok]%s       %s\n' "$C_G" "$C_0" "$1"
    return 0
  fi
  printf '  %s[BLOQUEADO]%s %s\n' "$C_R" "$C_0" "$1"
  return 1
}

cmd_preflight() {
  need curl
  local gh=0 pl=0 mj=0 mn=0
  echo "Rede do sandbox (saída para a internet):"
  probe "github.com (PocketMine, playit, binários)" "https://github.com" && gh=1
  probe "api.playit.gg (túnel playit)" "https://api.playit.gg" && pl=1
  probe "minecraft-services.net (descobrir link do BDS)" "https://net-secondary.web.minecraft-services.net/api/v1.0/download/links" && mj=1
  probe "www.minecraft.net (baixar o BDS)" "https://www.minecraft.net" && mn=1
  echo
  if [ "$USE_PLAYIT" = "1" ] && [ "$pl" -eq 0 ]; then
    warn "playit bloqueado: NINGUÉM conseguirá entrar. O Daytona só expõe HTTP (preview URLs), nunca UDP, então o"
    warn "Minecraft Bedrock só é alcançável por um túnel de saída. Isso exige internet liberada (Tier 3 ou 4 do Daytona)."
  fi
  if [ "$SERVER_TYPE" = "bds" ] && [ -z "$BDS_ZIP" ] && [ -z "$BDS_URL" ] && { [ "$mj" -eq 0 ] || [ "$mn" -eq 0 ]; }; then
    warn "Mojang bloqueada: o BDS não pode ser baixado aqui. Envie o .zip ao sandbox e use BDS_ZIP no config.env,"
    warn "ou troque para SERVER_TYPE=\"pocketmine\" (só precisa de github.com)."
  fi
  if [ "$gh" -eq 0 ]; then warn "github.com bloqueado: nem o playit nem o PocketMine podem ser baixados."; fi
  return 0
}

# ---------- BDS (servidor oficial) ----------
bds_url() {
  if [ -n "$BDS_URL" ]; then printf '%s' "$BDS_URL"; return 0; fi
  if [ "$BDS_VERSION" != "latest" ]; then
    printf 'https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-%s.zip' "$BDS_VERSION"
    return 0
  fi
  local json url=""
  json="$(curl -fsSL --http1.1 -A "$UA" --max-time 30 "https://net-secondary.web.minecraft-services.net/api/v1.0/download/links" 2>/dev/null || true)"
  if [ -n "$json" ] && command -v jq >/dev/null 2>&1; then
    url="$(printf '%s' "$json" | jq -r '.result.links[] | select(.downloadType=="serverBedrockLinux") | .downloadUrl // empty' 2>/dev/null | head -n1)"
  fi
  if [ -z "$url" ]; then
    local html
    html="$(curl -fsSL --http1.1 -A "$UA" --max-time 30 "https://www.minecraft.net/en-us/download/server/bedrock" 2>/dev/null || true)"
    url="$(printf '%s' "$html" | grep -Eo 'https://www\.minecraft\.net/bedrockdedicatedserver/bin-linux/bedrock-server-[0-9.]+\.zip' | head -n1)"
  fi
  printf '%s' "$url"
}

install_bds() {
  local mode="${1:-}" tmp zip url ver
  mkdir -p "$SERVER_DIR"
  if [ -x "$BDS_BIN" ] && [ "$mode" != "force" ]; then
    ok "BDS já instalado (versão $(cat "$SERVER_DIR/.bds-version" 2>/dev/null || echo desconhecida))"
    return 0
  fi
  need unzip
  tmp="$(mktemp -d)" || die "mktemp falhou"
  if [ -n "$BDS_ZIP" ]; then
    [ -f "$BDS_ZIP" ] || { rm -rf "$tmp"; die "BDS_ZIP não existe: $BDS_ZIP"; }
    zip="$BDS_ZIP"; url="$BDS_ZIP"
  else
    url="$(bds_url)"
    if [ -z "$url" ]; then
      rm -rf "$tmp"
      die "Não consegui descobrir o link do BDS (rede bloqueada?). Opções: cole o link do botão Ubuntu/Linux em BDS_URL, ou envie o .zip e use BDS_ZIP (config.env)."
    fi
    zip="$tmp/bds.zip"
    if ! dl "$url" "$zip"; then rm -rf "$tmp"; die "Falha ao baixar o BDS: $url"; fi
  fi
  ver="$(basename "$url" | sed -n 's/^bedrock-server-\(.*\)\.zip$/\1/p')"
  if [ "$mode" = "force" ] && [ -f "$BDS_BIN" ]; then
    unzip -q -o "$zip" -d "$SERVER_DIR" -x server.properties allowlist.json permissions.json 'worlds/*' || { rm -rf "$tmp"; die "Falha ao extrair o BDS"; }
  else
    unzip -q -o "$zip" -d "$SERVER_DIR" || { rm -rf "$tmp"; die "Falha ao extrair o BDS"; }
  fi
  rm -rf "$tmp"
  [ -f "$BDS_BIN" ] || die "O zip não tinha o arquivo bedrock_server (link errado? precisa ser a versão Linux)."
  chmod +x "$BDS_BIN"
  echo "${ver:-desconhecida}" > "$SERVER_DIR/.bds-version"
  ok "BDS instalado (versão ${ver:-desconhecida})"
}

seed_bds_properties() {
  local f="$SERVER_DIR/server.properties"
  if [ -f "$SERVER_DIR/.configured" ]; then
    ok "server.properties já configurado (não sobrescrito)"
    return 0
  fi
  [ -f "$f" ] || : > "$f"
  set_prop "$f" server-name "$SERVER_NAME"
  set_prop "$f" server-port "$SERVER_PORT"
  set_prop "$f" max-players "$MAX_PLAYERS"
  set_prop "$f" view-distance "$VIEW_DISTANCE"
  set_prop "$f" gamemode "$GAMEMODE"
  set_prop "$f" difficulty "$DIFFICULTY"
  set_prop "$f" online-mode "$ONLINE_MODE"
  set_prop "$f" level-name "$LEVEL_NAME"
  # Linha pedida pela página do túnel do playit (o BDS novo usa NetherNet por padrão; o túnel só aceita RakNet).
  if [ "$BDS_TRANSPORT_RAKNET" = "1" ]; then set_prop "$f" transport raknet; fi
  touch "$SERVER_DIR/.configured"
  ok "server.properties configurado"
}

# ---------- PocketMine (alternativa) ----------
install_php() {
  local force="${1:-}" marker="$SERVER_DIR/.php-version"
  if [ -x "$PHP_BIN" ] && [ "$force" != "force" ] && [ "$(cat "$marker" 2>/dev/null)" = "$PHP_VERSION" ]; then
    ok "PHP $PHP_VERSION já instalado"
    return 0
  fi
  local url="https://github.com/pmmp/PHP-Binaries/releases/download/pm5-php-${PHP_VERSION}-latest/PHP-${PHP_VERSION}-Linux-x86_64-PM5.tar.gz"
  local tmp; tmp="$(mktemp -d)" || die "mktemp falhou"
  mkdir -p "$SERVER_DIR"
  if ! dl "$url" "$tmp/php.tar.gz"; then rm -rf "$tmp"; die "Falha ao baixar o PHP $PHP_VERSION (valores: 8.2, 8.3, 8.4, 8.5)"; fi
  tar -xzf "$tmp/php.tar.gz" -C "$tmp" || { rm -rf "$tmp"; die "Falha ao extrair o PHP"; }
  [ -f "$tmp/bin/php7/bin/php" ] || { rm -rf "$tmp"; die "Pacote do PHP veio sem bin/php7/bin/php"; }
  chmod +x "$tmp/bin/php7/bin/php"
  rm -rf "${SERVER_DIR:?}/bin"
  mv "$tmp/bin" "$SERVER_DIR/bin"
  rm -rf "$tmp"
  echo "$PHP_VERSION" > "$marker"
  fix_php_ini
  php_run -r 'exit(extension_loaded("pmmpthread") ? 0 : 1);' >/dev/null 2>&1 || die "PHP instalado mas sem pmmpthread (veja ./mc doctor)"
  ok "PHP $PHP_VERSION instalado"
}

install_phar() {
  local force="${1:-}"
  mkdir -p "$SERVER_DIR"
  if [ -f "$PHAR" ] && [ "$force" != "force" ]; then ok "PocketMine-MP.phar já existe"; return 0; fi
  local url
  if [ "$PM_VERSION" = "latest" ]; then
    url="https://github.com/${PM_REPO}/releases/latest/download/PocketMine-MP.phar"
  else
    url="https://github.com/${PM_REPO}/releases/download/${PM_VERSION}/PocketMine-MP.phar"
  fi
  log "origem do phar: github.com/${PM_REPO}"
  if ! dl "$url" "$PHAR.new"; then rm -f "$PHAR.new"; die "Falha ao baixar o PocketMine-MP.phar (PM_REPO=$PM_REPO)"; fi
  local size; size="$(wc -c < "$PHAR.new")"
  if [ "$size" -lt 1000000 ]; then rm -f "$PHAR.new"; die "PocketMine-MP.phar parece inválido ($size bytes)"; fi
  [ -f "$PHAR" ] && mv -f "$PHAR" "$PHAR.bak"
  mv -f "$PHAR.new" "$PHAR"
  ok "PocketMine-MP.phar instalado ($size bytes)"
}

seed_pm_properties() {
  local f="$SERVER_DIR/server.properties" xb="on"
  [ "$ONLINE_MODE" = "false" ] && xb="off"
  if [ ! -f "$f" ]; then
    cat > "$f" <<EOF
motd=$SERVER_NAME
server-port=$SERVER_PORT
max-players=$MAX_PLAYERS
view-distance=$VIEW_DISTANCE
gamemode=$GAMEMODE
difficulty=$DIFFICULTY
xbox-auth=$xb
enable-ipv6=off
EOF
    ok "server.properties criado"
  fi
  # O fork consulta update.betterlite.org se o auto-updater estiver ligado.
  if [ ! -f "$SERVER_DIR/pocketmine.yml" ]; then
    printf 'auto-updater:\n  enabled: false\n' > "$SERVER_DIR/pocketmine.yml"
  elif sed -n '/^auto-updater:/,/^[^ ]/p' "$SERVER_DIR/pocketmine.yml" | grep -q '^  enabled: *true'; then
    sed -i '/^auto-updater:/,/^[^ ]/ s/^\(  enabled:\) *true/\1 false/' "$SERVER_DIR/pocketmine.yml"
  fi
}

# ---------- setup ----------
cmd_setup() {
  require_arch
  need curl; need tar
  mkdir -p "$SERVER_DIR" "$BACKUP_DIR"
  case "$SERVER_TYPE" in
    bds)        install_bds; seed_bds_properties ;;
    pocketmine) install_php; install_phar; seed_pm_properties ;;
    *)          die "SERVER_TYPE inválido: '$SERVER_TYPE' (use bds ou pocketmine)" ;;
  esac
  if [ "$USE_PLAYIT" = "1" ]; then
    playit_install || warn "playit não instalado — sem ele ninguém de fora entra (veja ./mc preflight)."
  fi
  ok "Setup concluído. Inicie com: ./mc start"
}

# ---------- servidor ----------
cmd_run() { # primeiro plano (usado dentro do tmux; também serve pra depurar)
  installed || die "Servidor '$SERVER_TYPE' não instalado. Rode: ./mc setup"
  cd "$SERVER_DIR" || exit 1
  local fast=0 code t0 t1
  while :; do
    t0="$(date +%s)"
    case "$SERVER_TYPE" in
      bds)        LD_LIBRARY_PATH=".${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ./bedrock_server ;;
      pocketmine) fix_php_ini; php_run "$PHAR" --no-wizard ;;
    esac
    code=$?
    t1="$(date +%s)"
    echo
    echo "[mc] servidor encerrou (código $code)"
    [ "$code" -eq 0 ] && break
    [ "$AUTO_RESTART" = "1" ] || break
    if [ $((t1 - t0)) -lt 30 ]; then fast=$((fast + 1)); else fast=0; fi
    if [ "$fast" -ge 3 ]; then
      echo "[mc] 3 quedas seguidas em menos de 30s: desisti de reiniciar. Rode ./mc doctor e ./mc run para ver o erro."
      break
    fi
    echo "[mc] reiniciando em 5s (Ctrl+C cancela)..."
    sleep 5
  done
}

cmd_start() {
  need tmux
  installed || die "Servidor '$SERVER_TYPE' não instalado. Rode: ./mc setup"
  if is_running; then
    warn "Servidor já está rodando (./mc console)"
  else
    tmux new-session -d -s "$SESSION" -c "$SERVER_DIR" "bash '$ROOT/mc' run" || die "Falha ao abrir sessão tmux"
    ok "Servidor ($SERVER_TYPE) iniciando na porta UDP $SERVER_PORT. Console: ./mc console (sair sem parar: Ctrl+B, depois D)"
  fi
  if [ "$USE_PLAYIT" = "1" ] && [ -s "$PLAYIT_DIR/secret" ]; then
    cmd_playit_start || warn "playit não subiu (veja ./mc playit-logs)"
  elif [ "$USE_PLAYIT" = "1" ]; then
    log "playit ainda não vinculado — rode ./mc playit-setup para liberar acesso pela internet."
  fi
}

cmd_stop() {
  if playit_running; then cmd_playit_stop; fi
  if is_running; then
    log "Parando servidor..."
    tmux send-keys -t "$SESSION" -l -- "stop"
    tmux send-keys -t "$SESSION" Enter
    local _
    for _ in $(seq 1 40); do
      is_running || break
      sleep 1
    done
    if is_running; then
      warn "Não parou em 40s, forçando."
      tmux kill-session -t "$SESSION" 2>/dev/null
    fi
    ok "Servidor parado"
  else
    warn "Servidor não estava rodando"
  fi
}

server_version() {
  case "$SERVER_TYPE" in
    bds) cat "$SERVER_DIR/.bds-version" 2>/dev/null ;;
    pocketmine) grep -h -o 'Bedrock Edition server version.*' "$SERVER_DIR/server.log" 2>/dev/null | tail -n1 | sed 's/Bedrock Edition server version //' ;;
  esac
}

cmd_status() {
  if is_running; then ok "servidor ($SERVER_TYPE): RODANDO (UDP $SERVER_PORT)"; else warn "servidor ($SERVER_TYPE): parado"; fi
  if playit_running; then ok "playit: rodando"; else log "playit: parado"; fi
  local ver; ver="$(server_version)"
  [ -n "$ver" ] && log "Versão do servidor: $ver (o seu Minecraft precisa ser compatível)"
  if playit_running; then log "Endereço público: site playit.gg > seu túnel > Overview (não aparece no terminal)"; fi
  return 0
}

cmd_console() {
  need tmux
  is_running || die "Servidor parado. Use ./mc start"
  log "Para sair sem parar o servidor: Ctrl+B, depois D"
  exec tmux attach -t "$SESSION"
}

cmd_logs() { # últimas 200 linhas do console do servidor
  is_running || die "Servidor parado"
  tmux capture-pane -p -J -t "$SESSION" -S -200 | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}

cmd_cmd() {
  [ $# -gt 0 ] || die "Uso: ./mc cmd <comando>   ex: ./mc cmd op Steve"
  is_running || die "Servidor parado"
  tmux send-keys -t "$SESSION" -l -- "$*"
  tmux send-keys -t "$SESSION" Enter
}

cmd_backup() {
  mkdir -p "$BACKUP_DIR"
  local held=0 i
  if is_running; then
    if [ "$SERVER_TYPE" = "bds" ]; then
      # Backup consistente do BDS: congela a escrita, espera confirmar, copia, libera.
      tmux send-keys -t "$SESSION" -l -- "save hold"; tmux send-keys -t "$SESSION" Enter
      held=1
      for i in $(seq 1 15); do
        sleep 1
        tmux send-keys -t "$SESSION" -l -- "save query"; tmux send-keys -t "$SESSION" Enter
        sleep 1
        if tmux capture-pane -p -J -t "$SESSION" -S -40 | grep -q "Data saved"; then break; fi
        [ "$i" -eq 15 ] && warn "BDS não confirmou o 'save hold' em 30s; copiando assim mesmo."
      done
    else
      tmux send-keys -t "$SESSION" -l -- "save-all"; tmux send-keys -t "$SESSION" Enter
      sleep 3
    fi
  fi
  local items=() f
  for f in worlds players plugins plugin_data server.properties pocketmine.yml allowlist.json permissions.json ops.txt white-list.txt banned-players.txt banned-ips.txt behavior_packs resource_packs config; do
    [ -e "$SERVER_DIR/$f" ] && items+=("$f")
  done
  local out="$BACKUP_DIR/mc-$(date +%Y%m%d-%H%M%S).tar.gz" rc=0
  if [ "${#items[@]}" -eq 0 ]; then
    warn "Nada para salvar ainda"
  else
    tar -czf "$out" -C "$SERVER_DIR" "${items[@]}" || rc=1
    if [ "$rc" -eq 0 ]; then ok "Backup: $out"; else warn "Backup falhou"; fi
  fi
  if [ "$held" -eq 1 ]; then
    tmux send-keys -t "$SESSION" -l -- "save resume"; tmux send-keys -t "$SESSION" Enter
  fi
  local n=0 old
  while IFS= read -r old; do
    n=$((n + 1))
    [ "$n" -gt "$BACKUP_KEEP" ] && rm -f "$old"
  done < <(ls -1t "$BACKUP_DIR"/mc-*.tar.gz 2>/dev/null)
  return "$rc"
}

cmd_update() {
  local was=0
  if is_running; then was=1; cmd_stop; fi
  cmd_backup
  case "$SERVER_TYPE" in
    bds)        install_bds force ;;
    pocketmine) install_phar force; seed_pm_properties; [ "${1:-}" = "--php" ] && install_php force ;;
  esac
  [ "$was" -eq 1 ] && cmd_start
  return 0
}

# ---------- playit (túnel de saída: a única forma de alcançar UDP no Daytona) ----------
playit_install() {
  local force="${1:-}" base
  mkdir -p "$PLAYIT_DIR"
  if [ -x "$PLAYIT_BIN" ] && [ -x "$PLAYIT_CLI" ] && [ "$force" != "force" ]; then
    ok "playit já instalado"
    return 0
  fi
  if [ "$PLAYIT_VERSION" = "latest" ]; then
    base="https://github.com/playit-cloud/playit-agent/releases/latest/download"
  else
    base="https://github.com/playit-cloud/playit-agent/releases/download/$PLAYIT_VERSION"
  fi
  dl "$base/playit-linux-amd64" "$PLAYIT_BIN" || return 1
  dl "$base/playit-cli-linux-amd64" "$PLAYIT_CLI" || return 1
  chmod +x "$PLAYIT_BIN" "$PLAYIT_CLI"
  ok "playit $PLAYIT_VERSION instalado"
}

cmd_playit_setup() {
  need curl
  playit_install || die "Não consegui baixar o playit (github.com bloqueado? rode ./mc preflight)"
  if [ -s "$PLAYIT_DIR/secret" ]; then
    ok "playit já vinculado (apague playit/secret para refazer)"
    return 0
  fi
  local code url secret
  code="$("$PLAYIT_CLI" claim generate 2>/dev/null | tail -n1 | tr -d '[:space:]')"
  [ -n "$code" ] || die "playit-cli claim generate não retornou código"
  url="$("$PLAYIT_CLI" claim url "$code" --name "mc-daytona" --type self-managed 2>/dev/null | tail -n1 | tr -d '[:space:]')"
  [ -n "$url" ] || die "playit-cli claim url não retornou link"
  echo
  log "Abra este link no SEU navegador, entre na conta playit e aprove o agente:"
  echo "    $url"
  echo
  log "Aguardando aprovação (Ctrl+C cancela)..."
  secret="$("$PLAYIT_CLI" claim exchange "$code" --wait 0 | tail -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  case "$secret" in
    ""|*[!A-Za-z0-9_-]*) die "Não recebi um secret válido (recebido: '$secret'). Rode de novo." ;;
  esac
  if [ "${#secret}" -lt 16 ]; then die "Secret curto demais (${#secret} chars). Rode de novo."; fi
  ( umask 077; printf '%s' "$secret" > "$PLAYIT_DIR/secret" )
  ok "playit vinculado."
  log "Faltam 2 passos manuais no site playit.gg:"
  log "  1) confirme o e-mail da conta (senão: account_status=email_not_verified e o túnel não funciona)"
  log "  2) crie um túnel 'Minecraft Bedrock' com origem 127.0.0.1 porta $SERVER_PORT"
  log "Depois: ./mc restart. O endereço público fica na aba Overview do túnel."
}

cmd_playit_run() { # interno (roda dentro do tmux)
  [ -s "$PLAYIT_DIR/secret" ] || die "playit sem secret: rode ./mc playit-setup"
  cd "$PLAYIT_DIR" || exit 1
  "$PLAYIT_BIN" --secret "$(cat "$PLAYIT_DIR/secret")" --socket-path "$PLAYIT_DIR/playit.sock"
}

cmd_playit_start() {
  need tmux
  [ -x "$PLAYIT_BIN" ] || die "playit não instalado: ./mc setup"
  [ -s "$PLAYIT_DIR/secret" ] || die "playit não vinculado: ./mc playit-setup"
  if playit_running; then warn "playit já está rodando"; return 0; fi
  tmux new-session -d -s "$PLAYIT_SESSION" -c "$PLAYIT_DIR" "bash '$ROOT/mc' _playit_run" || return 1
  ok "playit iniciado (logs: ./mc playit-logs)"
}

cmd_playit_stop() {
  playit_running || { warn "playit não estava rodando"; return 0; }
  tmux send-keys -t "$PLAYIT_SESSION" C-c
  sleep 2
  tmux kill-session -t "$PLAYIT_SESSION" 2>/dev/null
  ok "playit parado"
}

cmd_playit_status() {
  [ -x "$PLAYIT_CLI" ] || die "playit não instalado"
  playit_running || die "playit não está rodando (./mc playit-start)"
  "$PLAYIT_CLI" --socket-path "$PLAYIT_DIR/playit.sock" status
}

cmd_playit_logs() {
  playit_running || die "playit não está rodando"
  tmux capture-pane -p -J -t "$PLAYIT_SESSION" -S -200 | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}

# ---------- diagnóstico ----------
cmd_doctor() {
  local bad=0
  row() { # row OK|FALHA mensagem
    if [ "$1" = "OK" ]; then printf '  %s[ok]%s    %s\n' "$C_G" "$C_0" "$2"; else printf '  %s[FALHA]%s %s\n' "$C_R" "$C_0" "$2"; bad=1; fi
  }
  echo "Diagnóstico ($SERVER_TYPE):"
  case "$(uname -m)" in x86_64|amd64) row OK "arquitetura $(uname -m)";; *) row FALHA "arquitetura $(uname -m) (precisa x86_64)";; esac
  local t
  for t in curl tar tmux unzip; do
    if command -v "$t" >/dev/null 2>&1; then row OK "$t instalado"; else row FALHA "$t ausente (bash install.sh)"; fi
  done
  case "$SERVER_TYPE" in
    bds)
      if [ -x "$BDS_BIN" ]; then
        row OK "bedrock_server presente (versão $(cat "$SERVER_DIR/.bds-version" 2>/dev/null || echo ?))"
        if command -v ldd >/dev/null 2>&1; then
          local missing
          missing="$(cd "$SERVER_DIR" && LD_LIBRARY_PATH=. ldd ./bedrock_server 2>&1 | grep -i "not found" | head -3)"
          if [ -z "$missing" ]; then row OK "bibliotecas do bedrock_server resolvidas"; else row FALHA "bibliotecas faltando: $missing (precisa Ubuntu 22.04+ ou instalar libcurl4/libssl)"; fi
        fi
      else
        row FALHA "bedrock_server ausente (./mc setup)"
      fi ;;
    pocketmine)
      if [ -x "$PHP_BIN" ]; then
        if php_run -r 'exit(extension_loaded("pmmpthread") ? 0 : 1);' >/dev/null 2>&1; then row OK "PHP executa, pmmpthread carregado"; else row FALHA "PHP não executa ou sem pmmpthread"; fi
      else
        row FALHA "PHP não instalado (./mc setup)"
      fi
      if [ -f "$PHAR" ]; then row OK "PocketMine-MP.phar presente"; else row FALHA "PocketMine-MP.phar ausente"; fi ;;
  esac
  if [ "$USE_PLAYIT" = "1" ]; then
    if [ -x "$PLAYIT_BIN" ]; then row OK "playit instalado"; else row FALHA "playit não instalado"; fi
    if [ -s "$PLAYIT_DIR/secret" ]; then row OK "playit vinculado"; else log "playit não vinculado (./mc playit-setup)"; fi
    if playit_running; then
      local st
      st="$(tmux capture-pane -p -J -t "$PLAYIT_SESSION" -S -300 2>/dev/null | grep -o 'account_status="[a-z_]*"' | tail -n1)"
      case "$st" in
        'account_status="verified"') row OK "conta playit verificada" ;;
        "") log "playit: sem status de conta nos logs ainda (espere 20s e rode de novo)" ;;
        *) row FALHA "conta playit: $st. Confirme o e-mail em playit.gg e rode: ./mc playit-stop && ./mc playit-start" ;;
      esac
    fi
  fi
  echo
  cmd_preflight
  return "$bad"
}

usage() {
  cat <<'EOF'
mc — servidor Minecraft Bedrock em sandbox Linux x86_64 (ex.: Daytona)

  setup              baixa o servidor (BDS oficial ou PocketMine) e o playit; configura o server.properties
  start | stop | restart | status
  console            console do servidor (sair sem parar: Ctrl+B, depois D)
  logs               últimas 200 linhas do console
  cmd <comando>      envia comando ao servidor (ex: ./mc cmd op Steve)
  run                primeiro plano, sem tmux (para ver erros de inicialização)
  backup             compacta mundos e configs em backups/ (mantém BACKUP_KEEP)
  update [--php]     atualiza o servidor, com backup antes
  doctor             diagnóstico completo (inclui checagem de rede)
  preflight          só a checagem de rede: o sandbox alcança playit, Mojang e GitHub?
  playit-setup       vincula o playit à sua conta (gera link de aprovação)
  playit-start | playit-stop | playit-status | playit-logs

Config: edite config.env
EOF
}

case "${1:-help}" in
  setup)          cmd_setup ;;
  start)          cmd_start ;;
  stop)           cmd_stop ;;
  restart)        cmd_stop; cmd_start ;;
  status)         cmd_status ;;
  console|attach) cmd_console ;;
  logs)           cmd_logs ;;
  cmd)            shift; cmd_cmd "$@" ;;
  run|_run)       cmd_run ;;
  backup)         cmd_backup ;;
  update)         shift; cmd_update "${1:-}" ;;
  doctor)         cmd_doctor ;;
  preflight)      cmd_preflight ;;
  playit-setup)   cmd_playit_setup ;;
  playit-start)   cmd_playit_start ;;
  playit-stop)    cmd_playit_stop ;;
  playit-status)  cmd_playit_status ;;
  playit-logs)    cmd_playit_logs ;;
  _playit_run)    cmd_playit_run ;;
  help|-h|--help) usage ;;
  *)              usage; exit 1 ;;
esac

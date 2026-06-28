#!/bin/bash

# ============================================================
#           GITHUB BACKUP MANAGER v2.0
#   Auto Backup + Restore langsung dari GitHub
# ============================================================

TOKEN_FILE="$HOME/.github_token"
CONFIG_FILE="$HOME/.backup_config"
BACKUP_DIR="/tmp/backup_staging"
BACKUP_PREFIX="backup"
MAX_BACKUPS=10
LOG_FILE="/var/log/backup_manager.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# ── LOAD / SAVE CONFIG ───────────────────────────────────────
load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
GITHUB_USERNAME="$GITHUB_USERNAME"
GITHUB_REPO_NAME="$GITHUB_REPO_NAME"
GITHUB_BRANCH="$GITHUB_BRANCH"
LOCAL_REPO="$LOCAL_REPO"
ZIP_PASSWORD="$ZIP_PASSWORD"
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_USER_ID="$TG_USER_ID"
EOF
    chmod 600 "$CONFIG_FILE"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE"
}

show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}${BOLD}          GITHUB BACKUP MANAGER v2.0                 ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${BLUE}║${NC} ${CYAN}Repo  :${NC} ${GITHUB_USERNAME}/${GITHUB_REPO_NAME}"
        echo -e "${BLUE}║${NC} ${CYAN}Branch:${NC} ${GITHUB_BRANCH:-main}"
    else
        echo -e "${BLUE}║${NC} ${YELLOW}⚠  Belum dikonfigurasi. Pilih menu Setup dulu.${NC}"
    fi
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_deps() {
    local missing=()
    for cmd in git zip unzip curl jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}📦 Menginstall: ${missing[*]}${NC}"
        apt-get install -y "${missing[@]}" -qq 2>/dev/null
    fi
}

send_telegram() {
    local message="$1"
    [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_USER_ID" ] && return 0
    curl -s -o /dev/null \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" \
        -d "text=${message}" \
        -d "parse_mode=Markdown"
}

# ── HELPER: set remote URL dengan token ──────────────────────
git_set_remote() {
    local repo_dir="$1"
    local token="$2"
    git -C "$repo_dir" remote set-url origin \
        "https://${token}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"
}

git_unset_remote() {
    local repo_dir="$1"
    git -C "$repo_dir" remote set-url origin \
        "https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"
}

# ════════════════════════════════════════════════════════════
#  MENU 1 — SETUP GITHUB
# ════════════════════════════════════════════════════════════
setup_github() {
    show_header
    echo -e "${WHITE}${BOLD}[ SETUP GITHUB ]${NC}"
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo ""

    read -rp "$(echo -e "${WHITE}GitHub Username       : ${NC}")" GITHUB_USERNAME
    read -rp "$(echo -e "${WHITE}Nama Repository       : ${NC}")" GITHUB_REPO_NAME
    read -rp "$(echo -e "${WHITE}Branch [main]         : ${NC}")" GITHUB_BRANCH
    GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

    echo ""
    echo -e "${YELLOW}Token: GitHub → Settings → Developer Settings → Personal Access Tokens (classic) → centang 'repo'${NC}"
    echo ""
    read -rsp "$(echo -e "${WHITE}Personal Access Token : ${NC}")" GITHUB_TOKEN
    echo ""

    echo ""
    read -rsp "$(echo -e "${WHITE}Password ZIP backup   : ${NC}")" ZIP_PASSWORD
    echo ""

    echo ""
    echo -e "${YELLOW}Notifikasi Telegram (opsional, Enter untuk skip):${NC}"
    echo -e "${YELLOW}Bot Token → @BotFather | User ID → @userinfobot${NC}"
    echo ""
    read -rsp "$(echo -e "${WHITE}Telegram Bot Token    : ${NC}")" TG_BOT_TOKEN
    echo ""
    read -rp  "$(echo -e "${WHITE}Telegram User ID      : ${NC}")" TG_USER_ID

    echo "$GITHUB_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    LOCAL_REPO="$HOME/github_backup_repo"
    save_config

    # Test Telegram
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
        echo ""
        echo -e "${CYAN}📨 Test notifikasi Telegram...${NC}"
        local resp
        resp=$(curl -s -o /dev/null -w "%{http_code}" \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TG_USER_ID}&text=✅ Backup Manager terhubung!&parse_mode=Markdown")
        [ "$resp" == "200" ] \
            && echo -e "${GREEN}✓ Telegram OK!${NC}" \
            || echo -e "${YELLOW}⚠ Gagal (HTTP $resp). Cek token & user ID.${NC}"
    fi

    echo ""
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo -e "${WHITE}🔧 Inisialisasi repository lokal...${NC}"

    local REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"

    if [ -d "$LOCAL_REPO/.git" ]; then
        echo -e "${GREEN}✓ Repo lokal sudah ada, update remote URL.${NC}"
        git -C "$LOCAL_REPO" remote set-url origin "$REMOTE_URL"
    else
        mkdir -p "$LOCAL_REPO"
        if git clone "$REMOTE_URL" "$LOCAL_REPO" 2>/dev/null; then
            echo -e "${GREEN}✓ Repo berhasil di-clone dari GitHub.${NC}"
        else
            echo -e "${YELLOW}Repo belum ada, membuat baru...${NC}"
            git -C "$LOCAL_REPO" init -q
            git -C "$LOCAL_REPO" checkout -b "$GITHUB_BRANCH" 2>/dev/null || true
            echo "# Backup Repository" > "$LOCAL_REPO/README.md"
            git -C "$LOCAL_REPO" add README.md
            git -C "$LOCAL_REPO" config user.email "backup@server.local"
            git -C "$LOCAL_REPO" config user.name "Backup Manager"
            git -C "$LOCAL_REPO" commit -m "🚀 Initial commit" -q
            git -C "$LOCAL_REPO" remote add origin "$REMOTE_URL"
            if git -C "$LOCAL_REPO" push -u origin "$GITHUB_BRANCH" -q 2>/dev/null; then
                echo -e "${GREEN}✓ Repo baru berhasil dibuat di GitHub.${NC}"
            else
                echo -e "${YELLOW}⚠ Buat repo '${GITHUB_REPO_NAME}' dulu di GitHub, lalu setup lagi.${NC}"
            fi
        fi
    fi

    git -C "$LOCAL_REPO" config user.email "backup@server.local"
    git -C "$LOCAL_REPO" config user.name "Backup Manager"

    echo ""
    echo -e "${GREEN}✅ Setup selesai!${NC}"
    log "INFO" "Setup selesai: ${GITHUB_USERNAME}/${GITHUB_REPO_NAME}"
    echo ""
    read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
}

# ════════════════════════════════════════════════════════════
#  FUNGSI BACKUP CORE
# ════════════════════════════════════════════════════════════
do_backup() {
    load_config
    check_deps

    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPO_NAME" ] || [ -z "$LOCAL_REPO" ]; then
        echo -e "${RED}❌ Belum dikonfigurasi! Jalankan Setup dulu.${NC}"
        return 1
    fi

    if [ ! -d "$LOCAL_REPO/.git" ]; then
        echo -e "${RED}❌ Repo lokal tidak ditemukan: $LOCAL_REPO${NC}"
        echo -e "${YELLOW}Jalankan Setup (menu 1) terlebih dahulu.${NC}"
        return 1
    fi

    local GITHUB_TOKEN
    GITHUB_TOKEN=$(cat "$TOKEN_FILE")
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${RED}❌ Token GitHub tidak ditemukan!${NC}"
        return 1
    fi

    local TIMESTAMP BACKUP_FILENAME STAGE_DIR
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILENAME="${BACKUP_PREFIX}_${TIMESTAMP}.zip"
    STAGE_DIR="${BACKUP_DIR}/${TIMESTAMP}"

    echo -e "${CYAN}📂 Mengumpulkan file backup...${NC}"
    mkdir -p "$STAGE_DIR"

    cp /etc/passwd                        "$STAGE_DIR/"                &>/dev/null
    cp /etc/group                         "$STAGE_DIR/"                &>/dev/null
    cp /etc/shadow                        "$STAGE_DIR/"                &>/dev/null
    cp /etc/gshadow                       "$STAGE_DIR/"                &>/dev/null
    cp /etc/crontab                       "$STAGE_DIR/"                &>/dev/null
    cp /etc/vmess/.vmess.db               "$STAGE_DIR/.vmess.db"       &>/dev/null
    cp /etc/vless/.vless.db               "$STAGE_DIR/.vless.db"       &>/dev/null
    cp /etc/trojan/.trojan.db             "$STAGE_DIR/.trojan.db"      &>/dev/null
    cp /etc/shadowsocks/.shadowsocks.db   "$STAGE_DIR/.shadowsocks.db" &>/dev/null
    cp -r /etc/limit                      "$STAGE_DIR/limit"           &>/dev/null
    cp -r /etc/vmess                      "$STAGE_DIR/vmess"           &>/dev/null
    cp -r /etc/trojan                     "$STAGE_DIR/trojan"          &>/dev/null
    cp -r /etc/vless                      "$STAGE_DIR/vless"           &>/dev/null
    cp -r /etc/shadowsocks                "$STAGE_DIR/shadowsocks"     &>/dev/null
    cp -r /etc/xray                       "$STAGE_DIR/xray"            &>/dev/null
    cp -r /etc/conf                       "$STAGE_DIR/conf"            &>/dev/null
    cp -r /var/www/html/                  "$STAGE_DIR/html"            &>/dev/null
    cp -a /detail/                        "$STAGE_DIR/detail"          &>/dev/null

    echo -e "${CYAN}🔐 Membuat ZIP terenkripsi...${NC}"
    cd "$BACKUP_DIR" || { echo -e "${RED}❌ Gagal masuk $BACKUP_DIR${NC}"; rm -rf "$STAGE_DIR"; return 1; }
    zip -r -P "$ZIP_PASSWORD" "${LOCAL_REPO}/${BACKUP_FILENAME}" "$TIMESTAMP" -q

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Gagal membuat ZIP!${NC}"
        rm -rf "$STAGE_DIR"
        return 1
    fi

    rm -rf "$STAGE_DIR"
    echo -e "${GREEN}✓ ZIP dibuat: ${BACKUP_FILENAME}${NC}"

    # ── PUSH KE GITHUB ───────────────────────────────────────
    echo -e "${CYAN}☁  Push ke GitHub...${NC}"

    git_set_remote "$LOCAL_REPO" "$GITHUB_TOKEN"
    git -C "$LOCAL_REPO" checkout "$GITHUB_BRANCH" 2>/dev/null || \
        git -C "$LOCAL_REPO" checkout -b "$GITHUB_BRANCH"
    git -C "$LOCAL_REPO" pull origin "$GITHUB_BRANCH" -q 2>/dev/null || true
    git -C "$LOCAL_REPO" add "${LOCAL_REPO}/${BACKUP_FILENAME}"
    git -C "$LOCAL_REPO" commit -m "🔄 Auto backup: $TIMESTAMP" -q

    if git -C "$LOCAL_REPO" push origin "$GITHUB_BRANCH" -q 2>&1; then
        git_unset_remote "$LOCAL_REPO"
        echo -e "${GREEN}✅ Push ke GitHub berhasil!${NC}"
        log "INFO" "Backup sukses: $BACKUP_FILENAME"
    else
        git_unset_remote "$LOCAL_REPO"
        echo -e "${RED}❌ Gagal push ke GitHub!${NC}"
        log "ERROR" "Gagal push: $BACKUP_FILENAME"
        return 1
    fi

    # ── NOTIFIKASI TELEGRAM ──────────────────────────────────
    local SERVER_IP SERVER_DOMAIN BACKUP_DATE
    SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    SERVER_DOMAIN=$(hostname -f 2>/dev/null || hostname)
    BACKUP_DATE=$(date +"%d-%m-%Y %H:%M:%S")

    send_telegram "🔄 *AUTO BACKUP BERHASIL*
━━━━━━━━━━━━━━━━━━━━
📅 *Tanggal* : ${BACKUP_DATE}
🌐 *Domain*  : ${SERVER_DOMAIN}
🖥 *IP*      : ${SERVER_IP}
🔐 *Password*: ${ZIP_PASSWORD}
📦 *File*    : ${BACKUP_FILENAME}
━━━━━━━━━━━━━━━━━━━━
✅ Backup tersimpan di GitHub"
    log "INFO" "Notifikasi Telegram terkirim"

    # ── AUTO DELETE JIKA MENCAPAI BATAS ─────────────────────
    echo -e "${CYAN}🗑  Mengecek jumlah backup di GitHub...${NC}"

    mapfile -t all_backups < <(
        git -C "$LOCAL_REPO" ls-files "${BACKUP_PREFIX}_*.zip" | sort -r
    )
    local total=${#all_backups[@]}
    echo -e "${CYAN}   Total: ${total}/${MAX_BACKUPS}${NC}"

    if [ "$total" -ge "$MAX_BACKUPS" ]; then
        echo -e "${YELLOW}⚠  Batas ${MAX_BACKUPS} tercapai! Hapus SEMUA dan mulai dari 0...${NC}"

        git_set_remote "$LOCAL_REPO" "$GITHUB_TOKEN"

        local deleted=0
        for fname in "${all_backups[@]}"; do
            git -C "$LOCAL_REPO" rm -f "$fname" -q 2>/dev/null
            rm -f "${LOCAL_REPO}/${fname}"
            echo -e "${YELLOW}   🗑 Dihapus: ${fname}${NC}"
            log "INFO" "Auto-delete: $fname"
            (( deleted++ ))
        done

        git -C "$LOCAL_REPO" commit -m "🗑 Auto-delete: reset $deleted backup (batas $MAX_BACKUPS)" -q

        if git -C "$LOCAL_REPO" push origin "$GITHUB_BRANCH" -q 2>&1; then
            echo -e "${GREEN}✅ $deleted file dihapus dari GitHub. Mulai dari 1 lagi.${NC}"
            log "INFO" "Auto-delete sukses: $deleted file"
        else
            echo -e "${RED}❌ Gagal push penghapusan!${NC}"
            log "ERROR" "Gagal push auto-delete"
        fi

        git_unset_remote "$LOCAL_REPO"
    else
        echo -e "${GREEN}✓ Belum mencapai batas.${NC}"
    fi
}

# ════════════════════════════════════════════════════════════
#  MENU 2 — START AUTO BACKUP
# ════════════════════════════════════════════════════════════
start_auto_backup() {
    show_header
    echo -e "${WHITE}${BOLD}[ AUTO BACKUP - SETIAP 3 JAM ]${NC}"
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo ""

    load_config
    if [ -z "$GITHUB_USERNAME" ]; then
        echo -e "${RED}❌ Belum dikonfigurasi! Jalankan Setup dulu.${NC}"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    local SCRIPT_PATH
    SCRIPT_PATH="$(realpath "$0")"
    local CRON_JOB="0 */4 * * * $SCRIPT_PATH --run-backup >> $LOG_FILE 2>&1"

    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
        echo -e "${YELLOW}⚠  Auto backup sudah aktif!${NC}"
        echo ""
        crontab -l | grep "$SCRIPT_PATH"
        echo ""
        read -rp "$(echo -e "${CYAN}Reset jadwal? [y/N]: ${NC}")" confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && { read -rp "$(echo -e "${CYAN}Tekan Enter...${NC}")"; return; }
    fi

    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_JOB") | crontab -

    echo ""
    echo -e "${GREEN}✅ Auto backup aktif setiap 3 jam!${NC}"
    echo ""
    echo -e "   ${CYAN}Interval :${NC} 00:00, 03:00, 06:00, 09:00, 12:00, 15:00, 18:00, 21:00"
    echo -e "   ${CYAN}Log      :${NC} tail -f $LOG_FILE"
    echo -e "   ${CYAN}Manual   :${NC} bash $SCRIPT_PATH --run-backup"
    echo ""

    read -rp "$(echo -e "${CYAN}Jalankan backup sekarang? [y/N]: ${NC}")" now
    if [[ "$now" =~ ^[Yy]$ ]]; then
        echo ""
        do_backup
    fi

    echo ""
    read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
}

# ════════════════════════════════════════════════════════════
#  MENU 3 — RESTORE DATA (langsung dari GitHub)
# ════════════════════════════════════════════════════════════
restore_data() {
    show_header
    echo -e "${WHITE}${BOLD}[ RESTORE DATA ]${NC}"
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo ""

    load_config
    if [ -z "$GITHUB_USERNAME" ]; then
        echo -e "${RED}❌ Belum dikonfigurasi! Jalankan Setup dulu.${NC}"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    local GITHUB_TOKEN
    GITHUB_TOKEN=$(cat "$TOKEN_FILE")
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${RED}❌ Token GitHub tidak ditemukan!${NC}"
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    # ── AMBIL DAFTAR DARI GITHUB API ─────────────────────────
    echo -e "${CYAN}🔄 Mengambil daftar backup dari GitHub...${NC}"

    local API_RESP
    API_RESP=$(curl -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}/contents/?ref=${GITHUB_BRANCH}")

    # Cek error
    local err_msg
    err_msg=$(echo "$API_RESP" | jq -r '.message // empty' 2>/dev/null)
    if [ -n "$err_msg" ]; then
        echo -e "${RED}❌ GitHub API error: $err_msg${NC}"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    mapfile -t backup_files < <(
        echo "$API_RESP" \
        | jq -r '.[].name' 2>/dev/null \
        | grep "^${BACKUP_PREFIX}_.*\.zip$" \
        | sort -r
    )
    local total=${#backup_files[@]}

    if [ "$total" -eq 0 ]; then
        echo -e "${RED}❌ Tidak ada file backup di GitHub!${NC}"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    echo ""
    echo -e "${WHITE}📦 Daftar Backup di GitHub:${NC}"
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo ""

    for (( i = 0; i < total; i++ )); do
        printf "  ${GREEN}[%2d]${NC} ${WHITE}%s${NC}\n" \
            $(( i + 1 )) "${backup_files[$i]}"
    done

    echo ""
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo -e "  ${RED}[0]${NC} Batal"
    echo ""
    read -rp "$(echo -e "${WHITE}Pilih nomor backup: ${NC}")" choice

    if [ "$choice" -eq 0 ] 2>/dev/null; then
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$total" ]; then
        echo -e "${RED}❌ Pilihan tidak valid!${NC}"
        sleep 2
        return
    fi

    local selected_name="${backup_files[$(( choice - 1 ))]}"

    echo ""
    echo -e "${YELLOW}⚠  File dipilih: ${CYAN}${selected_name}${NC}"
    echo ""
    read -rsp "$(echo -e "${WHITE}Masukkan password ZIP: ${NC}")" input_password
    echo ""
    echo ""
    read -rp "$(echo -e "${RED}Konfirmasi restore? Data lama akan ditimpa! [y/N]: ${NC}")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Restore dibatalkan.${NC}"
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    # ── DOWNLOAD DARI GITHUB ──────────────────────────────────
    local RESTORE_TMP="/tmp/restore_$$"
    local DOWNLOAD_PATH="${RESTORE_TMP}/${selected_name}"
    mkdir -p "$RESTORE_TMP"

    echo ""
    echo -e "${CYAN}⬇  Mengunduh ${selected_name} dari GitHub...${NC}"

    local HTTP_CODE
    HTTP_CODE=$(curl -L -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -o "$DOWNLOAD_PATH" \
        -w "%{http_code}" \
        "https://raw.githubusercontent.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}/${GITHUB_BRANCH}/${selected_name}")

    if [ "$HTTP_CODE" != "200" ] || [ ! -s "$DOWNLOAD_PATH" ]; then
        echo -e "${RED}❌ Gagal download (HTTP $HTTP_CODE)!${NC}"
        rm -rf "$RESTORE_TMP"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    echo -e "${GREEN}✓ Download selesai.${NC}"

    # ── VERIFIKASI PASSWORD ───────────────────────────────────
    echo -e "${CYAN}🔐 Verifikasi password...${NC}"
    if ! unzip -t -P "$input_password" "$DOWNLOAD_PATH" &>/dev/null; then
        echo -e "${RED}❌ Password salah atau file rusak!${NC}"
        rm -rf "$RESTORE_TMP"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi
    echo -e "${GREEN}✓ Password benar.${NC}"

    # ── EXTRACT ───────────────────────────────────────────────
    echo -e "${CYAN}📦 Mengekstrak...${NC}"
    unzip -q -P "$input_password" "$DOWNLOAD_PATH" -d "$RESTORE_TMP"

    local EXTRACT_DIR
    EXTRACT_DIR=$(find "$RESTORE_TMP" -mindepth 1 -maxdepth 1 -type d | head -1)
    [ -z "$EXTRACT_DIR" ] && EXTRACT_DIR="$RESTORE_TMP"

    if [ ! -d "$EXTRACT_DIR" ]; then
        echo -e "${RED}❌ Gagal ekstrak file!${NC}"
        rm -rf "$RESTORE_TMP"
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    # ── RESTORE ───────────────────────────────────────────────
    echo -e "${CYAN}♻  Memulai restore...${NC}"
    echo ""

    cp    "$EXTRACT_DIR/passwd"          /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/passwd"
    cp    "$EXTRACT_DIR/group"           /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/group"
    cp    "$EXTRACT_DIR/shadow"          /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/shadow"
    cp    "$EXTRACT_DIR/gshadow"         /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/gshadow"
    cp    "$EXTRACT_DIR/crontab"         /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/crontab"
    cp -r "$EXTRACT_DIR/conf"            /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/conf"
    cp -r "$EXTRACT_DIR/xray"            /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/xray"
    cp -r "$EXTRACT_DIR/html"            /var/www/         &>/dev/null && echo -e "  ${GREEN}✓${NC} /var/www/html"
    cp    "$EXTRACT_DIR/.vmess.db"       /etc/vmess/       &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vmess/.vmess.db"
    cp    "$EXTRACT_DIR/.vless.db"       /etc/vless/       &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vless/.vless.db"
    cp    "$EXTRACT_DIR/.trojan.db"      /etc/trojan/      &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/trojan/.trojan.db"
    cp    "$EXTRACT_DIR/.shadowsocks.db" /etc/shadowsocks/ &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/shadowsocks/.shadowsocks.db"
    cp -r "$EXTRACT_DIR/limit"           /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/limit"
    cp -r "$EXTRACT_DIR/vmess"           /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vmess"
    cp -r "$EXTRACT_DIR/trojan"          /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/trojan"
    cp -r "$EXTRACT_DIR/vless"           /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vless"
    cp -r "$EXTRACT_DIR/shadowsocks"     /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/shadowsocks"
    cp -a "$EXTRACT_DIR/detail/."        /detail/          &>/dev/null && echo -e "  ${GREEN}✓${NC} /detail"

    rm -rf "$RESTORE_TMP"

    echo ""
    echo -e "${GREEN}✅ Restore selesai dari: ${selected_name}${NC}"
    log "INFO" "Restore berhasil dari GitHub: $selected_name"
    echo ""
    read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
}

# ════════════════════════════════════════════════════════════
#  MAIN MENU
# ════════════════════════════════════════════════════════════
main_menu() {
    while true; do
        show_header
        echo -e "${WHITE}${BOLD}  MAIN MENU${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} ${WHITE}Setup GitHub${NC}"
        echo -e "      ${CYAN}Konfigurasi token, repo, dan password ZIP${NC}"
        echo ""
        echo -e "  ${GREEN}[2]${NC} ${WHITE}Start Auto Backup${NC}"
        echo -e "      ${CYAN}Aktifkan jadwal backup otomatis setiap 3 jam${NC}"
        echo ""
        echo -e "  ${GREEN}[3]${NC} ${WHITE}Restore Data${NC}"
        echo -e "      ${CYAN}Download & restore langsung dari GitHub${NC}"
        echo ""
        echo -e "  ${RED}[0]${NC} ${WHITE}Keluar${NC}"
        echo ""
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        read -rp "$(echo -e "${WHITE}Pilih menu [0-3]: ${NC}")" choice

        case "$choice" in
            1) setup_github ;;
            2) start_auto_backup ;;
            3) restore_data ;;
            0) echo ""; echo -e "${GREEN}Sampai jumpa!${NC}"; exit 0 ;;
            *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

# ── ENTRY POINT ──────────────────────────────────────────────
if [ "$1" == "--run-backup" ]; then
    load_config
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========== Cron backup mulai =========="
    do_backup
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========== Cron backup selesai ========="
    exit 0
fi

check_deps
main_menu

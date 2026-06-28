#!/bin/bash

# ============================================================
#           GITHUB BACKUP MANAGER v2.1
#   Auto Backup + Restore langsung dari GitHub
# ============================================================

# ── KONFIGURASI ─────────────────────────────────────────────
TOKEN_FILE="$HOME/.github_token"
CONFIG_FILE="$HOME/.backup_config"
BACKUP_DIR="/tmp/backup_staging"
BACKUP_PREFIX="backup"
MAX_BACKUPS=10
LOG_FILE="/var/log/backup_manager.log"
LOCAL_REPO="$HOME/github_backup_repo"   # FIX: Didefinisikan di awal
# ────────────────────────────────────────────────────────────

# ── WARNA ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
# ────────────────────────────────────────────────────────────

# ── LOAD / SAVE CONFIG ───────────────────────────────────────
load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
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

# ── LOG ──────────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE"
}

# ── HEADER ───────────────────────────────────────────────────
show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}${BOLD}          GITHUB BACKUP MANAGER v2.1                 ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${BLUE}║${NC} ${CYAN}Repo  :${NC} ${GITHUB_USERNAME}/${GITHUB_REPO_NAME}"
        echo -e "${BLUE}║${NC} ${CYAN}Branch:${NC} ${GITHUB_BRANCH:-main}"
        echo -e "${BLUE}║${NC} ${CYAN}Path  :${NC} ${LOCAL_REPO}"
    else
        echo -e "${BLUE}║${NC} ${YELLOW}⚠  Belum dikonfigurasi. Pilih menu Setup dulu.${NC}"
    fi
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── CEK DEPENDENSI ───────────────────────────────────────────
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

# ── TELEGRAM ─────────────────────────────────────────────────
send_telegram() {
    local message="$1"
    [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_USER_ID" ] && return 0
    curl -s -o /dev/null \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" \
        -d "text=${message}" \
        -d "parse_mode=Markdown"
}

# ════════════════════════════════════════════════════════════
#  FUNGSI: CEK & INIT REPO GIT (FIX BUG)
# ════════════════════════════════════════════════════════════
ensure_git_repo() {
    load_config
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPO_NAME" ]; then
        echo -e "${RED}❌ Belum dikonfigurasi! Jalankan Setup dulu.${NC}"
        return 1
    fi

    local GITHUB_TOKEN
    GITHUB_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null)
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${RED}❌ Token tidak ditemukan! Jalankan Setup ulang.${NC}"
        return 1
    fi

    local REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"
    local REMOTE_URL_PUBLIC="https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"

    # ── Cek apakah repo lokal ada ────────────────────────────
    if [ ! -d "$LOCAL_REPO" ]; then
        echo -e "${YELLOW}⚠  Folder repo tidak ditemukan. Membuat baru...${NC}"
        mkdir -p "$LOCAL_REPO"
    fi

    cd "$LOCAL_REPO" || return 1

    # ── Cek apakah .git ada ──────────────────────────────────
    if [ ! -d "$LOCAL_REPO/.git" ]; then
        echo -e "${YELLOW}⚠  Repo Git belum diinisialisasi.${NC}"
        
        # Coba clone dulu
        echo -e "${CYAN}   Mencoba clone dari GitHub...${NC}"
        if git clone "$REMOTE_URL" . 2>/dev/null; then
            echo -e "${GREEN}✓ Clone berhasil!${NC}"
        else
            echo -e "${YELLOW}   Repo di GitHub belum ada atau kosong. Membuat baru...${NC}"
            git init -q
            git checkout -b "$GITHUB_BRANCH" 2>/dev/null || true
            echo "# Backup Repository - $(date)" > README.md
            git add README.md
            git config user.email "backup@server.local"
            git config user.name "Backup Manager"
            git commit -m "🚀 Initial commit" -q
            git remote add origin "$REMOTE_URL"
            
            echo -e "${CYAN}   Push ke GitHub...${NC}"
            if git push -u origin "$GITHUB_BRANCH" -q 2>/dev/null; then
                echo -e "${GREEN}✓ Repo baru berhasil dibuat di GitHub!${NC}"
            else
                echo -e "${RED}❌ Gagal push ke GitHub. Buat repo manual dulu di GitHub.${NC}"
                return 1
            fi
        fi
    fi

    # ── Pastikan remote URL benar ────────────────────────────
    git remote set-url origin "$REMOTE_URL" 2>/dev/null || git remote add origin "$REMOTE_URL"
    
    # ── Pastikan branch benar ────────────────────────────────
    git checkout "$GITHUB_BRANCH" 2>/dev/null || git checkout -b "$GITHUB_BRANCH"
    
    # ── Set konfigurasi Git ──────────────────────────────────
    git config user.email "backup@server.local"
    git config user.name "Backup Manager"

    # ── Simpan remote public untuk digunakan setelah push ────
    echo "$REMOTE_URL_PUBLIC" > "$LOCAL_REPO/.remote_public"
    
    echo -e "${GREEN}✓ Repo Git siap digunakan.${NC}"
    return 0
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

    # Simpan token
    echo "$GITHUB_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    
    # Simpan config
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
            && echo -e "${GREEN}✓ Telegram berhasil!${NC}" \
            || echo -e "${YELLOW}⚠ Gagal (HTTP $resp). Cek bot token & user ID.${NC}"
    fi

    echo ""
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo -e "${WHITE}🔧 Inisialisasi repository lokal...${NC}"

    # Panggil fungsi ensure_git_repo
    if ensure_git_repo; then
        echo -e "${GREEN}✅ Setup selesai!${NC}"
        log "INFO" "Setup selesai: ${GITHUB_USERNAME}/${GITHUB_REPO_NAME}"
    else
        echo -e "${RED}❌ Setup gagal! Periksa koneksi dan token.${NC}"
        log "ERROR" "Setup gagal"
    fi

    echo ""
    read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
}

# ════════════════════════════════════════════════════════════
#  FUNGSI BACKUP CORE
# ════════════════════════════════════════════════════════════
do_backup() {
    load_config
    check_deps

    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPO_NAME" ]; then
        echo -e "${RED}❌ Belum dikonfigurasi!${NC}"
        return 1
    fi

    # ── FIX: PASTIKAN REPO GIT VALID ─────────────────────────
    if ! ensure_git_repo; then
        echo -e "${RED}❌ Repo Git tidak valid. Jalankan Setup ulang.${NC}"
        return 1
    fi

    # ── Mulai backup ──────────────────────────────────────────
    local TIMESTAMP BACKUP_FILENAME STAGE_DIR
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILENAME="${BACKUP_PREFIX}_${TIMESTAMP}.zip"
    STAGE_DIR="${BACKUP_DIR}/${TIMESTAMP}"

    echo -e "${CYAN}📂 Mengumpulkan file backup...${NC}"
    mkdir -p "$STAGE_DIR"

    # ── COPY FILE ────────────────────────────────────────────
    cp /etc/passwd                       "$STAGE_DIR/"              &>/dev/null
    cp /etc/group                        "$STAGE_DIR/"              &>/dev/null
    cp /etc/shadow                       "$STAGE_DIR/"              &>/dev/null
    cp /etc/gshadow                      "$STAGE_DIR/"              &>/dev/null
    cp /etc/crontab                      "$STAGE_DIR/"              &>/dev/null
    cp /etc/vmess/.vmess.db              "$STAGE_DIR/.vmess.db"     &>/dev/null
    cp /etc/vless/.vless.db              "$STAGE_DIR/.vless.db"     &>/dev/null
    cp /etc/trojan/.trojan.db            "$STAGE_DIR/.trojan.db"    &>/dev/null
    cp /etc/shadowsocks/.shadowsocks.db  "$STAGE_DIR/.shadowsocks.db" &>/dev/null
    cp -r /etc/limit                     "$STAGE_DIR/limit"         &>/dev/null
    cp -r /etc/vmess                     "$STAGE_DIR/vmess"         &>/dev/null
    cp -r /etc/trojan                    "$STAGE_DIR/trojan"        &>/dev/null
    cp -r /etc/vless                     "$STAGE_DIR/vless"         &>/dev/null
    cp -r /etc/shadowsocks               "$STAGE_DIR/shadowsocks"   &>/dev/null
    cp -r /etc/xray                      "$STAGE_DIR/xray"          &>/dev/null
    cp -r /etc/conf                      "$STAGE_DIR/conf"          &>/dev/null
    cp -r /var/www/html/                 "$STAGE_DIR/html"          &>/dev/null
    cp -a /detail/                       "$STAGE_DIR/detail"        &>/dev/null
    # ─────────────────────────────────────────────────────────

    echo -e "${CYAN}🔐 Membuat ZIP terenkripsi...${NC}"
    cd "$BACKUP_DIR" || return 1
    zip -r -P "$ZIP_PASSWORD" "${LOCAL_REPO}/${BACKUP_FILENAME}" "$TIMESTAMP" -q

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Gagal membuat ZIP!${NC}"
        rm -rf "$STAGE_DIR"
        return 1
    fi

    rm -rf "$STAGE_DIR"
    echo -e "${GREEN}✓ Backup dibuat: ${BACKUP_FILENAME}${NC}"

    # ── PUSH KE GITHUB ───────────────────────────────────────
    echo -e "${CYAN}☁  Push ke GitHub...${NC}"
    cd "$LOCAL_REPO" || return 1

    local GITHUB_TOKEN
    GITHUB_TOKEN=$(cat "$TOKEN_FILE")
    local REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"
    local REMOTE_URL_PUBLIC="https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"

    # Set remote dengan token
    git remote set-url origin "$REMOTE_URL"
    git checkout "$GITHUB_BRANCH" 2>/dev/null || git checkout -b "$GITHUB_BRANCH"
    
    git add "${BACKUP_FILENAME}"
    git commit -m "🔄 Auto backup: $TIMESTAMP" -q

    # Push dengan error handling
    if ! git push origin "$GITHUB_BRANCH" 2>&1; then
        # Reset remote ke public (tanpa token)
        git remote set-url origin "$REMOTE_URL_PUBLIC"
        echo -e "${RED}❌ Gagal push ke GitHub!${NC}"
        log "ERROR" "Gagal push: $BACKUP_FILENAME"
        return 1
    fi

    # Reset remote ke public (tanpa token) untuk keamanan
    git remote set-url origin "$REMOTE_URL_PUBLIC"
    echo -e "${GREEN}✅ Backup berhasil di-push ke GitHub!${NC}"
    log "INFO" "Backup sukses: $BACKUP_FILENAME"

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
    echo -e "${CYAN}🗑  Mengecek batas backup...${NC}"

    # Ambil daftar dari git tracking
    mapfile -t all_backups < <(
        git -C "$LOCAL_REPO" ls-files "${BACKUP_PREFIX}_*.zip" | sort -r
    )
    local total=${#all_backups[@]}
    echo -e "${CYAN}   Total backup di GitHub: ${total}/${MAX_BACKUPS}${NC}"

    if [ "$total" -ge "$MAX_BACKUPS" ]; then
        echo -e "${YELLOW}⚠  Batas ${MAX_BACKUPS} tercapai! Menghapus SEMUA backup lama...${NC}"

        # Set remote dengan token untuk push delete
        git remote set-url origin "$REMOTE_URL"

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
            log "INFO" "Auto-delete: $deleted file dihapus"
        else
            echo -e "${RED}❌ Gagal push penghapusan!${NC}"
            log "ERROR" "Gagal push auto-delete"
        fi

        # Reset remote ke public
        git remote set-url origin "$REMOTE_URL_PUBLIC"
    else
        echo -e "${GREEN}✓ Jumlah backup: ${total}/${MAX_BACKUPS}, belum mencapai batas.${NC}"
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
    local CRON_JOB="0 */3 * * * /bin/bash $SCRIPT_PATH --run-backup >> $LOG_FILE 2>&1"

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
    echo -e "${GREEN}✅ Auto backup aktif!${NC}"
    echo ""
    echo -e "   ${CYAN}Interval :${NC} Setiap 3 jam (00:00, 03:00, 06:00, ...)"
    echo -e "   ${CYAN}Log      :${NC} tail -f $LOG_FILE"
    echo -e "   ${CYAN}Manual   :${NC} bash $SCRIPT_PATH --run-backup"
    echo ""

    read -rp "$(echo -e "${CYAN}Jalankan backup sekarang? [y/N]: ${NC}")" now
    [[ "$now" =~ ^[Yy]$ ]] && { echo ""; do_backup; }

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

    # ── AMBIL DAFTAR FILE DARI GITHUB API ────────────────────
    echo -e "${CYAN}🔄 Mengambil daftar backup dari GitHub...${NC}"

    local API_URL="https://api.github.com/repos/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}/contents/"
    local API_RESP
    API_RESP=$(curl -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${API_URL}?ref=${GITHUB_BRANCH}")

    # Cek error API
    if echo "$API_RESP" | jq -e '.message' &>/dev/null; then
        local err_msg
        err_msg=$(echo "$API_RESP" | jq -r '.message')
        echo -e "${RED}❌ Gagal ambil data dari GitHub: $err_msg${NC}"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    # Filter hanya file backup_.zip, urutkan terbaru dulu
    mapfile -t backup_files < <(
        echo "$API_RESP" | jq -r '.[].name' 2>/dev/null \
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
    echo -e "${YELLOW}⚠  PERHATIAN! Restore akan menimpa data saat ini!${NC}"
    echo -e "${WHITE}File dipilih: ${CYAN}${selected_name}${NC}"
    echo ""
    read -rsp "$(echo -e "${WHITE}Masukkan password ZIP: ${NC}")" input_password
    echo ""
    echo ""
    read -rp "$(echo -e "${RED}Konfirmasi restore? [y/N]: ${NC}")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Restore dibatalkan.${NC}"
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    # ── DOWNLOAD LANGSUNG DARI GITHUB ────────────────────────
    local RESTORE_TMP="/tmp/restore_$$"
    local DOWNLOAD_PATH="${RESTORE_TMP}/${selected_name}"
    mkdir -p "$RESTORE_TMP"

    echo ""
    echo -e "${CYAN}⬇  Mengunduh ${selected_name} dari GitHub...${NC}"

    local DOWNLOAD_URL="https://raw.githubusercontent.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}/${GITHUB_BRANCH}/${selected_name}"
    local HTTP_CODE
    HTTP_CODE=$(curl -L -s -o "$DOWNLOAD_PATH" -w "%{http_code}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        "$DOWNLOAD_URL")

    if [ "$HTTP_CODE" != "200" ] || [ ! -f "$DOWNLOAD_PATH" ]; then
        echo -e "${RED}❌ Gagal download (HTTP $HTTP_CODE)!${NC}"
        rm -rf "$RESTORE_TMP"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    echo -e "${GREEN}✓ Download selesai.${NC}"

    # ── VERIFIKASI PASSWORD ───────────────────────────────────
    echo -e "${CYAN}🔐 Memverifikasi password ZIP...${NC}"
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

    # ── RESTORE ───────────────────────────────────────────────
    echo -e "${CYAN}♻  Memulai restore...${NC}"
    echo ""
    cd "$EXTRACT_DIR" || { echo -e "${RED}❌ Gagal masuk direktori extract!${NC}"; rm -rf "$RESTORE_TMP"; return 1; }

    cp passwd                /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/passwd"
    cp group                 /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/group"
    cp shadow                /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/shadow"
    cp gshadow               /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/gshadow"
    cp crontab               /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/crontab"
    cp -r conf               /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/conf"
    cp -r xray               /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/xray"
    cp -r html               /var/www/         &>/dev/null && echo -e "  ${GREEN}✓${NC} /var/www/html"
    cp .vmess.db             /etc/vmess/       &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vmess/.vmess.db"
    cp .vless.db             /etc/vless/       &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vless/.vless.db"
    cp .trojan.db            /etc/trojan/      &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/trojan/.trojan.db"
    cp .shadowsocks.db       /etc/shadowsocks/ &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/shadowsocks/.shadowsocks.db"
    cp -r limit              /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/limit"
    cp -r vmess              /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vmess"
    cp -r trojan             /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/trojan"
    cp -r vless              /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vless"
    cp -r shadowsocks        /etc/             &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/shadowsocks"
    cp -a detail/.           /detail/          &>/dev/null && echo -e "  ${GREEN}✓${NC} /detail"

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

#!/bin/bash

# ============================================================
#           GITHUB BACKUP MANAGER
#   Auto Backup + Restore dengan enkripsi ZIP & password
# ============================================================

# ── KONFIGURASI ─────────────────────────────────────────────
TOKEN_FILE="$HOME/.github_token"
CONFIG_FILE="$HOME/.backup_config"
BACKUP_DIR="/tmp/backup_staging"
BACKUP_PREFIX="backup"
MAX_BACKUPS=10
LOG_FILE="/var/log/backup_manager.log"
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

# ── LOAD CONFIG ──────────────────────────────────────────────
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
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

# ── FUNGSI LOG ───────────────────────────────────────────────
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

# ── HEADER ───────────────────────────────────────────────────
show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}${BOLD}           GITHUB BACKUP MANAGER v1.0                ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${NC}"

    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${BLUE}║${NC} ${CYAN}Repo  :${NC} ${GITHUB_USERNAME}/${GITHUB_REPO_NAME}                "
        echo -e "${BLUE}║${NC} ${CYAN}Branch:${NC} ${GITHUB_BRANCH:-main}                               "
        echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${BLUE}║${NC} ${YELLOW}⚠  Belum dikonfigurasi. Pilih menu Setup dulu.${NC}       "
        echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    fi
    echo ""
}

# ── CEK DEPENDENSI ───────────────────────────────────────────
check_deps() {
    local missing=()
    for cmd in git zip unzip curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}📦 Menginstall dependensi yang kurang: ${missing[*]}${NC}"
        apt-get install -y "${missing[@]}" -qq
    fi
}

# ════════════════════════════════════════════════════════════
#  MENU 1 — SETUP GITHUB
# ════════════════════════════════════════════════════════════
setup_github() {
    show_header
    echo -e "${WHITE}${BOLD}[ SETUP GITHUB ]${NC}"
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo ""

    # Username
    read -rp "$(echo -e "${WHITE}GitHub Username : ${NC}")" GITHUB_USERNAME
    # Repo name
    read -rp "$(echo -e "${WHITE}Nama Repository : ${NC}")" GITHUB_REPO_NAME
    # Branch
    read -rp "$(echo -e "${WHITE}Branch [main]   : ${NC}")" GITHUB_BRANCH
    GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

    # Token
    echo ""
    echo -e "${YELLOW}Dapatkan token di: GitHub → Settings → Developer Settings${NC}"
    echo -e "${YELLOW}→ Personal Access Tokens (classic) → centang 'repo'${NC}"
    echo ""
    read -rsp "$(echo -e "${WHITE}Personal Access Token : ${NC}")" GITHUB_TOKEN
    echo ""

    # ZIP Password
    echo ""
    read -rsp "$(echo -e "${WHITE}Password ZIP backup   : ${NC}")" ZIP_PASSWORD
    echo ""

    # Telegram Notifikasi
    echo ""
    echo -e "${YELLOW}Notifikasi Telegram (opsional, Enter untuk skip):${NC}"
    echo -e "${YELLOW}Buat bot via @BotFather → dapatkan token & user ID via @userinfobot${NC}"
    echo ""
    read -rsp "$(echo -e "${WHITE}Telegram Bot Token    : ${NC}")" TG_BOT_TOKEN
    echo ""
    read -rp  "$(echo -e "${WHITE}Telegram User ID      : ${NC}")" TG_USER_ID

    # Simpan token
    echo "$GITHUB_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"

    # Path repo lokal
    LOCAL_REPO="$HOME/github_backup_repo"

    # Simpan config
    save_config

    # Test notif Telegram jika diisi
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
        echo ""
        echo -e "${CYAN}📨 Mengirim pesan test ke Telegram...${NC}"
        local test_msg="✅ *Backup Manager Terhubung!*%0ASetup berhasil dikonfigurasi di server ini."
        local test_resp
        test_resp=$(curl -s -o /dev/null -w "%{http_code}"             "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"             -d "chat_id=${TG_USER_ID}&text=${test_msg}&parse_mode=Markdown")
        if [ "$test_resp" == "200" ]; then
            echo -e "${GREEN}✓ Notifikasi Telegram berhasil dikirim!${NC}"
        else
            echo -e "${YELLOW}⚠ Gagal kirim test Telegram (HTTP $test_resp). Cek bot token & user ID.${NC}"
        fi
    fi

    echo ""
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo -e "${WHITE}🔧 Menginisialisasi repository lokal...${NC}"

    # Clone atau init repo
    if [ -d "$LOCAL_REPO/.git" ]; then
        echo -e "${GREEN}✓ Repo lokal sudah ada.${NC}"
    else
        mkdir -p "$LOCAL_REPO"
        cd "$LOCAL_REPO" || exit 1

        REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"

        # Coba clone dulu
        if git clone "$REMOTE_URL" . 2>/dev/null; then
            echo -e "${GREEN}✓ Repository berhasil di-clone dari GitHub.${NC}"
        else
            # Jika repo belum ada di GitHub, init baru
            git init
            git checkout -b "$GITHUB_BRANCH" 2>/dev/null || true
            echo "# Backup Repository" > README.md
            git add README.md
            git config user.email "backup@server.local"
            git config user.name "Backup Manager"
            git commit -m "🚀 Initial commit"
            git remote add origin "$REMOTE_URL"
            git push -u origin "$GITHUB_BRANCH" 2>/dev/null && \
                echo -e "${GREEN}✓ Repository baru berhasil dibuat di GitHub.${NC}" || \
                echo -e "${YELLOW}⚠ Buat repo '${GITHUB_REPO_NAME}' dulu di GitHub secara manual, lalu jalankan setup lagi.${NC}"
        fi
    fi

    # Set git config
    cd "$LOCAL_REPO" || exit 1
    git config user.email "backup@server.local"
    git config user.name "Backup Manager"

    echo ""
    echo -e "${GREEN}✅ Setup berhasil!${NC}"
    log "INFO" "Setup GitHub selesai: ${GITHUB_USERNAME}/${GITHUB_REPO_NAME}"
    echo ""
    read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
}

# ════════════════════════════════════════════════════════════
#  FUNGSI NOTIFIKASI TELEGRAM
# ════════════════════════════════════════════════════════════
send_telegram() {
    local message="$1"

    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_USER_ID" ]; then
        return 0  # Skip jika tidak dikonfigurasi
    fi

    curl -s -o /dev/null         "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"         -d "chat_id=${TG_USER_ID}"         -d "text=${message}"         -d "parse_mode=Markdown"
}

# ════════════════════════════════════════════════════════════
#  FUNGSI BACKUP CORE
# ════════════════════════════════════════════════════════════
do_backup() {
    load_config
    check_deps

    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPO_NAME" ]; then
        echo -e "${RED}❌ Belum dikonfigurasi! Jalankan Setup dulu.${NC}"
        return 1
    fi

    local TIMESTAMP
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local BACKUP_FILENAME="${BACKUP_PREFIX}_${TIMESTAMP}.zip"
    local STAGE_DIR="${BACKUP_DIR}/${TIMESTAMP}"

    echo -e "${CYAN}📂 Mengumpulkan file backup...${NC}"
    mkdir -p "$STAGE_DIR"

    # ── COPY FILE BACKUP ─────────────────────────────────────
    cp /etc/passwd        "$STAGE_DIR/"          &>/dev/null
    cp /etc/group         "$STAGE_DIR/"          &>/dev/null
    cp /etc/shadow        "$STAGE_DIR/"          &>/dev/null
    cp /etc/gshadow       "$STAGE_DIR/"          &>/dev/null
    cp /etc/crontab       "$STAGE_DIR/"          &>/dev/null
    cp /etc/vmess/.vmess.db         "$STAGE_DIR/" &>/dev/null
    cp /etc/vless/.vless.db         "$STAGE_DIR/" &>/dev/null
    cp /etc/trojan/.trojan.db       "$STAGE_DIR/" &>/dev/null
    cp /etc/shadowsocks/.shadowsocks.db "$STAGE_DIR/" &>/dev/null
    cp -r /etc/limit      "$STAGE_DIR/limit"     &>/dev/null
    cp -r /etc/vmess      "$STAGE_DIR/vmess"     &>/dev/null
    cp -r /etc/trojan     "$STAGE_DIR/trojan"    &>/dev/null
    cp -r /etc/vless      "$STAGE_DIR/vless"     &>/dev/null
    cp -r /etc/shadowsocks "$STAGE_DIR/shadowsocks" &>/dev/null
    cp -r /etc/xray       "$STAGE_DIR/xray"      &>/dev/null
    cp -r /etc/conf       "$STAGE_DIR/conf"      &>/dev/null
    cp -r /var/www/html/  "$STAGE_DIR/html"      &>/dev/null
    cp -a /detail/        "$STAGE_DIR/detail"    &>/dev/null
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

    # ── PUSH BACKUP BARU KE GITHUB ───────────────────────────
    echo -e "${CYAN}☁  Push backup baru ke GitHub...${NC}"
    cd "$LOCAL_REPO" || return 1

    local GITHUB_TOKEN
    GITHUB_TOKEN=$(cat "$TOKEN_FILE")
    git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"

    git checkout "$GITHUB_BRANCH" 2>/dev/null || git checkout -b "$GITHUB_BRANCH"
    git add "${BACKUP_FILENAME}"
    git commit -m "🔄 Auto backup: $TIMESTAMP" -q

    if ! git push origin "$GITHUB_BRANCH" -q 2>&1; then
        git remote set-url origin "https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"
        echo -e "${RED}❌ Gagal push ke GitHub!${NC}"
        log "ERROR" "Gagal push: $BACKUP_FILENAME"
        return 1
    fi

    echo -e "${GREEN}✅ Backup berhasil di-push ke GitHub!${NC}"
    log "INFO" "Backup sukses: $BACKUP_FILENAME"

    # ── KIRIM NOTIFIKASI TELEGRAM ────────────────────────────
    local SERVER_IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    local SERVER_DOMAIN
    SERVER_DOMAIN=$(hostname -f 2>/dev/null || hostname)
    local BACKUP_DATE
    BACKUP_DATE=$(date +"%d-%m-%Y %H:%M:%S")

    local TG_MESSAGE
    TG_MESSAGE="🔄 *AUTO BACKUP BERHASIL*
━━━━━━━━━━━━━━━━━━━━
📅 *Tanggal* : ${BACKUP_DATE}
🌐 *Domain*  : ${SERVER_DOMAIN}
🖥 *IP*      : ${SERVER_IP}
🔐 *Password*: \`${ZIP_PASSWORD}\`
📦 *File*    : \`${BACKUP_FILENAME}\`
━━━━━━━━━━━━━━━━━━━━
✅ Backup tersimpan di GitHub"

    send_telegram "$TG_MESSAGE"
    log "INFO" "Notifikasi Telegram terkirim"

    # ── AUTO DELETE BACKUP LAMA ──────────────────────────────
    # Jika total backup di GitHub sudah mencapai MAX_BACKUPS (10),
    # hapus SEMUA file backup lalu mulai dari 0 lagi
    echo -e "${CYAN}🗑  Mengecek batas maksimal backup...${NC}"

    # Ambil daftar file backup dari git tracking (sumber = GitHub)
    mapfile -t backup_files < <(
        git -C "$LOCAL_REPO" ls-files "${BACKUP_PREFIX}_*.zip" | sort -r
    )
    local total=${#backup_files[@]}

    echo -e "${CYAN}   Total backup di GitHub: ${total}/${MAX_BACKUPS}${NC}"

    if [ "$total" -ge "$MAX_BACKUPS" ]; then
        echo -e "${YELLOW}⚠  Batas $MAX_BACKUPS file tercapai! Menghapus SEMUA backup lama...${NC}"

        local deleted=0
        for old_name in "${backup_files[@]}"; do
            # Hapus dari git tracking → hilang dari GitHub saat push
            git -C "$LOCAL_REPO" rm -f "$old_name" -q 2>/dev/null

            # Hapus file fisik lokal
            rm -f "${LOCAL_REPO}/${old_name}"

            echo -e "${YELLOW}   🗑 Dihapus: ${old_name}${NC}"
            log "INFO" "Auto-delete: $old_name"
            (( deleted++ ))
        done

        # Commit & push penghapusan semua file ke GitHub
        git -C "$LOCAL_REPO" commit -m "🗑 Auto-delete: reset semua $deleted backup (batas $MAX_BACKUPS tercapai)" -q
        if git -C "$LOCAL_REPO" push origin "$GITHUB_BRANCH" -q 2>&1; then
            echo -e "${GREEN}✅ Semua $deleted file backup lama berhasil dihapus dari GitHub!${NC}"
            echo -e "${GREEN}   Backup baru akan mulai dari 1 lagi.${NC}"
            log "INFO" "Auto-delete reset: $deleted file dihapus, mulai dari 0"
        else
            echo -e "${RED}❌ Gagal push penghapusan ke GitHub!${NC}"
            log "ERROR" "Gagal push delete reset ke GitHub"
        fi
    else
        echo -e "${GREEN}✓ Jumlah backup: ${total}/${MAX_BACKUPS}, belum mencapai batas.${NC}"
    fi

    # Bersihkan token dari remote URL
    git remote set-url origin "https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"
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

    # Cek apakah cron sudah ada
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
        echo -e "${YELLOW}⚠  Auto backup sudah aktif!${NC}"
        echo ""
        echo -e "${WHITE}Jadwal saat ini:${NC}"
        crontab -l | grep "$SCRIPT_PATH"
        echo ""
        read -rp "$(echo -e "${CYAN}Reset/update jadwal? [y/N]: ${NC}")" confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
            return
        fi
    fi

    # Daftarkan cron
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_JOB") | crontab -

    echo ""
    echo -e "${GREEN}✅ Auto backup berhasil diaktifkan!${NC}"
    echo ""
    echo -e "${WHITE}📋 Detail jadwal:${NC}"
    echo -e "   ${CYAN}Interval  :${NC} Setiap 3 jam (00:00, 03:00, 06:00, ...)"
    echo -e "   ${CYAN}Log file  :${NC} $LOG_FILE"
    echo -e "   ${CYAN}Max file  :${NC} $MAX_BACKUPS backup"
    echo ""
    echo -e "${WHITE}Perintah berguna:${NC}"
    echo -e "   ${YELLOW}Lihat log   :${NC} tail -f $LOG_FILE"
    echo -e "   ${YELLOW}Backup kini :${NC} bash $SCRIPT_PATH --run-backup"
    echo -e "   ${YELLOW}Hapus cron  :${NC} crontab -e"
    echo ""

    read -rp "$(echo -e "${CYAN}Jalankan backup sekarang juga? [y/N]: ${NC}")" now
    if [[ "$now" =~ ^[Yy]$ ]]; then
        echo ""
        do_backup
    fi

    echo ""
    read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
}

# ════════════════════════════════════════════════════════════
#  MENU 3 — RESTORE DATA
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

    # Pull dulu biar update
    echo -e "${CYAN}🔄 Mengambil daftar backup dari GitHub...${NC}"
    cd "$LOCAL_REPO" || { echo -e "${RED}❌ Repo lokal tidak ditemukan!${NC}"; return; }

    local GITHUB_TOKEN
    GITHUB_TOKEN=$(cat "$TOKEN_FILE")
    git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"
    git pull origin "$GITHUB_BRANCH" -q 2>/dev/null
    git remote set-url origin "https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"

    # Ambil daftar file backup
    mapfile -t backup_files < <(ls -1t "${LOCAL_REPO}/${BACKUP_PREFIX}_"*.zip 2>/dev/null)
    local total=${#backup_files[@]}

    if [ "$total" -eq 0 ]; then
        echo -e "${RED}❌ Tidak ada file backup ditemukan!${NC}"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    echo ""
    echo -e "${WHITE}📦 Daftar Backup Tersedia:${NC}"
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo ""

    for (( i = 0; i < total; i++ )); do
        local fname
        fname=$(basename "${backup_files[$i]}")
        local fdate
        fdate=$(echo "$fname" | grep -oP '\d{8}_\d{6}' | sed 's/\(\d\{4\}\)\(\d\{2\}\)\(\d\{2\}\)_\(\d\{2\}\)\(\d\{2\}\)\(\d\{2\}\)/\1-\2-\3 \4:\5:\6/')
        local fsize
        fsize=$(du -sh "${backup_files[$i]}" 2>/dev/null | cut -f1)

        printf "  ${GREEN}[%2d]${NC} ${WHITE}%-42s${NC} ${CYAN}%s${NC} ${YELLOW}(%s)${NC}\n" \
            $(( i + 1 )) "$fname" "$fdate" "$fsize"
    done

    echo ""
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo -e "  ${RED}[0]${NC} Batal"
    echo ""
    read -rp "$(echo -e "${WHITE}Pilih nomor backup yang ingin di-restore: ${NC}")" choice

    if [ "$choice" -eq 0 ] 2>/dev/null; then
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$total" ]; then
        echo -e "${RED}❌ Pilihan tidak valid!${NC}"
        sleep 2
        return
    fi

    local selected_file="${backup_files[$(( choice - 1 ))]}"
    local selected_name
    selected_name=$(basename "$selected_file")

    echo ""
    echo -e "${YELLOW}⚠  PERHATIAN! Restore akan menimpa data yang ada saat ini!${NC}"
    echo -e "${WHITE}File dipilih: ${CYAN}${selected_name}${NC}"
    echo ""
    read -rsp "$(echo -e "${WHITE}Masukkan password ZIP: ${NC}")" input_password
    echo ""

    # Test password dulu
    echo -e "${CYAN}🔐 Memverifikasi password...${NC}"
    if ! unzip -t -P "$input_password" "$selected_file" &>/dev/null; then
        echo -e "${RED}❌ Password salah atau file rusak!${NC}"
        echo ""
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi
    echo -e "${GREEN}✓ Password benar.${NC}"

    echo ""
    read -rp "$(echo -e "${RED}Konfirmasi restore? Data lama akan ditimpa! [y/N]: ${NC}")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Restore dibatalkan.${NC}"
        read -rp "$(echo -e "${CYAN}Tekan Enter untuk kembali...${NC}")"
        return
    fi

    # Extract ke temp
    local RESTORE_TMP="/tmp/restore_$$"
    mkdir -p "$RESTORE_TMP"

    echo ""
    echo -e "${CYAN}📦 Mengekstrak file backup...${NC}"
    unzip -q -P "$input_password" "$selected_file" -d "$RESTORE_TMP"

    # Cari folder hasil extract (subfolder timestamp)
    local EXTRACT_DIR
    EXTRACT_DIR=$(find "$RESTORE_TMP" -mindepth 1 -maxdepth 1 -type d | head -1)

    if [ -z "$EXTRACT_DIR" ]; then
        EXTRACT_DIR="$RESTORE_TMP"
    fi

    echo -e "${CYAN}♻  Memulai restore...${NC}"
    cd "$EXTRACT_DIR" || return 1

    # ── RESTORE FILE ─────────────────────────────────────────
    cp passwd          /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/passwd"
    cp group           /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/group"
    cp shadow          /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/shadow"
    cp gshadow         /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/gshadow"
    cp crontab         /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/crontab"
    cp -r conf         /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/conf"
    cp -r xray         /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/xray"
    cp -r html         /var/www/          &>/dev/null && echo -e "  ${GREEN}✓${NC} /var/www/html"
    cp .vmess.db       /etc/vmess/        &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vmess/.vmess.db"
    cp .vless.db       /etc/vless/        &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vless/.vless.db"
    cp .trojan.db      /etc/trojan/       &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/trojan/.trojan.db"
    cp .shadowsocks.db /etc/shadowsocks/  &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/shadowsocks/.shadowsocks.db"
    cp -r limit        /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/limit"
    cp -r vmess        /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vmess"
    cp -r trojan       /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/trojan"
    cp -r vless        /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/vless"
    cp -r shadowsocks  /etc/              &>/dev/null && echo -e "  ${GREEN}✓${NC} /etc/shadowsocks"
    cp -a detail/.     /detail/           &>/dev/null && echo -e "  ${GREEN}✓${NC} /detail"
    # ─────────────────────────────────────────────────────────

    rm -rf "$RESTORE_TMP"

    echo ""
    echo -e "${GREEN}✅ Restore selesai dari: ${selected_name}${NC}"
    log "INFO" "Restore berhasil dari: $selected_name"
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
        echo -e "      ${CYAN}Pilih dan restore dari daftar backup di GitHub${NC}"
        echo ""
        echo -e "  ${RED}[0]${NC} ${WHITE}Keluar${NC}"
        echo ""
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        read -rp "$(echo -e "${WHITE}Pilih menu [0-3]: ${NC}")" choice

        case "$choice" in
            1) setup_github ;;
            2) start_auto_backup ;;
            3) restore_data ;;
            0)
                echo ""
                echo -e "${GREEN}Sampai jumpa!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

# ── ENTRY POINT ──────────────────────────────────────────────
# Dipanggil dari cron dengan flag --run-backup
if [ "$1" == "--run-backup" ]; then
    load_config
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========== Cron backup mulai =========="
    do_backup
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========== Cron backup selesai ========="
    exit 0
fi

# Panggil menu utama
check_deps
main_menu

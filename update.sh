#!/bin/bash
clear
y='\033[1;33m'
BGX="\033[42m"
CYAN="\033[96m"
Putih="\033[97m"
RED='\033[0;31m'
NC='\033[0m'
green='\033[0;32m'
BIBlack='\033[1;90m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIBlue='\033[1;94m'
BIPurple='\033[1;95m'
BICyan='\033[1;96m'
BIWhite='\033[1;97m'
UWhite='\033[4;37m'
On_IPurple='\033[0;105m'
On_IRed='\033[0;101m'
IBlack='\033[0;90m'
IGreen='\033[0;92m'
IYellow='\033[0;93m'
IBlue='\033[0;94m'
IPurple='\033[0;95m'
ICyan='\033[0;96m'
IWhite='\033[0;97m'
GREENBO='\033[1;32m'
bgwhite='\e[40;97;1m'
bgred='\e[41;97;1m'
bggreen='\e[42;97;1m'
bgyellow='\e[43;97;1m'
bgmagenta='\e[45;97;1m'
bgblue='\e[46;97;1m'
bgblack='\e[47;30;1m'
w='\033[97m'
ORANGE='\033[0;34m'
dateFromServer=$(curl -v --insecure --silent https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
biji=`date +"%Y-%m-%d" -d "$dateFromServer"`
red() { echo -e "\\033[32;1m${*}\\033[0m"; }
PERMISSION() {
    MYIP=$(curl -sS ipv4.icanhazip.com)

    TODAY_DATE=$(date +'%Y-%m-%d')

    AUTHORIZED_ENTRY=$(curl -sS https://raw.githubusercontent.com/xawn22/LITE-V.1/main/ip | grep -w "$MYIP" | head -1)

    if [[ -n "$AUTHORIZED_ENTRY" ]]; then
        # IP_FROM_ENTRY sekarang adalah field ke-4
        IP_FROM_ENTRY=$(echo "$AUTHORIZED_ENTRY" | awk '{print $4}')
        # EXP_DATE_OR_LIFETIME_STATUS sekarang adalah field ke-3
        EXP_DATE_OR_LIFETIME_STATUS=$(echo "$AUTHORIZED_ENTRY" | awk '{print $3}') 

        if [ "$MYIP" = "$IP_FROM_ENTRY" ]; then
            # Cek apakah statusnya 'lifetime'
            if [[ "$EXP_DATE_OR_LIFETIME_STATUS" == "lifetime" ]]; then
                echo -e "\033[1;92mPermission Accepted (Lifetime User)\033[0m"
                echo -e "\033[1;97mAkses Di Izinkan (Pengguna Lifetime)${NC}"
            # Jika bukan 'lifetime', baru lakukan perbandingan tanggal
            elif [[ "$TODAY_DATE" < "$EXP_DATE_OR_LIFETIME_STATUS" ]]; then
                echo -e "\033[1;92mPermission Accepted\033[0m"
                echo -e "\033[1;97mAkses Di Izinkan${NC}"
            elif [[ "$TODAY_DATE" == "$EXP_DATE_OR_LIFETIME_STATUS" ]]; then
                echo -e "\033[1;93mPermission Accepted (Today is Expiry Date)\033[0m"
                echo -e "\033[1;97mAkses Di Izinkan (Hari Ini Kadaluarsa)${NC}"
            else
                echo -e "\033[1;91mPermission Denied (Expired)\033[0m"
                echo -e "\033[1;97mAkses Di Tolak (Kadaluarsa)${NC}"
                read -n 1 -s -r -p "Press [ Enter ] to Exit"
                exit 1
            fi
        else
            echo -e "\033[1;91mPermission Denied (IP Mismatch)\033[0m"
            echo -e "\033[1;97mAkses Di Tolak (IP Tidak Cocok)${NC}"
            read -n 1 -s -r -p "Press [ Enter ] to Exit"
            exit 1
        fi
    else
        echo -e "\033[1;91mPermission Denied (IP Not Found)\033[0m"
        echo -e "\033[1;97mAkses Di Tolak (IP Tidak Ditemukan)${NC}"
        read -n 1 -s -r -p "Press [ Enter ] to Exit"
        exit 1
    fi
}
fun_bar() {
    CMD[0]="$1"
    CMD[1]="$2"
    (
        [[ -e $HOME/fim ]] && rm $HOME/fim
        ${CMD[0]} -y >/dev/null 2>&1
        ${CMD[1]} -y >/dev/null 2>&1
        touch $HOME/fim
    ) >/dev/null 2>&1 &
    tput civis
    echo -ne "\033[0;33mLoading\033[1;37m - \033[0;33m["
    while true; do
        for ((i = 0; i < 21; i++)); do
            echo -ne "\033[0;32m#"
            sleep 0.1s
        done
        [[ -e $HOME/fim ]] && rm $HOME/fim && break
        echo -e "\033[0;33m]"
        sleep 1s
        tput cuu1
        tput dl1
        echo -ne "\033[0;33mLoading\033[1;37m - \033[0;33m["
    done
    echo -e "\033[0;33m]\033[1;37m -\033[1;32m OK\033[1;37m"
    tput cnorm
}
memperbarui_script() {
    wget https://raw.githubusercontent.com/xawn22/LITE-V.1/main/menu/menu.zip
    unzip menu.zip
    chmod +x menu/* 
    mv menu/* /usr/local/sbin
    sleep 2
    sudo dos2unix /usr/local/sbin/*
 
    rm -rf menu
    rm -rf menu.*
    rm -rf menu.zip
    rm -rf update.sh
    rm -rf update.sh.*
    rm -rf menu.zip.*
}
PERMISSION
clear
echo -e "${BIWhite}──────────────────────────────────────${NC}"
echo -e "${bggreen}             UPDATE SCRIPT            ${NC}"
echo -e "${BIWhite}──────────────────────────────────────${NC}"
echo -e ""
fun_bar 'memperbarui_script'
echo -e "${BIWhite}──────────────────────────────────────${NC}"
echo -e ""
read -n 1 -s -r -p "Press [ Enter ] to back on menu"
menu
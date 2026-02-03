AutoScript LITE AIO By SetiawanYzz
```
echo -e "net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf && sysctl -p
```

```
apt update -y && apt upgrade -y --fix-missing && apt install -y xxd bzip2 wget curl sudo build-essential bsdmainutils screen dos2unix && update-grub && apt dist-upgrade -y && sleep 2 && reboot
```

```
screen -S setup-session bash -c "wget -q https://raw.githubusercontent.com/xawn22/LITE-V.1/main/debian_ubuntu.sh && chmod +x debian_ubuntu.sh && ./debian_ubuntu.sh; read -p 'Tap enter to back....'"
```
#!/bin/bash

VERSION=4.3.0.0
DOCKER_IMAGE_NAME="leshared/nr-plugin-dev:$VERSION"
PRODUCT_NAME="Плагин ГИС НР (DEV)"
SILENT="no"
UNINSTALL="no"

while getopts "su" OPTION
do
     case $OPTION in
         s)
             SILENT="yes"
         ;;
         u)
             UNINSTALL="yes"
         ;;
         *)
             exit 1
         ;;
     esac
done

halt_error() {
  echo $1
  if [ $SILENT == "no" ]; then
    zenity --error --no-wrap --text="$1"
  fi
  exit 1
}

confirm() {
  echo $1
  if [ $SILENT == "no" ]; then
    zenity --question --no-wrap --text="$1"
    return $?
  fi
  return 0
}

info() {
  echo $1
  if [ $SILENT == "no" ]; then
    zenity --info --no-wrap --text="$1"
  fi
}

WHICH_ZENITY=$(which zenity)
if [ -z $WHICH_ZENITY ]; then
  echo "ОШИБКА! zenity не установлен (в Ubuntu/Debian: sudo apt install zenity)"
  exit 1
fi

if [[ $(id -u) != 0 ]]; then
    halt_error 'Запустите программу под администратором: sudo /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/lesha-red/nr-plugin/main/install-nr-plugin-dev.sh)"'
fi

if [ $UNINSTALL = "yes" ]; then
  confirm "Вы действительно хотите удалить $PRODUCT_NAME $VERSION?"
  if [ $? == 0 ]; then
    echo "Останавливаем работающие контейнеры Docker"
    docker ps -q --filter ancestor="$DOCKER_IMAGE_NAME" | xargs -r docker stop
    docker image rm $DOCKER_IMAGE_NAME
    killall nr-plugin-xdg-open
    rm /usr/bin/nr-plugin
#    rm /usr/bin/nr-plugin-xdg-open
    rm /usr/share/nr-plugin/nr_plugin.ico
    rm /home/$SUDO_USER/.config/autostart/nr-plugin.desktop
    rm /usr/share/applications/nr-plugin.desktop
    rm /opt/yandex/browser/Extensions/cdjkkeofanojcdolaakkckkmfcjejlij.json
    rm /opt/google/chrome/extensions/cdjkkeofanojcdolaakkckkmfcjejlij.json
    info "$PRODUCT_NAME был успешно удален"
  fi
  exit 0
fi

WELCOME_MSG=$(cat <<EOF
Установщик $PRODUCT_NAME $VERSION.

Перед установкой $PRODUCT_NAME $VERSION убедитесь, что установлены следующие компоненты:

1. Docker (в Ubuntu/Debian: sudo apt install docker-io)
2. xdg-utils (в Ubuntu/Debian: sudo apt install xdg-utils)
3. gnome-terminal (в Ubuntu/Debian: sudo apt install gnome-terminal)
4. КриптоПро CSP (https://cryptopro.ru/products/csp/downloads#latest_csp50r3_linux)
5. КриптоПро ЭЦП SDK (https://cryptopro.ru/products/cades/downloads)

Продолжить?
EOF
)

confirm "$WELCOME_MSG"
if [ $? != 0 ]; then
  exit 2
fi

WHICH_DOCKER=$(which docker)
if [ -z $WHICH_DOCKER ]; then
  halt_error "ОШИБКА! Docker не установлен (в Ubuntu/Debian: sudo apt install docker-io)"
fi

WHICH_XDG_OPEN=$(which xdg-open)
if [ -z $WHICH_XDG_OPEN ]; then
  halt_error "ОШИБКА! xdg-open не установлен (в Ubuntu/Debian: sudo apt install xdg-utils)"
fi

WHICH_XDG_OPEN=$(which gnome-terminal)
if [ -z $WHICH_XDG_OPEN ]; then
  halt_error "ОШИБКА! gnome-terminal не установлен (в Ubuntu/Debian: sudo apt install gnome-terminal)"
fi


CSP_LIBS="/opt/cprocsp/lib/amd64/libcsp.so /opt/cprocsp/lib/amd64/libcapi20.so /opt/cprocsp/lib/amd64/libssp.so /opt/cprocsp/lib/amd64/librdrsup.so /opt/cprocsp/lib/amd64/libcpext.so /opt/cprocsp/lib/amd64/libcapi10.so /opt/cprocsp/lib/amd64/libcpcurl.so"
for EACH_LIB in $CSP_LIBS
do
  if [ ! -f $EACH_LIB ] && [ ! -L $EACH_LIB ]; then
    halt_error "ОШИБКА! КриптоПро CSP не установлен (https://cryptopro.ru/products/csp/downloads#latest_csp50r3_linux)"
  fi
done

CADES_LIBS="/opt/cprocsp/lib/amd64/libtspcli.so /opt/cprocsp/lib/amd64/libades-core.so"
for EACH_LIB in $CADES_LIBS
do
  if [ ! -f $EACH_LIB ] && [ ! -L $EACH_LIB ]; then
    halt_error "ОШИБКА! КриптоПро ЭЦП SDK не установлен (https://cryptopro.ru/products/cades/downloads)"
  fi
done

echo "Останавливаем работающие контейнеры Docker"
docker ps -q --filter ancestor="$DOCKER_IMAGE_NAME" | xargs -r docker stop

echo "Устанавливаем образ Docker"
DOCKER_PULL_OUTPUT=$(docker pull $DOCKER_IMAGE_NAME 2>&1 | tee /dev/tty)
if [ $? != 0 ]; then
  halt_error "Ошибка установки образа Docker: $DOCKER_PULL_OUTPUT"
fi

cat > /usr/bin/nr-plugin <<EOF
#!/bin/bash

DOCKER_IMAGE_NAME="$DOCKER_IMAGE_NAME"

if [[ \$(id -u) == 0 ]]; then
    ERROR_TEXT="Запустите программу НЕ под администратором (без sudo)"
    echo \$ERROR_TEXT
    zenity --error --no-wrap --text="\$ERROR_TEXT"
    exit 1
fi

if [ ! -d ~/.nr_plugin ]; then
  mkdir -p ~/.nr_plugin
fi

if [ -p ~/.nr_plugin/xdg-pipe ]; then
  rm ~/.nr_plugin/xdg-pipe
fi

mkfifo ~/.nr_plugin/xdg-pipe

killall nr-plugin-xdg-open

nohup /usr/bin/nr-plugin-xdg-open >/dev/null 2>&1 &
echo \$! > ~/.nr_plugin/nr-plugin-xdg-open.pid

docker ps -q --filter ancestor="\$DOCKER_IMAGE_NAME" | xargs -r docker stop

echo "Started: \$(date)" | tee -a ~/.nr_plugin/logs/stdout_host.txt

docker run \
  -h \$(hostname) \
  --network host \
  -p 9822:9822 \
  --ipc=host \
  -v /dev:/dev \
  -v /tmp:/tmp \
  -v /opt:/opt \
  -v /var/opt:/var/opt \
  -v /home/\$USER:/home/\$USER \
  -v /run/user/\$(id -u)/bus:/run/user/1000/bus \
  -v /etc/opt:/etc/opt \
  -v /etc/passwd:/etc/passwd \
  -v /etc/group:/etc/group \
  -v /etc/shadow:/etc/shadow \
  -e DISPLAY=\$DISPLAY \
  -e TZ=\$(cat /etc/timezone) \
  -e DBUS_SESSION_BUS_ADDRESS=\$DBUS_SESSION_BUS_ADDRESS \
  -e USER=\$USER \
  -u \$(id -u):\$(id -g) \
  --rm \
  --name my-nr-plugin \
  --security-opt apparmor=unconfined \
  -d \
  \$DOCKER_IMAGE_NAME 2>&1 | tee -a ~/.nr_plugin/logs/stdout_host.txt
EOF
chmod a+x /usr/bin/nr-plugin

cat > /usr/bin/./nr-plugin-xdg-open <<EOF
#!/bin/bash

while true; do 
  CMD=\$(cat \$HOME/.nr_plugin/xdg-pipe 2>/dev/null)

  if [[ \${CMD:0:6} == "nr-cmd" ]]; then
    eval "\${CMD:6}"
  elif [ ! -z "\$CMD" ]; then
    eval "/bin/xdg-open '\$CMD'"
  fi
  sleep 1
done
EOF
chmod a+x /usr/bin/nr-plugin-xdg-open

mkdir -p /usr/share/nr-plugin
chmod a+r /usr/share/nr-plugin
ICON_BASE64="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Ofs6KDr/CwwLWQAAAAAAAAAAAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAtIy3qQDlA/wx6DP4HjQf+EIEQ/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kTvwP58/7T+TP+09PD3/KiIq8gAAAAIAAAAAAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAAAAAAAAwODGJILEj/Hlse/wCUAP4OgQ7+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZE970OsQ+o7Zzv4Oyg7/w8QD20AAAAAAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAAAAAAAC0hLec8Pjz/CYAJ/gaJBv4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970GcQe1Cl0LsPUE9/yggKO4AAAABAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAACwwLWkYsRv8dWx3/AJIA/guAC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CTQO5GrEbpPWg99zknOf8MDQxcAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAAJR4lxUA8QP8JeQn/BIoE/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5EoETrQ45D7D88P/8gGyDEAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAASOSQ5/ytNK/8AjAD/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtSKdI6D5WPv8vHy//AgICHAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAODg5oRC1E/xhiGP8AjwD/CYAJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClELtSKlI6EB3QPI7LTv/ExMTfwAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAkHCTEPT49/wd6B/8ChwL/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRpxG6kiZSOk/Rj//JB0k4AAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAABABU4Ijj/K04r/wCKAP8HgQf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EupS+ZAXUD/LyAv/wMDAyYAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAsLC1FCK0L/Gl4a/wCPAP8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EysTOZBcEH1Nyg3/w4ODl0AAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAABYTFn1CNUL/Dm4O/wCMAP8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EunS+dEf0TuOzI7/xYVFokAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAACEaIbM9Pj3/B3kH/wCHAP8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EmgSelJk0nqP0E//yAaIMQAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAC8gL+UzRjP/AIIA/wODA/8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EiaSOpMo0znQFJA/ykeKfgAAAAK////AP///wD///8A////AP///wD///8A////AP///wD///8AAgICITokOv8nUCf/AIoA/wWBBf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+pOqk7lQWFB/TAiMP8GBgY4////AP///wD///8A////AP///wD///8A////AP///wD///8ACAgIRT8oP/8fVx//AI0A/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tPrE/lQmlC9jQmNP8MDAxV////AP///wD///8A////AP///wD///8A////AP///wD///8ADQ0NXkMsQ/8ZXRn/AI4A/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tPrE/mQ3FD8jcqN/8REBFt////AP///wD///8A////AP///wD///8A////AP///wD///8AEhESckMvQ/8VYhX/AI0A/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tOqk7mRXlF7zkuOf8UExSA////AP///wD///8A////AP///wD///8A////AP///wD///8AFhQWhUMyQ/8SZhL/AIwA/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tOqE7mRn9G7jsyO/8YFxiW////AP///wD///8A////AP///wD///8A////AP///wD///8AGRcZlUM1Q/8Pag//AIsA/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tOp07mR4RH7Tw2PP8bGRum////AP///wD///8A////AP///wD///8A////AP///wD///8AHRkdo0I4Qv8Mbwz/AIoA/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tNpk3nSIdI7Dw4PP8dGh2x////AP///wD///8A////AP///wD///8A////AP///wD///8AIBogsT86P/8Jcgn/AIkA/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tNpE3nSYxJ6z07Pf8fGx+8////AP///wD///8A////AP///wD///8A////AP///wD///8AJB0kvz08Pf8HdQf/AIgA/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tNok3nSpBK6j0+Pf8hHCHF////AP///wD///8A////AP///wD///8A////AP///wD///8AJx8nyjs+O/8FeAX/AIYA/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tMoUzoS5RL6T5APv8jHSPM////AP///wD///8A////AP///wD///8A////AP///wD///8AKyAr1ThCOP8CfQL/AIQA/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tMoEzoTJhM6T5EPv8lHiXU////AP///wD///8A////AP///wD///8A////AP///wD///8ALyEv4zNFM/8AhAD/AIUA/wWABf8HgAf/CYEJ/guBC/4Ngg3+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZM970CUQO5ClULtRZZF7EeYR+tLoEvoT6NP5j9NP/8mHCbe////AP///wD///8A////AP///wD///8A////AP///wD///8AMiUy8TM/M/8BfgH/AI0A/wCOAP8AjgD/A4sD/giHCP4MhAz+D4IP/hGDEf0TgxP9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jzTzNpA28zmROfI7kjvwPZQ970GaQe1EoUTrSKhI6UurS+dOqk7mTqFO5j1KPf8pHynp////AP///wD///8A////AP///wD///8A////AP///wD///8ANTQ1/z89P/8xPjH/J0on/x5WHv8XZBf/EXIR/gx+DP4Iigj+CJEI/guQC/0RiBH9FYQV/ReEF/wZhRn8HIYc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctjC32L40v9TKOMvQ0jjTzNpU28zqgOvA8pTztPqA+7UCUQO5AhEDvP3Q/8T1jPfQ8Uzz6OkM6/z07Pf82Njb/////AP///wD///8A////AP///wD///8A////AP///wD///8AHyAfvy8vL+85LTn/Qi1C/0YvRv9FMUX/PjU+/zQ7NP8rRyv/Ilki/xptGv0TgxP9DpQO/BOQE/wZhxn8HIUc+x2HHfsghyD6Iogi+SSJJPkmiSb4KYsp9yuMK/ctiy32L44v9TKbMvM0ojTxNpI28jh4OPU4Yzj3N1A3+jc/N/85NDn/Oi46/zoqOv82KTb/Mioy/y8vL/IiIyLC////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAA0GBgYyDg4OXRcXF4ohISG4LCgs4zctN/9BL0H/RS5F/z4uPv8yOjL/JlUm/hx2HPwVkBX7F5YX+hyLHPsghiD6Iogi+SSJJPkmiSb4KYop9yuPK/csnSz0Lpsu8zJ/MvU0XDT5NT01/zksOf88Kzz/Oyw7/zUtNf8sKSzuIiIivxgYGI0ODw5eBwcHNQAAABAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgUFBS4RERFsIiIitS8uL+8+Mj7/RC1E/zouOv8tRi3+Imwi/BuNG/obmRv5IYwh+SWHJfkmjCb4J50n9iqVKvYvdS/3Mkwy+zcuN/8+Kj7/OzA7/y8uL/IjIyO5FBQUeQgICD0AAAAMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA8PDw9fIiMiuTUyNf9DMEP/Pio+/zE8Mf8mZib7II8g+R+eH/cklCT3LG8s+TJCMv46Kjr/Py4//zUyNf8jJCO9EBEQZAEBARIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUFBTAaGxqUMC8w8EAxQP8/Kj//MEMw/yloKfswSjD9PCk8/z8vP/8yMTL6Hh8eoQcHBzgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAERUWFX0uLi7sQDRA/0ArQP9AM0D/MTEx+RgaGIwCAgIbAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPFxcXhS8uL94cHByaAQEBHQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///g///8AAP//8B///wAA///AB///AAD//4AD//8AAP//AAH//wAA//4AAP//AAD//AAAf/8AAP/4AAA//wAA//AAAB//AAD/8AAAH/8AAP/gAAAP/wAA/8AAAAf/AAD/wAAAB/8AAP+AAAAD/wAA/4AAAAH/AAD/AAAAAf8AAP8AAAAA/wAA/gAAAAD/AAD+AAAAAP8AAPwAAAAAfwAA/AAAAAB/AAD8AAAAAH8AAPgAAAAAPwAA+AAAAAA/AAD4AAAAAD8AAPgAAAAAPwAA+AAAAAAfAADwAAAAAB8AAPAAAAAAHwAA8AAAAAAfAADwAAAAAB8AAPAAAAAAHwAA8AAAAAAfAADwAAAAAB8AAPAAAAAAHwAA8AAAAAAfAADwAAAAAB8AAPAAAAAAHwAA8AAAAAAfAADwAAAAAB8AAPAAAAAAHwAA8AAAAAAfAAD4AAAAAD8AAP/AAAAH/wAA//wAAH//AAD//4AD//8AAP//4A///wAA///4P///AAA="
echo $ICON_BASE64 | base64 -d > /usr/share/nr-plugin/nr_plugin.ico
chmod a+r /usr/share/nr-plugin/nr_plugin.ico

cat > /usr/share/applications/nr-plugin.desktop <<EOF
[Desktop Entry]
Type=Application
Name[ru]=$PRODUCT_NAME
Name=GIS NR Plugin
Icon=/usr/share/nr-plugin/nr_plugin.ico
TryExec=/usr/bin/nr-plugin
Exec=/usr/bin/nr-plugin
Categories=Utility
EOF

chmod a+r /usr/share/applications/nr-plugin.desktop

CHROME_EXTENSION_JSON=$(cat <<EOF
{
    "external_update_url": "https://clients2.google.com/service/update2/crx"
}
EOF
)

# Install chrome and yandex browser extension
[ -d "/opt/yandex/browser/Extensions" ] && echo $CHROME_EXTENSION_JSON > /opt/yandex/browser/Extensions/cdjkkeofanojcdolaakkckkmfcjejlij.json 
[ -d "/opt/google/chrome/extensions" ] && echo $CHROME_EXTENSION_JSON > /opt/google/chrome/extensions/cdjkkeofanojcdolaakkckkmfcjejlij.json 

FINISH_MSG=$(cat <<EOF
$PRODUCT_NAME $VERSION был успешно установлен

Запуск программы:
- nr-plugin
ИЛИ
- \"Плагин ГИС НР\" (\"GIS NR Plugin\") в списке программ Unity

Для удаления $PRODUCT_NAME запустите: sudo /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/lesha-red/nr-plugin/main/install-nr-plugin-dev.sh)" -u -u
EOF
)

info "$FINISH_MSG"

if [[ -z $DBUS_SESSION_BUS_ADDRESS ]]; then
    pgrep "gnome-session" -u "$SUDO_USER" | while read -r line; do
        DBUS_EXP=$(cat /proc/$line/environ 2>/dev/null | grep -z "^DBUS_SESSION_BUS_ADDRESS=" 2>/dev/null)
        echo export "$DBUS_EXP" > ~/.exports.sh
        break
    done
    if [[ -f ~/.exports.sh ]]; then
        source ~/.exports.sh
        rm ~/.exports.sh
    else
      exit 0
    fi
fi

mkdir -p /home/$SUDO_USER/.config/autostart
chmod a+rx /home/$SUDO_USER/.config/autostart
ln -s /usr/share/applications/nr-plugin.desktop /home/$SUDO_USER/.config/autostart/nr-plugin.desktop 2>/dev/null

sudo -u $SUDO_USER -E gtk-launch nr-plugin

#!/bin/bash

set -ue

current_dir=$(dirname ${0})
. ${current_dir}/lib/default_config.sh
. ${current_dir}/lib/function.sh

if [ -f "${current_dir}/config.sh" ]
then
    . ${current_dir}/config.sh
fi

rm -f ${fifo_path}
mkfifo ${fifo_path}

echo "listen ${listen_ip} ${listen_port}"

while true
do
    (
        # 取得情報
        from=''
        to=''
        body=''
        auth=''
        apikey=''

        # start
        echo '220 OK'

        # データを受け取るモードか
        datamode=false
        while read -r line
        do
            line=$(echo ${line} | tr -d '\r')

            if ${debug}
            then
                echo ${line} 1>&2
            fi

            # データ受け取り処理
            if ${datamode}
            then
                # DATA終わり
                if [ "${line}" = '.' ]
                then
                    datamode=false
                    echo '250 OK'
                    continue
                fi

                body+="${line}\n"
                continue
            fi

            case ${line} in
            # データ受け取り開始
            DATA)
                datamode=true
                echo '354 OK'
                ;;
            # 終了
            QUIT)
                echo '221'
                break
                ;;
            # 全般
            *)
                case ${line} in
                # FROM
                "MAIL FROM"*)
                    #MAIL FROM:<mail address>
                    from=${line#MAIL FROM:}
                    from=${from/</}
                    from=${from/>/}
                    ;;
                # TO
                "RCPT TO"*)
                    #RCPT TO:<mail address>
                    to=${line#RCPT TO:}
                    to=${to/</}
                    to=${to/>/}
                    ;;
                "AUTH PLAIN"*)
                    # AUTH
                    auth=${line#*PLAIN }

                    access_info=$(parse_access_info "${auth}")
                    if ! check_apikey ${access_info}
                    then
                        echo '535 5.7.8 Error: authentication failed: Invalid authentication.'
                        exit
                    fi
                    ;;
                "AUTH"*)
                    echo '535 5.7.8 Error: authentication failed: Invalid authentication.'
                    continue
                    ;;
                # HELO -> AUTH
                "HELO"*|"EHLO"*)
                    echo '250-AUTH=PLAIN LOGIN DIGEST-MD5 CRAM-MD5'
                    ;;
                esac

                echo '250 OK'
                ;;
            esac
        done < ${fifo_path}

        register_main "${from}" "${to}" "${body}" "${access_info}" &

    ) | nc -l ${listen_ip} ${listen_port} > ${fifo_path}

    if ${re_listen}
    then
        echo -n
    else
        break
    fi

done

rm -f ${fifo_path}

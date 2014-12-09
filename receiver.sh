#!/bin/bash

set -ue

current_dir=$(dirname ${0})
. ${current_dir}/lib/default_config.sh
. ${current_dir}/lib/function.sh

rm -f ${fifo_path}
mkfifo ${fifo_path}

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
                    apikey=$(echo ${auth} | base64 -d |cut -d '' -f 1| tail -n 1)
                    exit
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

        register_main "${from}" "${to}" "${body}" "${auth}" "${apikey}" &

    ) | nc -l ${listen_ip} ${listen_port} > ${fifo_path}

    if ${re_listen}
    then
        echo -n
    else
        break
    fi

done


#$ nc -l 43001
#220 OK
#EHLO [127.0.0.1]
#250 OK
#MAIL FROM:<yoshio@interlink-j.com>
#250 OK
#RCPT TO:<hoge@hoge.hoge>
#250 OK
#DATA
#354 OK
#Message-ID: <547D18B1.5070104@interlink-j.com>
#Date: Tue, 02 Dec 2014 10:41:05 +0900
#From: =?ISO-2022-JP?B?GyRCQTBFRBsoQiAbJEJOSUlXGyhC?=
# <yoshio@interlink-j.com>
# User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64; rv:24.0) Gecko/20100101 Thunderbird/24.6.0
# MIME-Version: 1.0
# To: hoge@hoge.hoge
# Subject: a
# Content-Type: text/plain; charset=ISO-2022-JP
# Content-Transfer-Encoding: 7bit
#
# bb
# .
# 250 OK
# QUIT
# 221 OK

rm -f ${fifo_path}

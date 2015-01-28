register_main()
{
    local from=${1}
    local to=${2}
    local body=${3}
    local access_info=${4}

    # information
    local ticket_id=${to%%@*}
    local project_id=${to#*@}

    local subject=$(parse_subject "${body}")
    local contents=$(parse_contents "${body}")

    local message_header=$(parse_message_header "${body}")
    local message_subject=$(parse_message_subject "${body}")
    local message_body=$(parse_message_body "${body}")

    register_ticket "${access_info}" \
        "${ticket_id}" \
        "${project_id}" \
        "${subject}" \
        "${contents}" \
        "${message_header}" \
        "${message_subject}" \
        "${message_body}"
}

parse_access_info()
{
    local access_infos=( $(echo ${1} | base64 -d | cut -d '' --output-delimiter=' ' -f 2,3) )
    local access_to=${access_infos[0]}
    local api_key=${access_infos[1]}

    local proto_host=( ${access_to/@/ } )
    local proto=${proto_host[0]}

    local host_port=( ${proto_host[1]/:/ } )
    local host=${host_port[0]}

    local port=${host_port[1]:-''}
    if [ ! "${port}" ]
    then
        case "${proto}" in
            https)
                port=443
                ;;
            *)
                port=80
                ;;
        esac
    fi

    echo -n "${proto} ${host} ${port} ${api_key}"
}

parse_header()
{
    local date=""
    local from=""
    local to=""
    local cc=""
    local type=""
    local boundary=""

    local mode=""

    while read -r line
    do
        if [ ! "${line}" ]
        then
            break
        fi

        if [ "${mode}" ] && ! echo "$line" | grep -E '^.*: ' >/dev/null 2>&1
        then
            line="${mode}: $(echo -n ${line})"
        fi

        case "${line}" in
            Date:*|DATE:*)
                date=${line#*: }
                date=$(date -d "${date}" '+%Y/%m/%d %H:%M:%S' 2>/dev/null || echo "${date}")
                ;;
            From:*|FROM:*)
                from=${line#*: }
                ;;
            To:*|TO:*)
                mode="To"
                to+=${line#*: }
                ;;
            CC:*|CC:*)
                mode="Cc"
                cc+=${line#*: }
                ;;
            Content-Type:*)
                type=${line#*: }
                ;;
            boundary=*)
                boundary=${line#*=}
                boundary=${boundary#\"}
                boundary=${boundary%\"}
                ;;
            *)
                mode=""
                ;;
        esac
    done < <(echo -ne "${1}")

    echo "'${date}' '${from}' '${to}' '${cc}' '${type}' '${boundary}'"
}

parse_subject()
{
    local subject_str=$(echo -e "${1}" | grep -E '^Subject: ' | head -n 1)
    subject_str=${subject_str#*: }

    decode_mime_string "${subject_str}"
}

parse_contents()
{
    local body=${1}
    local boundary=$(echo -e "${body}" | grep -E '^boundary=' | head -n 1)
    boundary=${boundary#*=}
    boundary=${boundary#\"}
    boundary=${boundary%\"}

    local inbody=${body#*${boundary}}
    inbody=${inbody#*${boundary}}
    inbody=${inbody%${boundary}--*}

    local contents_all=${inbody%--${boundary}*}
    parse_mail_body "${contents_all}"
}

parse_mail_body()
{
    local cnt=0
    local ishead=true
    local evebody=false
    local charset=''
    local encode=''
    local contents=''
    while read -r line
    do
        cnt=$(($cnt + 1))
        if [ $cnt -eq 1 ]
        then
            continue
        fi

        if $ishead
        then
            case "${line}" in
                'Content-Type: '*)
                    charset=${line#*charset=}
                    ;;
                'Content-Transfer-Encoding: '*)
                    encode=${line#*: }
                    ;;
                '')
                    ishead=false
                    ;;
            esac
        else
            if [ "${contents}" ]
            then
                contents+="\n"
            fi
            contents+=${line}
        fi
    done < <(echo -ne "${1}")

    echo -ne "${contents}" | iconv -f ${charset} -t 'UTF-8'
}

parse_message()
{
    local body=${1}
    local boundary=$(echo -e "${body}" | grep -E '^boundary=' | head -n 1)
    boundary=${boundary#*=}
    boundary=${boundary#\"}
    boundary=${boundary%\"}

    local inbody=${body#*${boundary}}
    inbody=${inbody#*${boundary}}
    inbody=${inbody%${boundary}--*}

    local message_info_all=${inbody#*--${boundary}}

    cnt=0
    ishead=true
    local message_info=''

    while read -r line
    do
        cnt=$(($cnt + 1))
        if [ $cnt -eq 1 ]
        then
            continue
        fi

        if ${ishead}
        then
            if [ ! "${line}" ]
            then
                ishead=false
            fi
        else
            if [ "${message_info}" ]
            then
                message_info+="\n"
            fi
            message_info+=${line}
        fi

    done < <(echo -ne "${message_info_all}")

    echo ${message_info}
}

parse_message_header()
{
    local info=$(parse_message "${1}")
    parse_header "${info}"
}

parse_message_subject()
{
    local info=$(parse_message "${1}")
    parse_subject "${info}"
}

parse_message_body()
{
    local info=$(parse_message "${1}")
    parse_mail_body "${info}"
}

check_apikey()
{
    local proto=${1}
    local host=${2}
    local key=${3}

    if $(request "GET" "/projects.json" "${@}" | grep 'HTTP/1.1 2' >/dev/null)
    then
        return 0
    else
        return 1
    fi
}

get_msg()
{
    var_name_base=$1
    var_name=${1}_${message_lang}

    eval 'echo "${'$var_name'}"'
}

register_ticket()
{
    local access_info=( ${1} )
    local ticket_id=${2}
    local project_id=${3}
    local ticket_subject=${4}
    local ticket_contents=${5}
    local message_header=${6}
    local message_subject=${7}
    local message_body=${8}

    eval "local headers=(${message_header})"
    local date=${headers[0]}
    local from=${headers[1]}
    from=${from#*<}
    from=${from%>*}
    IFS=','
    local tos=(${headers[2]})
    local ccs=(${headers[3]})

    local to=""
    if [ -v tos ] && [ ${#tos} -ne 0 ]
    then
        for to1 in ${tos[@]}
        do
            to1=${to1#*<}
            to1=${to1%>*}
            if [ "${to}" ]
            then
                to+="\n"
            fi
            to+=${to1}
        done
    fi

    local cc=""
    if [ -v ccs ] && [ ${#ccs} -ne 0 ]
    then
        for cc1 in ${ccs[@]}
        do
            cc1=${cc1#*<}
            cc1=${cc1%>*}
            if [ "${cc}" ]
            then
                cc+="\n"
            fi
            cc+=${cc1}
        done
    fi

    local subject=${message_subject}
    local body=${message_body}
    local comment_base=$(get_msg comment_format)
    body=$(eval 'echo "'${comment_base}'"')


    subject=${ticket_subject}
    local description="${ticket_contents}

${body}
"
    local data=''
    local method=''
    local path=""
    case "${ticket_id}" in
        'new')
            method='POST'
            path="/projects/${project_id}/issues.xml"
            data=$(eval 'echo "'${send_data_format_new}'"')
            ;;
        *)
            method='PUT'
            path="/issues/${ticket_id}.xml"
            data=$(eval 'echo "'${send_data_format_edit}'"')
            ;;
    esac

    if ${testmode}
    then
        res=$(reqtest \
            "${method}" \
            "${path}" \
            "${access_info[0]}" \
            "${access_info[1]}" \
            "${access_info[2]}" \
            "${access_info[3]}" \
            "${data}")

        echo "${res}" >&2
    else
        res=$(request \
            "${method}" \
            "${path}" \
            "${access_info[0]}" \
            "${access_info[1]}" \
            "${access_info[2]}" \
            "${access_info[3]}" \
            "${data}")

        echo "${res}" >&2
    fi

}

reqtest()
{
    local method=${1}
    local path=${2}
    local proto=${3}
    local host=${4}
    local port=${5}
    local key=${6}
    local data=${7:-''}


    data=${data///\r\n}
    len=$(echo -ne "${data}" | wc -c)

    echo -ne "${data}" 1>&2
    echo -ne "${len}" 1>&2

    echo -ne "${data}" >&2
}

request()
{
    local method=${1}
    local path=${2}
    local proto=${3}
    local host=${4}
    local port=${5}
    local key=${6}
    local data=${7:-''}

    case "${path}" in
        *\?*)
            path+="&key=${key}"
            ;;
        *)
            path+="?key=${key}"
            ;;
    esac

    local header_opt=""

    local cmd="nc ${host} ${port}"
    if [ "${proto}" = "https" ]
    then
        cmd="openssl s_client -crlf -connect ${host}:${port}"
    fi

    eval '
    (
        echo -ne "${method} ${path} HTTP/1.1\r\n"
        echo -ne "Host: ${host}\r\n"

        if [ "${data}" ] && [ "${method}" = "POST" -o "${method}" = "PUT" ]
        then
            len=$(echo -ne "${data}" | wc -c)

            echo -ne "Content-Type: text/xml; charset=UTF8\r\n"
            echo -ne "Content-Length: ${len}\r\n\r\n"

            echo -ne "${data}"

        fi

        echo -ne "\r\n"

        sleep 1
    ) | '${cmd}
}

decode_mime_string()
{
    local mimed_str=$1

    case "${mimed_str}" in
        *=?*)
            local mimed_info=( ${mimed_str//\?/ } )

            local encode=${mimed_info[1]}
            local type=${mimed_info[2]}
            local enc_mimed=${mimed_info[3]}

            case ${type} in
                B)
                    echo "${enc_mimed}" | base64 -d | iconv -f ${encode} -t 'UTF-8'
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        *)
            echo "${mimed_str}"
            ;;
    esac

}

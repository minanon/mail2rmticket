register_main()
{
    local from=${1}
    local to=${2}
    local org_body=${3}
    local access_info=( ${4} )

    # information
    local ticket_id=${to%%@*}
    local project_id=${to#*@}

    local ticket_subject=$(parse_subject "${org_body}")
    local ticket_contents=$(parse_contents "${org_body}")

    local message_header=$(parse_message_header "${org_body}")
    local message_subject=$(parse_message_subject "${org_body}")
    local message_body=$(parse_message_body "${org_body}")
    local message_attached=()
    parse_attached_file 'message_attached' "${org_body}"


    eval "local headers=(${message_header})"
    local date=${headers[0]}
    local from=${headers[1]}
    from=${from#*<}
    from=${from%>*}
    local OLD_IFS=${IFS}
    IFS=','
    local tos=(${headers[2]})
    local ccs=(${headers[3]})
    IFS=${OLD_IFS}

    local to=""
    if [ -v tos ] && [ ${#tos[@]} -ne 0 ]
    then
        for to1 in "${tos[@]}"
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
    if [ -v ccs ] && [ ${#ccs[@]} -ne 0 ]
    then
        for cc1 in "${ccs[@]}"
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
    body=$(eval 'echo "'"${comment_base}"'"' | sed -e 's/</\&lt;/' -e 's/>/\&gt;/')

    subject=$( echo "${ticket_subject}" | sed -e 's/</\&lt;/' -e 's/>/\&gt;/' )
    local description="$( echo "${ticket_contents}" | sed -e 's/</\&lt;/' -e 's/>/\&gt;/' )

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
        local tokens=()
        [ ${#message_attached[@]} -ne 0 ] && upload 'tokens' \
            "${access_info[0]}" \
            "${access_info[1]}" \
            "${access_info[2]}" \
            "${access_info[3]}" \
            "${message_attached[@]}"

        local con=( $(parse_message "${org_body}") )
        upload 'attach_content' "${access_info[0]}" \
            "${access_info[1]}" \
            "${access_info[2]}" \
            "${access_info[3]}" \
            "\nContent-Type: message/rfc822\nfilename=\"${subject}\"\n\n$(parse_message "${org_body}")"

        token_str='<uploads type="array">'$(
            for token_info in "${tokens[@]-}" "${attach_content}"
            do
                [ ! "${token_info}" ] && continue
                local token="${token_info%%,*}"
                local type="${token_info#*,}"; type="${type%%,*}"
                local name="${token_info#*,}"; name="${name#*,}"
                echo -n "<upload><token>${token}</token><content_type>${type}</content_type><filename>${name}</filename></upload>"
            done
        )'</uploads>'
        data=$(echo "${data}" | sed -e "s|</issue>|${token_str}</issue>|")

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

parse_access_info()
{
    local access_infos=( $(echo "${1}" | base64 -d | cut -d '' --output-delimiter=' ' -f 2,3) )
    local access_to=${access_infos[0]}
    local api_key=${access_infos[1]}

    local proto_host=( $( echo "${access_to}" | sed -e 's/@/ /' ) )
    local proto=${proto_host[0]}

    local host_port=( $( echo "${proto_host[1]}" | sed -e 's/:/ /' ) )
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
            Cc:*|CC:*)
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
    local body="${1}"
    local subject_start=$(echo -e "${body}" | grep -nE '^Subject: ' | head -n 1 | cut -f'1' -d':' )
    local subject=$( decode_subject_mime "$(echo -e "${body}" | sed -ne "${subject_start}{ s/^Subject: \+//; p}" )" )
    for ((i=$subject_start+1; ; i++))
    do
        echo -e "${body}" | head -n ${i} | tail -n 1 | grep -E '^.+:|^$' >/dev/null \
            && break \
            || subject+=$( decode_subject_mime "$(echo -e "${body}" | sed -ne "${i}p")" )
    done

    echo "${subject}"
}

parse_contents()
{
    local body="${1}"
    local boundary=$(echo -e "${body}" | grep -E '^boundary=|^Content-Type:.*boundary=' | head -n 1)
    boundary=${boundary#*boundary=}
    boundary=${boundary#\"}
    boundary=${boundary%\"}

    local inbody=${body#*${boundary}}
    inbody=${inbody#*${boundary}}
    inbody=${inbody%%--${boundary}*}
    parse_mail_body "${inbody}"
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
                    charset=${charset%;*}
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
    local content=$(parse_message "${1}")
    if echo -e "${content}" | grep 'Content-Type:' | head -n1 | grep 'multipart/' >/dev/null
    then
        parse_contents "${content}"
    else
        parse_mail_body "${content}"
    fi
}

parse_attached_file()
{
    local var=${1}
    local content=$(parse_message "${2}")
    echo -e "${content}" | grep 'Content-Type:' | head -n1 | grep 'multipart/' >/dev/null \
        || return 0

    local boundary=$(echo -e "${content}" | grep -E '^boundary=|^Content-Type:.*boundary=' | head -n 1)
    boundary=${boundary#*boundary=}
    boundary=${boundary#\"}
    boundary=${boundary%\"}

    local inbody=${content#*${boundary}}
    inbody=${inbody#*${boundary}}
    inbody=${inbody#*${boundary}}
    inbody="${inbody%--${boundary}*}${boundary}"

    local arr=()
    while [ "${inbody}" ]
    do
        arr+=( "${inbody%%${boundary}*}" )
        inbody=${inbody#*${boundary}}
    done

    eval "${var}"'=( "${arr[@]}" )'
}

check_apikey()
{
    local proto=${1}
    local host=${2}
    local key=${3}

    request "GET" "/projects.json" "${@}" | grep 'HTTP/1.1 2' >/dev/null
}

get_msg()
{
    var_name_base=$1
    var_name=${1}_${message_lang}

    eval 'echo "${'$var_name'}"'
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


    data=$( echo "${data}" | sed -e 's//\n/g' )
    len=$(echo -ne "${data}" | wc -c)

    echo -ne "${data}" 1>&2
    echo -ne "${len}" 1>&2

    echo -ne "${data}" >&2
}

upload()
{
    local var="${1}"
    local proto=${2}
    local host=${3}
    local port=${4}
    local key=${5}
    local attaches=( "${@:6}" )
    local path="/uploads.xml"
    local _tokens=()

    for attach in "${attaches[@]}"
    do
        local type=""
        local name=""
        local body=""
        local count=0
        local encode=""
        local is_body=false
        while read -r line
        do
            count=$(( ${count} + 1 ))
            [ ${count} -eq 1 ] && continue
            if ${is_body}
            then
                body+="${line}\n"
            else
                [ ! "${line}" ] && { is_body=true ; continue ; }
                case "${line}" in
                    "filename="*|"name="*)
                        [ ! "${name}" ] && {
                            name="${line#*\"}"
                            name="${name%\"*}"
                        }
                        ;;
                    "Content-Description"*)
                        [ ! "${name}" ] && {
                            name="${line#* }"
                        }
                        ;;
                    "Content-Type"*)
                        type=${line#* }
                        type=${type%%;*}
                        ;;
                    "Content-Transfer-Encoding"*)
                        encode=${line#* }
                        ;;
                esac

            fi
        done < <(echo -ne "${attach}")

        [[ "${name}" =~ \. ]] || name+='.eml'

        res=$(
            request 'POST' "${path}" "${proto}" "${host}" "${port}" "${key}" \
                "${body}" "application/octet-stream" "${encode}"
        )

        local token=${res#*<token>}
        token=${token%</token>*}
        _tokens+=( "${token},${type},${name}" )
    done

    eval "${var}"'=( "${_tokens[@]}" )'
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
    local content_type=${8:-'text/xml; charset=UTF8'}
    local encode=${9:-''}

    local cmd="nc -C ${host} ${port}"
    [ "${proto}" = "https" ] && cmd="openssl s_client -crlf -connect ${host}:${port}"

    (
        echo -ne "${method} ${path} HTTP/1.1\n"
        echo -ne "Host: ${host}\n"
        echo -ne "X-Redmine-API-Key: ${key}\n"
        echo -ne "Connection: close\n"

        if [ "${data}" ] && [ "${method}" = "POST" -o "${method}" = "PUT" ]
        then
            len=$(
                if [[ "${content_type}" =~ ^text/|message/ ]]
                then
                    echo -ne "${data}" | perl -p -e 's/\n/\r\n/' | wc -c
                else

                    case "${encode}" in
                        'base64'|'BASE64')
                            echo -n "${body}" | sed -e 's/\\n//g' | base64 -d | wc -c
                            ;;
                        *)
                            echo -ne "${data}" | wc -c
                            ;;
                    esac
                fi
            )

            echo -ne "Content-Type: ${content_type}\n"
            echo -ne "Content-Length: ${len}\n\n"

            case "${encode}" in
                'base64'|'BASE64')
                    echo -n "${body}" | sed -e 's/\\n//g' | base64 -d
                    ;;
                *)
                    echo -ne "${data}"
                    ;;
            esac

        fi

        echo -ne "\n"

        sleep 1
    ) | (
        [ "${proto}" = "https" ] \
            && openssl s_client -crlf -connect ${host}:${port} \
            || nc -C ${host} ${port}
    )
}

decode_subject_mime()
{
    local mimed_str="${1}"

    if [[ "${mimed_str}" =~ =\? ]]
    then
        for cnt in {1..10}
        do
            local mime_info=${mimed_str#*=?}
            mime_info=${mime_info%%?=*}
            [ "${mimed_str}" = "${mime_info}" ] && break
            mimed_str=$( echo "${mimed_str}" | sed -e "s/=?${mime_info}?=/$(decode_mime_string "${mime_info}")/" )
        done
    fi

    echo "${mimed_str}"
}

decode_mime_string()
{
    local mimed_str="$1"
    local mimed_info=( $( IFS='?'; arr=( ${mimed_str} ); echo "${arr[@]}" ) )

    local encode=${mimed_info[0]}
    local type=${mimed_info[1]}
    local enc_mimed=${mimed_info[2]}

    case ${type} in
        B)
            echo "${enc_mimed}" | base64 -d | iconv -f "${encode}" -t 'UTF-8'
            ;;
        *)
            return 1
            ;;
    esac

}

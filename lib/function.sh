register_main()
{
    local from=${1}
    local to=${2}
    local body=${3}
    local auth=${4}
    local apikey=${5}

    echo ${to} 1>&2
    echo ${from} 1>&2

    local access_info=$(split_addr "${to}")

    echo ${access_info} 1>&2

    if ! check_apikey "${access_info}" "${apikey}"
    then
        return 1
    fi

}

parse_access_info()
{
    local return_value=''
    local access_info_str=$(echo ${1} | base64 -d | cut -d '' -f 1 | tail -n 2)
    local access_to=$(echo "${access_info_str}" | head -n 1)
    local api_key=$(echo "${access_info_str}" | tail -n 1)

    echo "${access_to/@/://} ${api_key}" 1>&2
    echo -n "${access_to/@/://} ${api_key}"
}

split_addr()
{
    local return_value=''
    local split=( ${1/@/ } )

    local access=( ${split[1]/./ } )
    local hosts=( ${access[1]/:/ } )
    local port=${hosts[1]:-''}
    if [ ! "${port}" ]
    then
        case "${access[0]}" in
            https)
                port=443
                ;;
            *)
                port=80
                ;;
        esac
    fi

    return_value+="${split[0]/./ } ${access[0]} ${hosts[0]} ${port}"

    echo ${return_value}
}

check_apikey()
{
    local access_info=($1)
    local key=$2

    local ticket_id=${access_info[0]}
    local project_id=${access_info[1]}
    local proto=${access_info[2]}
    local host=${access_info[3]}

    echo ${ticket_id} 1>&2
    echo ${project_id} 1>&2
    echo ${proto} 1>&2
    echo ${host} 1>&2


    #ip
    #http://192.168.1.123/projects.xml?key=228006758d11d8f6373488d8fd63401a6fd2bb67

    if [ "${to}" ]
    then
        return 5
    else
        # empty to
        return 1
    fi

    if [ ! "${key}" ]
    then
        # empty key
        return 2
    fi

    return 1
}

get_request()
{
    local access_info=${1}
    local apikey=${2}
    local path=${3}

    local cmd="nc -C ${host} ${port}"
    if [ "${proto}" != "http" ]
    then
        cmd="openssl s_client -crlf -connect ${host}:${port}"
    fi
    (
        echo 'GET / '
    ) | ${cmd}
}

register_main()
{
    local from=${1}
    local to=${2}
    local body=${3}
    local access_info=${4}

    echo ${to} 1>&2
    echo ${from} 1>&2
    echo -e ${body} 1>&2
    echo ${access_info} 1>&2

}

parse_access_info()
{
    local access_info_str=$(echo ${1} | base64 -d | cut -d '' -f 1 | tail -n 2)
    local access_to=$(echo "${access_info_str}" | head -n 1)
    local api_key=$(echo "${access_info_str}" | tail -n 1)

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

request()
{
    local method=${1}
    local path=${2}
    local proto=${3}
    local host=${4}
    local port=${5}
    local key=${6}

    case "${path}" in
        *\?*)
            path+="&key=${key}"
            ;;
        *)
            path+="?key=${key}"
            ;;
    esac

    local cmd="nc -C ${host} ${port}"
    if [ "${proto}" = "https" ]
    then
        cmd="openssl s_client -crlf -connect ${host}:${port}"
    fi

    (
        echo -ne "${method} ${path} HTTP/1.1\nHost: ${host}\n\n"
        sleep 1
    ) | ${cmd}
}

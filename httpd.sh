#!/bin/bash

source config.sh

declare -A ENV=(
    ["SERVER_NAME"]=${CONFIG[SERVER_NAME]}
    ["SERVER_PORT"]=${CONFIG[SERVER_PORT]}
    ["SERVER_SOFTWARE"]=${CONFIG[SERVER_SOFTWARE]}
    ["GATEWAY_INTERFACE"]=${CONFIG[GATEWAY_INTERFACE]}
    ["SERVER_PROTOCOL"]=
    ["SERVER_ADDR"]=${CONFIG[SERVER_ADDR]}
    ["REQUEST_METHOD"]=
    ["HTTP_ACCEPT"]=
    ["HTTP_ACCEPT_ENCODING"]=
    ["HTTP_ACCEPT_LANGUAGE"]=
    ["HTTP_CACHE_CONTROL"]=
    ["HTTP_COOKIE"]=
    ["HTTP_CONNECTION"]=
    ["HTTP_HOST"]=
    ["HTTP_USER_AGENT"]=
    ["HTTP_REFERER"]=
    ["PATH_INFO"]=
    ["PATH_TRANSLATED"]=
    ["SCRIPT_FILENAME"]=
    ["SCRIPT_NAME"]=
    ["QUERY_STRING"]=
    ["REMOTE_ADDR"]=$SOCAT_PEERADDR
    ["CONTENT_TYPE"]=
    ["CONTENT_LENGTH"]=
    ["REQUEST_METHOD"]=
);

[ -z "$IS_SERVER" ] && {
    export IS_SERVER=1
    export REDIRECT_STATUS=1    #PHP support
    rm $CACHE_DIR/*

    if [ ${CONFIG[HTTPS_ENABLED]} == "yes" ]; then
        SSL_KEY_PATH=$SSL_DIR/server.key
        SSL_SIGN_PATH=$SSL_DIR/server.crt
        SSL_CERT_PATH=$SSL_DIR/server.pem
        SSL_DHPARAMS_PATH=$SSL_DIR/dhparams.pem

        if [ ! -d $SSL_DIR ]; then
            mkdir $SSL_DIR
            openssl genrsa -out $SSL_KEY_PATH 1024
            openssl req -new -key $SSL_KEY_PATH -x509 -days 3653 -out $SSL_SIGN_PATH
            cat $SSL_KEY_PATH $SSL_SIGN_PATH >$SSL_CERT_PATH
            openssl dhparam -out $SSL_DHPARAMS_PATH 1024
            cat $SSL_DHPARAMS_PATH >>$SSL_CERT_PATH
        fi
        
        LISTEN_ARGS="OPENSSL-LISTEN":${ENV[SERVER_PORT]}",cert=$SSL_CERT_PATH,key=$SSL_KEY_PATH,verify=0"
    else
        LISTEN_ARGS="TCP-LISTEN":${ENV[SERVER_PORT]}
    fi

    socat -t2 -T20 $LISTEN_ARGS,fork,reuseaddr exec:"$0"
    exit -1
}

function readtoken()
{
    CR=""
    read -d$CR $*
}

function error()
{
    echo error_code:$1
    echo reason: $2
    exit -1
}

readtoken method path protocol

case "$method" in 
    HEAD|GET)
        ;;

    *)
        error 500 "method not implement"
        ;;
esac

case $protocol in
    HTTP/1.1|HTTP/1.0)
        ;;
        
    *)
        error 500 "$protocol not support"
        ;;
esac

[ "${path:0:1}" != "/" ] && error 500 "bad http request!"

ENV[REQUEST_METHOD]=$method
ENV[SCRIPT_NAME]=${path%%\?*}
[ ${#ENV[SCRIPT_NAME]} -eq 1 ] && ENV[SCRIPT_NAME]=/$INDEX
ENV[SCRIPT_FILENAME]=$DOCUMENT_ROOT${ENV[SCRIPT_NAME]}
ENV[PATH_INFO]=${ENV[SCRIPT_NAME]}
ENV[SERVER_PROTOCOL]=$protocol

[ ${#ENV[SCRIPT_NAME]} -eq 1 ] && error 404 "not found"

[[ "$path" =~ [^\?]*\?.* ]] && ENV[QUERY_STRING]=${path#*\?}

while readtoken line; do
#echo $line
    case $line in
        Accept:*)
            ENV[HTTP_ACCEPT]=`echo ${line#*:}`
            ;;

        Accept-Language:*)
            ENV[HTTP_ACCEPT_LANGUAGE]=`echo ${line#*:}`
            ;;

        Accept-Encoding:*)
            ENV[HTTP_ACCEPT_ENCODING]=`echo ${line#*:}`
            ;;

        Connection:*)
            ENV[HTTP_CONNECTION]=`echo ${line#*:}`
            ;;

        Cache-Control:*)
            ENV[HTTP_CACHE_CONTROL]=`echo ${line#*:}`
            ;;

        Content-Type:*)
            ENV[CONTENT_TYPE]=`echo ${line#*:}`
            ;;

        Content-Length:*)
            ENV[CONTENT_LENGTH]=`echo ${line#*:}`
            ;;

        Host:*)
            ENV[HTTP_HOST]=`echo ${line#*:}`
            ;;

        User-Agent:*)
            ENV[HTTP_USER_AGENT]=`echo ${line#*:}`
            ;;

        Referer:*)
            ENV[HTTP_REFERER]=`echo ${line#*:}`
            ;;

        "")
            break
            ;;

        *)
            #Connection,Cache-Control and so on
            ;;
    esac
done

ENV[PATH_TRANSLATED]=${ENV[HTTP_HOST]}${ENV[PATH_INFO]}

for index in ${!ENV[@]}; do
#echo $index:${ENV[$index]}
    export $index="${ENV[$index]}"
done

cgi_type=
case ${ENV[SCRIPT_NAME]#*.} in 
    css)
        mine_type=text/css
        ;;

    js)
        mine_type=text/javascript
        ;;

    html)
        mine_type=text/html
        ;;

    php)
        mine_type=text/plain
        cgi_type=php
        ;;

    sh)
        mine_type=text/plain
        cgi_type=sh
        ;;

    gif)
        mine_type=image/gif
        ;;
    
    jpg)
        mine_type=image/jpeg
        ;;

    png)
        mine_type=image/png
        ;;

    mpeg|mpg)
        mine_type=video/mpeg
        ;;

    mp3)
        mine_type=audio/mp3
        ;;

    pdf)
        mine_type=application/pdf
        ;;

    wav)
        mine_type=audio/x-wav
        ;;

    *)
        mine_type=text/plain
        ;;
esac


if [ ! $cgi_type ]; then
    if [ ! -f "${ENV[SCRIPT_FILENAME]}" ]; then 
        error 404 "not found"
    fi

    echo ${ENV[SERVER_PROTOCOL]} 200 OK
    echo Connection: close
    echo Date: `date -u +"%F %T GMT"`
    echo Content-Type: $mine_type
    echo Content-Length: \
        `stat ${ENV[SCRIPT_FILENAME]} | awk '/Size/{ print $2 }'`
    echo
    cat ${ENV[SCRIPT_FILENAME]} 
    exit -1
fi

echo HTTP/1.1 200 OK
echo Connection: close

cache_file=`uuidgen`

if [ $cgi_type == "php" ]; then
    CGI_RUN="php-cgi -n"
elif [ $cgi_type == "sh" ]; then
    CGI_RUN="bash"
else
    exit -1
fi

$CGI_RUN ${ENV[SCRIPT_FILENAME]} | {
    while readtoken line; do
        case $line in
            Content-type:*)
                echo $line
                ;;

            "")
                break
                ;;

            *)
                echo $line
                ;;
        esac
    done >&9
    cat
} 9>&1 >$cache_file
echo Content-Length: `stat $cache_file | awk '/Size/{ print $2 }'`
echo
cat $cache_file

rm $cache_file

 

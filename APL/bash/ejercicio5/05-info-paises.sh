#!/bin/bash

function ayuda(){
    echo -e "\e[1mNAME\e[0m"
    echo -e "\t05-info-paises.sh"
    echo -e "\n\e[1mSYNOPSIS\e[0m"
    echo -e "\t ./05-info-paises -n PAIS... [OPTION] TimeToLeave"
    echo -e "\n\e[1mDESCRIPTION\e[0m"
    echo -e "\tMuestra la informacion de los paises solicitados extrayendolos de una API"
    echo -e "\n\e[1m\tAPI: https://restcountries.com/v3.1/translation/{nombre}\e[0m"
    echo -e "\n\tMas infomacion en: https://restcountries.com/"
    echo -e "\n\tPara agilizar las consultas, se utiliza un archivo cache opcional con TTL."
    echo -e "\tCada linea de cache contiene: info|timestamp."
    echo -e "\tCuando el TTL expire, la linea se elimina automaticamente."
    echo -e "\n\tLos argumentos obligatorios para las opciones largas también son obligatorios para las opciones cortas."
    echo -e "\n\t\e[1m-n, --nombre=PAIS\e[0m"
    echo -e "\t\tpais o paises a consultar. Entre paises se precisa la separacion por ',' sin espacios"
    echo -e "\n\t\e[1m-t, --ttl=TimeToLeave\e[0m"
    echo -e "\t\topcional. Tiempo de vida de cache por pais en segundos. Si no se especifica, no se guarda en cache."
    echo -e "\n\t\e[1m-h, --help\e[0m"
    echo -e "\t\tayuda para el uso del comandos"
}

options=$(getopt -o n:t:h --l nombre:,ttl:,help -- "$@" 2> /dev/null)
if [ "$?" != "0" ]; then
    echo 'Opciones incorrectas.'
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

eval set -- "$options"

HELP=false
NOMBRES_PAISES=""
TTL_CACHE=0
BASE_URL="https://restcountries.com/v3.1/translation/"

while true; do
    case "$1" in
        -n | --nombre)
            NOMBRES_PAISES="$2"
            shift 2
            ;;
        -t | --ttl)
            TTL_CACHE="$2"
            shift 2
            ;;
        -h | --help)
            HELP=true
            shift 1
            ;;
        --)
            break
            ;;
        *)
            echo "Error en parametros"
            echo "Utilice -h o --help para ayuda"
            exit 1
            ;;
    esac
done

if [ "$HELP" = true ]; then
    ayuda
    exit 0
fi

if [ -z "$NOMBRES_PAISES" ]; then
    echo "Error: paises no especificados"
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

DIRECTORY_SCRIPT="$(dirname "$(realpath "$0")")"
mkdir -p "$DIRECTORY_SCRIPT"/.tmp
CACHE_FILE="$DIRECTORY_SCRIPT"/.tmp/paises.cache

IFS=',' read -ra paisesABuscar <<< "$NOMBRES_PAISES"

# Función para limpiar cache vencida (solo si TTL > 0)
function limpiar_cache() {
    if [ -f "$CACHE_FILE" ]; then
        tmpfile=$(mktemp)
        now=$(date +%s)
        while IFS= read -r linea; do
            timestamp="$(echo "$linea" | awk -F'|' '{print $4}')"
            if [[ "$timestamp" =~ ^[0-9]+$ ]] && (( now - timestamp <= 0 )); then
                echo "$linea" >> "$tmpfile"
            fi
        done < "$CACHE_FILE"
        mv "$tmpfile" "$CACHE_FILE"
        if [ ! -s "$CACHE_FILE" ]; then
            rm -r "$DIRECTORY_SCRIPT"/.tmp
        fi
    fi
}

limpiar_cache

# Buscar en cache primero (TTL opcional)
if [ -f "$CACHE_FILE" ]; then
    tmpPaises=("${paisesABuscar[@]}")
    while IFS= read -r linea; do
        info="${linea%|*}"
        for i in "${!tmpPaises[@]}"; do
            currentPais="${tmpPaises[i]}"
            if echo "$info" | grep -qi "$currentPais"; then
                ttl_arch="$(echo "$info" | awk -F'|' '{print $4}')"
                result_ttl=$(( $(date +%s) - ttl_arch ))
                if [ "$result_ttl" -lt 0 ]; then
                    echo -e "\nBuscando en CACHE: $currentPais\n"
                    echo "$info" | awk -F'|' '{printf "%s\n%s\n%s\n", $1, $2, $3}'
                    unset 'paisesABuscar[i]'
                fi
            fi
        done
    done < "$CACHE_FILE"
fi

# Buscar en API los paises restantes
for pais in "${paisesABuscar[@]}"; do
    echo -e "\nBuscando en API: $pais\n"
    pais=$(echo -n "$pais" | jq -sRr @uri)
    resp=$(curl -s "$BASE_URL""$pais")

    if echo "$resp" | jq -e 'type=="array"' >/dev/null; then
        resultadoCurl="$(echo "$resp" | jq -r '.[] | "Pais: \(.translations.spa.common)|Capital: \((.capital | join(", ")))|Moneda: \((.currencies | keys | join(", ")))"')"

        if [ "$TTL_CACHE" -gt 0 ]; then
            ttl_arch=$(( $(date +%s) + TTL_CACHE ))
            echo "$resultadoCurl|$ttl_arch|" >> "$CACHE_FILE"
        fi

        echo "$resultadoCurl" | awk -F'|' '{printf "%s\n%s\n%s\n", $1, $2, $3}'
        echo ""
    else
        echo -e "Error: No se encontro el pais: $pais.\nConsulte en otro idioma o compruebe que este escrito correctamente\n"
    fi
done

#curl "https://restcountries.com/v3.1/name/spain"
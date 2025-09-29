#!/bin/bash

CACHE_FILE="./tmp/paises_cache.json"

function help() {
    echo -e "\e[1mNAME\e[0m"
    echo -e "\tpaises_info"

    echo -e "\n\e[1mSYNOPSIS\e[0m"
    echo -e "\t./script.sh -n NOMBRES -t TTL"

    echo -e "\n\e[1mDESCRIPTION\e[0m"
    echo -e "\tConsulta información de países usando la API restcountries.com."
    echo -e "\tLos resultados se almacenan en caché para evitar consultas repetidas dentro del tiempo TTL."

    echo -e "\n\tLos argumentos obligatorios para las opciones largas también son obligatorios para las opciones cortas."
    echo -e "\n\t\e[1m-n, --nombre=NOMBRES\e[0m"
    echo -e "\t\tLista de países separados por comas. Ejemplo: \"Argentina, Brasil, Chile\""
    echo -e "\n\t\e[1m-t, --ttl=SEGUNDOS\e[0m"
    echo -e "\t\tTiempo en segundos para mantener la caché válida."

    if [[ \"$1\" = true ]]
    then
        echo -e "\n\t\e[1m-h, --help\e[0m"
        echo -e "\t\tMuestra este mensaje de ayuda."
    fi
}

options=$(getopt -o n:t:h --l nombre:,ttl:,help -- "$@" 2> /dev/null)
if [ "$?" != "0" ]; then
    echo 'Opciones incorrectas.'
    help true
    exit 1
fi

eval set -- "$options"

NOMBRES=""
TTL=""

while true
do
    case "$1" in
        -n | --nombre)
            NOMBRES="$2"
            shift 2
            ;;

        -t | --ttl)
            TTL="$2"
            shift 2
            ;;

        -h | --help)
            help
            exit 0
            ;;

        --)
            shift
            break
            ;;

        *)
            echo "Parámetro desconocido: $1"
            help
            exit 1
            ;;
    esac
done

if [[ -z "$NOMBRES" || -z "$TTL" ]]
then
    echo "Error: Faltan parámetros obligatorios"
    exit 1
fi

# Validar que TTL sea numérico y mayor a 0
if ! [[ "$TTL" =~ ^[0-9]+$ ]] || [[ "$TTL" -le 0 ]]; then
    echo "Error: TTL debe ser un número entero positivo"
    exit 1
fi

# ======================================
# Verifica si el pais está en la caché
# ======================================
esta_en_cache(){
    local pais="$1"

    # -e: retorna 0 si la clave existe, 1 si no
    if jq -e ".\"$pais\"" "$CACHE_FILE" >/dev/null 2>&1
    then
        local timestamp=$(jq -r ".\"$pais\".timestamp" "$CACHE_FILE")
        local ahora=$(date +%s)
        if (( ahora - timestamp < TTL )); then
            return 0
        fi
    fi
    return 1
}

# ======================================
# Guarda un país y sus datos en la caché
# ======================================
guardar_cache(){
    local pais="$1"
    local data="$2"
    local ahora=$(date +%s)

    # Creo el archivo cache si no existe
    if [[ ! -f "$CACHE_FILE" ]]; then
        mkdir -p "$(dirname "$CACHE_FILE")"
        echo "{}" > "$CACHE_FILE"
    fi

    # Actualizo cache de forma segura, manteniendo los registros anteriores
    tmp_file=$(mktemp)

    jq --arg pais "$pais" \
       --argjson registro "$(echo "$data" | jq --argjson ts "$ahora" '. + {timestamp: $ts}')" \
       '. + {($pais): $registro}' "$CACHE_FILE" > "$tmp_file" \
       && mv "$tmp_file" "$CACHE_FILE"
}

# ======================================
# Itera los países recibidos en NOMBRES
# ======================================
IFS=',' read -ra PAISES <<< "$NOMBRES"
for pais in "${PAISES[@]}"
do
    pais_trim=$(echo "$pais" | xargs)

    if esta_en_cache "$pais_trim"
    then
        echo "[CACHE] $pais_trim"

        jq -r ".\"$pais_trim\" | 
            \"Nombre: \(.nombre)\nCapital: \(.capital)\nRegión: \(.region)\nPoblación: \(.poblacion)\nMoneda: \(.moneda)\"" \
            "$CACHE_FILE"
    else
        echo "[API] $pais_trim"

        respuesta=$(wget -qO- "https://restcountries.com/v3.1/name/$pais_trim?fullText=true")

        if [[ -z "$respuesta" || "$respuesta" == *"Not Found"* ]]; then
            echo "No se encontró información para $pais_trim"
            continue
        fi

        info=$(echo "$respuesta" | jq '.[0] | {
            nombre: .name.common,
            capital: .capital[0],
            region: .region,
            poblacion: .population,
            moneda: (.currencies | to_entries[0].value.name + " (" + to_entries[0].key + ")")
        }')

        guardar_cache "$pais_trim" "$info"

        jq -r ". | \"Nombre: \(.nombre)\nCapital: \(.capital)\nRegión: \(.region)\nPoblación: \(.poblacion)\nMoneda: \(.moneda)\"" <<< "$info"
    fi
done

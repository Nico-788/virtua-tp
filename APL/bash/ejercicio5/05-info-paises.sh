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
    echo -e "\n\tPara agilizar las consultas, se utiliza un archivo cache que se crea al especificar -t o --tll."
    echo -e "\tUna vez consultados los paises se almacenan en el archivo <dir_script>/.tmp/paises.cache. Una vez excedido el"
    echo -e "\ttiempo de vida, se elimina."
    echo -e "\tEl tiempo de vida especificado mayor a 0 se almacena en el archivo <dir_script>/.ttl_cache."
    echo -e "\n\tLos argumentos obligatorios para las opciones largas también son obligatorios para las opciones cortas."
    echo -e "\n\t\e[1m-n, --nombre=PAIS\e[0m"
    echo -e "\t\tpais o paises a consultar. Entre paises se precisa la separacion por ',' sin espacios"
    echo -e "\n\t\e[1m-t, --ttl=TimeToLeave\e[0m"
    echo -e "\t\ttiempo de vida del archivo cache. Al usarse se crea un archivo cache con el tiempo de vida asignado."
    echo -e "\t\tCuando se asigna otro tiempo de vida sin haber terminado el anterior, se reemplaza el anterior por el nuevo."
    echo -e "\n\t\e[1m-h, --help\e[0m"
    echo -e "\t\tayuda para el uso del comandos"
}

options=$(getopt -o n:t:h --l nombre:,ttl:,help -- "$@" 2> /dev/null)
if [ "$?" != "0" ]
then
    echo 'Opciones incorrectas.'
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

eval set -- "$options"

HELP=false
NOMBRES_PAISES=""
TTL_CACHE=0
BASE_URL="https://restcountries.com/v3.1/translation/"

while true
do
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
            echo Error en parametros
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
CACHE_FILE="$DIRECTORY_SCRIPT"/.tmp/paises.cache
TTL_CACHE_FILE="$DIRECTORY_SCRIPT"/.ttl_cache

if [ $TTL_CACHE -eq 0 ]; then
    if [ -f "$CACHE_FILE" ]; then
        TTL_CACHE=$(cat "$TTL_CACHE_FILE")
    fi
else
    if [[ $TTL_CACHE =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "$TTL_CACHE" > "$TTL_CACHE_FILE"
        mkdir -p "$DIRECTORY_SCRIPT"/.tmp
    else
        echo "Error: numero de ttl invalido"
        echo "Utilice -h o --help para ayuda"
        exit 1
    fi
fi

IFS=',' read -ra paisesABuscar <<< "$NOMBRES_PAISES"

if [ -f "$CACHE_FILE" ]; then
    if (( $(date +%s) - $(stat -c %Y "$CACHE_FILE") <= "$TTL_CACHE" )); then
        while IFS= read -r infoPais; do
            for i in "${!paisesABuscar[@]}"; do
                currentPais="${paisesABuscar[i]}"

                if echo "$infoPais" | grep -qi "$currentPais"; then
                    echo -e "\nBuscando en CACHE: $currentPais\n"
                    echo "$infoPais" | awk -F'|' '{printf "%s\n%s\n%s\n", $1, $2, $3}'
                    unset 'paisesABuscar[i]'
                fi
            done
        done < "$CACHE_FILE"
    else
        rm -r "$DIRECTORY_SCRIPT"/.tmp
        rm "$TTL_CACHE_FILE"
        TTL_CACHE=0
    fi
fi

for pais in "${paisesABuscar[@]}"; do
    echo -e "\nBuscando en API: $pais\n"
    pais=$(echo -n "$pais" | jq -sRr @uri) #normalizo $pais ya que puede tener caracteres especiales
    resp=$(curl -s "$BASE_URL""$pais")

    if echo "$resp" | jq -e 'type=="array"' >/dev/null; then    #la API devuelve un array si lo encontro, caso contrario envia un msj de error
        resultadoCurl="$(echo "$resp" | jq -r '.[] | "Pais: \(.translations.spa.common)|Capital: \((.capital | join(", ")))|Moneda: \((.currencies | keys | join(", ")))"')"

        if [ "$TTL_CACHE" -gt 0 ]; then
            echo "$resultadoCurl" >> "$CACHE_FILE"
        fi
        echo "$resultadoCurl" | awk -F'|' '{printf "%s\n%s\n%s\n", $1, $2, $3}'
        echo ""
    else
        echo -e "Error: No se encontro el pais: $pais.\nConsulte en otro idioma o compruebe que este escrito correctamente\n" #si no es array, no lo encontro
    fi
done


#curl "https://restcountries.com/v3.1/name/spain"
#!/bin/bash

function ayuda() {
    echo -e "\e[1mNAME\e[0m"
    echo -e "\t03-contador-eventos"
    echo -e "\n\e[1mSYNOPSIS\e[0m"
    echo -e "\t ./03-contador-eventos OPTION DIR OPTION STRING..."
    echo -e "\n\e[1mDESCRIPTION\e[0m"
    echo -e "\tProcesa los archivos .log contando coincidencia en palabras especificadas"
    echo -e "\n\tLos argumentos obligatorios para las opciones largas también son obligatorios para las opciones cortas."
    echo -e "\n\t\e[1m-d, --directorio=DIRECTORY\e[0m"
    echo -e "\t\truta del directorio con los archivos a procesar."
    echo -e "\n\t\e[1m-h, --help\e[0m"
    echo -e "\t\tayuda para el uso del comandos"
    echo -e "\n\t\e[1m-p, --palabras=WORDS\e[0m"
    echo -e "\t\tpalabras a buscar dentro de los archivos. Si son mas de una, se separan por comas (,) sin espacios"
}

options=$(getopt -o d:p:h --l help,directorio:,palabras: -- "$@" 2> /dev/null)
if [ "$?" != "0" ]
then
    echo 'Opciones incorrectas.'
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

eval set -- "$options"

DIR=""
PALABRAS=""
HELP='false'

while true
do
    case "$1" in
        -d | --directorio)
            DIR="$2"
            shift 2
            ;;
        -p | --palabras)
            PALABRAS="$2"
            shift 2
            ;;
        -h | --help)
            HELP='true'
            shift 1
            ;;
        --)
            break
            ;;
        *)
            echo "Error: parametros inválidos ($1)"
            exit 1
    esac
done

if [ "$HELP" = true ]
then
    ayuda
    exit 0
fi

if [ -n "$DIR" ]
then
    if [ -n "$PALABRAS" ]
    then
        awk -v strPalabras="$PALABRAS" -f procesador-eventos.awk "$DIR"/*.log
    else
        echo "Complete las palabras a buscar"
        echo "Utilice -h o --help para ayuda"
    fi
else
    echo "Directorio inexistente o inaccesible."
    echo "Utilice -h o --help para ayuda"
fi
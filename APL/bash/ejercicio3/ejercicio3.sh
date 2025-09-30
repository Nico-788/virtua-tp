#!/bin/bash

ayuda(){
    echo -e "Script de búsqueda de palabras en archivos de log"
    echo -e "Lista de parámetros disponibles"
    echo -e "\t-d | --directorio (Necesario)"
    echo -e "\t\tIndica el directorio donde están ubicados los archivos"
    echo -e "\t-p | --palabras (Necesario)"
    echo -e "\t\tIndica las palabras a buscar en los archivos"
    echo -e "\t-h | --help"
    echo -e "\t\tMuestra este mensaje de ayuda"
}

opciones=$(getopt -o hd:p: --l help,directorio:,palabras: -- "$@" 2> /dev/null)

if [ $? != '0' ]
then 
echo "Parámetros incorrectos, utilice -h o --help para ayuda"
exit 1
fi

eval set -- "$opciones"

AYUDA=false
DIR=""
palabras=""

while true
do
    case "$1" in 
        -d | --directorio)
            DIR="$2"
            shift 2
            ;;
        -p | --palabras)
            palabras="$2"
            shift 2
            ;;
        -h | --help)
            AYUDA=true
            shift 1
            ;;
        --)
            break
            ;;
        *)
            echo Error
            exit 1
            ;;
    esac
done

if [ $AYUDA = true ]
then
    ayuda
    exit 0
fi

awk -v palabras="$palabras" -f buscador_palabras.awk "$DIR"/*.log

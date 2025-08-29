#!/bin/bash

function ayuda() {
    echo -e "\e[1mNAME\e[0m"
    echo -e "\t01-procesador-encuestas"
    echo -e "\n\e[1mSYNOPSIS\e[0m"
    echo -e "\t ./01-procesador-encuestas OPTION DIR OPTION [FILE]"
    echo -e "\n\e[1mDESCRIPTION\e[0m"
    echo -e "\tProcesa los archivos .txt que almacenan encuestas el siguiente formato:"
    echo -e "\n\e[1m\tID_ENCUESTA|FECHA|CANAL|TIEMPO_RESPUESTA|NOTA_SATISFACCION\e[0m"
    echo -e "\n\tLos argumentos obligatorios para las opciones largas también son obligatorios para las opciones cortas."
    echo -e "\n\t\e[1m-d, --directorio=DIRECTORY\e[0m"
    echo -e "\t\truta del directorio con los archivos a procesar."
    echo -e "\n\t\e[1m-a, --archivo=FILE\e[0m"
    echo -e "\t\truta completa del archivo JSON de salida. No se puede usar con -p / --pantalla."
    echo -e "\n\t\e[1m-p, --pantalla\e[0m"
    echo -e "\t\tmuestra la salida por pantalla. No se puede usar con -a / --archivo."
}

options=$(getopt -o d:a:ph --l help,pantalla,archivo:,directorio: -- "$@" 2> /dev/null)
if [ "$?" != "0" ]
then
    echo 'Opciones incorrectas.'
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

eval set -- "$options"

DIR=""
ARCHDEST=""
PANT=false

while true
do
    case "$1" in
        -d | --directorio)
            DIR="$2"
            shift 2
            ;;
        -a | --archivo)
            ARCHDEST="$2"
            shift 2
            ;;
        -p | --pantalla)
            PANT=true
            shift 1
            ;;
        -h | --help)
            HELP=true
            shift 1
            ;;
        --)
            break
            ;;
        *)
            echo error
            exit 1
            ;;
    esac
done

if [ "$HELP" = true ]
then
    ayuda
    exit 0
fi

if [[ -z "$DIR" || ! -d "$DIR" ]] 
then
    echo "Error: El directorio $DIR no existe o no es un directorio"
    exit 1
fi

if [ -n "$ARCHDEST" ]
then
    if [[ "$ARCHDEST" == *.json ]]
    then
        if [ "$PANT" = false ]
        then
            awk -f procesador-entrada.awk "$DIR"/*.txt > "$ARCHDEST"
        else
            echo "Error: No es posible imprimir por pantalla y guardar en archivo al mismo tiempo"
            exit 1
        fi
    else
        echo "Error: Ruta destino erronea"
        exit 1
    fi
fi

if [ "$PANT" = true ]
then
    if [ -z "$ARCHDEST" ]
    then
        awk -f procesador-entrada.awk "$DIR"/*.txt
    else
        echo "Error: No es posible imprimir por pantalla y guardar en archivo al mismo tiempo"
    fi
fi
#!/bin/bash

function ayuda() {
    echo "La ayuda llego"
}

options=$(getopt -o d:a:ph --l help,pantalla,archivo:,directorio: -- "$@" 2> /dev/null)
if [ "$?" != "0" ]
then
    echo 'Opciones incorrectas'
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
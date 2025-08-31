#!/bin/bash

# Procesamiento de parámetros con getopt
TEMP=$(getopt -o d:p: --long directorio:,palabras: -n 'log_analyzer' -- "$@")

if [ $? != 0 ]; then
    echo "Error en los parámetros. Uso: $0 -d <directorio> -p <palabras>" >&2
    exit 1
fi

eval set -- "$TEMP"

pathLogs=""
palabras_array=()

while true; do
    case "$1" in
        -d|--directorio)
            pathLogs="$2"
            shift 2
            ;;
        -p|--palabras)
            # Dividimos las palabras separadas por comas
            IFS=',' read -ra palabras_temp <<< "$2"
            palabras_array+=("${palabras_temp[@]}")
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Parámetro no reconocido: $1"
            exit 1
            ;;
    esac
done

# Verificamos que se hayan proporcionado ambos parámetros
if [ -z "$pathLogs" ] || [ ${#palabras_array[@]} -eq 0 ]; then
    echo "Error: Debes especificar tanto el directorio (-d) como las palabras (-p)"
    echo "Uso: $0 -d <ruta_archivo> -p <palabra1,palabra2,palabra3>"
    exit 1
fi

declare -A contador
# Cargamos dinámicamente las palabras en el vector asociativo
for palabra in "${palabras_array[@]}"; do
    contador["$palabra"]=0
done 

#Mostramos el vector cargado
echo 
echo "VECTOR ASOCIATIVO GENERADO y CARGADO"
for clave in "${!contador[@]}"; do
    echo "$clave = ${contador[$clave]}"
done
echo "LECTURA DEL ARCHIVO CARGADO, SE LLAMA $pathLogs"
while IFS= read -r variable; do
    echo "$variable"
done < "$pathLogs"
echo
#APARTADO DE ARCHIVO DE SYSTEM.LOGS
#LECTURA DE UN ARCHIVO LÍNEA A LÍNEA
echo "LECTURA ARCHIVO $pathLogs"
while IFS= read -r linea; do
    for palabra in "${!contador[@]}"; do
        if [[ "$linea" == *"$palabra"* ]]; then
            contador["$palabra"]=$(( contador["$palabra"] + 1 ))
        fi
    done
done < "$pathLogs"
#MOSTRAMOS LAS CANTIDADES Y LOS VALORES CARGADOS
echo 
echo "RESULTADO FINAL - VECTOR ASOCIATIVO CARGADO"
for palabra in "${!contador[@]}"; do
    echo "Palabra: $palabra; cantidad cargada: ${contador[$palabra]}"
done

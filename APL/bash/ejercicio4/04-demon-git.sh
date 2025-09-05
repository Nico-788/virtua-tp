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
    echo -e "\n\t\e[1m-a, --archivo=FILE\e[0m"
    echo -e "\t\truta completa del archivo JSON de salida. No se puede usar con -p / --pantalla."
    echo -e "\n\t\e[1m-d, --directorio=DIRECTORY\e[0m"
    echo -e "\t\truta del directorio con los archivos a procesar."
    echo -e "\n\t\e[1m-h, --help\e[0m"
    echo -e "\t\tayuda para el uso del comandos"
    echo -e "\n\t\e[1m-p, --pantalla\e[0m"
    echo -e "\t\tmuestra la salida por pantalla. No se puede usar con -a / --archivo."
}

options=$(getopt -o r:c:l:kh --l repo:,configuracion:,log:,kill,help -- "$@" 2> /dev/null)
if [ "$?" != "0" ]
then
    echo 'Opciones incorrectas.'
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

eval set -- "$options"

KILL=false

while true
do
    case "$1" in
        -r | --repo)
            REPOSITORY="$2"
            shift 2
            ;;
        -c | --configuracion)
            ARCH_CONFIG="$2"
            shift 2
            ;;
        -l | --log)
            ARCH_LOG="$2"
            shift 2
            ;;
        -k | --kill)
            KILL=true
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

if [ "$HELP" = true ]; then
    ayuda
    exit 0
fi

SCRIPT_CURRENT=$(dirname "$(realpath "$0")")

if [[ -n "$REPOSITORY" && -d "$REPOSITORY" ]]; then
    if ! git -C "$REPOSITORY" rev-parse --is-inside-work-tree &>/dev/null; then
        echo "Error: ingrese un repositorio valido"
        exit 1
    fi 
else
    echo "Error: especifique una ruta de repositorio valido"
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

REPOSITORY_ABS="$(realpath "$REPOSITORY")"
PID_FILE="$SCRIPT_CURRENT/.tmp/demon_pid.conf"

if [ "$KILL" = true ]; then
    if [ -s "$PID_FILE" ]; then
        while IFS="|" read -r PID REPO; do
            if [ "$REPOSITORY_ABS" = "$REPO" ]; then
                kill $PID
                break;
            else
                echo "Error: repositorio no monitoreado"
            fi
        done < "$PID_FILE"

        if ps -p "$PID" > /dev/null; then
            echo "Error: El proceso no puedo matarse"
            exit 1
        else
            rm -r "$SCRIPT_CURRENT/.tmp"
            echo "Proceso finalizado"
            exit 0
        fi
    else
        echo "Error: El proceso no existe"
        exit 1
    fi
fi

if [[ -n "$ARCH_CONFIG" && -f "$ARCH_CONFIG" ]]; then
    
    declare -a palabrasBuscar
    declare -a patronesRegex
    
    while IFS= read -r linea; do
        if [[ "$linea" == regex:* ]]; then
            patronesRegex+=("${linea#*regex:}")
        else
            palabrasBuscar+=("$linea")
        fi
    done < "$ARCH_CONFIG"

    if [ -n "$linea" ]; then
        if [[ "$linea" == regex:* ]]; then
            patronesRegex+=("${linea#*regex:}")
        else
            palabrasBuscar+=("$linea")
        fi
    fi
else
    echo "Error: especifique una ruta de archivo de configuraciones valido"
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

if [[ -z "$ARCH_LOG" && ! -f "$ARCH_LOG" && "$ARCH_LOG" != *.log ]]; then
    echo "Error: especifique una ruta de archivo de configuraciones valido"
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

ARCH_CONFIG_ABS=$(realpath "$ARCH_CONFIG")
ARCH_LOG_ABS=$(realpath "$ARCH_LOG")
cd "$REPOSITORY_ABS"

declare -a archivosFiltradosPrevios=()
while true; do
    mapfile -t archivosStaged < <(git diff --cached --name-only)

    archivosFiltrados=()
    for archActual in "${archivosStaged[@]}"; do
        archActualAbs=$(realpath "$archActual") #paso archActual a ruta absoluta

        # Voy a sacar de la evaluacion a los archivos ya escaneados y a los de log y configuracion
        # " ${archivosFiltradosPrevios[*]} " pongo todos los valores en una misma cadena separada por espacios
        if [[ ! " ${archivosFiltradosPrevios[*]} " =~ " $archActualAbs " ]] \
           && [[ "$archActualAbs" != "$ARCH_CONFIG_ABS" ]] \
           && [[ "$archActualAbs" != "$ARCH_LOG_ABS" ]]; then
            archivosFiltrados+=("$archActual")
            archivosFiltradosPrevios+=("$archActualAbs")
        fi
    done

    for file in "${archivosFiltrados[@]}"; do
        for pal in "${palabrasBuscar[@]}"; do
            if grep -q "$pal" "$file"; then
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] Alerta: palabra '$pal' encontrada en $(realpath "$file")" >> "$ARCH_LOG_ABS"
            fi
        done

        for pat in "${patronesRegex[@]}"; do
            if grep -q "$pat" "$file"; then
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] Alerta: patrón '$pat' encontrado en $(realpath "$file")" >> "$ARCH_LOG_ABS"
            fi
        done
    done
    sleep 2
done &
mkdir -p "$SCRIPT_CURRENT/.tmp"
echo "$!|$REPOSITORY_ABS"> "$PID_FILE"

#!/bin/bash

function ayuda() {
    echo -e "\e[1mNAME\e[0m"
    echo -e "\t04-demon-git.sh"
    echo -e "\n\e[1mSYNOPSIS\e[0m"
    echo -e "\t ./04-demon-git.sh REPO [CONFIGURACON] [LOG] [KILL]"
    echo -e "\n\e[1mDESCRIPTION\e[0m"
    echo -e "\tMonitorea la rama de un repositorio de Git para detectar credenciales o datos sensibles."
    echo -e "\n\tEl demonio lee un archivo de conficuracion que contiene una lista de palabras clave o patrones regex a buscar."
    echo -e "\n\tLos argumentos obligatorios para las opciones largas también son obligatorios para las opciones cortas."
    echo -e "\n\t\e[1m-r, --repo=DIRECTORY\e[0m"
    echo -e "\t\truta del repositorio de git"
    echo -e "\n\t\e[1m-c, --configuracion=FILE\e[0m"
    echo -e "\t\truta del archivo con los patrones o palabras a buscar."
    echo -e "\n\t\e[1m-h, --help\e[0m"
    echo -e "\t\tayuda para el uso del comandos"
    echo -e "\n\t\e[1m-k, --kill\e[0m"
    echo -e "\t\tflag para matar el proceso. Debe especificarse junto -r o --repo"
    echo -e "\n\t\e[1m-l, --log\e[0m"
    echo -e "\t\truta del archivo log a guardar las coincidencias encontradas."
    echo -e "\t\tSe necesita un archivo de extensión .log."
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
            echo Error: parametros mal especificados.
            echo "Utilice -h o --help para ayuda"
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
        FOUND=false
        while IFS="|" read -r PID REPO; do
            if [ "$REPOSITORY_ABS" = "$REPO" ]; then
                kill "$PID" 2>/dev/null
                sed -i "/^$PID/d" "$PID_FILE"
                FOUND=true
                break
            fi
        done < "$PID_FILE"

        if [ "$FOUND" = false ]; then
            echo "Error: repositorio no monitoreado"
            exit 1
        fi
        sleep 5
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "Error: el proceso no pudo matarse"
            exit 1
        fi
        exit 0
    else
        echo "Error: el proceso no existe"
        exit 1
    fi
fi

if [ -f "$PID_FILE" ]; then
    while IFS="|" read -r PID REPO; do
        if ps -p "$PID" > /dev/null 2>&1; then
            if [ "$REPO" = "$REPOSITORY_ABS" ]; then
                echo "Error: ya existe un demonio monitoreando $REPOSITORY_ABS con PID $PID"
                exit 1
            fi
        fi
    done < "$PID_FILE"
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

if [[ -z "$ARCH_LOG" || ! -f "$ARCH_LOG" || "$ARCH_LOG" != *.log ]]; then
    echo "Error: especifique una ruta de archivo de configuraciones valido"
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

ARCH_CONFIG_ABS=$(realpath "$ARCH_CONFIG")
ARCH_LOG_ABS=$(realpath "$ARCH_LOG")
cd "$REPOSITORY_ABS"

demon(){
    limpiezaTmp() { 
        echo "Limpiando..." 
        tmpfile=$(mktemp) 
        if [ -f "$PID_FILE" ]; then 
            while IFS="|" read -r PID REPO; do 
                if [ "$PID" != "$$" ]; then 
                    echo "$PID|$REPO" >> "$tmpfile" 
                fi 
            done < "$PID_FILE" 
            mv "$tmpfile" "$PID_FILE" 
        fi 
        
        if [ ! -s "$PID_FILE" ]; then 
            echo "Archivo vacío, borrando carpeta tmp" 
            rm -r "$SCRIPT_CURRENT/.tmp" 
        fi
        exit 0
    }
    trap limpiezaTmp SIGINT SIGTERM
    LAST_COMMIT=$(git rev-parse main)

    while true; do
        CURRENT_COMMIT=$(git rev-parse main)

        if [ "$CURRENT_COMMIT" != "$LAST_COMMIT" ]; then
            
            mapfile -t archivosCommit < <(git diff --name-only "$LAST_COMMIT" "$CURRENT_COMMIT")

            for file in "${archivosCommit[@]}"; do
                [ ! -f "$file" ] && continue  

                for pal in "${palabrasBuscar[@]}"; do
                    if grep -q "$pal" "$file"; then
                        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Alerta: palabra '$pal' encontrada en $(realpath "$file")" >> "$ARCH_LOG_ABS"
                    fi
                done

                for pat in "${patronesRegex[@]}"; do
                    if grep -Eq "$pat" "$file"; then
                        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Alerta: patrón '$pat' encontrado en $(realpath "$file")" >> "$ARCH_LOG_ABS"
                    fi
                done
            done

            LAST_COMMIT=$CURRENT_COMMIT
        fi

        sleep 5
    done
}
mkdir -p "$SCRIPT_CURRENT/.tmp"
demon &
echo "$!|$REPOSITORY_ABS" >> "$PID_FILE"

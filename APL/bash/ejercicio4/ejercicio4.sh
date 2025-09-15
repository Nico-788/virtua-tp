#!/bin/bash

ayuda(){
    echo "Análisis de seguridad en repositorios GIT"
    echo "El script monitorea los cambios en un directorio especificado, detectando patrones específicos en el contenido de dichos archivos."
    echo "Parámetros:"
    echo -e "\t -r | --repo"
    echo -e "\t\tRecibe la ruta del directorio a monitorear"
    echo -e "\t -l | --log"
    echo -e "\t\tRecibe la ruta del archivo donde volcar las coincidencias detectadas"
    echo -e "\t -c | --configuracion"
    echo -e "\t\tRecibe la ruta del archivo de configuración donde se detallan los patrones a encontrar"
    echo -e "\t -k | --kill"
    echo -e "\t\tTermina el proceso que monitorea el repositorio especificado. Funciona sólo si se especifica también -r o --repo"
    echo -e "\t -h | --help"
    echo -e "\t\tMuestra este mensaje"
}

opciones=$(getopt -o hr:l:c:k --l help,kill,repo:,configuracion:,log: -- "$@" 2> /dev/null)

if [ $? != '0' ]
then 
    echo "Parámetros incorrectos, utilice -h o --help para ayuda"
    exit 1
fi

eval set -- "$opciones"

AYUDA=false
KILL=false
LOG=""
CONFIG=""
REPO=""

while true
do
    case "$1" in 
        -r | --repo)
            REPO=$(realpath "$2")
            shift 2
            ;;
        -c | --configuracion)
            CONFIG="$2"
            shift 2
            ;;
        -l | --log)
            LOG=$(realpath "$2")
            shift 2
            ;;
        -h | --help)
            AYUDA=true
            shift 1
            ;;
        -k | --kill)
            KILL=true
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

if [ ! -d "$REPO" ]
then
    echo "Debe ingresar un repositorio válido"
fi

archReposObs="$REPO/temp.pid"

if [ $KILL = true ]
then
    if [ -f "$archReposObs" ]
    then
        kill $(cat $archReposObs)
        rm "$archReposObs"
        echo "El monitoreo del repositorio fue detenido exitosamente"
        exit 0
    else
        echo "ERROR: El directorio especificado no está siendo monitoreado"
        exit 1
    fi
fi

if [ ! -f "$CONFIG" ]
then
    echo "Debe ingresar un archivo de configuración válido"
    exit 1
fi

declare -a patrones

while IFS= read -r line
do
    if [[ $line =~ "regex:" ]]
    then
        patrones+=("${line#"regex:"}")
    else
        patrones+=("$line")
    fi
done < "$CONFIG"

if [ -f "$archReposObs" ]
then
    echo "El repositorio especificado ya está siendo monitoreado"
    exit 1
fi

echo "$$" > "$archReposObs"

inotifywait -m -r -e modify,move "$REPO" |
while read path action file
do
    rutaComp="$path$file"
    if [[ $action != "DELETE" && "$rutaComp" != "$LOG" && "$rutaComp" != "$archReposObs" ]]
    then
        contenido=$(cat "$REPO/$file" 2> /dev/null)
        for patron in ${patrones[@]}
        do
            coincidencias=$(echo "$contenido" | grep "$patron")
            
            if [ -n "$coincidencias" ]
            then
                fecha=$(date +"%Y-%m-%d %H:%M:%S")
                echo "["$fecha"] Alerta: patrón "$patron" encontrado en el archivo '$file'." >> "$LOG"
            fi
        done
    fi
done

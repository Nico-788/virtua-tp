#!/bin/bash

# Función que muestra la ayuda del script con formato y colores
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

# Procesa y valida los argumentos de línea de comandos usando getopt
options=$(getopt -o n:t:h --l nombre:,ttl:,help -- "$@" 2> /dev/null)
if [ "$?" != "0" ]
then
    echo 'Opciones incorrectas.'
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

# Reorganiza los argumentos procesados por getopt
eval set -- "$options"

# Inicialización de variables globales
HELP=false                                                    # Flag para mostrar ayuda
NOMBRES_PAISES=""                                            # String con países separados por comas
TTL_CACHE=0                                                  # Tiempo de vida del cache en segundos
BASE_URL="https://restcountries.com/v3.1/translation/"      # URL base de la API

# Bucle para procesar cada argumento individualmente
while true
do
    case "$1" in
        -n | --nombre)
            NOMBRES_PAISES="$2"          # Guarda los países solicitados
            shift 2                      # Salta el flag y su valor
            ;;
        -t | --ttl)
            TTL_CACHE="$2"              # Guarda el tiempo de vida especificado
            shift 2                     # Salta el flag y su valor
            ;;
        -h | --help)
            HELP=true                   # Marca que se pidió ayuda
            shift 1                     # Salta solo el flag
            ;;
        --)
            break                       # Fin de argumentos procesados por getopt
            ;;
        *)
            echo Error en parametros
            echo "Utilice -h o --help para ayuda"
            exit 1
            ;;
    esac
done

# Si se pidió ayuda, la muestra y termina
if [ "$HELP" = true ]; then
    ayuda
    exit 0
fi

# Valida que se hayan especificado países para buscar
if [ -z "$NOMBRES_PAISES" ]; then
    echo "Error: paises no especificados"
    echo "Utilice -h o --help para ayuda"
    exit 1
fi

# QUEREMOS GUARDAR LA UBICACIÓN DEL SCRIPT, PARA QUE CUANDO CREEMOS EL ARCHIVO CACHE, ESTE
# SIEMPRE EN EL MISMO LUGAR JUNTO AL SCRIPT SIN IMPORTAR DESDE DONDE SE EJECUTEN.
DIRECTORY_SCRIPT="$(dirname "$(realpath "$0")")"            # Directorio donde está el script
CACHE_DIR="$DIRECTORY_SCRIPT"/.tmp                          # Directorio para archivos cache individuales
TTL_CACHE_FILE="$DIRECTORY_SCRIPT"/.ttl_cache               # Archivo que guarda el TTL global

# Gestión del TTL (Time To Live) del cache
if [ $TTL_CACHE -eq 0 ]; then # Si el tiempo de la caché es 0 (no especificado)
    if [ -f "$TTL_CACHE_FILE" ]; then # Y si hay archivo de TTL anterior
        TTL_CACHE=$(cat "$TTL_CACHE_FILE") # Usa ese TTL anterior
    fi
else
    # Valida que el TTL sea un número válido (entero o decimal)
    if [[ $TTL_CACHE =~ ^[0-9]+\.?[0-9]*$ ]]; then # Sino hay archivo caché, creas un archivo con un timing especificado
        echo "$TTL_CACHE" > "$TTL_CACHE_FILE" # Guardo el archivo ttl_file 
        # -p es de parents, sirve para crear directorios sino existe, y no da error si ya existía
        mkdir -p "$CACHE_DIR" # Y crea un directorio temporal en caso de que no existe
    else # Si el TTL no es un número válido, muestra error y termina.
        echo "Error: numero de ttl invalido" 
        echo "Utilice -h o --help para ayuda"
        exit 1
    fi
fi

# APARTADO DE PARSEO SEGÚN CADA PAÍS, Y LOS CARGA EN UN VECTOR ASOCIATIVO
# Convierte la cadena "España,Francia,Italia" en array ["España", "Francia", "Italia"]
IFS=',' read -ra paisesABuscar <<< "$NOMBRES_PAISES"

# IMPLEMENTACIÓN MEJORADA: Cache individual por país
# Verifica cache individual para cada país antes de ir a la API
for i in "${!paisesABuscar[@]}"; do
    currentPais="${paisesABuscar[i]}"
    # Normaliza el nombre del país para usarlo como nombre de archivo
    paisNormalizado=$(echo -n "$currentPais" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_')
    INDIVIDUAL_CACHE_FILE="$CACHE_DIR/${paisNormalizado}.cache"
    
    # Si existe el archivo cache individual para este país
    if [ -f "$INDIVIDUAL_CACHE_FILE" ]; then
        # Verifica si el cache individual sigue siendo válido
        if (( $(date +%s) - $(stat -c %Y "$INDIVIDUAL_CACHE_FILE") <= "$TTL_CACHE" )); then
            # Lee la información del cache individual
            if [ -s "$INDIVIDUAL_CACHE_FILE" ]; then  # -s verifica que no esté vacío
                infoPais=$(cat "$INDIVIDUAL_CACHE_FILE")
                # Verifica que la información coincida con el país buscado
                if echo "$infoPais" | grep -qi "$currentPais"; then
                    echo -e "\nBuscando en CACHE: $currentPais\n" # Informamos que encontramos en cache
                    # Parsea el archivo cache que viene separado por pipes
                    echo "$infoPais" | awk -F'|' '{printf "%s\n%s\n%s\n", $1, $2, $3}'
                    unset 'paisesABuscar[i]'  # Elimina el país del array para no buscarlo en API
                fi
            fi
        else
            # Si el cache individual expiró, lo elimina
            rm -f "$INDIVIDUAL_CACHE_FILE"
        fi
    fi
done

# Busqueda en la API, acá llegamos sino enganchamos arriba en el archivo caché
# Solo procesa países que no se encontraron en cache individual
for pais in "${paisesABuscar[@]}"; do
    echo -e "\nBuscando en API: $pais\n"
    # Acá normalizamos la info del vector a un formato entendible para la URL
    paisParaURL=$(echo -n "$pais" | jq -sRr @uri) # Normaliza $pais ya que puede tener caracteres especiales
    # Realizamos la petición real a internet
    resp=$(curl -s "$BASE_URL""$paisParaURL") # -s no muestra barra de progreso ni errores
    # "$BASE_URL""$paisParaURL" = concatena la URL base con el país
    
    # Verifica si la API devolvió un resultado válido (array) o error (objeto)
    if echo "$resp" | jq -e 'type=="array"' >/dev/null; then    # La API devuelve un array si lo encontró, caso contrario envía un msj de error
        # Extrae y formatea la información específica del JSON de respuesta
        resultadoCurl="$(echo "$resp" | jq -r '.[] | "Pais: \(.translations.spa.common)|Capital: \((.capital | join(", ")))|Moneda: \((.currencies | keys | join(", ")))"')"

        # Si hay TTL configurado, guarda en cache individual
        if [ "$TTL_CACHE" -gt 0 ]; then
            # Crea nombre de archivo normalizado para el cache individual
            paisNormalizado=$(echo -n "$pais" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_')
            INDIVIDUAL_CACHE_FILE="$CACHE_DIR/${paisNormalizado}.cache"
            # Guarda la información en el archivo cache individual
            echo "$resultadoCurl" > "$INDIVIDUAL_CACHE_FILE"
        fi
        
        # Muestra el resultado formateado separando por pipes en líneas
        echo "$resultadoCurl" | awk -F'|' '{printf "%s\n%s\n%s\n", $1, $2, $3}'
        echo ""
    else
        echo -e "Error: No se encontro el pais: $pais.\nConsulte en otro idioma o compruebe que este escrito correctamente\n" # Si no es array, no lo encontró
    fi
done

# Ejemplo de URL para referencia
#curl "https://restcountries.com/v3.1/name/spain"

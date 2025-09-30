#!/bin/bash

#echo "PRUEBA DE LECTURA A LA MATRIZ"
#path=$1          # Guardamos en "path" el primer argumento que le pasemos al script (la ruta del archivo)
#matriz=()        # Creamos un cajón vacío para guardar las filas de la matriz
#separador=$4 
#ACA BAJAMOS LA MATRIZ DEL ARCHIVO CON EL PATH $1

function ayuda() {
    echo -e "\e[1mNAME\e[0m"
    echo -e "\t02-mapa"
    echo -e "\n\e[1mSYNOPSIS\e[0m"
    echo -e "\t ./02-mapa OPTION FILE OPTION"
    echo -e "\n\e[1mDESCRIPTION\e[0m"
    echo -e "\tAnaliza rutas en un mapa de transporte representado como matriz de adyacencia."
    echo -e "\n\t\e[1m-m, --matriz=FILE\e[0m"
    echo -e "\t\tRuta del archivo con la matriz."
    echo -e "\n\t\e[1m-h, --hub\e[0m"
    echo -e "\t\tCalcula el hub de la red (estación con más conexiones)."
    echo -e "\n\t\e[1m-c, --camino=INICIO,FIN\e[0m"
    echo -e "\t\tCalcula el camino más corto entre dos estaciones usando Dijkstra."
    echo -e "\n\t\e[1m-s, --separador SEP\e[0m"
    echo -e "\t\tSeparador de columnas (default: |)"
}

options=$(getopt -o m:c:s:hu --l help,matriz:,camino:,separador:,hub -- "$@" 2> /dev/null)
if [ "$?" != "0" ]
then
    echo 'Opciones incorrectas.'
    echo "Utilice --help para ayuda"
    exit 1
fi

eval set -- "$options"

archivo_matriz=""   # Archivo de matriz
hub="false"         # Estación hub (opcional)
camino="false"      # Camino más corto (opcional)
separador="|"       # Separador por defecto
HELP="false"

while true; do
    case "$1" in
        -m|--matriz)
            archivo_matriz="$2"   
            shift 2               
            ;;
        -h|--hub)               
            if [ "$camino" = true ]
            then
                echo "No se puede usar -h y -c a la vez"
                echo "Utilice --help para ayuda"
                exit 1
            fi
            hub="true"
            shift 1
            ;;
        -c|--camino)
            if [ "$hub" = true ]
            then
                echo "No se puede usar -h y -c a la vez"
                echo "Utilice --help para ayuda"
                exit 1
            fi
            camino="true"
            nodoInicioRecorrido=$(echo "$2" | cut -d',' -f1)
            nodoFinRecorrido=$(echo "$2" | cut -d',' -f2)
            shift 2
            ;;
        -s|--separador)
            separador="$2"        
            shift 2
            ;;
        -u|--help)
            HELP="true"
            shift 1
            ;;
        --)
            break
            ;;
        *)
            echo "Parametro desconocido: $1"
            exit 1
            ;;
    esac
done

# -----------------------------
# VALIDACIÓN DE ENTRADAS
# -----------------------------
if [ "$HELP" = true ]
then
    ayuda
    exit 0
fi

if [[ -z "$archivo_matriz" ]]; then
   echo "Error: Debe especificar un archivo de matriz con -m/--matriz"
   exit 1
fi

if [[ "$hub" = false && "$camino" = false ]]; then
    echo "Error: Debe especificar un parametro para buscar camino"
    echo "Utilice --help para ayuda"
    exit 1
fi

# -----------------------------
# LECTURA DE LA MATRIZ
# -----------------------------
archivo_matriz="$(realpath "$archivo_matriz")" 
mapfile -t lineas < "$archivo_matriz"
cantNodos=${#lineas[@]}
declare -A matriz

for i in "${!lineas[@]}"; do
    IFS="$separador" read -ra fila <<< "${lineas[$i]}"
    if [[ ${#fila[@]} -ne $cantNodos ]]; then
        echo "Error: la matriz no es cuadrada"; exit 1
    fi
    for j in "${!fila[@]}"; do
        val="${fila[$j]}"

        if ! [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "Error: valor no numérico ($val)"; exit 1
        fi
        matriz[$i,$j]=$val
    done
done

# Validar simetría
for ((i=0; i<cantNodos; i++)); do
    for ((j=0; j<cantNodos; j++)); do
        if [[ "${matriz[$i,$j]}" != "${matriz[$j,$i]}" ]]; then
            echo "Error: la matriz no es simétrica"; exit 1
        fi
    done
done

nombre_out="informe.$(basename "$archivo_matriz")"

# -----------------------------
# LÓGICA PARA ENCONTRAR HUB
# -----------------------------
if [ "$hub" = true ]
then
    echo "Buscando estación hub..."

    max_conex=0; hub=-1
    for ((i=0; i<cantNodos; i++)); do
        conexiones=0
        for ((j=0; j<cantNodos; j++)); do
            if [[ $i -ne $j && "${matriz[$i,$j]}" != "0" ]]; then
                ((conexiones++))
            fi
        done
        if (( conexiones > max_conex )); then
            max_conex=$conexiones
            hub=$((i+1))
        fi
    done
    echo "**Hub de la red:** Estación $hub ($max_conex conexiones)" > "$nombre_out"
    echo "Informe generado en: $nombre_out"
    exit 0
fi

# -----------------------------
# INICIALIZACIÓN DE VECTORES PARA DIJKSTRA
# -----------------------------
dijkstra() {
    local start=$((nodoInicioRecorrido-1)) 
    local end=$((nodoFinRecorrido-1))
    for ((i=0; i<cantNodos; i++)); do
        dist[$i]=999999; prev[$i]=-1; visitado[$i]=0
    done
    dist[$start]=0

    for ((c=0; c<cantNodos; c++)); do
        min=999999; u=-1
        for ((i=0; i<cantNodos; i++)); do
            if (( visitado[i]==0 && dist[i]<min )); then
                min=${dist[$i]}; u=$i
            fi
        done
        [[ $u -eq -1 ]] && break
        visitado[$u]=1

        for ((v=0; v<cantNodos; v++)); do
            peso=${matriz[$u,$v]}
            if (( peso > 0 )); then
                if (( dist[$u] + peso < dist[$v] )); then
                    dist[$v]=$((dist[$u] + peso))
                    prev[$v]=$u
                fi
            fi
        done
    done

    ruta=()
    u=$end
    while [[ $u -ne -1 ]]; do
        ruta=($((u+1)) "${ruta[@]}")
        u=${prev[$u]}
    done

    echo "**Camino más corto: entre Estación $nodoInicioRecorrido y Estación $nodoFinRecorrido:**"
    echo "**Tiempo total:** ${dist[$end]} minutos"
    echo "**Ruta:** ${ruta[*]} " | sed 's/ / -> /g'
}

if [ "$camino" = true ]; then

    dijkstra > "$nombre_out"

    echo "Informe generado en: $nombre_out"
fi


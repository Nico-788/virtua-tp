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
    echo -e "\n\t\e[1m-c, --camino\e[0m"
    echo -e "\t\tCalcula el camino más corto usando Dijkstra."
    echo -e "\n\t\e[1m-s, --separador SEP\e[0m"
    echo -e "\t\tSeparador de columnas (default: |)"
}

options=$(getopt -o m:cs:hu --l help,matriz:,camino,separador:,hub -- "$@" 2> /dev/null)
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
            shift 1
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
    # Inicializar matrices de distancia y camino
    declare -A dist
    declare -A next
    
    # Copiar la matriz de adyacencia a dist
    for ((i=0; i<cantNodos; i++)); do
        for ((j=0; j<cantNodos; j++)); do
            if [[ $i -eq $j ]]; then
                dist[$i,$j]=0
            elif [[ "${matriz[$i,$j]}" == "0" ]]; then
                dist[$i,$j]=999999  # Infinito
                next[$i,$j]=-1
            else
                dist[$i,$j]="${matriz[$i,$j]}"
                next[$i,$j]=$j
            fi
        done
    done
    
    # Realizo los calculos de distancias mínimas
    for ((k=0; k<cantNodos; k++)); do
        for ((i=0; i<cantNodos; i++)); do
            for ((j=0; j<cantNodos; j++)); do
                suma=$(echo "${dist[$i,$k]} + ${dist[$k,$j]}" | bc)
                if (( $(echo "$suma < ${dist[$i,$j]}" | bc -l) )); then
                    dist[$i,$j]=$suma
                    next[$i,$j]=${next[$i,$k]}
                fi
            done
        done
    done
    
    # Encontrar el camino más corto de todos
    min_dist=999999
    for ((i=0; i<cantNodos; i++)); do
        for ((j=i+1; j<cantNodos; j++)); do
            if [[ ${next[$i,$j]} -ne -1 ]]; then
                if (( $(echo "${dist[$i,$j]} < $min_dist" | bc -l) )); then
                    min_dist=${dist[$i,$j]}
                fi
            fi
        done
    done
    
    # Generar informe solo con los caminos de distancia mínima
    echo "## Informe de análisis de red de transporte"
    echo ""
    echo "**Camino/s más corto/s: **"
    
    for ((i=0; i<cantNodos; i++)); do
        for ((j=i+1; j<cantNodos; j++)); do
            if [[ ${next[$i,$j]} -ne -1 ]]; then
                # Solo mostrar si la distancia es igual a la mínima
                # Si hay varios caminos con la misma distancia mínima, se muestran todos
                if (( $(echo "${dist[$i,$j]} == $min_dist" | bc -l) )); then
                    origen=$((i+1))
                    destino=$((j+1))
                    
                    echo -e "\t**Entre Estación $origen y Estación $destino:**"
                    
                    # Reconstruir el camino
                    ruta="$origen"
                    actual=$i
                    while [[ $actual -ne $j ]]; do
                        actual=${next[$actual,$j]}
                        ruta="$ruta -> $((actual+1))"
                    done
                    
                    echo -e "\t**Tiempo total:** ${dist[$i,$j]} minutos"
                    echo -e "\t**Ruta:** $ruta"
                    echo ""
                fi
            fi
        done
    done
}

if [ "$camino" = true ]; then

    dijkstra > "$nombre_out"

    echo "Informe generado en: $nombre_out"
fi


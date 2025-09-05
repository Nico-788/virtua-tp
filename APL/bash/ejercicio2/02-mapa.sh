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

options=$(getopt -o m:c:s:h --l help,matriz:,camino:,separador:,hub -- "$@" 2> /dev/null)
if [ "$?" != "0" ]
then
    echo 'Opciones incorrectas.'
    echo "Utilice --help para ayuda"
    exit 1
fi

eval set -- "$options"

archivo_matriz=""   # Archivo de matriz
hub="false"              # Estación hub (opcional)
camino=""           # Camino más corto (opcional)
separador="|"       # Separador por defecto
HELP="false"

# -----------------------------
# LECTURA DE PARÁMETROS
# -----------------------------
# Recorremos todos los parámetros pasados al script
while true; do
    case "$1" in
        -m|--matriz)
            archivo_matriz="$2"   
            shift 2               
            ;;
        -h|--hub)               
            if [ -n "$camino" ]
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
            camino="$2"
            shift 2
            ;;
        -s|--separador)
            separador="$2"        
            shift 2
            ;;
        --help)
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

echo "Archivo matriz: $archivo_matriz"
echo "Hub: $hub"
echo "Camino: $camino"
echo "Separador: $separador"

# -----------------------------
# LECTURA DE LA MATRIZ
# -----------------------------
echo "PRUEBA DE LECTURA A LA MATRIZ"
matriz=()  # Array principal para guardar las filas de la matriz

# Leemos cada línea del archivo
while IFS= read -r linea; do
   # Reemplazamos el separador por espacio para convertir a array correctamente
   linea=${linea//$separador/ }

   # Convertimos la línea en array de columnas
   read -r -a columnas <<< "$linea"

   # Mostramos la fila completa
   echo "Fila completa: ${columnas[@]}"

   # Guardamos la fila como un string separado por espacios
   matriz+=("${columnas[*]}")

   # Mostramos cada columna individualmente
   for i in "${!columnas[@]}"; do
       echo "Columna $((i+1)): ${columnas[$i]}"
   done
   echo "----"
done < "$archivo_matriz"

# -----------------------------
# VALIDACIONES DE LA MATRIZ
# -----------------------------
cantNodos=${#matriz[@]}

# Validar que la matriz sea cuadrada
for ((i=0; i<cantNodos; i++)); do
   fila_actual=(${matriz[i]})
   if [[ ${#fila_actual[@]} -ne $cantNodos ]]; then
       echo "Error: La matriz no es cuadrada. Fila $((i+1)) tiene ${#fila_actual[@]} columnas, esperadas $cantNodos"
       exit 1
   fi
done

# Validar que la matriz sea simétrica y contenga solo valores numéricos
for ((i=0; i<cantNodos; i++)); do
   fila_i=(${matriz[i]})
   for ((j=0; j<cantNodos; j++)); do
       fila_j=(${matriz[j]})
       
       # Validar que el valor sea numérico
       if ! [[ ${fila_i[j]} =~ ^[0-9]+([.][0-9]+)?$ ]]; then
           echo "Error: Valor no numérico encontrado en posición [$((i+1)),$((j+1))]: ${fila_i[j]}"
           exit 1
       fi
       
       # Validar simetría
       if [[ ${fila_i[j]} != ${fila_j[i]} ]]; then
           echo "Error: La matriz no es simétrica. Posición [$((i+1)),$((j+1))] = ${fila_i[j]}, pero posición [$((j+1)),$((i+1))] = ${fila_j[i]}"
           exit 1
       fi
   done
done

# -----------------------------
# CANTIDAD DE NODOS
# -----------------------------
# El número de filas en la matriz corresponde al número de nodos

# Nodo inicial (por defecto, 0 = primera estación)
nodoInicial=0

echo "Cantidad de nodos: $cantNodos"
echo "Nodo inicial: $nodoInicial"

# -----------------------------
# LÓGICA PARA ENCONTRAR HUB
# -----------------------------
if [ "$hub" = true ]
then
    echo "Buscando estación hub..."

    # Contamos las conexiones de cada estación (valores diferentes de 0)
    declare -a conexiones_por_estacion

    for ((i=0; i<cantNodos; i++)); do
        fila_actual=(${matriz[i]})
        contador_conexiones=0
        
        for ((j=0; j<cantNodos; j++)); do
            if [[ i -ne j && ${fila_actual[j]} -ne 0 ]]; then
                contador_conexiones=$((contador_conexiones + 1))
            fi
        done
        
        conexiones_por_estacion[i]=$contador_conexiones
        echo -e "\nEstación $((i+1)): $contador_conexiones conexiones"
    done

    # Encontramos la estación con más conexiones
    max_conexiones=0
    estacion_hub=0

    for ((i=0; i<cantNodos; i++)); do
        if [[ ${conexiones_por_estacion[i]} -gt $max_conexiones ]]; then
            max_conexiones=${conexiones_por_estacion[i]}
            estacion_hub=$i
        fi
    done

    echo "Hub encontrado: Estación $((estacion_hub+1)) con $max_conexiones conexiones"

fi

# -----------------------------
# INICIALIZACIÓN DE VECTORES PARA DIJKSTRA
# -----------------------------
if [[ -n "$camino" ]]; then
   # distancia[i] -> distancia mínima conocida desde nodo inicial hasta nodo i
   # nodoVistado[i] -> 1 si el nodo i ya fue visitado, 0 si no
   # predecesor[i] -> nodo anterior en el camino más corto hacia nodo i
   declare -a distancia
   declare -a nodoVistado
   declare -a predecesor

   # Convertimos el parámetro camino de 1-indexado a 0-indexado
   nodo_destino_especificado=$((camino - 1))

   # Inicializamos todos los nodos
   for ((i=0; i<cantNodos; i++)); do
       distancia[i]=9999   # Número grande para simular infinito
       nodoVistado[i]=0    # Marcamos todos los nodos como no visitados
       predecesor[i]=-1    # Sin predecesor inicialmente
   done

   # La distancia del nodo inicial a sí mismo es 0
   distancia[$nodoInicial]=0

   # -----------------------------
   # FUNCIÓN: Buscar nodo no visitado con distancia mínima
   # -----------------------------
   buscarDistMinima() {
       local min=9999
       local min_index=-1

       for ((i=0;i<cantNodos;i++)); do
           if [[ ${nodoVistado[i]} -eq 0 && ${distancia[i]} -le $min ]]; then
               min=${distancia[i]}
               min_index=$i
           fi
       done

       echo $min_index
   }

   # -----------------------------
   # FUNCIÓN: Reconstruir camino desde predecesor
   # -----------------------------
   reconstruir_camino() {
       local destino=$1
       local origen=$2
       local camino_completo=""
       local nodo_actual=$destino
       
       # Construimos el camino desde el destino hasta el origen
       while [[ $nodo_actual -ne $origen ]]; do
           if [[ -z "$camino_completo" ]]; then
               camino_completo="$((nodo_actual+1))"
           else
               camino_completo="$((nodo_actual+1)) -> $camino_completo"
           fi
           nodo_actual=${predecesor[$nodo_actual]}
       done
       
       # Agregamos el nodo origen al inicio
       camino_completo="$((origen+1)) -> $camino_completa"
       echo "$camino_completo"
   }

   # Variables para almacenar información del camino más corto global
   distancia_minima_global=9999
   origen_camino_corto=-1
   destino_camino_corto=-1

   # Si se especificó un destino, calculamos solo hacia ese nodo
   # Si no, buscamos el camino más corto entre todas las estaciones
   if [[ $nodo_destino_especificado -ge 0 && $nodo_destino_especificado -lt $cantNodos ]]; then
       # Modo específico: calcular camino desde nodo inicial hacia destino especificado
       echo "Calculando camino desde estación $((nodoInicial+1)) hacia estación $camino"
       
       # -----------------------------
       # ALGORITMO DE DIJKSTRA
       # -----------------------------
       for ((count=0; count<cantNodos-1; count++)); do
           # Buscamos el nodo no visitado con distancia mínima
           u=$(buscarDistMinima)
           nodoVistado[$u]=1

           # Obtenemos la fila de la matriz correspondiente al nodo seleccionado
           row=(${matriz[$u]})

           # Recorremos todos los nodos vecinos
           for ((i=0; i<cantNodos; i++)); do
               # Solo actualizamos si:
               # 1. No ha sido visitado
               # 2. Hay conexión (valor distinto de 0)
               # 3. La distancia pasando por u es menor que la actual
               if [[ ${nodoVistado[i]} -eq 0 && ${row[i]} -ne 0 && $((distancia[u]+row[i])) -lt ${distancia[i]} ]]; then
                   distancia[i]=$((distancia[u]+row[i]))
                   predecesor[i]=$u
               fi
           done
       done

       # Guardamos el resultado para el destino especificado
       distancia_minima_global=${distancia[$nodo_destino_especificado]}
       origen_camino_corto=$nodoInicial
       destino_camino_corto=$nodo_destino_especificado
       
   else
       # Modo búsqueda global: encontrar el camino más corto entre todas las estaciones
       echo "Buscando camino más corto entre todas las estaciones..."
       
       # Ejecutamos Dijkstra desde cada nodo para encontrar el camino más corto global
       for ((nodo_origen=0; nodo_origen<cantNodos; nodo_origen++)); do
           
           # Inicializamos todos los nodos para este origen
           for ((i=0; i<cantNodos; i++)); do
               distancia[i]=9999
               nodoVistado[i]=0
               predecesor[i]=-1
           done

           distancia[$nodo_origen]=0

           # Ejecutamos Dijkstra desde este origen
           for ((count=0; count<cantNodos-1; count++)); do
               u=$(buscarDistMinima)
               nodoVistado[$u]=1
               row=(${matriz[$u]})

               for ((i=0; i<cantNodos; i++)); do
                   if [[ ${nodoVistado[i]} -eq 0 && ${row[i]} -ne 0 && $((distancia[u]+row[i])) -lt ${distancia[i]} ]]; then
                       distancia[i]=$((distancia[u]+row[i]))
                       predecesor[i]=$u
                   fi
               done
           done

           # Buscamos la distancia más corta desde este origen hacia cualquier otro nodo
           for ((destino=0; destino<cantNodos; destino++)); do
               if [[ $destino -ne $nodo_origen && ${distancia[destino]} -lt $distancia_minima_global ]]; then
                   distancia_minima_global=${distancia[destino]}
                   origen_camino_corto=$nodo_origen
                   destino_camino_corto=$destino
               fi
           done
       done
   fi

   echo "Camino más corto encontrado: desde estación $((origen_camino_corto+1)) hasta estación $((destino_camino_corto+1))"
   echo "Distancia: $distancia_minima_global"
fi

# -----------------------------
# GENERACIÓN DEL ARCHIVO DE INFORME
# -----------------------------
# Extraemos el nombre base del archivo sin la ruta
nombre_archivo=$(basename "$archivo_matriz")
archivo_salida="informe.$nombre_archivo"

# Creamos el archivo de informe en el mismo directorio que el archivo original
directorio_archivo=$(dirname "$archivo_matriz")
ruta_completa_salida="$directorio_archivo/$archivo_salida"

echo "Generando informe en: $ruta_completa_salida"

# Escribimos el encabezado del informe
echo "## Informe de análisis de red de transporte" > "$ruta_completa_salida"

if [[ -n "$hub" ]]; then
   echo "**Hub de la red:** Estación $((estacion_hub+1)) ($max_conexiones conexiones)" >> "$ruta_completa_salida"
fi

if [[ -n "$camino" ]]; then
   # Recalculamos Dijkstra para el camino específico encontrado para obtener la ruta completa
   for ((i=0; i<cantNodos; i++)); do
       distancia[i]=9999
       nodoVistado[i]=0
       predecesor[i]=-1
   done
   
   distancia[$origen_camino_corto]=0
   
   for ((count=0; count<cantNodos-1; count++)); do
       u=$(buscarDistMinima)
       nodoVistado[$u]=1
       row=(${matriz[$u]})
       
       for ((i=0; i<cantNodos; i++)); do
           if [[ ${nodoVistado[i]} -eq 0 && ${row[i]} -ne 0 && $((distancia[u]+row[i])) -lt ${distancia[i]} ]]; then
               distancia[i]=$((distancia[u]+row[i]))
               predecesor[i]=$u
           fi
       done
   done
   
   ruta_completa=$(reconstruir_camino $destino_camino_corto $origen_camino_corto)
   
   echo "**Camino más corto: entre Estación $((origen_camino_corto+1)) y Estación $((destino_camino_corto+1)):**" >> "$ruta_completa_salida"
   echo "**Tiempo total:** $distancia_minima_global minutos" >> "$ruta_completa_salida"
   echo "**Ruta:** $ruta_completa" >> "$ruta_completa_salida"
fi

echo "Informe generado exitosamente en $ruta_completa_salida"

# -----------------------------
# MOSTRAR RESULTADOS DIJKSTRA
# -----------------------------
echo "Distancias más cortas desde el nodo $nodoInicial:"
for ((i=0; i<cantNodos; i++)); do
   echo "Hasta nodo $((i+1)): ${distancia[i]}"
done

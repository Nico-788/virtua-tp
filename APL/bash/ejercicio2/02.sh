#!/bin/bash

# -----------------------------
# FUNCIÓN DE AYUDA
# -----------------------------
mostrar_ayuda() {
    cat << EOF
Uso: $0 -m ARCHIVO [OPCIONES]
Analiza rutas en red de transporte usando matriz de adyacencia.

PARÁMETROS OBLIGATORIOS:
  -m, --matriz ARCHIVO    Archivo con matriz de adyacencia

OPCIONES (mutuamente exclusivas):
  --hub                   Encuentra estación hub (más conexiones)
  -c, --camino [NODO]     Camino más corto (opcional: hacia nodo específico)
  
OTROS:
  -s, --separador CHAR    Separador de columnas (por defecto: |)
      --help              Muestra esta ayuda

EJEMPLOS:
  $0 -m matriz.txt --hub
  $0 -m matriz.txt -c 3
  $0 -m matriz.txt -c -s ","
  $0 --help

NOTAS:
  - La matriz debe ser cuadrada y simétrica
  - Los valores deben ser numéricos (enteros o decimales)
  - Un 0 indica sin conexión directa entre estaciones
EOF
}

# -----------------------------
# MANEJO DE ERRORES Y LIMPIEZA
# -----------------------------
trap 'echo "Error: Script interrumpido"; exit 1' INT TERM

archivo_matriz=""   # Archivo de matriz
hub_mode=false      # Modo búsqueda de hub
camino=""           # Camino más corto (opcional)
separador="|"       # Separador por defecto

# -----------------------------
# LECTURA DE PARÁMETROS CON getopt
# -----------------------------

# Verificar si --help fue solicitado antes de getopt
for arg in "$@"; do
    if [[ "$arg" == "--help" ]]; then
        mostrar_ayuda
        exit 0
    fi
done

# Usar getopt para parsing robusto de parámetros
TEMP=$(getopt -o m:c:s:h --long matriz:,camino:,separador:,hub,help -n "$0" -- "$@")

# Verificar si getopt falló
if [ $? != 0 ]; then
    echo "Error en los parámetros. Use --help para ver opciones disponibles"
    exit 1
fi

# Reemplazar parámetros con salida normalizada de getopt
eval set -- "$TEMP"

# Procesar parámetros normalizados
while true; do
    case "$1" in
        --help)
            mostrar_ayuda
            exit 0
            ;;
        -m|--matriz)
            archivo_matriz="$2"
            shift 2
            ;;
        --hub)
            if [[ "$hub_mode" == "true" ]]; then
                echo "Error: --hub especificado múltiples veces"
                exit 1
            fi
            if [[ -n "$camino" ]]; then
                echo "Error: --hub no puede usarse con -c/--camino"
                exit 1
            fi
            hub_mode=true
            shift
            ;;
        -c|--camino)
            if [[ "$hub_mode" == "true" ]]; then
                echo "Error: -c/--camino no puede usarse con --hub"
                exit 1
            fi
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                camino="$2"
                shift 2
            else
                camino="global"  # Búsqueda global si no se especifica nodo
                shift
            fi
            ;;
        -s|--separador)
            separador="$2"
            shift 2
            ;;
        -h)
            # Conflicto: getopt interpreta -h como opción corta para --hub
            # pero también tenemos --help. En este contexto, -h = --hub
            if [[ "$hub_mode" == "true" ]]; then
                echo "Error: -h/--hub especificado múltiples veces"
                exit 1
            fi
            if [[ -n "$camino" ]]; then
                echo "Error: -h/--hub no puede usarse con -c/--camino"
                exit 1
            fi
            hub_mode=true
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error interno en procesamiento de parámetros"
            exit 1
            ;;
    esac
done

# -----------------------------
# VALIDACIÓN DE ENTRADAS
# -----------------------------
if [[ -z "$archivo_matriz" ]]; then
   echo "Error: Debe especificar un archivo de matriz con -m/--matriz"
   echo "Use --help para ver el uso correcto"
   exit 1
fi

# Validar que el archivo existe y es legible
if [[ ! -f "$archivo_matriz" ]]; then
   echo "Error: El archivo '$archivo_matriz' no existe"
   exit 1
fi

if [[ ! -r "$archivo_matriz" ]]; then
   echo "Error: No se puede leer el archivo '$archivo_matriz'"
   exit 1
fi

# Validar que el archivo no esté vacío
if [[ ! -s "$archivo_matriz" ]]; then
   echo "Error: El archivo '$archivo_matriz' está vacío"
   exit 1
fi

# Validación: debe especificar al menos una opción de procesamiento
if [[ "$hub_mode" == "false" && -z "$camino" ]]; then
   echo "Error: Debe especificar --hub o -c/--camino"
   echo "Use --help para ver opciones disponibles"
   exit 1
fi

# Validar que el directorio de destino sea escribible
directorio_archivo=$(dirname "$archivo_matriz")
if [[ ! -w "$directorio_archivo" ]]; then
   echo "Error: No se puede escribir en el directorio '$directorio_archivo'"
   exit 1
fi

echo "Archivo matriz: $archivo_matriz"
echo "Hub mode: $hub_mode"
echo "Camino: $camino"
echo "Separador: [$separador]"

# -----------------------------
# LECTURA DE LA MATRIZ
# -----------------------------
echo "PRUEBA DE LECTURA A LA MATRIZ"
matriz=()  # Array principal para guardar las filas de la matriz

# Contador de líneas para mejor reporte de errores
numero_linea=0

# Leemos cada línea del archivo
while IFS= read -r linea; do
   numero_linea=$((numero_linea + 1))
   
   # Saltar líneas vacías
   if [[ -z "$linea" || "$linea" =~ ^[[:space:]]*$ ]]; then
       continue
   fi

   # Reemplazamos el separador por espacio para convertir a array correctamente
   linea=${linea//$separador/ }

   # Convertimos la línea en array de columnas
   read -r -a columnas <<< "$linea"
   
   # Validar que la línea tenga al menos una columna
   if [[ ${#columnas[@]} -eq 0 ]]; then
       echo "Error: Línea $numero_linea está vacía o mal formateada"
       exit 1
   fi

   # Mostramos la fila completa
   echo "Fila $numero_linea: ${columnas[@]}"

   # Guardamos la fila como un string separado por espacios
   matriz+=("${columnas[*]}")

   # Mostramos cada columna individualmente
   for i in "${!columnas[@]}"; do
       echo "  Columna $((i+1)): ${columnas[$i]}"
   done
   echo "----"
done < "$archivo_matriz"

# Validar que se leyó al menos una fila
if [[ ${#matriz[@]} -eq 0 ]]; then
   echo "Error: No se pudieron leer datos válidos del archivo"
   exit 1
fi

# -----------------------------
# VALIDACIONES DE LA MATRIZ
# -----------------------------
cantNodos=${#matriz[@]}

echo "Validando matriz de ${cantNodos}x${cantNodos}..."

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
       
       # Validar que el valor sea numérico (entero o decimal)
       if ! [[ ${fila_i[j]} =~ ^[0-9]+([.][0-9]+)?$ ]]; then
           echo "Error: Valor no numérico encontrado en posición [$((i+1)),$((j+1))]: '${fila_i[j]}'"
           exit 1
       fi
       
       # Validar simetría
       if [[ ${fila_i[j]} != ${fila_j[i]} ]]; then
           echo "Error: La matriz no es simétrica. Posición [$((i+1)),$((j+1))] = ${fila_i[j]}, pero posición [$((j+1)),$((i+1))] = ${fila_j[i]}"
           exit 1
       fi
   done
done

echo "Matriz validada correctamente: cuadrada, simétrica y con valores numéricos"

# -----------------------------
# CANTIDAD DE NODOS
# -----------------------------
nodoInicial=0

echo "Cantidad de nodos: $cantNodos"
echo "Nodo inicial: $nodoInicial"

# -----------------------------
# LÓGICA PARA ENCONTRAR HUB
# -----------------------------
if [[ "$hub_mode" == "true" ]]; then
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
       echo "Estación $((i+1)): $contador_conexiones conexiones"
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
   declare -a distancia
   declare -a nodoVistado
   declare -a predecesor

   # Validar nodo de destino si se especificó
   if [[ "$camino" != "global" ]]; then
       nodo_destino_especificado=$((camino - 1))
       if [[ $nodo_destino_especificado -lt 0 || $nodo_destino_especificado -ge $cantNodos ]]; then
           echo "Error: Nodo destino $camino está fuera del rango válido (1-$cantNodos)"
           exit 1
       fi
   fi

   # Inicializamos todos los nodos
   for ((i=0; i<cantNodos; i++)); do
       distancia[i]=9999
       nodoVistado[i]=0
       predecesor[i]=-1
   done

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
           
           # Prevenir bucles infinitos
           if [[ $nodo_actual -eq -1 ]]; then
               echo "Error: No hay camino válido"
               return 1
           fi
       done
       
       # Agregamos el nodo origen al inicio - CORREGIDO el typo
       camino_completo="$((origen+1)) -> $camino_completo"
       echo "$camino_completo"
   }

   # Variables para almacenar información del camino más corto global
   distancia_minima_global=9999
   origen_camino_corto=-1
   destino_camino_corto=-1

   # Si se especificó un destino, calculamos solo hacia ese nodo
   if [[ "$camino" != "global" ]]; then
       echo "Calculando camino desde estación $((nodoInicial+1)) hacia estación $camino"
       
       # ALGORITMO DE DIJKSTRA
       for ((count=0; count<cantNodos-1; count++)); do
           u=$(buscarDistMinima)
           
           if [[ $u -eq -1 ]]; then
               echo "Error: No se puede continuar el algoritmo"
               exit 1
           fi
           
           nodoVistado[$u]=1
           row=(${matriz[$u]})

           for ((i=0; i<cantNodos; i++)); do
               if [[ ${nodoVistado[i]} -eq 0 && ${row[i]} -ne 0 && $((distancia[u]+row[i])) -lt ${distancia[i]} ]]; then
                   distancia[i]=$((distancia[u]+row[i]))
                   predecesor[i]=$u
               fi
           done
       done

       distancia_minima_global=${distancia[$nodo_destino_especificado]}
       origen_camino_corto=$nodoInicial
       destino_camino_corto=$nodo_destino_especificado
       
   else
       # Modo búsqueda global: encontrar el camino más corto entre todas las estaciones
       echo "Buscando camino más corto entre todas las estaciones..."
       
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
               if [[ $u -eq -1 ]]; then break; fi
               
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
               if [[ $destino -ne $nodo_origen && ${distancia[destino]} -lt $distancia_minima_global && ${distancia[destino]} -ne 9999 ]]; then
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
nombre_archivo=$(basename "$archivo_matriz")
archivo_salida="informe.$nombre_archivo"
directorio_archivo=$(dirname "$archivo_matriz")
ruta_completa_salida="$directorio_archivo/$archivo_salida"

echo "Generando informe en: $ruta_completa_salida"

# Escribimos el encabezado del informe
if ! echo "## Informe de análisis de red de transporte" > "$ruta_completa_salida"; then
   echo "Error: No se pudo crear el archivo de informe '$ruta_completa_salida'"
   exit 1
fi

if [[ "$hub_mode" == "true" ]]; then
   echo "**Hub de la red:** Estación $((estacion_hub+1)) ($max_conexiones conexiones)" >> "$ruta_completa_salida"
fi

if [[ -n "$camino" ]]; then
   # Recalculamos Dijkstra para el camino específico encontrado
   for ((i=0; i<cantNodos; i++)); do
       distancia[i]=9999
       nodoVistado[i]=0
       predecesor[i]=-1
   done
   
   distancia[$origen_camino_corto]=0
   
   for ((count=0; count<cantNodos-1; count++)); do
       u=$(buscarDistMinima)
       if [[ $u -eq -1 ]]; then break; fi
       
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
if [[ -n "$camino" ]]; then
   echo "Distancias más cortas desde el nodo $((nodoInicial+1)):"
   for ((i=0; i<cantNodos; i++)); do
       if [[ ${distancia[i]} -eq 9999 ]]; then
           echo "Hasta nodo $((i+1)): Sin conexión"
       else
           echo "Hasta nodo $((i+1)): ${distancia[i]}"
       fi
   done
fi

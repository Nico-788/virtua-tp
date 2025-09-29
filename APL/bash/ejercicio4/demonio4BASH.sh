#!/bin/bash

#ACA SON TODAS LA FUNCIONES QUE VOY A USAR EN EL SCRIPT, ES COMO EL HEADER DE C

#FUNCION QUE MUESTRA LA AYUDA, SINO SABES QUE HACER, LA USAS
mostrar_ayuda() {
    echo "Uso: $0 -r <repo> -c <config> -l <log> [-a <intervalo>] [-k]"
    echo "  -r, --repo         Ruta del repositorio Git (OBLIGATORIO)"
    echo "  -c, --configuracion Archivo de patrones (OBLIGATORIO)"
    echo "  -l, --log          Archivo de log (OBLIGATORIO)"
    echo "  -k, --kill         Detener demonio"
    echo "  -a, --alerta       Intervalo de alerta en segundos (opcional, por defecto 10s)"
    echo "  -h, --help         Mostrar esta ayuda"
    echo ""
    echo "Ejemplo archivo de configuración (patrones.conf):"
    echo "  password"
    echo "  API_KEY"
    echo "  secret"
    echo "  regex:^.*API_KEY\\s*=\\s*['\"].*['\"].*$"
}

#VARIABLES GLOBALES DE LOS DIRECTORIOS QUE PASAN POR PARAMETRO
REPO=""
CONFIGURACION=""
LOG=""
KILL=false
INTERVALO=10
#Este es el vector de patrones que voy a llenar con leer_patrones
declare -a patrones=()

#FUNCION QUE LEE EL ARCHIVO DE CONFIGURACION Y GUARDA LOS PATRONES EN UN ARRAY
leer_patrones() {
    # Vaciar array por si ya tenía contenido
    patrones=()

    # Verificar que el archivo existe y es legible
    if [ ! -r "$CONFIGURACION" ]; then
        echo "ERROR: No se puede leer el archivo de configuración $CONFIGURACION" >&2
        exit 1
    fi

    # Leer archivo línea por línea
    while IFS= read -r linea || [ -n "$linea" ]; do
        # Saltar líneas vacías o comentarios (opcional)
        [[ -z "$linea" || "$linea" =~ ^# ]] && continue

        # Guardar cada línea en el array
        patrones+=("$linea")
    done < "$CONFIGURACION"

    # Verificar que se cargó al menos un patrón
    if [ ${#patrones[@]} -eq 0 ]; then
        echo "ERROR: No se encontraron patrones válidos en $CONFIGURACION" >&2
        exit 1
    fi
}

#Caso de querer mostrar los parametros a buscar cargados:
#leer_patrones
# Recorremos todos los patrones
#for p in "${patrones[@]}"; do
#    echo "Patrón a buscar: $p"
#done

# Recibe: $1 = patrón encontrado, $2 = archivo
escribir_log() {
    local patron="$1"
    local archivo="$2"
    local fecha
    fecha=$(date '+%Y-%m-%d %H:%M:%S') #aca te tira la fehca y hs actual

    # CORRECCIÓN: Verificar que se puede escribir en el log
    if ! echo "[$fecha] Alerta: patrón '$patron' encontrado en '$archivo'" >> "$LOG" 2>/dev/null; then
        echo "ERROR: No se puede escribir en el archivo de log $LOG" >&2
        return 1
    fi
    #el >> "$LOG" agrega la linea al final del archivo de log, sin hacerte desaparecer lo que pusiste antes. es como una apertura append
}

# CORRECCIÓN: Función mejorada para buscar patrones con soporte para regex
buscar_patrones_en_archivo() {
    local archivo="$1"
    local nombre_archivo=$(basename "$archivo")  # Solo el nombre para el log

    # Verificar que el archivo existe y es legible
    if [ ! -r "$archivo" ]; then
        return 0
    fi

    for p in "${patrones[@]}"; do
        # CORRECCIÓN: Distinguir entre patrones regex y simples
        if [[ "$p" =~ ^regex: ]]; then
            # Es un patrón regex - extraer la parte después de "regex:"
            local patron_regex="${p#regex:}"
            if grep -qE "$patron_regex" "$archivo" 2>/dev/null; then
                escribir_log "$p" "$nombre_archivo"
            fi
        else
            # Es un patrón simple - búsqueda literal
            if grep -qF "$p" "$archivo" 2>/dev/null; then
                escribir_log "$p" "$nombre_archivo"
            fi
        fi
    done
}

#ACA RECIBO LOS PARAMETROS, LOS PARSEO Y LUEGO ASIGNO A LAS VARIABLES GLOBALES
#k no ncecesita valor, es un flag
#OPTIONS=$(getopt -o r:c:l:k:h --long repo:,configuracion,-log,-kill,-help -- "$@")
#OPTIONS=$(getopt -o r:c:l:kh --long repo:,configuracion:,log:,kill,help,daemon-final -- "$@")
# set -- reemplaza los parámetros posicionales $1, $2, etc. con lo que devolvió getopt.
#eval set -- "$OPTIONS"
#while true; do
#    case "$1" in
#        -r| --repo) REPO="$2"; shift 2 ;;
#        -c| --configuracion) CONFIGURACION="$2"; shift 2 ;;
#        -l| --log) LOG="$2"; shift 2;;
#        -k| --kill) KILL=true; shift ;;
#        -h| --help) mostrar_ayuda; exit 0 ;;
#        --daemon-final) shift ;;
#        --) shift; break ;;
#        *) echo "Error: Tiraste cualquier cosa"; exit 1 ;;
#   esac
#done

#ACA VAMOS A VALIDAR QUE LOS PARAMETROS QUE ME PASARON EXISTAN Y SEAN DIRECTORIOS
validar_parametros(){
    # 1. Si es kill, validar diferente
    if [ "$KILL" = true ]; then
        if [ -z "$REPO" ]; then
            echo "ERROR: Para usar -k necesitas especificar -r/--repo"
            exit 1
        fi
        if [ ! -d "$REPO" ]; then
            echo "ERROR: El repositorio $REPO no existe"
            exit 1
        fi
        # CORRECCIÓN: Validar que sea un repositorio Git válido
        if [ ! -d "$REPO/.git" ]; then
            echo "ERROR: $REPO no es un repositorio Git válido"
            exit 1
        fi
        # Para kill no necesitamos validar config ni log
        return 0
    fi

    # CORRECCIÓN: Validación más estricta - todos los parámetros son obligatorios
    if [ -z "$REPO" ]; then
        echo "ERROR: El parámetro -r/--repo es obligatorio"
        mostrar_ayuda
        exit 1
    fi

    if [ -z "$CONFIGURACION" ]; then
        echo "ERROR: El parámetro -c/--configuracion es obligatorio"
        mostrar_ayuda
        exit 1
    fi

    if [ -z "$LOG" ]; then
        echo "ERROR: El parámetro -l/--log es obligatorio"
        mostrar_ayuda
        exit 1
    fi

    #verifico si está vacío o no existe el repositorio
    if [ ! -d "$REPO" ]; then
        echo "ERROR: El directorio $REPO no existe"
        exit 1
    fi

    # CORRECCIÓN: Validar que sea un repositorio Git válido
    if [ ! -d "$REPO/.git" ]; then
        echo "ERROR: $REPO no es un repositorio Git válido (falta directorio .git)"
        exit 1
    fi

    # CORRECCIÓN: Validar que git funciona en el repositorio
    if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
        echo "ERROR: $REPO no es un repositorio Git funcional"
        exit 1
    fi

    #verifico si está vacío o no existe el archivo de configuración
    if [ ! -f "$CONFIGURACION" ]; then
        echo "ERROR: El archivo de configuración $CONFIGURACION no existe"
        exit 1
    fi

    # CORRECCIÓN: Verificar que podemos escribir en el directorio del log
    local log_dir=$(dirname "$LOG")
    if [ ! -d "$log_dir" ]; then
        echo "ERROR: El directorio del archivo de log $log_dir no existe"
        exit 1
    fi

    # Verificar que podemos escribir en el archivo de log
    if ! touch "$LOG" 2>/dev/null; then
        echo "ERROR: No se puede escribir en el archivo de log $LOG"
        exit 1
    fi

    # CORRECCIÓN: Validar intervalo si se especifica
    if ! [[ "$INTERVALO" =~ ^[0-9]+$ ]] || [ "$INTERVALO" -lt 1 ]; then
        echo "ERROR: El intervalo debe ser un número entero mayor a 0"
        exit 1
    fi
}

#Qué hace un demonio real
#Un proceso demonio debe:
#Ejecutarse en segundo plano y liberarse de la terminal que lo lanzó.
#Desasociarse de la sesión y del grupo de control (session leader) para que no reciba señales de la terminal.
#Cerrar los descriptores de entrada/salida (stdin, stdout, stderr) o redirigirlos a archivos/log.
#Opcionalmente cambiar permisos o directorio de trabajo (umask, cd /).
#Evitar duplicados (usando un archivo PID típico).

iniciar_demonio() {
    # Acá generamos el nombre del lockfile que sería donde depositaremos el PID del demonio
    local LOCKFILE="/tmp/audit_daemon_$(basename "$REPO").lock"
    # chequeamos que si ya hay un archivo de diablo, cuidando el mismo repositorio, osea el directorio, no generamos otro
    # PASO 1: Control de duplicados
    if [ -f "$LOCKFILE" ]; then
        local PID=$(cat "$LOCKFILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "ERROR: Demonio ya está corriendo (PID: $PID)"
            exit 1
        fi
        echo "INFO: Limpiando lockfile de proceso muerto"
        rm -f "$LOCKFILE"
    fi

    # PASO 2: Primer fork - crear hijo y morir padre
    if [ "$DAEMON_FORKED" != "1" ]; then #sino es 1, osea no hizo fork entra
        echo "INFO: Iniciando proceso demonio..."
        # EXPORTAR VARIABLES PARA QUE LAS HEREDEN LOS SUBPROCESOS, post fork
        export DAEMON_REPO="$REPO" #Estas export se mantienen en el entorno del sistema
        export DAEMON_CONFIG="$CONFIGURACION"
        export DAEMON_LOG="$LOG"
        export DAEMON_LOCKFILE="$LOCKFILE"
        export DAEMON_INTERVALO="${INTERVALO:-10}"  # ← AGREGADO
        #hacer fork
        DAEMON_FORKED=1 exec "$0" --daemon-final &
        local PID=$! # PID del hijo capturamos
        echo $PID > "$LOCKFILE"
        echo "INFO: Demonio iniciado con PID $PID"
        echo "INFO: Para detener usar: $0 -r $REPO -k"
        exit 0  # Padre muere aquí
    fi

    # PASO 3: Ya somos el hijo - convertirse en demonio completo
    convertir_a_demonio_completo
}

convertir_a_demonio_completo() {
    # PASO 1: Segunda sesión (setsid)
    if [ "$DAEMON_SESSION" != "1" ]; then #si no es 1, osea no hizo setsid entra, si ya desligó el hilo de la terminal no entra
        export DAEMON_SESSION=1
        exec setsid "$0" --daemon-final &
        exit 0  # Primer hijo muere (renuncia liderazgo)
    fi

    # PASO 2: Ya somos el segundo hijo - configurar demonio
    # Restaurar variables desde el entorno
    REPO="$DAEMON_REPO"
    CONFIGURACION="$DAEMON_CONFIG"
    LOG="$DAEMON_LOG"
    INTERVALO="$DAEMON_INTERVALO"
    local LOCKFILE="$DAEMON_LOCKFILE"

    # CORRECCIÓN: Solo cambiar directorio si el actual no es accesible
    if ! pwd >/dev/null 2>&1; then
        cd / || exit 1
    fi

    # umask predecible
    umask 022

    # Guardar PID del demonio real
    echo $$ > "$LOCKFILE"

    # Cerrar file descriptors
    exec 0</dev/null   # stdin desde /dev/null
    exec 1>/dev/null   # stdout a /dev/null
    exec 2>/dev/null   # stderr a /dev/null también

    # Manejo de señales para limpieza
    #TERM es un kill, INT es ctrl-c, QUIT es ctrl+
    #Basicamente si matan al demonio tengo que limpiar el lockfile que guarda su pid
    #esto ocurre porque trap intercepta señales y ejecuta el comando que le pasamos
    #sin necesidad de ejecutar esta función en el bucle principal
    trap "rm -f '$LOCKFILE'; exit 0" TERM INT QUIT

    # PASO 3: Bucle principal del demonio
    ejecutar_bucle_demonio "$LOCKFILE"
}

ejecutar_bucle_demonio() {
    local LOCKFILE="$1" #Recibo el Repo por parámetro
    local ULTIMO_COMMIT_FILE="/tmp/audit_ultimo_commit_$(basename "$REPO")"

    # Cargar patrones en el proceso demonio
    leer_patrones

    # CORRECCIÓN: Obtener commit inicial con mejor manejo de errores
    local ULTIMO_COMMIT
    if ! ULTIMO_COMMIT=$(git -C "$REPO" rev-parse HEAD 2>/dev/null); then
        # Si no hay commits, usar cadena vacía
        ULTIMO_COMMIT=""
    fi
    echo "$ULTIMO_COMMIT" > "$ULTIMO_COMMIT_FILE"

    # Bucle infinito de monitoreo
    while [ -f "$LOCKFILE" ]; do #mientras exista el archivo con el pid cargado sigo
        # CORRECCIÓN: Verificar si hay nuevos commits con mejor manejo de errores
        local COMMIT_ACTUAL
        if ! COMMIT_ACTUAL=$(git -C "$REPO" rev-parse HEAD 2>/dev/null); then
            # Si hay error, esperar y continuar
            sleep "${INTERVALO:-10}"
            continue
        fi

        if [ -n "$COMMIT_ACTUAL" ] && [ "$COMMIT_ACTUAL" != "$ULTIMO_COMMIT" ]; then
            # Hay cambios - obtener archivos modificados
            local archivos
            if [ -z "$ULTIMO_COMMIT" ]; then
                # Primer commit - analizar todos los archivos
                archivos=$(git -C "$REPO" ls-tree -r --name-only HEAD 2>/dev/null)
            else
                # Commits posteriores - solo archivos modificados
                archivos=$(git -C "$REPO" diff --name-only "$ULTIMO_COMMIT" "$COMMIT_ACTUAL" 2>/dev/null)
            fi

            # Procesar cada archivo modificado
            for archivo in $archivos; do
                local archivo_completo="$REPO/$archivo"
                if [ -f "$archivo_completo" ]; then
                    buscar_patrones_en_archivo "$archivo_completo"
                fi
            done

            # Actualizar último commit procesado
            echo "$COMMIT_ACTUAL" > "$ULTIMO_COMMIT_FILE"
            ULTIMO_COMMIT="$COMMIT_ACTUAL"
        fi

        # Esperar antes de la siguiente verificación
        sleep "${INTERVALO:-10}"  # Intervalo configurable, por defecto 10 segundos
    done

    # Limpieza al salir, Esto medio que asegura que si el bucle termina por alguna razon, se limpia el lockfile
    #pero es un cte escribir y borrar archivo
    rm -f "$ULTIMO_COMMIT_FILE"
    rm -f "$LOCKFILE"
}

manejar_parametros_demonio() {
    # Si somos llamados con --daemon-final, es el segundo hijo
    #y debemos convertirnos en demonio completo
    if [ "$1" = "--daemon-final" ]; then
        # Restaurar variables desde variables de entorno
        REPO="$DAEMON_REPO"
        CONFIGURACION="$DAEMON_CONFIG"
        LOG="$DAEMON_LOG"
        INTERVALO="$DAEMON_INTERVALO"

        convertir_a_demonio_completo
        return 0
    fi
    return 1
}

# ... tu código de parseo y validación ...

# Al final del script principal:
main() {
    # PRIMERO: Manejar parámetros especiales ANTES de getopt
    if manejar_parametros_demonio "$@"; then
        exit 0
    fi
    # X si le pifia, mostramos ayuda asi el user se da una idea que poner
    if [ $# -eq 0 ]; then
        mostrar_ayuda
        exit 1
    fi

    # SEGUNDO: Parseo de parámetros solo si NO es --daemon-final
    # CORRECCIÓN: Verificar que getopt está disponible
    if ! command -v getopt >/dev/null 2>&1; then
        echo "ERROR: El comando getopt no está disponible en este sistema"
        exit 1
    fi

    # CORRECCIÓN: Mejor manejo de errores en getopt
    if ! OPTIONS=$(getopt -o r:c:l:a:kh --long repo:,configuracion:,log:,alerta:,kill,help,daemon-final -- "$@" 2>/dev/null); then
        echo "ERROR: Parámetros inválidos"
        mostrar_ayuda
        exit 1
    fi

    eval set -- "$OPTIONS"

    while true; do
        case "$1" in
            -r| --repo) REPO="$2"; shift 2 ;;
            -c| --configuracion) CONFIGURACION="$2"; shift 2 ;;
            -l| --log) LOG="$2"; shift 2;;
            -k| --kill) KILL=true; shift ;;
            -a| --alerta) INTERVALO="$2"; shift 2 ;;
            -h| --help) mostrar_ayuda; exit 0 ;;
            --daemon-final) shift ;;
            --) shift; break ;;
            *) echo "Error: Parámetro desconocido: $1"; mostrar_ayuda; exit 1 ;;
        esac
    done

    # TERCERO: Resto de la lógica
    validar_parametros
    if [ "$KILL" = true ]; then
        detener_demonio
        return 0
    fi
    leer_patrones
    iniciar_demonio "$@"
}

# FUNCIÓN PARA DETENER
detener_demonio() {
    local LOCKFILE="/tmp/audit_daemon_$(basename "$REPO").lock"
    if [ ! -f "$LOCKFILE" ]; then #si el archivo no existe, es porque no hay demonio
        echo "ERROR: No hay demonio corriendo para $REPO"
        exit 1
    fi

    local PID=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -z "$PID" ]; then
        echo "ERROR: No se pudo leer el PID del lockfile"
        rm -f "$LOCKFILE"
        exit 1
    fi

    if kill -0 "$PID" 2>/dev/null; then
        echo "INFO: Deteniendo demonio (PID: $PID)..."
        kill -TERM "$PID" #activa el term de la anterior función del demonio
        sleep 2 #sino lo mató con la básica, forzamos el kill
        if kill -0 "$PID" 2>/dev/null; then
            echo "INFO: Forzando terminación..."
            kill -KILL "$PID"
        fi
        echo "INFO: Demonio detenido (PID: $PID)"
    else
        echo "INFO: Demonio ya no estaba corriendo"
    fi
    rm -f "$LOCKFILE" #limpio el lockfile
}

# Ejecutar función principal
main "$@"


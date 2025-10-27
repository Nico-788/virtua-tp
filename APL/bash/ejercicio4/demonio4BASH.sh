#!/bin/bash

# Script demonio para monitorear credenciales en directorios
# Uso: ./4demonio.sh -r <directorio> -c <config> -l <log> [-a <segundos>] [-k]

set -euo pipefail

# Variables globales
REPO=""
CONFIG=""
LOG=""
ALERTA=10
KILL_MODE=false
DAEMON_MODE=false

# Función de ayuda
show_help() {
    cat << EOF
SINOPSIS
    Script demonio para monitorear un directorio y detectar credenciales o datos sensibles.

USO
    $0 -r <directorio> -c <configuracion> -l <log> [-a <segundos>]
    $0 -r <directorio> -k

PARÁMETROS
    -r, --repo <directorio>          Ruta del directorio a monitorear (OBLIGATORIO)
    -c, --configuracion <archivo>    Ruta del archivo de configuración con patrones (OBLIGATORIO para iniciar)
    -l, --log <archivo>              Ruta del archivo de logs (OBLIGATORIO para iniciar)
    -a, --alerta <segundos>          Intervalo en segundos (opcional, default: 10)
    -k, --kill                       Detener el demonio
    -h, --help                       Mostrar esta ayuda

EJEMPLOS
    # Iniciar demonio
    $0 -r /home/user/myrepo -c ./patrones.conf -l ./audit.log -a 10
    
    # Detener demonio
    $0 -r /home/user/myrepo -k

ARCHIVO DE CONFIGURACIÓN
    El archivo debe contener un patrón por línea:
    - Patrones simples: password, API_KEY, secret
    - Patrones regex: regex:^.*API_KEY\s*=\s*['"].*['"].*$
    - Líneas que comienzan con # son comentarios

EOF
}

# Función para convertir ruta a absoluta
get_absolute_path() {
    local path="$1"
    
    if [[ -z "$path" ]]; then
        echo "$path"
        return
    fi
    
    # Si ya es absoluta
    if [[ "$path" = /* ]]; then
        echo "$path"
        return
    fi
    
    # Convertir relativa a absoluta
    if [[ -e "$path" ]]; then
        realpath "$path" 2>/dev/null || readlink -f "$path" 2>/dev/null || echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    else
        # Si no existe, construir manualmente
        echo "$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")" || echo "$PWD/$path"
    fi
}

# Parsear argumentos
parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -r|--repo)
                REPO="$2"
                shift 2
                ;;
            -c|--configuracion)
                CONFIG="$2"
                shift 2
                ;;
            -l|--log)
                LOG="$2"
                shift 2
                ;;
            -a|--alerta)
                ALERTA="$2"
                shift 2
                ;;
            -k|--kill)
                KILL_MODE=true
                shift
                ;;
            --daemon-mode)
                DAEMON_MODE=true
                shift
                ;;
            *)
                echo "ERROR: Parámetro desconocido: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done
}

# Validar parámetros obligatorios
validate_params() {
    if [[ "$KILL_MODE" == true ]]; then
        if [[ -z "$REPO" ]]; then
            echo "ERROR: -k/--kill requiere -r/--repo" >&2
            exit 1
        fi
        return
    fi
    
    if [[ -z "$REPO" ]]; then
        echo "ERROR: -r/--repo es obligatorio" >&2
        show_help
        exit 1
    fi
    
    if [[ -z "$CONFIG" ]]; then
        echo "ERROR: -c/--configuracion es obligatorio" >&2
        show_help
        exit 1
    fi
    
    if [[ -z "$LOG" ]]; then
        echo "ERROR: -l/--log es obligatorio" >&2
        show_help
        exit 1
    fi
    
    # Validar directorio
    local repo_abs
    repo_abs=$(get_absolute_path "$REPO")
    if [[ ! -d "$repo_abs" ]]; then
        echo "ERROR: El directorio '$repo_abs' no existe" >&2
        exit 1
    fi
    
    # Validar archivo de configuración
    local config_abs
    config_abs=$(get_absolute_path "$CONFIG")
    if [[ ! -f "$config_abs" ]]; then
        echo "ERROR: El archivo de configuración '$config_abs' no existe" >&2
        exit 1
    fi
    
    # Validar/crear archivo de log
    local log_abs
    log_abs=$(get_absolute_path "$LOG")
    local log_dir
    log_dir=$(dirname "$log_abs")
    
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || {
            echo "ERROR: No se puede crear el directorio de logs '$log_dir'" >&2
            exit 1
        }
    fi
    
    if [[ ! -f "$log_abs" ]]; then
        touch "$log_abs" || {
            echo "ERROR: No se puede crear el archivo de log '$log_abs'" >&2
            exit 1
        }
    fi
    
    if [[ ! -w "$log_abs" ]]; then
        echo "ERROR: No se puede escribir en el archivo de log '$log_abs'" >&2
        exit 1
    fi
    
    # Validar que alerta sea un número positivo
    if ! [[ "$ALERTA" =~ ^[0-9]+$ ]] || [[ "$ALERTA" -lt 1 ]]; then
        echo "ERROR: -a/--alerta debe ser un número positivo" >&2
        exit 1
    fi
}

# Generar identificador único para el repositorio
get_repo_id() {
    local repo_path="$1"
    local abs_path
    abs_path=$(get_absolute_path "$repo_path")
    echo -n "$abs_path" | sha256sum | cut -c1-16
}

# Leer patrones del archivo de configuración
read_patterns() {
    local config_abs
    config_abs=$(get_absolute_path "$CONFIG")
    
    declare -g -a PATTERNS=()
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Eliminar espacios en blanco al inicio y final
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        
        # Ignorar líneas vacías y comentarios
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi
        
        PATTERNS+=("$line")
    done < "$config_abs"
    
    if [[ ${#PATTERNS[@]} -eq 0 ]]; then
        echo "ERROR: No hay patrones válidos en el archivo de configuración" >&2
        exit 1
    fi
}

# Escribir alerta en el log
write_alert() {
    local pattern="$1"
    local file="$2"
    local log_abs
    log_abs=$(get_absolute_path "$LOG")
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] Alerta: patrón '$pattern' encontrado en el archivo '$file'." >> "$log_abs"
}

# Buscar patrones en un archivo
search_patterns_in_file() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        return
    fi
    
    local filename
    filename=$(basename "$file_path")
    
    # Leer contenido del archivo
    local content
    if ! content=$(cat "$file_path" 2>/dev/null); then
        return
    fi
    
    for pattern in "${PATTERNS[@]}"; do
        local found=false
        
        if [[ "$pattern" =~ ^regex: ]]; then
            # Patrón regex
            local regex_pattern="${pattern#regex:}"
            if echo "$content" | grep -qE "$regex_pattern" 2>/dev/null; then
                found=true
            fi
        else
            # Patrón simple (case-insensitive)
            if echo "$content" | grep -qiF "$pattern" 2>/dev/null; then
                found=true
            fi
        fi
        
        if [[ "$found" == true ]]; then
            write_alert "$pattern" "$filename"
        fi
    done
}

# Obtener snapshot del directorio (archivo -> timestamp)
get_directory_snapshot() {
    local dir="$1"
    declare -A snapshot
    
    while IFS= read -r -d '' file; do
        local timestamp
        timestamp=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0")
        snapshot["$file"]="$timestamp"
    done < <(find "$dir" -type f -print0 2>/dev/null)
    
    # Exportar el snapshot como variables
    for file in "${!snapshot[@]}"; do
        echo "$file|${snapshot[$file]}"
    done
}

# Comparar snapshots y retornar archivos modificados
compare_snapshots() {
    local old_snap="$1"
    local new_snap="$2"
    
    declare -A old_files
    declare -A new_files
    
    # Leer snapshot antiguo
    while IFS='|' read -r file timestamp; do
        if [[ -n "$file" ]]; then
            old_files["$file"]="$timestamp"
        fi
    done <<< "$old_snap"
    
    # Leer snapshot nuevo
    while IFS='|' read -r file timestamp; do
        if [[ -n "$file" ]]; then
            new_files["$file"]="$timestamp"
        fi
    done <<< "$new_snap"
    
    # Detectar archivos nuevos o modificados
    for file in "${!new_files[@]}"; do
        if [[ ! -v old_files["$file"] ]]; then
            # Archivo nuevo
            echo "$file"
        elif [[ "${new_files[$file]}" != "${old_files[$file]}" ]]; then
            # Archivo modificado
            echo "$file"
        fi
    done
}

# Iniciar demonio
start_daemon() {
    local repo_id
    repo_id=$(get_repo_id "$REPO")
    local lock_file="/tmp/audit_daemon_${repo_id}.lock"
    
    # Verificar si ya existe un demonio corriendo
    if [[ -f "$lock_file" ]]; then
        local pid
        pid=$(cat "$lock_file" 2>/dev/null || echo "")
        
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "ERROR: Demonio ya corriendo (PID: $pid)" >&2
            exit 1
        else
            # Lock file obsoleto, eliminarlo
            rm -f "$lock_file"
        fi
    fi
    
    # Convertir rutas a absolutas
    local repo_abs config_abs log_abs
    repo_abs=$(get_absolute_path "$REPO")
    config_abs=$(get_absolute_path "$CONFIG")
    log_abs=$(get_absolute_path "$LOG")
    
    # Iniciar demonio en segundo plano
    nohup "$0" --daemon-mode -r "$repo_abs" -c "$config_abs" -l "$log_abs" -a "$ALERTA" \
        > /dev/null 2>&1 &
    
    local daemon_pid=$!
    
    # Esperar un poco para verificar que se inició correctamente
    sleep 1
    
    if ! kill -0 "$daemon_pid" 2>/dev/null; then
        echo "ERROR: No se pudo iniciar el demonio" >&2
        exit 1
    fi
    
    echo "INFO: Demonio iniciado (PID: $daemon_pid)"
    echo "INFO: Monitoreando directorio: $repo_abs"
    echo "INFO: Para detener: $0 -r \"$REPO\" -k"
}

# Bucle principal del demonio
daemon_loop() {
    local repo_id
    repo_id=$(get_repo_id "$REPO")
    local lock_file="/tmp/audit_daemon_${repo_id}.lock"
    
    # Crear lock file con nuestro PID
    echo $$ > "$lock_file"
    
    # Asegurar limpieza al terminar
    trap "rm -f '$lock_file'; exit" EXIT INT TERM
    
    # Leer patrones
    read_patterns
    
    local repo_abs
    repo_abs=$(get_absolute_path "$REPO")
    
    # Tomar snapshot inicial
    local old_snapshot
    old_snapshot=$(get_directory_snapshot "$repo_abs")
    
    # Bucle infinito de monitoreo
    while [[ -f "$lock_file" ]]; do
        sleep "$ALERTA"
        
        # Tomar nuevo snapshot
        local new_snapshot
        new_snapshot=$(get_directory_snapshot "$repo_abs")
        
        # Comparar snapshots
        local modified_files
        modified_files=$(compare_snapshots "$old_snapshot" "$new_snapshot")
        
        # Analizar archivos modificados
        if [[ -n "$modified_files" ]]; then
            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    search_patterns_in_file "$file"
                fi
            done <<< "$modified_files"
        fi
        
        # Actualizar snapshot
        old_snapshot="$new_snapshot"
    done
}

# Detener demonio
stop_daemon() {
    local repo_id
    repo_id=$(get_repo_id "$REPO")
    local lock_file="/tmp/audit_daemon_${repo_id}.lock"
    
    if [[ ! -f "$lock_file" ]]; then
        echo "ERROR: No hay demonio corriendo para este directorio" >&2
        exit 1
    fi
    
    local pid
    pid=$(cat "$lock_file" 2>/dev/null || echo "")
    
    if [[ -z "$pid" ]]; then
        echo "ERROR: No se pudo leer el PID del demonio" >&2
        rm -f "$lock_file"
        exit 1
    fi
    
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
        echo "INFO: Demonio detenido (PID: $pid)"
    else
        echo "INFO: Proceso ya no estaba corriendo"
    fi
    
    rm -f "$lock_file"
}

# Main
main() {
    parse_args "$@"
    
    if [[ "$DAEMON_MODE" == true ]]; then
        daemon_loop
    else
        validate_params
        if [[ "$KILL_MODE" == true ]]; then
            stop_daemon
        else
            read_patterns  # Validar patrones antes de iniciar
            start_daemon
        fi
    fi
}

main "$@"

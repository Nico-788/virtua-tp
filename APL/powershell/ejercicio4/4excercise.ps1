# 4exercise.ps1 - Demonio para monitorear credenciales en Git
# ACA SON TODAS LAS FUNCIONES QUE VOY A USAR EN EL SCRIPT, ES COMO EL HEADER DE C

# FUNCION QUE MUESTRA LA AYUDA, SINO SABES QUE HACER, LA USAS
function Mostrar-Ayuda {
    Write-Host "Uso: .\4exercise.ps1 -Repo <repo> -Config <config> [-Log <log>] [-Kill]"
    Write-Host "  -Repo          Ruta del repositorio Git"
    Write-Host "  -Config        Archivo de patrones"
    Write-Host "  -Log           Archivo de log (opcional)"
    Write-Host "  -Kill          Detener demonio"
    Write-Host "  -Alerta        Intervalo de alerta en segundos (opcional, por defecto 10s)"
    Write-Host "  -Help          Mostrar esta ayuda"
}

# VARIABLES GLOBALES DE LOS DIRECTORIOS QUE PASAN POR PARAMETRO
$script:REPO = ""
$script:CONFIGURACION = ""
$script:LOG = ""
$script:KILL = $false
$script:INTERVALO = 10
# Este es el array de patrones que voy a llenar con Leer-Patrones
$script:patrones = @()

# FUNCION QUE LEE EL ARCHIVO DE CONFIGURACION Y GUARDA LOS PATRONES EN UN ARRAY
function Leer-Patrones {
    # Vaciar array por si ya tenía contenido
    $script:patrones = @()

    # Leer archivo línea por línea
    if (Test-Path $script:CONFIGURACION) {
        $lineas = Get-Content $script:CONFIGURACION
        foreach ($linea in $lineas) {
            # Saltar líneas vacías o comentarios (opcional)
            if ($linea -and !$linea.StartsWith("#")) {
                # Guardar cada línea en el array
                $script:patrones += $linea
            }
        }
    }
}

# Caso de querer mostrar los parametros a buscar cargados:
# Leer-Patrones
# foreach ($p in $script:patrones) {
#     Write-Host "Patrón a buscar: $p"
# }

# Recibe: patron encontrado, archivo
function Escribir-Log {
    param(
        [string]$patron,
        [string]$archivo
    )
    
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss" # aca te tira la fecha y hs actual
    $mensaje = "[$fecha] Alerta: patrón '$patron' encontrado en '$archivo'"
    
    # el Add-Content agrega la linea al final del archivo de log, sin hacerte desaparecer lo que pusiste antes. es como una apertura append
    Add-Content -Path $script:LOG -Value $mensaje
}

# Recibe: archivo a escanear
function Buscar-PatronesEnArchivo {
    param([string]$archivo)
    
    $nombre_archivo = Split-Path $archivo -Leaf  # Solo el nombre para el log
    
    foreach ($p in $script:patrones) {
        # PowerShell tiene Select-String que es como grep
        if (Select-String -Path $archivo -Pattern $p -Quiet) {
            Escribir-Log -patron $p -archivo $nombre_archivo  # Usar nombre corto
        }
    }
}

# ACA VAMOS A VALIDAR QUE LOS PARAMETROS QUE ME PASARON EXISTAN Y SEAN DIRECTORIOS
function Validar-Parametros {
    # 1. Si es kill, validar diferente
    if ($script:KILL) {
        if (-not $script:REPO) {
            Write-Error "ERROR: Para usar -Kill necesitas especificar -Repo"
            exit 1
        }
        if (-not (Test-Path $script:REPO -PathType Container)) {
            Write-Error "ERROR: El repositorio $script:REPO no existe"
            exit 1
        }
        # Para kill no necesitamos validar config ni log
        return
    }
    
    # verifico si está vacío o no existe el repositorio
    if (-not $script:REPO -or -not (Test-Path $script:REPO -PathType Container) -or -not (Test-Path "$script:REPO\.git" -PathType Container)) {
        Write-Error "ERROR, falta el parametro -Repo, el string que me diste tiene longitud 0"
        exit 1
    }
    
    # verifico si está vacío o no existe el archivo de log
    # 4. Validar LOG (opcional, si no se especifica usar por defecto)
    if (-not $script:LOG) {
        $script:LOG = Join-Path $script:REPO "audit.log"
        Write-Host "INFO: Usando archivo de log por defecto: $script:LOG"
    }
    
    # Verificar que podemos escribir en el archivo de log
    try {
        New-Item -Path $script:LOG -ItemType File -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "ERROR: No se puede escribir en el archivo de log $script:LOG"
        exit 1
    }
    
    if (-not $script:CONFIGURACION -or -not (Test-Path $script:CONFIGURACION -PathType Leaf)) {
        Write-Error "ERROR, el parametro -Config o --configuracion no lo pusiste"
        exit 1
    }
}

# Qué hace un demonio real en PowerShell
# Un proceso demonio debe:
# Ejecutarse en segundo plano y liberarse de la terminal que lo lanzó.
# Desasociarse de la sesión y del grupo de control para que no reciba señales de la terminal.
# Opcionalmente cambiar permisos o directorio de trabajo.
# Evitar duplicados (usando un archivo PID típico).

function Iniciar-Demonio {
    # Acá generamos el nombre del lockfile que sería donde depositaremos el PID del demonio
    $repoName = Split-Path $script:REPO -Leaf
    $LOCKFILE = "$env:TEMP\audit_daemon_$repoName.lock"
    
    # chequeamos que si ya hay un archivo de diablo, cuidando el mismo repositorio, osea el directorio, no generamos otro
    # PASO 1: Control de duplicados
    if (Test-Path $LOCKFILE) {
        try {
            $PID = Get-Content $LOCKFILE -ErrorAction Stop
            $proceso = Get-Process -Id $PID -ErrorAction Stop
            Write-Error "ERROR: Demonio ya está corriendo (PID: $PID)"
            exit 1
        }
        catch {
            Write-Host "INFO: Limpiando lockfile de proceso muerto"
            Remove-Item $LOCKFILE -Force -ErrorAction SilentlyContinue
        }
    }
    
    # PASO 2: En PowerShell usamos Jobs para crear procesos en background
    # En lugar del doble fork de Unix, PowerShell maneja esto diferente
    Write-Host "INFO: Iniciando proceso demonio..."
    
    # PowerShell usa Start-Process para crear procesos independientes
    $argumentos = @(
        "-NoProfile"
        "-WindowStyle", "Hidden"
        "-ExecutionPolicy", "Bypass"
        "-File", $PSCommandPath
        "-Repo", "`"$script:REPO`""
        "-Config", "`"$script:CONFIGURACION`""
        "-Log", "`"$script:LOG`""
        "-Alerta", "$script:INTERVALO"
        "-DaemonMode"  # Flag especial para modo demonio
    )
    
    $proceso = Start-Process -FilePath "powershell.exe" -ArgumentList $argumentos -PassThru -WindowStyle Hidden
    $PID = $proceso.Id
    
    # Guardar PID en lockfile
    Set-Content -Path $LOCKFILE -Value $PID
    Write-Host "INFO: Demonio iniciado con PID $PID"
    Write-Host "INFO: Para detener usar: .\4exercise.ps1 -Repo $script:REPO -Kill"
}

function Convertir-ADemonioCompleto {
    # En PowerShell, el proceso ya está separado de la consola
    # Solo necesitamos configurar el entorno
    
    $repoName = Split-Path $script:REPO -Leaf
    $LOCKFILE = "$env:TEMP\audit_daemon_$repoName.lock"
    
    # Cambiar directorio de trabajo (PowerShell maneja esto mejor)
    try {
        Set-Location $env:SystemRoot  # Equivalente a cd /
    }
    catch {
        Write-Error "ERROR: No se puede cambiar a directorio del sistema"
        exit 1
    }
    
    # En PowerShell no necesitamos cerrar descriptores, pero podemos redirigir
    # La salida ya está manejada por el WindowStyle Hidden
    
    # Guardar PID del demonio real
    $PID = $PID = [System.Diagnostics.Process]::GetCurrentProcess().Id
    Set-Content -Path $LOCKFILE -Value $PID
    
    # Manejo de señales para limpieza en PowerShell
    # PowerShell usa eventos del sistema en lugar de trap
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        $lockPath = "$env:TEMP\audit_daemon_*.lock"
        Get-ChildItem $lockPath -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    
    # PASO 3: Bucle principal del demonio
    Ejecutar-BucleDemonio -LOCKFILE $LOCKFILE
}

function Ejecutar-BucleDemonio {
    param([string]$LOCKFILE)
    
    $repoName = Split-Path $script:REPO -Leaf
    $ULTIMO_COMMIT_FILE = "$env:TEMP\audit_ultimo_commit_$repoName.txt"
    
    # Cargar patrones en el proceso demonio
    Leer-Patrones
    
    # Obtener commit inicial
    try {
        Push-Location $script:REPO
        $ULTIMO_COMMIT = (git rev-parse HEAD 2>$null)
        if (-not $ULTIMO_COMMIT) { $ULTIMO_COMMIT = "" }
    }
    catch {
        $ULTIMO_COMMIT = ""
    }
    finally {
        Pop-Location
    }
    
    Set-Content -Path $ULTIMO_COMMIT_FILE -Value $ULTIMO_COMMIT
    
    # Bucle infinito de monitoreo
    while (Test-Path $LOCKFILE) { # mientras exista el archivo con el pid cargado sigo
        try {
            # Verificar si hay nuevos commits
            Push-Location $script:REPO
            $COMMIT_ACTUAL = (git rev-parse HEAD 2>$null)
            if (-not $COMMIT_ACTUAL) { $COMMIT_ACTUAL = "" }
            
            if ($COMMIT_ACTUAL -and ($COMMIT_ACTUAL -ne $ULTIMO_COMMIT)) {
                # Hay cambios - obtener archivos modificados
                $archivos = (git diff --name-only $ULTIMO_COMMIT $COMMIT_ACTUAL 2>$null)
                
                # Procesar cada archivo modificado
                foreach ($archivo in $archivos) {
                    if ($archivo) {  # verificar que no esté vacío
                        $archivo_completo = Join-Path $script:REPO $archivo
                        if (Test-Path $archivo_completo -PathType Leaf) {
                            Buscar-PatronesEnArchivo -archivo $archivo_completo
                        }
                    }
                }
                
                # Actualizar último commit procesado
                Set-Content -Path $ULTIMO_COMMIT_FILE -Value $COMMIT_ACTUAL
                $ULTIMO_COMMIT = $COMMIT_ACTUAL
            }
        }
        catch {
            # Si hay error con git, continuar (similar al 2>/dev/null de bash)
        }
        finally {
            Pop-Location
        }
        
        # Esperar antes de la siguiente verificación
        Start-Sleep -Seconds $script:INTERVALO  # Intervalo configurable, por defecto 10 segundos
    }
    
    # Limpieza al salir, Esto medio que asegura que si el bucle termina por alguna razón, se limpia el lockfile
    # pero es un cte escribir y borrar archivo
    Remove-Item $ULTIMO_COMMIT_FILE -Force -ErrorAction SilentlyContinue
    Remove-Item $LOCKFILE -Force -ErrorAction SilentlyContinue
}

# FUNCIÓN PARA DETENER
function Detener-Demonio {
    $repoName = Split-Path $script:REPO -Leaf
    $LOCKFILE = "$env:TEMP\audit_daemon_$repoName.lock"
    
    if (-not (Test-Path $LOCKFILE)) { # si el archivo no existe, es porque no hay demonio
        Write-Error "ERROR: No hay demonio corriendo para $script:REPO"
        exit 1
    }
    
    try {
        $PID = Get-Content $LOCKFILE -ErrorAction Stop
        $proceso = Get-Process -Id $PID -ErrorAction Stop
        
        # activa el term de la anterior función del demonio
        $proceso.CloseMainWindow()  # Intento elegante
        Start-Sleep -Seconds 2
        
        # sino lo mató con la básica, forzamos el kill
        if (-not $proceso.HasExited) {
            $proceso.Kill()  # Fuerza bruta
        }
        Write-Host "INFO: Demonio detenido (PID: $PID)"
    }
    catch {
        Write-Host "INFO: Demonio ya no estaba corriendo"
    }
    
    # limpio el lockfile
    Remove-Item $LOCKFILE -Force -ErrorAction SilentlyContinue
}

# Función principal - maneja todos los parámetros y lógica
function Main {
    param(
        [string]$Repo,
        [string]$Config,
        [string]$Log,
        [int]$Alerta = 10,
        [switch]$Kill,
        [switch]$Help,
        [switch]$DaemonMode  # Parámetro especial para modo demonio
    )
    
    # PRIMERO: Si es modo demonio, ir directo al bucle
    if ($DaemonMode) {
        $script:REPO = $Repo
        $script:CONFIGURACION = $Config
        $script:LOG = $Log
        $script:INTERVALO = $Alerta
        
        Convertir-ADemonioCompleto
        return
    }
    
    # Si le pifia, mostramos ayuda así el user se da una idea que poner
    if ($Help -or (-not $Repo -and -not $Kill)) {
        Mostrar-Ayuda
        return
    }
    
    # Asignar variables globales
    $script:REPO = $Repo
    $script:CONFIGURACION = $Config
    $script:LOG = $Log
    $script:KILL = $Kill
    $script:INTERVALO = $Alerta
    
    # TERCERO: Resto de la lógica
    Validar-Parametros
    
    if ($script:KILL) {
        Detener-Demonio
        return
    }
    
    Leer-Patrones
    Iniciar-Demonio
}

# Ejecutar función principal solo si no estamos siendo importados
if ($MyInvocation.InvocationName -ne '.') {
    # Parsear parámetros de línea de comandos
    $params = @{}
    
    for ($i = 0; $i -lt $args.Count; $i++) {
        switch ($args[$i]) {
            {$_ -in @('-Repo', '-r')} { 
                $params['Repo'] = $args[++$i] 
            }
            {$_ -in @('-Config', '-c')} { 
                $params['Config'] = $args[++$i] 
            }
            {$_ -in @('-Log', '-l')} { 
                $params['Log'] = $args[++$i] 
            }
            {$_ -in @('-Alerta', '-a')} { 
                $params['Alerta'] = [int]$args[++$i] 
            }
            {$_ -in @('-Kill', '-k')} { 
                $params['Kill'] = $true 
            }
            {$_ -in @('-Help', '-h')} { 
                $params['Help'] = $true 
            }
            '-DaemonMode' { 
                $params['DaemonMode'] = $true 
            }
        }
    }
    
    Main @params
}

# COMANDOS DE PRUEBA (comentados):
# 1. Verificar que el proceso está corriendo
# Get-Process | Where-Object {$_.ProcessName -like "*powershell*" -and $_.CommandLine -like "*4exercise*"}

# 2. Hacer un commit para probar el monitoreo
# Set-Location ~/repositorioGit
# Add-Content test_config.js 'const new_password = "secret123"'
# git add test_config.js
# git commit -m "Added password for testing"

# 3. Esperar unos segundos y verificar el log
# Start-Sleep 15
# Get-Content ~/repositorioGit/audit.log

# 4. Probar detener el demonio
# Set-Location ~
# .\4exercise.ps1 -Repo ~/repositorioGit -Kill

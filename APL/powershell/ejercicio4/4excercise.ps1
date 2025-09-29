<#
.SYNOPSIS
Demonio para monitorear credenciales en repositorios Git

.DESCRIPTION
Script demonio para monitorear un repositorio Git y detectar credenciales o datos sensibles.
El demonio lee un archivo de configuración con patrones a buscar y monitorea cambios en el repositorio.

.PARAMETER Repo
Ruta del repositorio Git a monitorear (OBLIGATORIO)

.PARAMETER Configuracion
Ruta del archivo de configuración que contiene la lista de patrones a buscar (OBLIGATORIO)

.PARAMETER Log
Ruta del archivo de logs que contiene la lista de eventos identificados (OBLIGATORIO)

.PARAMETER Alerta
Intervalo de alerta en segundos (opcional, por defecto 10s)

.PARAMETER Kill
Flag para detener el demonio. Solo se usa junto con -Repo

.EXAMPLE
.\4demonio.ps1 -Repo "C:\MyRepo" -Configuracion ".\patrones.conf" -Log ".\audit.log"

.EXAMPLE
.\4demonio.ps1 -Repo "C:\MyRepo" -Kill

.NOTES
Archivo de configuración debe contener patrones línea por línea:
password
API_KEY
regex:^.*API_KEY\s*=\s*['"].*['"].*$
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_ -PathType Container)) {
            throw "El directorio '$_' no existe"
        }
        if ($_ -and -not (Test-Path "$_\.git" -PathType Container)) {
            throw "'$_' no es un repositorio Git válido"
        }
        return $true
    })]
    [string]$Repo,
    
    [Parameter(Mandatory=$false)]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_ -PathType Leaf)) {
            throw "El archivo de configuración '$_' no existe"
        }
        return $true
    })]
    [string]$Configuracion,
    
    [Parameter(Mandatory=$false)]
    [string]$Log,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Alerta = 10,
    
    [Parameter(Mandatory=$false)]
    [switch]$Kill,
    
    [Parameter(Mandatory=$false, DontShow)]
    [switch]$DaemonMode
)

# Variables globales del script
$script:patrones = @()
$script:LogPath = $Log

# Función para validar parámetros obligatorios
function Test-ParametrosObligatorios {
    if ($Kill) {
        if (-not $Repo) {
            Write-Error "ERROR: Para usar -Kill necesitas especificar -Repo"
            exit 1
        }
        return
    }
    
    if (-not $Repo) {
        Write-Error "ERROR: El parámetro -Repo es obligatorio"
        Get-Help $PSCommandPath -Detailed
        exit 1
    }
    
    if (-not $Configuracion) {
        Write-Error "ERROR: El parámetro -Configuracion es obligatorio"
        Get-Help $PSCommandPath -Detailed
        exit 1
    }
    
    if (-not $Log) {
        Write-Error "ERROR: El parámetro -Log es obligatorio"
        Get-Help $PSCommandPath -Detailed
        exit 1
    }
    
    # Verificar que podemos escribir en el archivo de log
    try {
        $logDir = Split-Path $Log -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        # Crear archivo de log si no existe
        if (-not (Test-Path $Log)) {
            New-Item -Path $Log -ItemType File -Force | Out-Null
        }
        
        # Probar escritura
        $testWrite = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] INFO: Inicializando log..."
        Add-Content -Path $Log -Value $testWrite -ErrorAction Stop
    }
    catch {
        Write-Error "ERROR: No se puede escribir en el archivo de log '$Log': $_"
        exit 1
    }
}

# Función que lee el archivo de configuración y guarda los patrones en un array
function Read-Patrones {
    $script:patrones = @()
    
    try {
        $lineas = Get-Content $Configuracion -ErrorAction Stop
        foreach ($linea in $lineas) {
            $lineaTrim = $linea.Trim()
            # Saltar líneas vacías o comentarios
            if ($lineaTrim -and !$lineaTrim.StartsWith("#")) {
                $script:patrones += $lineaTrim
            }
        }
        
        if ($script:patrones.Count -eq 0) {
            Write-Error "ERROR: No se encontraron patrones válidos en '$Configuracion'"
            exit 1
        }
    }
    catch {
        Write-Error "ERROR: No se puede leer el archivo de configuración '$Configuracion': $_"
        exit 1
    }
}

# Función para escribir en el log de forma thread-safe
function Write-AlertaLog {
    param(
        [string]$Patron,
        [string]$Archivo
    )
    
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $mensaje = "[$fecha] Alerta: patrón '$Patron' encontrado en '$Archivo'"
    
    try {
        # Lock para evitar problemas de escritura concurrente
        $mutex = New-Object System.Threading.Mutex($false, "AuditLogMutex")
        [void]$mutex.WaitOne()
        try {
            Add-Content -Path $script:LogPath -Value $mensaje -ErrorAction Stop
        }
        finally {
            $mutex.ReleaseMutex()
            $mutex.Dispose()
        }
    }
    catch {
        Write-Error "ERROR: No se puede escribir en el archivo de log: $_"
    }
}

# Función para escribir logs informativos
function Write-InfoLog {
    param([string]$Mensaje)
    
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $mensajeCompleto = "[$fecha] INFO: $Mensaje"
    
    try {
        Add-Content -Path $script:LogPath -Value $mensajeCompleto -ErrorAction Stop
    }
    catch {
        # Silenciar errores de log informativo
    }
}

# Función mejorada para buscar patrones con soporte para regex
function Search-PatronesEnArchivo {
    param([string]$ArchivoPath)
    
    if (-not (Test-Path $ArchivoPath -PathType Leaf)) {
        return
    }
    
    $nombreArchivo = Split-Path $ArchivoPath -Leaf
    
    try {
        # Leer contenido completo del archivo
        $contenido = Get-Content $ArchivoPath -Raw -ErrorAction Stop
        
        if (-not $contenido) {
            return
        }
        
        foreach ($patron in $script:patrones) {
            $encontrado = $false
            
            # Distinguir entre patrones regex y simples
            if ($patron.StartsWith("regex:")) {
                # Es un patrón regex - extraer la parte después de "regex:"
                $patronRegex = $patron.Substring(6)
                try {
                    if ($contenido -match $patronRegex) {
                        $encontrado = $true
                    }
                }
                catch {
                    Write-InfoLog "Advertencia: Regex inválido '$patronRegex'"
                }
            }
            else {
                # Es un patrón simple - búsqueda literal (case insensitive)
                $patronEscapado = [regex]::Escape($patron)
                if ($contenido -match "(?i)$patronEscapado") {
                    $encontrado = $true
                }
            }
            
            if ($encontrado) {
                Write-AlertaLog -Patron $patron -Archivo $nombreArchivo
            }
        }
    }
    catch {
        Write-InfoLog "Advertencia: No se pudo leer '$nombreArchivo': $_"
    }
}

# Función para obtener el nombre único del repositorio
function Get-RepoIdentifier {
    param([string]$RepoPath)
    
    # Convertir a ruta absoluta y normalizar
    $absolutePath = (Resolve-Path $RepoPath -ErrorAction SilentlyContinue).Path
    if (-not $absolutePath) {
        $absolutePath = $RepoPath
    }
    
    # Crear hash único basado en la ruta
    $hash = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($absolutePath.ToLower())
    $hashBytes = $hash.ComputeHash($bytes)
    $hashString = [System.BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 16)
    
    return $hashString
}

# Función para iniciar el demonio
function Start-Demonio {
    $repoId = Get-RepoIdentifier -RepoPath $Repo
    $lockFile = Join-Path $env:TEMP "audit_daemon_$repoId.lock"
    
    # Control de duplicados
    if (Test-Path $lockFile) {
        try {
            $pidData = Get-Content $lockFile -ErrorAction Stop | ConvertFrom-Json
            $proceso = Get-Process -Id $pidData.PID -ErrorAction Stop
            
            Write-Error "ERROR: Demonio ya está corriendo para este repositorio (PID: $($pidData.PID))"
            Write-Host "Para detenerlo use: .\4demonio.ps1 -Repo `"$Repo`" -Kill"
            exit 1
        }
        catch {
            Write-Host "INFO: Limpiando lockfile de proceso anterior..."
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Host "INFO: Iniciando proceso demonio..."
    
    # Convertir rutas a absolutas para el demonio
    $RepoAbsoluto = (Resolve-Path $Repo).Path
    $ConfigAbsoluto = (Resolve-Path $Configuracion).Path
    $LogAbsoluto = if (Test-Path $Log) { 
        (Resolve-Path $Log).Path 
    } else { 
        Join-Path (Get-Location).Path $Log
    }
    
    # Crear proceso demonio en segundo plano
    $scriptPath = $PSCommandPath
    $argumentos = @(
        "-NoProfile"
        "-WindowStyle", "Hidden"
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$scriptPath`""
        "-Repo", "`"$RepoAbsoluto`""
        "-Configuracion", "`"$ConfigAbsoluto`""
        "-Log", "`"$LogAbsoluto`""
        "-Alerta", $Alerta
        "-DaemonMode"
    )
    
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = "powershell.exe"
        $startInfo.Arguments = $argumentos -join " "
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $false
        $startInfo.RedirectStandardError = $false
        
        $proceso = [System.Diagnostics.Process]::Start($startInfo)
        $IdDelProceso = $proceso.Id
        
        # Guardar información del proceso en lockfile
        $lockData = @{
            PID = $IdDelProceso
            Repo = $RepoAbsoluto
            Started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
        $lockData | ConvertTo-Json | Set-Content -Path $lockFile
        
        Write-Host "INFO: Demonio iniciado con PID $IdDelProceso"
        Write-Host "INFO: Monitoreando: $RepoAbsoluto"
        Write-Host "INFO: Log de alertas: $LogAbsoluto"
        Write-Host "INFO: Intervalo de verificación: $Alerta segundos"
        Write-Host "INFO: Para detener usar: .\4demonio.ps1 -Repo `"$Repo`" -Kill"
    }
    catch {
        Write-Error "ERROR: No se pudo iniciar el proceso demonio: $_"
        exit 1
    }
}

# Función del bucle principal del demonio
function Start-BucleDemonio {
    $repoId = Get-RepoIdentifier -RepoPath $Repo
    $lockFile = Join-Path $env:TEMP "audit_daemon_$repoId.lock"
    $ultimoCommitFile = Join-Path $env:TEMP "audit_ultimo_commit_$repoId.txt"
    
    # Actualizar PID en lockfile
    $IdDelProcesoActual = [System.Diagnostics.Process]::GetCurrentProcess().Id
    try {
        $lockData = @{
            PID = $IdDelProcesoActual
            Repo = $Repo
            Started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
        $lockData | ConvertTo-Json | Set-Content -Path $lockFile
    }
    catch {
        Write-InfoLog "ERROR: No se pudo actualizar lockfile"
        exit 1
    }
    
    # Cargar patrones
    Read-Patrones
    Write-InfoLog "Demonio iniciado - Monitoreando repositorio: $Repo"
    Write-InfoLog "Patrones cargados: $($script:patrones.Count)"
    
    # Obtener commit inicial
    $ultimoCommit = ""
    try {
        Push-Location $Repo -ErrorAction Stop
        $ultimoCommit = (git rev-parse HEAD 2>$null)
        if (-not $ultimoCommit) { 
            $ultimoCommit = "EMPTY"
        }
        Write-InfoLog "Commit inicial: $ultimoCommit"
    }
    catch {
        Write-InfoLog "ERROR: No se pudo acceder al repositorio Git"
        $ultimoCommit = "EMPTY"
    }
    finally {
        Pop-Location
    }
    
    Set-Content -Path $ultimoCommitFile -Value $ultimoCommit
    
    # Bucle infinito de monitoreo
    $iteracion = 0
    while (Test-Path $lockFile) {
        $iteracion++
        
        try {
            Push-Location $Repo -ErrorAction Stop
            
            # Obtener commit actual
            $commitActual = (git rev-parse HEAD 2>$null)
            if (-not $commitActual) { 
                $commitActual = "EMPTY"
            }
            
            # Verificar si hay cambios
            if ($commitActual -ne "EMPTY" -and $commitActual -ne $ultimoCommit) {
                Write-InfoLog "Nuevo commit detectado: $commitActual"
                
                # Obtener archivos modificados
                $archivos = @()
                if ($ultimoCommit -ne "EMPTY") {
                    # Hay commit anterior - obtener diff
                    $diffOutput = (git diff --name-only $ultimoCommit $commitActual 2>$null)
                    if ($diffOutput) {
                        $archivos = $diffOutput -split "`n" | Where-Object { $_.Trim() }
                    }
                }
                else {
                    # Primer commit - analizar todos los archivos
                    $lsOutput = (git ls-tree -r --name-only HEAD 2>$null)
                    if ($lsOutput) {
                        $archivos = $lsOutput -split "`n" | Where-Object { $_.Trim() }
                    }
                }
                
                Write-InfoLog "Archivos a analizar: $($archivos.Count)"
                
                # Procesar cada archivo modificado
                $patronesEncontrados = 0
                foreach ($archivo in $archivos) {
                    if ($archivo) {
                        $archivoCompleto = Join-Path $Repo $archivo
                        if (Test-Path $archivoCompleto -PathType Leaf) {
                            $logSizeBefore = (Get-Item $script:LogPath).Length
                            Search-PatronesEnArchivo -ArchivoPath $archivoCompleto
                            $logSizeAfter = (Get-Item $script:LogPath).Length
                            
                            if ($logSizeAfter -gt $logSizeBefore) {
                                $patronesEncontrados++
                            }
                        }
                    }
                }
                
                if ($patronesEncontrados -gt 0) {
                    Write-InfoLog "Se encontraron patrones en $patronesEncontrados archivo(s)"
                }
                else {
                    Write-InfoLog "No se encontraron patrones sensibles en este commit"
                }
                
                # Actualizar último commit procesado
                Set-Content -Path $ultimoCommitFile -Value $commitActual
                $ultimoCommit = $commitActual
            }
        }
        catch {
            Write-InfoLog "ERROR en iteración $iteracion : $_"
        }
        finally {
            Pop-Location
        }
        
        # Dormir por el intervalo configurado
        Start-Sleep -Seconds $Alerta
    }
    
    # Limpieza al salir
    Write-InfoLog "Demonio detenido"
    Remove-Item $ultimoCommitFile -Force -ErrorAction SilentlyContinue
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

# Función para detener el demonio
function Stop-Demonio {
    $repoId = Get-RepoIdentifier -RepoPath $Repo
    $lockFile = Join-Path $env:TEMP "audit_daemon_$repoId.lock"
    
    if (-not (Test-Path $lockFile)) {
        Write-Error "ERROR: No hay demonio corriendo para este repositorio"
        exit 1
    }
    
    try {
        $lockData = Get-Content $lockFile -ErrorAction Stop | ConvertFrom-Json
        $IdDelProceso = $lockData.PID
        
        $proceso = Get-Process -Id $IdDelProceso -ErrorAction Stop
        
        Write-Host "INFO: Deteniendo demonio (PID: $IdDelProceso)..."
        
        # Intentar cierre graceful
        $proceso.CloseMainWindow() | Out-Null
        Start-Sleep -Seconds 2
        
        # Verificar si sigue corriendo
        if (-not $proceso.HasExited) {
            Write-Host "INFO: Forzando terminación..."
            $proceso.Kill()
            Start-Sleep -Seconds 1
        }
        
        Write-Host "INFO: Demonio detenido exitosamente"
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        Write-Host "INFO: El proceso demonio ya no estaba corriendo"
    }
    catch {
        Write-Host "INFO: Error al detener demonio, limpiando archivos: $_"
    }
    
    # Limpiar archivos
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    
    $ultimoCommitFile = Join-Path $env:TEMP "audit_ultimo_commit_$repoId.txt"
    Remove-Item $ultimoCommitFile -Force -ErrorAction SilentlyContinue
}

# Función principal
function Main {
    # Si es modo demonio, ejecutar bucle principal
    if ($DaemonMode) {
        try {
            Start-BucleDemonio
        }
        catch {
            Write-InfoLog "ERROR FATAL en modo demonio: $_"
            exit 1
        }
        return
    }
    
    # Validar parámetros
    Test-ParametrosObligatorios
    
    # Ejecutar acción solicitada
    if ($Kill) {
        Stop-Demonio
    }
    else {
        Read-Patrones
        Start-Demonio
    }
}

# Punto de entrada - Ejecutar función principal
try {
    Main
}
catch {
    Write-Error "ERROR: $_"
    exit 1
}

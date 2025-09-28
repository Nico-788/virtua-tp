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

# Función para validar parámetros obligatorios
function Test-ParametrosObligatorios {
    if ($Kill) {
        if (-not $Repo) {
            Write-Error "ERROR: Para usar -Kill necesitas especificar -Repo"
            exit 1
        }
        return
    }
    
    # Validar que todos los parámetros obligatorios estén presentes
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
            Write-Error "ERROR: El directorio del archivo de log '$logDir' no existe"
            exit 1
        }
        
        # Crear archivo de log si no existe
        if (-not (Test-Path $Log)) {
            New-Item -Path $Log -ItemType File -Force | Out-Null
        }
        
        # Probar escritura
        Add-Content -Path $Log -Value "" -ErrorAction Stop
    }
    catch {
        Write-Error "ERROR: No se puede escribir en el archivo de log '$Log'"
        exit 1
    }
}

# Función que lee el archivo de configuración y guarda los patrones en un array
function Read-Patrones {
    $script:patrones = @()
    
    try {
        $lineas = Get-Content $Configuracion -ErrorAction Stop
        foreach ($linea in $lineas) {
            # Saltar líneas vacías o comentarios
            if ($linea -and !$linea.StartsWith("#")) {
                $script:patrones += $linea.Trim()
            }
        }
        
        if ($script:patrones.Count -eq 0) {
            Write-Error "ERROR: No se encontraron patrones válidos en '$Configuracion'"
            exit 1
        }
    }
    catch {
        Write-Error "ERROR: No se puede leer el archivo de configuración '$Configuracion'"
        exit 1
    }
}

# Función para escribir en el log
function Write-AlertaLog {
    param(
        [string]$Patron,
        [string]$Archivo
    )
    
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $mensaje = "[$fecha] Alerta: patrón '$Patron' encontrado en '$Archivo'"
    
    try {
        Add-Content -Path $Log -Value $mensaje -ErrorAction Stop
    }
    catch {
        Write-Error "ERROR: No se puede escribir en el archivo de log '$Log'"
    }
}

# Función mejorada para buscar patrones con soporte para regex
function Search-PatronesEnArchivo {
    param([string]$ArchivoPath)
    
    $nombreArchivo = Split-Path $ArchivoPath -Leaf
    
    # Verificar que el archivo existe y es legible
    if (-not (Test-Path $ArchivoPath -PathType Leaf)) {
        return
    }
    
    try {
        $contenido = Get-Content $ArchivoPath -Raw -ErrorAction Stop
        
        foreach ($patron in $script:patrones) {
            $encontrado = $false
            
            # Distinguir entre patrones regex y simples
            if ($patron.StartsWith("regex:")) {
                # Es un patrón regex - extraer la parte después de "regex:"
                $patronRegex = $patron.Substring(6)
                if ($contenido -match $patronRegex) {
                    $encontrado = $true
                }
            }
            else {
                # Es un patrón simple - búsqueda literal
                if ($contenido -match [regex]::Escape($patron)) {
                    $encontrado = $true
                }
            }
            
            if ($encontrado) {
                Write-AlertaLog -Patron $patron -Archivo $nombreArchivo
            }
        }
    }
    catch {
        # Error leyendo archivo, continuar con el siguiente
    }
}

# Función para iniciar el demonio
function Start-Demonio {
    $repoName = Split-Path $Repo -Leaf
    $lockFile = Join-Path $env:TEMP "audit_daemon_$repoName.lock"
    
    # Control de duplicados
    if (Test-Path $lockFile) {
        try {
            $IdDelProceso = Get-Content $lockFile -ErrorAction Stop
            $proceso = Get-Process -Id $IdDelProceso -ErrorAction Stop
            Write-Error "ERROR: Demonio ya está corriendo (PID: $IdDelProceso)"
            exit 1
        }
        catch {
            Write-Host "INFO: Limpiando lockfile de proceso muerto"
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Host "INFO: Iniciando proceso demonio..."
    
    # Crear proceso demonio en segundo plano
    $argumentos = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", $PSCommandPath
        "-Repo", "`"$Repo`""
        "-Configuracion", "`"$Configuracion`""
        "-Log", "`"$Log`""
        "-Alerta", "$Alerta"
        "-DaemonMode"
    )
    
    try {
        $proceso = Start-Process -FilePath "powershell.exe" -ArgumentList $argumentos -PassThru -ErrorAction Stop
        $IdDelProceso = $proceso.Id
        
        # Guardar PID en lockfile
        Set-Content -Path $lockFile -Value $IdDelProceso
        Write-Host "INFO: Demonio iniciado con PID $IdDelProceso"
        Write-Host "INFO: Para detener usar: .\4demonio.ps1 -Repo `"$Repo`" -Kill"
    }
    catch {
        Write-Error "ERROR: No se pudo iniciar el proceso demonio: $_"
        exit 1
    }
}

# Función del bucle principal del demonio
function Start-BucleDemonio {
    $repoName = Split-Path $Repo -Leaf
    $lockFile = Join-Path $env:TEMP "audit_daemon_$repoName.lock"
    $ultimoCommitFile = Join-Path $env:TEMP "audit_ultimo_commit_$repoName.txt"
    
    # Actualizar PID en lockfile (porque ahora es el proceso real del demonio)
    $IdDelProcesoActual = [System.Diagnostics.Process]::GetCurrentProcess().Id
    Set-Content -Path $lockFile -Value $IdDelProcesoActual
    
    # Cargar patrones
    Read-Patrones
    
    # Obtener commit inicial
    try {
        Push-Location $Repo -ErrorAction Stop
        $ultimoCommit = (git rev-parse HEAD 2>$null)
        if (-not $ultimoCommit) { $ultimoCommit = "" }
    }
    catch {
        $ultimoCommit = ""
    }
    finally {
        Pop-Location
    }
    
    Set-Content -Path $ultimoCommitFile -Value $ultimoCommit
    
    # Bucle infinito de monitoreo
    while (Test-Path $lockFile) {
        try {
            Push-Location $Repo -ErrorAction Stop
            $commitActual = (git rev-parse HEAD 2>$null)
            if (-not $commitActual) { $commitActual = "" }
            
            if ($commitActual -and ($commitActual -ne $ultimoCommit)) {
                # Hay cambios - obtener archivos modificados
                if ($ultimoCommit) {
                    $archivos = (git diff --name-only $ultimoCommit $commitActual 2>$null)
                }
                else {
                    # Primer commit - analizar todos los archivos
                    $archivos = (git ls-tree -r --name-only HEAD 2>$null)
                }
                
                # Procesar cada archivo modificado
                foreach ($archivo in $archivos) {
                    if ($archivo) {
                        $archivoCompleto = Join-Path $Repo $archivo
                        if (Test-Path $archivoCompleto -PathType Leaf) {
                            Search-PatronesEnArchivo -ArchivoPath $archivoCompleto
                        }
                    }
                }
                
                # Actualizar último commit procesado
                Set-Content -Path $ultimoCommitFile -Value $commitActual
                $ultimoCommit = $commitActual
            }
        }
        catch {
            # Error con git, continuar
        }
        finally {
            Pop-Location
        }
        
        Start-Sleep -Seconds $Alerta
    }
    
    # Limpieza al salir
    Remove-Item $ultimoCommitFile -Force -ErrorAction SilentlyContinue
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

# Función para detener el demonio
function Stop-Demonio {
    $repoName = Split-Path $Repo -Leaf
    $lockFile = Join-Path $env:TEMP "audit_daemon_$repoName.lock"
    
    if (-not (Test-Path $lockFile)) {
        Write-Error "ERROR: No hay demonio corriendo para '$Repo'"
        exit 1
    }
    
    try {
        $IdDelProceso = Get-Content $lockFile -ErrorAction Stop
        $proceso = Get-Process -Id $IdDelProceso -ErrorAction Stop
        
        Write-Host "INFO: Deteniendo demonio (PID: $IdDelProceso)..."
        $proceso.CloseMainWindow()
        Start-Sleep -Seconds 2
        
        if (-not $proceso.HasExited) {
            $proceso.Kill()
            Write-Host "INFO: Forzando terminación..."
        }
        Write-Host "INFO: Demonio detenido (PID: $IdDelProceso)"
    }
    catch {
        Write-Host "INFO: Demonio ya no estaba corriendo"
    }
    
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

# Función principal
function Main {
    # Si es modo demonio, ejecutar bucle principal
    if ($DaemonMode) {
        try {
            Start-BucleDemonio
        }
        catch {
            Write-Error "Error en modo demonio: $_"
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

# Ejecutar función principal
try {
    Main
}
catch {
    Write-Error "Error general: $_"
    exit 1
}

<#
.SYNOPSIS
  Demonio PowerShell para auditar repositorios Git buscando patrones sensibles.

.DESCRIPTION
  - Usa un archivo de configuración con patrones (líneas vacías comentadas con # serán ignoradas).
  - Patrones normales se tratan como búsqueda literal (case-insensitive).
  - Patrones que comienzan con "regex:" se interpretan como expresiones regulares (sin modificación).
  - Crea en el repo archivos de control:
      .auditdaemon.pid     -> PID del proceso demonio
      .auditdaemon.last    -> último commit analizado (hash)
      .auditdaemon.log     -> log por defecto (si no se pasa -log)
  - Para iniciar en background (liberando terminal) el script relanza una instancia oculta de PowerShell con el flag interno -runWorker.
  - Para detener el demonio usar -kill junto con -repo.

.PARAMETER repo
  Ruta al repositorio Git (requerido para iniciar o detener).

.PARAMETER configuracion
  Ruta al archivo de patrones (requerido para iniciar).

.PARAMETER alerta
  Intervalo de polling en segundos (por defecto 10).

.PARAMETER log
  Ruta al archivo de log (si no se provee, usa $repo/.auditdaemon.log).

.PARAMETER kill
  Flag para detener demonio en ejecución para el repo dado.

.PARAMETER runWorker
  Flag interno: la instancia que ejecuta el bucle infinito. No usar manualmente.

.EXAMPLE
  Iniciar:
    ./audit.ps1 -repo 'C:\repos\miRepo' -configuracion .\patrones.conf -alerta 10

  Detener:
    ./audit.ps1 -repo 'C:\repos\miRepo' -kill

#>

param(
    [Parameter(Mandatory=$false)][string]$repo,
    [Parameter(Mandatory=$false)][string]$configuracion,
    [int]$alerta = 10,
    [string]$log,
    [switch]$kill,
    [switch]$runWorker
)

function Show-Usage {
    Write-Host "Uso:"
    Write-Host "  Iniciar:  .\audit.ps1 -repo <ruta_repo> -configuracion <patrones.conf> [-alerta <segundos>] [-log <ruta_log>]"
    Write-Host "  Detener:  .\audit.ps1 -repo <ruta_repo> -kill"
}

function Resolve-PathStrict($p) {
    try { return (Resolve-Path -Path $p).ProviderPath } catch { return $null }
}

function Read-Patterns($file) {
    $lines = @()
    foreach ($l in Get-Content -Raw -ErrorAction Stop $file -Encoding UTF8 | Split-String "`n") {
        $t = $l.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t.StartsWith('#')) { continue }
        $lines += $t
    }
    return $lines
}

function Write-Log($logFile, $message) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$ts] $message"
    $dir = Split-Path $logFile -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $logFile -Value $entry -Encoding UTF8
}

function Get-GitHash($repoPath, $ref) {
    # devuelve null en error
    try {
        $h = git -C $repoPath rev-parse $ref 2>$null
        return $h.Trim()
    } catch { return $null }
}

function Ensure-GitAvailable {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git no está disponible en PATH. Instala git o añade git al PATH."
    }
}

# ---------- Validaciones iniciales ----------
if ($runWorker) {
    # Worker mode: requiere repo y configuracion
    if (-not $repo -or -not $configuracion) {
        Write-Error "Modo worker requiere -repo y -configuracion."
        exit 2
    }
} else {
    # Modo supervisor (arrancar o detener)
    if (-not $repo) {
        Show-Usage
        exit 1
    }
}

$repoPath = Resolve-PathStrict $repo
if (-not $repoPath) {
    Write-Error "Repositorio no encontrado: $repo"
    exit 1
}

# rutas de control dentro del repo
$pidFile    = Join-Path $repoPath ".auditdaemon.pid"
$lastFile   = Join-Path $repoPath ".auditdaemon.last"
$defaultLog = Join-Path $repoPath ".auditdaemon.log"
if (-not $log) { $log = $defaultLog }

# ---------- Operación de detener (-kill) ----------
if ($kill -and -not $runWorker) {
    if (-not (Test-Path $pidFile)) {
        Write-Host "No hay demonio en ejecución (no se encontró $pidFile)."
        exit 0
    }
    try {
        $pidString = Get-Content -Raw -ErrorAction Stop $pidFile
        $pidDemon = [int]$pidString.Trim()
    } catch {
        Write-Error "No se pudo leer $pidFile. Eliminando archivo y saliendo."
        Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
        exit 1
    }

    $proc = Get-Process -Id $pidDemon -ErrorAction SilentlyContinue
    if ($null -eq $proc) {
        Write-Host "No existe proceso con PID $pidDemon. Eliminando $pidFile."
        Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
        exit 0
    }

    try {
        Stop-Process -Id $pidDemon -ErrorAction Stop
        Start-Sleep -Seconds 1
        if (Test-Path $pidFile) { Remove-Item -Force $pidFile -ErrorAction SilentlyContinue }
        Write-Host "Demonio (PID $pidDemon) detenido correctamente."
        Write-Log $log "Info: demonio detenido (PID $pidDemon)."
        exit 0
    } catch {
        Write-Error "No se pudo detener el proceso PID $pidDemon : $_"
        exit 1
    }
}

# ---------- Evitar múltiples demonios para el mismo repo ----------
if (-not $runWorker) {
    if (Test-Path $pidFile) {
        try {
            $existingPid = [int](Get-Content -Raw $pidFile).Trim()
            if (Get-Process -Id $existingPid -ErrorAction SilentlyContinue) {
                Write-Host "Ya existe un demonio en ejecución para este repositorio (PID $existingPid). No se iniciará otro."
                exit 0
            } else {
                # PID muerto: limpiar pidfile y continuar
                Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
            }
        } catch {
            # Si no se puede leer, borrar y seguir
            Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
        }
    }

    # Validaciones para iniciar
    if (-not $configuracion) {
        Write-Error "Debes especificar -configuracion <patrones.conf> al iniciar."
        exit 1
    }
    $confPath = Resolve-PathStrict $configuracion
    if (-not $confPath) {
        Write-Error "Archivo de configuracion no encontrado: $configuracion"
        exit 1
    }

    # Lanzar la misma script como proceso oculto worker para liberar la terminal
    $scriptFull = $MyInvocation.MyCommand.Definition
    $pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshExe) { $pwshExe = (Get-Command powershell -ErrorAction SilentlyContinue).Source }
    if (-not $pwshExe) {
        Write-Error "No se encontró pwsh ni powershell en PATH."
        exit 1
    }

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptFull`"",
        "-repo", "`"$repoPath`"",
        "-configuracion", "`"$confPath`"",
        "-alerta", $alerta,
        "-log", "`"$log`"",
        "-runWorker"
    )

    try {
        $joinedArgs = $args -join ' '
        $nohupCmd = "nohup $pwshExe $joinedArgs > /dev/null 2>&1 & disown; pgrep -n -f '$pwshExe.*-runWorker'"
        $pidDemon = bash -c $nohupCmd
        if ($pidDemon) {
            $pidDemon.Trim() | Out-File -FilePath $pidFile -Encoding ascii -Force
            Write-Host "Demonio iniciado (PID $pidDemon). Log: $log"
            Write-Log $log "Info: demonio iniciado (PID $pidDemon)."
            exit 0
        } else {
            Write-Error "No se pudo iniciar el demonio con nohup."
            exit 1
        }
    } catch {
        Write-Error "No se pudo iniciar el demonio: $_"
        exit 1
    }
}

# ---------- Modo worker (bucle principal) ----------
try {
    Ensure-GitAvailable
} catch {
    Write-Error $_
    exit 1
}

# Validar archivo de patrones
$configPath = Resolve-PathStrict $configuracion
if (-not $configPath) {
    Write-Error "Archivo de patrones no encontrado: $configuracion"
    exit 1
}

# Escribe su propio PID (en caso de que el iniciador falle antes de hacerlo)
try {
    $PID | Out-File -FilePath $pidFile -Encoding ascii -Force
} catch {
    Write-Warning "No se pudo escribir $pidFile : $_"
}

# cargar patrones
try {
    $patterns = Read-Patterns $configPath
} catch {
    Write-Error "Error leyendo patrones: $_"
    exit 1
}

# Inicializar último hash si no existe
if (-not (Test-Path $lastFile)) {
    $cur = Get-GitHash $repoPath 'main'
    if (-not $cur) { $cur = Get-GitHash $repoPath 'HEAD' }
    if ($cur) {
        Set-Content -Path $lastFile -Value $cur -Encoding ascii
    } else {
        Write-Error "No se pudo determinar hash inicial de la rama 'main' ni 'HEAD'. Asegurate que $repoPath es un repo git."
        exit 1
    }
}

Write-Log $log "Info: worker iniciado (PID $PID). Poll cada $alerta segs. Patrones: $($patterns.Count)."

# Bucle infinito (se puede detener con Stop-Process sobre $PID o con -kill desde otro proceso)
while ($true) {
    try {
        # fetch remoto para detectar cambios en caso de que se use origin
        git -C $repoPath fetch --all --prune 2>$null

        $oldHash = (Get-Content -Raw $lastFile -ErrorAction Stop).Trim()
        # intentar obtener el hash actual de main, si falla intentar HEAD
        $newHash = Get-GitHash $repoPath 'main'
        if (-not $newHash) { $newHash = Get-GitHash $repoPath 'HEAD' }

        if ($newHash -and $newHash -ne $oldHash) {
            # obtener archivos modificados entre $oldHash y $newHash
            $files = @()
            try {
                $diffOutput = git -C $repoPath diff --name-only $oldHash $newHash 2>$null
                if ($diffOutput) {
                    $files = $diffOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                }
            } catch {
                $files = @()
            }

            if ($files.Count -gt 0) {
                foreach ($f in $files) {
                    $fullPath = Join-Path $repoPath $f
                    if (-not (Test-Path $fullPath)) { continue } # eliminado o submodulo
                    # intentar leer archivo como texto
                    $content = $null
                    try {
                        $content = Get-Content -Raw -ErrorAction Stop -Encoding UTF8 $fullPath
                    } catch {
                        # intentar con default encoding
                        try { $content = Get-Content -Raw -ErrorAction Stop $fullPath } catch { $content = $null }
                    }
                    if (-not $content) { continue }

                    foreach ($p in $patterns) {
                        if ($p.StartsWith("regex:", [System.StringComparison]::InvariantCultureIgnoreCase)) {
                            $rx = $p.Substring(6) # todo lo después de regex:
                            try {
                                if ([regex]::IsMatch($content, $rx, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                                    Write-Log $log "Alerta: patrón '$p' encontrado en el archivo '$f'."
                                }
                            } catch {
                                Write-Log $log "Error: patrón regex inválido '$rx' (archivo '$f'): $_"
                            }
                        } else {
                            # búsqueda literal - case-insensitive
                            $escaped = [regex]::Escape($p)
                            if ([regex]::IsMatch($content, $escaped, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                                Write-Log $log "Alerta: patrón '$p' encontrado en el archivo '$f'."
                            }
                        }
                    }
                }
            }
            # actualizar last hash
            try {
                Set-Content -Path $lastFile -Value $newHash -Encoding ascii
            } catch {
                Write-Warning "No se pudo actualizar $lastFile : $_"
            }
        }

    } catch {
        Write-Log $log "Error en ciclo audit: $_"
    }

    Start-Sleep -Seconds $alerta
}
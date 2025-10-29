<#
.SYNOPSIS
Demonio para monitorear credenciales en directorios

.DESCRIPTION
Script demonio para monitorear un directorio y detectar credenciales o datos sensibles.

.PARAMETER Repo
Ruta del directorio a monitorear (OBLIGATORIO)

.PARAMETER Configuracion
Ruta del archivo de configuración con patrones a buscar (OBLIGATORIO)

.PARAMETER Log
Ruta del archivo de logs (OBLIGATORIO)

.PARAMETER Alerta
Intervalo en segundos (opcional, default 10s)

.PARAMETER Kill
Flag para detener el demonio

.EXAMPLE
./4demonio.ps1 -Repo "/home/user/MyRepo" -Configuracion "./patrones.conf" -Log "./audit.log"

.EXAMPLE
./4demonio.ps1 -Repo "/home/user/MyRepo" -Kill
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Repo,
    
    [Parameter(Mandatory=$false)]
    [string]$Configuracion,
    
    [Parameter(Mandatory=$false)]
    [string]$Log,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Alerta = 10,
    
    [Parameter(Mandatory=$false)]
    [switch]$Kill,
    
    [Parameter(DontShow)]
    [switch]$DaemonMode
)

$script:patrones = @()

# Función para convertir a ruta absoluta de forma segura
function Get-AbsolutePath {
    param([string]$Path)
    
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    
    # Si ya es absoluto, devolverlo tal cual
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    
    # Si es relativo, convertir a absoluto
    try {
        $resolved = Resolve-Path $Path -ErrorAction Stop
        return $resolved.Path
    } catch {
        # Si Resolve-Path falla (archivo no existe), construir manualmente
        return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
    }
}

function Test-ParametrosObligatorios {
    if ($Kill) {
        if (-not $Repo) { Write-Error "ERROR: -Kill requiere -Repo"; exit 1 }
        return
    }
    
    if (-not $Repo) { Write-Error "ERROR: -Repo obligatorio"; Get-Help $PSCommandPath; exit 1 }
    if (-not $Configuracion) { Write-Error "ERROR: -Configuracion obligatorio"; Get-Help $PSCommandPath; exit 1 }
    if (-not $Log) { Write-Error "ERROR: -Log obligatorio"; Get-Help $PSCommandPath; exit 1 }
    
    # Validar directorio (SIN validar que sea repositorio Git)
    $repoAbs = Get-AbsolutePath $Repo
    if (-not (Test-Path $repoAbs -PathType Container)) {
        Write-Error "ERROR: El directorio '$repoAbs' no existe"
        exit 1
    }
    
    # Validar configuración
    $configAbs = Get-AbsolutePath $Configuracion
    if (-not (Test-Path $configAbs -PathType Leaf)) {
        Write-Error "ERROR: El archivo de configuración '$configAbs' no existe"
        exit 1
    }
    
    # Validar log
    try {
        $logAbs = Get-AbsolutePath $Log
        $logDir = Split-Path $logAbs -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $logAbs)) {
            New-Item -Path $logAbs -ItemType File -Force | Out-Null
        }
        Add-Content -Path $logAbs -Value "" -ErrorAction Stop
    } catch {
        Write-Error "ERROR: No se puede escribir en log '$logAbs': $_"
        exit 1
    }
}

function Read-Patrones {
    $script:patrones = @()
    $configAbs = Get-AbsolutePath $Configuracion
    
    try {
        Get-Content $configAbs -ErrorAction Stop | ForEach-Object {
            $line = $_.Trim()
            if ($line -and !$line.StartsWith("#")) {
                $script:patrones += $line
            }
        }
        if ($script:patrones.Count -eq 0) {
            throw "Sin patrones válidos"
        }
    } catch {
        Write-Error "ERROR: No se puede leer configuración: $_"
        exit 1
    }
}

function Write-AlertaLog {
    param([string]$Patron, [string]$Archivo)
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $mensaje = "[$fecha] Alerta: patrón '$Patron' encontrado en el archivo '$Archivo'."
    $logAbs = Get-AbsolutePath $Log
    Add-Content -Path $logAbs -Value $mensaje -ErrorAction SilentlyContinue
}

function Search-PatronesEnArchivo {
    param([string]$ArchivoPath)
    
    if (-not (Test-Path $ArchivoPath -PathType Leaf)) { return }
    $nombreArchivo = Split-Path $ArchivoPath -Leaf
    
    try {
        $contenido = Get-Content $ArchivoPath -Raw -ErrorAction Stop
        if (-not $contenido) { return }
        
        foreach ($patron in $script:patrones) {
            $encontrado = $false
            
            if ($patron.StartsWith("regex:")) {
                $patronRegex = $patron.Substring(6)
                try {
                    if ($contenido -match $patronRegex) { $encontrado = $true }
                } catch { }
            } else {
                $patronEscapado = [regex]::Escape($patron)
                if ($contenido -match "(?i)$patronEscapado") { $encontrado = $true }
            }
            
            if ($encontrado) {
                Write-AlertaLog -Patron $patron -Archivo $nombreArchivo
            }
        }
    } catch { }
}

function Get-RepoIdentifier {
    param([string]$RepoPath)
    $absolutePath = Get-AbsolutePath $RepoPath
    $hash = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($absolutePath.ToLower())
    $hashBytes = $hash.ComputeHash($bytes)
    return [System.BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 16)
}

function Get-DirectorySnapshot {
    param([string]$Path)
    
    $snapshot = @{}
    Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $snapshot[$_.FullName] = $_.LastWriteTime
        } catch { }
    }
    return $snapshot
}

function Start-Demonio {
    $repoId = Get-RepoIdentifier -RepoPath $Repo
    
    # Obtener directorio temporal correcto (funciona en Linux y Windows)
    $tempDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
    $lockFile = Join-Path $tempDir "audit_daemon_$repoId.lock"
    
    if (Test-Path $lockFile) {
        try {
            $pidData = Get-Content $lockFile | ConvertFrom-Json
            $proceso = Get-Process -Id $pidData.PID -ErrorAction Stop
            Write-Error "ERROR: Demonio ya corriendo (PID: $($pidData.PID))"; exit 1
        } catch {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Convertir todas las rutas a absolutas de forma segura
    $RepoAbs = Get-AbsolutePath $Repo
    $ConfigAbs = Get-AbsolutePath $Configuracion
    $LogAbs = Get-AbsolutePath $Log
    
    $argumentos = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$PSCommandPath`""
        "-Repo", "`"$RepoAbs`""
        "-Configuracion", "`"$ConfigAbs`""
        "-Log", "`"$LogAbs`""
        "-Alerta", $Alerta
        "-DaemonMode"
    )
    
    try {
        # Iniciar proceso SIN WindowStyle (compatible con Linux)
        $proceso = Start-Process -FilePath "pwsh" `
                                 -ArgumentList $argumentos `
                                 -PassThru `
                                 -ErrorAction Stop
        
        $processId = $proceso.Id
        
        @{ PID = $processId; Repo = $RepoAbs; Started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") } | 
            ConvertTo-Json | Set-Content $lockFile
        
        Write-Host "INFO: Demonio iniciado (PID: $processId)"
        Write-Host "INFO: Monitoreando directorio: $RepoAbs"
        Write-Host "INFO: Para detener: pwsh $PSCommandPath -Repo `"$Repo`" -Kill"
    } catch {
        Write-Error "ERROR: No se pudo iniciar demonio: $_"; exit 1
    }
}

function Start-BucleDemonio {
    $repoId = Get-RepoIdentifier -RepoPath $Repo
    $tempDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
    $lockFile = Join-Path $tempDir "audit_daemon_$repoId.lock"
    
    @{ PID = $PID; Repo = $Repo; Started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") } |
        ConvertTo-Json | Set-Content $lockFile
    
    Read-Patrones
    
    $repoAbs = Get-AbsolutePath $Repo
    
    # Tomar snapshot inicial
    $snapshotAnterior = Get-DirectorySnapshot -Path $repoAbs
    
    while (Test-Path $lockFile) {
        try {
            Start-Sleep -Seconds $Alerta
            
            # Tomar nuevo snapshot
            $snapshotActual = Get-DirectorySnapshot -Path $repoAbs
            
            # Detectar archivos nuevos o modificados
            $archivosModificados = @()
            
            foreach ($archivo in $snapshotActual.Keys) {
                if (-not $snapshotAnterior.ContainsKey($archivo)) {
                    # Archivo nuevo
                    $archivosModificados += $archivo
                } elseif ($snapshotActual[$archivo] -ne $snapshotAnterior[$archivo]) {
                    # Archivo modificado
                    $archivosModificados += $archivo
                }
            }
            
            # Analizar archivos modificados
            if ($archivosModificados.Count -gt 0) {
                foreach ($archivo in $archivosModificados) {
                    if (Test-Path $archivo -PathType Leaf) {
                        Search-PatronesEnArchivo -ArchivoPath $archivo
                    }
                }
            }
            
            # Actualizar snapshot
            $snapshotAnterior = $snapshotActual
            
        } catch {
            # Continuar en caso de error
        }
    }
}

function Stop-Demonio {
    $repoId = Get-RepoIdentifier -RepoPath $Repo
    $tempDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
    $lockFile = Join-Path $tempDir "audit_daemon_$repoId.lock"
    
    if (-not (Test-Path $lockFile)) {
        Write-Error "ERROR: No hay demonio corriendo para este directorio"
        exit 1
    }
    
    try {
        $lockData = Get-Content $lockFile | ConvertFrom-Json
        $proceso = Get-Process -Id $lockData.PID -ErrorAction Stop
        $proceso.Kill()
        Write-Host "INFO: Demonio detenido (PID: $($lockData.PID))"
    } catch {
        Write-Host "INFO: Proceso ya no estaba corriendo"
    }
    
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

# MAIN
if ($DaemonMode) {
    Start-BucleDemonio
} else {
    Test-ParametrosObligatorios
    if ($Kill) { Stop-Demonio } else { Read-Patrones; Start-Demonio }
}

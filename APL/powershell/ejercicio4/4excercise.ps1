<#
.SYNOPSIS
Demonio para monitorear credenciales en repositorios Git

.DESCRIPTION
Script demonio para monitorear un repositorio Git y detectar credenciales o datos sensibles.

.PARAMETER Repo
Ruta del repositorio Git a monitorear (OBLIGATORIO)

.PARAMETER Configuracion
Ruta del archivo de configuración con patrones a buscar (OBLIGATORIO)

.PARAMETER Log
Ruta del archivo de logs (OBLIGATORIO)

.PARAMETER Alerta
Intervalo en segundos (opcional. default 10s)

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

# Función para obtener path absoluto de forma portable
function Get-AbsolutePath {
    param([string]$Path)
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }
    
    # Si ya es absoluto (comienza con /)
    if ($Path.StartsWith('/')) {
        return $Path
    }
    
    # Si es relativo, combinarlo con la ubicación actual
    $currentLocation = Get-Location | Select-Object -ExpandProperty Path
    
    # Normalizar el path
    if ($Path.StartsWith('./')) {
        $Path = $Path.Substring(2)
    }
    
    # Combinar paths
    $combined = Join-Path $currentLocation $Path
    
    # Normalizar barras
    return $combined.Replace('\', '/')
}

function Test-ParametrosObligatorios {
    if ($Kill) {
        if (-not $Repo) { Write-Error "ERROR: -Kill requiere -Repo"; exit 1 }
        return
    }
    if (-not $Repo) { Write-Error "ERROR: -Repo obligatorio"; Get-Help $PSCommandPath; exit 1 }
    if (-not $Configuracion) { Write-Error "ERROR: -Configuracion obligatorio"; Get-Help $PSCommandPath; exit 1 }
    if (-not $Log) { Write-Error "ERROR: -Log obligatorio"; Get-Help $PSCommandPath; exit 1 }
    
    # Convertir a paths absolutos
    $script:Repo = Get-AbsolutePath $Repo
    $script:Configuracion = Get-AbsolutePath $Configuracion
    $script:Log = Get-AbsolutePath $Log
    
    # Validar Repo
    if (-not (Test-Path $script:Repo)) {
        Write-Error "ERROR: El directorio del repositorio '$script:Repo' no existe"
        exit 1
    }
    
    # Validar Configuracion
    if (-not (Test-Path $script:Configuracion)) {
        Write-Error "ERROR: El archivo de configuración '$script:Configuracion' no existe"
        exit 1
    }
    
    # Crear Log si no existe
    try {
        $logDir = Split-Path $script:Log -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $script:Log)) {
            New-Item -Path $script:Log -ItemType File -Force | Out-Null
        }
        Add-Content -Path $script:Log -Value "" -ErrorAction Stop
    } catch {
        Write-Error "ERROR: No se puede escribir en log '$script:Log'"
        exit 1
    }
}

function Read-Patrones {
    $script:patrones = @()
    try {
        $configPath = Get-AbsolutePath $Configuracion
        
        if (-not (Test-Path $configPath)) {
            throw "El archivo de configuración '$configPath' no existe"
        }
        
        Get-Content $configPath | ForEach-Object {
            $line = $_.Trim()
            if ($line -and !$line.StartsWith("#")) { $script:patrones += $line }
        }
        if ($script:patrones.Count -eq 0) { throw "Sin patrones válidos" }
    } catch {
        Write-Error "ERROR: No se puede leer configuración: $_"
        exit 1
    }
}

function Write-AlertaLog {
    param([string]$Patron, [string]$Archivo)
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $mensaje = "[$fecha] Alerta: patrón '$Patron' encontrado en '$Archivo'"
    Add-Content -Path $Log -Value $mensaje -ErrorAction SilentlyContinue
}

function Search-PatronesEnArchivo {
    param([string]$ArchivoPath)
    
    if (-not (Test-Path $ArchivoPath)) { return }
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
            
            if ($encontrado) { Write-AlertaLog -Patron $patron -Archivo $nombreArchivo }
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

function Get-TempDirectory {
    # Intentar obtener el directorio temporal de forma portable
    $tempDir = $env:TMPDIR
    if (-not $tempDir) { $tempDir = $env:TEMP }
    if (-not $tempDir) { $tempDir = $env:TMP }
    if (-not $tempDir) { $tempDir = "/tmp" }
    
    return $tempDir
}

function Start-Demonio {
    $repoId = Get-RepoIdentifier -RepoPath $Repo
    $tempDir = Get-TempDirectory
    $lockFile = Join-Path $tempDir "audit_daemon_$repoId.lock"
    
    if (Test-Path $lockFile) {
        try {
            $pidData = Get-Content $lockFile | ConvertFrom-Json
            $proceso = Get-Process -Id $pidData.PID -ErrorAction Stop
            Write-Error "ERROR: Demonio ya corriendo (PID: $($pidData.PID))"
            exit 1
        } catch {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    }
    
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
        $proceso = Start-Process -FilePath "pwsh" `
                                 -ArgumentList $argumentos `
                                 -PassThru `
                                 -ErrorAction Stop
        
        $processId = $proceso.Id
        
        @{ PID = $processId; Repo = $RepoAbs; Started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") } | 
            ConvertTo-Json | Set-Content $lockFile
        
        Write-Host "INFO: Demonio iniciado (PID: $processId)"
        Write-Host "INFO: Para detener: ./4demonio.ps1 -Repo `"$Repo`" -Kill"
    } catch {
        Write-Error "ERROR: No se pudo iniciar demonio: $_"
        exit 1
    }
}

function Start-BucleDemonio {
    $repoId = Get-RepoIdentifier -RepoPath $Repo
    $tempDir = Get-TempDirectory
    $lockFile = Join-Path $tempDir "audit_daemon_$repoId.lock"
    $commitFile = Join-Path $tempDir "audit_commit_$repoId.txt"
    
    @{ PID = $PID; Repo = $Repo; Started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") } |
        ConvertTo-Json | Set-Content $lockFile
    
    Read-Patrones
    
    Push-Location $Repo
    $ultimoCommit = (git rev-parse HEAD 2>$null)
    if (-not $ultimoCommit) { $ultimoCommit = "EMPTY" }
    Pop-Location
    
    Set-Content $commitFile -Value $ultimoCommit
    
    while (Test-Path $lockFile) {
        try {
            Push-Location $Repo
            $commitActual = (git rev-parse HEAD 2>$null)
            if (-not $commitActual) { $commitActual = "EMPTY" }
            
            if ($commitActual -ne "EMPTY" -and $commitActual -ne $ultimoCommit) {
                $archivos = @()
                if ($ultimoCommit -ne "EMPTY") {
                    $diff = git diff --name-only $ultimoCommit $commitActual 2>$null
                    if ($diff) { $archivos = $diff -split "`n" | Where-Object { $_.Trim() } }
                } else {
                    $ls = git ls-tree -r --name-only HEAD 2>$null
                    if ($ls) { $archivos = $ls -split "`n" | Where-Object { $_.Trim() } }
                }
                
                foreach ($archivo in $archivos) {
                    $path = Join-Path $Repo $archivo
                    if (Test-Path $path -PathType Leaf) {
                        Search-PatronesEnArchivo -ArchivoPath $path
                    }
                }
                
                Set-Content $commitFile -Value $commitActual
                $ultimoCommit = $commitActual
            }
            Pop-Location
        } catch {
            Pop-Location
        }
        
        Start-Sleep -Seconds $Alerta
    }
    
    Remove-Item $commitFile -Force -ErrorAction SilentlyContinue
}

function Stop-Demonio {
    $repoId = Get-RepoIdentifier -RepoPath $Repo
    $tempDir = Get-TempDirectory
    $lockFile = Join-Path $tempDir "audit_daemon_$repoId.lock"
    
    if (-not (Test-Path $lockFile)) {
        Write-Error "ERROR: No hay demonio corriendo"
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
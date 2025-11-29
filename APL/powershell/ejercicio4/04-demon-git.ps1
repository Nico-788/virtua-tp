<#
.SYNOPSIS
Demonio para monitorear credenciales en directorios usando Event Subscribers

.DESCRIPTION
Script demonio para monitorear un directorio y detectar credenciales o datos sensibles
utilizando FileSystemWatcher y Event Subscribers de PowerShell.

.PARAMETER Repo
Ruta del directorio a monitorear (OBLIGATORIO)

.PARAMETER Configuracion
Ruta del archivo de configuración con patrones a buscar (OBLIGATORIO)

.PARAMETER Log
Ruta del archivo de logs (OBLIGATORIO)

.PARAMETER Alerta
Intervalo en segundos para revisar cambios (opcional, default 10s)

.PARAMETER Kill
Flag para detener el demonio

.EXAMPLE
./audit.ps1 -Repo "/home/user/MyRepo" -Configuracion "./patrones.conf" -Log "./audit.log"

.EXAMPLE
./audit.ps1 -Repo "/home/user/MyRepo" -Kill
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
    [switch]$Kill
)

# Función para convertir a ruta absoluta
function Get-AbsolutePath {
    param([string]$Path)
    
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    
    try {
        $resolved = Resolve-Path $Path -ErrorAction Stop
        return $resolved.Path
    } catch {
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
    
    $repoAbs = Get-AbsolutePath $Repo
    if (-not (Test-Path $repoAbs -PathType Container)) {
        Write-Error "ERROR: El directorio '$repoAbs' no existe"
        exit 1
    }
    
    $configAbs = Get-AbsolutePath $Configuracion
    if (-not (Test-Path $configAbs -PathType Leaf)) {
        Write-Error "ERROR: El archivo de configuración '$configAbs' no existe"
        exit 1
    }
    
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

function Get-RepoIdentifier {
    param([string]$RepoPath)
    $absolutePath = Get-AbsolutePath $RepoPath
    $hash = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($absolutePath.ToLower())
    $hashBytes = $hash.ComputeHash($bytes)
    return [System.BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 16)
}

function Get-LockFilePath {
    param([string]$RepoPath)
    $repoId = Get-RepoIdentifier -RepoPath $RepoPath
    $tempDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
    return Join-Path $tempDir "audit_daemon_$repoId.lock"
}

function Start-Demonio {
    $repoAbs = Get-AbsolutePath $Repo
    $configAbs = Get-AbsolutePath $Configuracion
    $logAbs = Get-AbsolutePath $Log
    $lockFile = Get-LockFilePath -RepoPath $Repo
    
    # Verificar si ya existe un demonio
    if (Test-Path $lockFile) {
        try {
            $lockData = Get-Content $lockFile | ConvertFrom-Json
            $null = Get-EventSubscriber -SourceIdentifier $lockData.SubscriberID -ErrorAction Stop
            Write-Error "ERROR: Demonio ya corriendo (Subscriber: $($lockData.SubscriberID))"
            exit 1
        } catch {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Leer patrones
    $patrones = @()
    Get-Content $configAbs | ForEach-Object {
        $line = $_.Trim()
        if ($line -and !$line.StartsWith("#")) {
            $patrones += $line
        }
    }
    
    if ($patrones.Count -eq 0) {
        Write-Error "ERROR: No hay patrones válidos en configuración"
        exit 1
    }
    
    # Crear FileSystemWatcher
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $repoAbs
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor 
                           [System.IO.NotifyFilters]::FileName -bor
                           [System.IO.NotifyFilters]::CreationTime

    #Para no detectar 2 veces lo mismo
    $ultimoCambio = $null

    # Script para analizar archivos
    $action = {
        param($source, $eventArguments)

        if ($null -ne $ultimoCambio){
            $fechaActual = Get-Date
            $diferencia = $fechaActual.Subtract($ultimoCambio)

            if ($diferencia.TotalSeconds -le 2){
                return 
            }
        }
        
        $ultimoCambio = Get-Date

        $archivoPath = $eventArguments.FullPath
        $nombreArchivo = Split-Path $archivoPath -Leaf
        
        # Obtener configuración del evento
        $logPath = $event.MessageData.LogPath
        $patrones = $event.MessageData.Patrones
        
        # Esperar a que el archivo esté disponible
        Start-Sleep -Milliseconds 100
        
        if (-not (Test-Path $archivoPath -PathType Leaf)) { return }
        
        try {
            $contenido = Get-Content $archivoPath -Raw -ErrorAction Stop
            if (-not $contenido) { return }
            
            foreach ($patron in $patrones) {
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
                    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $mensaje = "[$fecha] Alerta: patrón '$patron' encontrado en el archivo '$nombreArchivo'."
                    Add-Content -Path $logPath -Value $mensaje -ErrorAction SilentlyContinue
                }
            }
        } catch { }
    }
    
    # Datos para pasar al script
    $messageData = @{
        LogPath = $logAbs
        Patrones = $patrones
    }
    
    # Registrar eventos
    $subscriberID = "AuditDaemon_$(Get-RepoIdentifier -RepoPath $Repo)"
    
    Register-ObjectEvent -InputObject $watcher -EventName "Changed" `
                        -SourceIdentifier $subscriberID `
                        -Action $action `
                        -MessageData $messageData | Out-Null
    
    Register-ObjectEvent -InputObject $watcher -EventName "Created" `
                        -SourceIdentifier "${subscriberID}_Created" `
                        -Action $action `
                        -MessageData $messageData | Out-Null
    
    # Iniciar el watcher
    $watcher.EnableRaisingEvents = $true
    
    # Guardar información del lock
    @{
        SubscriberID = $subscriberID
        Repo = $repoAbs
        Started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json | Set-Content $lockFile
    
    Write-Host "INFO: Demonio iniciado (Subscriber: $subscriberID)"
    Write-Host "INFO: Monitoreando directorio: $repoAbs"
    Write-Host "INFO: Para detener: pwsh $PSCommandPath -Repo `"$Repo`" -Kill"
}

function Stop-Demonio {
    $lockFile = Get-LockFilePath -RepoPath $Repo
    
    if (-not (Test-Path $lockFile)) {
        Write-Error "ERROR: No hay demonio corriendo para este directorio"
        exit 1
    }
    
    try {
        $lockData = Get-Content $lockFile | ConvertFrom-Json
        
        # Detener event subscribers
        Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like "$($lockData.SubscriberID)*" } | ForEach-Object {
            Unregister-Event -SourceIdentifier $_.SourceIdentifier -ErrorAction SilentlyContinue
        }
        
        Write-Host "INFO: Demonio detenido (Subscriber: $($lockData.SubscriberID))"
    } catch {
        Write-Host "INFO: Event subscriber ya no estaba registrado"
    }
    
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

# MAIN
Test-ParametrosObligatorios

if ($Kill) {
    Stop-Demonio
} else {
    Start-Demonio
}
#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory=$false)][string]$repo,
    [Parameter(Mandatory=$false)][string]$configuracion,
    [Parameter(Mandatory=$false)][string]$log,
    [switch]$kill,
    [switch]$help
)

function Show-Help {
    Write-Host "NAME"
    Write-Host "`t04-demon-git.ps1"
    Write-Host ""
    Write-Host "SYNOPSIS"
    Write-Host "`t./04-demon-git.ps1 -repo <DIRECTORIO> [-configuracion <FILE>] [-log <FILE>] [-kill]"
    Write-Host ""
    Write-Host "DESCRIPTION"
    Write-Host "`tMonitorea la rama de un repositorio Git para detectar credenciales o datos sensibles."
    Write-Host "`tEl archivo de configuración contiene palabras clave o regex a buscar."
    Write-Host ""
    Write-Host "OPTIONS"
    Write-Host "`t-repo / -r   Ruta del repositorio git"
    Write-Host "`t-configuracion / -c   Archivo con palabras o regex (regex:patron)"
    Write-Host "`t-log / -l    Archivo .log donde guardar coincidencias"
    Write-Host "`t-kill / -k   Mata el proceso que monitorea el repo"
    Write-Host "`t-help / -h   Muestra esta ayuda"
}

if ($help) {
    Show-Help
    exit 0
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile   = Join-Path $scriptDir ".tmp/demon_pid.conf"

if (-not $repo) {
    Write-Error "Error: especifique -repo"
    exit 1
}

if (-not (Test-Path $repo)) {
    Write-Error "Error: $repo no existe"
    exit 1
}

# Validar si es repositorio Git
try {
    git -C $repo rev-parse --is-inside-work-tree *>$null
} catch {
    Write-Error "Error: no es un repositorio válido"
    exit 1
}
$repoAbs = (Resolve-Path $repo).Path

# ---- KILL ----
if ($kill) {
    if (Test-Path $pidFile -PathType Leaf) {
        $found = $false
        $lines = Get-Content $pidFile
        Write-Host "$lines"
        foreach ($line in $lines) {
            $pidDaemon,$r = $line -split "\|"
            Write-Host "$pidDaemon"
            if ($r -eq $repoAbs) {
                try {
                    Stop-Process -Id $pidDaemon -ErrorAction SilentlyContinue
                    $found = $true
                } catch {}
                # eliminar registro de ese demonio en el archivo
                $updatedLines = $lines | Where-Object {$_ -notlike "$pidDaemon|*"}
                
                # 🔹 Manejar archivo vacío correctamente
                if ($updatedLines) {
                    $updatedLines | Set-Content $pidFile
                } else {
                    # Si no quedan líneas, crear archivo vacío
                    "" | Set-Content $pidFile
                }

                # borrar el script temporal asociado
                $tmpDir     = Join-Path $scriptDir ".tmp"
                $daemonFile = Join-Path $tmpDir "daemon_instance.ps1"
                if (Test-Path $daemonFile) {
                    Remove-Item $daemonFile -Force
                    Write-Host "Script temporal eliminado: $daemonFile"
                }
                break
            }
        }
        if (-not $found) {
            Write-Error "Error: repositorio no monitoreado"
            exit 1
        }

        Start-Sleep -Seconds 5
        if (Get-Process -Id $pidDaemon -ErrorAction SilentlyContinue) {
            Write-Error "Error: el proceso no pudo matarse"
            exit 1
        }

        # 🔹 Si ya no quedan demonios, borrar la carpeta .tmp
        if (-not (Get-Content $pidFile)) {
            Remove-Item (Split-Path $pidFile -Parent) -Recurse -Force
            Write-Host "Carpeta temporal eliminada: $(Split-Path $pidFile -Parent)"
        }

        exit 0
    } else {
        Write-Error "Error: proceso no existe"
        exit 1
    }
}

# Evitar duplicados
if (Test-Path $pidFile) {
    foreach ($line in Get-Content $pidFile) {
        $pidDaemon,$r = $line -split "\|"
        if (Get-Process -Id $pidDaemon -ErrorAction SilentlyContinue) {
            if ($r -eq $repoAbs) {
                Write-Error "Error: ya existe un demonio monitoreando $repoAbs con PID $pidDaemon"
                exit 1
            }
        }
    }
}

# Configuración
if (-not $configuracion -or -not (Test-Path $configuracion)) {
    Write-Error "Error: especifique archivo de configuración válido"
    exit 1
}
$palabrasBuscar = @()
$patronesRegex  = @()
foreach ($line in Get-Content $configuracion) {
    if ($line -match "^regex:(.*)") {
        $patronesRegex += $matches[1]
    } elseif ($line.Trim() -ne "") {
        $palabrasBuscar += $line.Trim()
    }
}

# Log
if (-not $log -or $log -notmatch "\.log$") {
    Write-Error "Error: especifique archivo .log válido"
    exit 1
}
$logAbs = (Resolve-Path $log).Path
#$configAbs = (Resolve-Path $configuracion).Path

# Script que corre como demonio real
$daemonScript = @"
#!/usr/bin/env pwsh
param(
    [string]`$repoAbs,
    [string]`$logAbs,
    [string[]]`$palabrasBuscar,
    [string[]]`$patronesRegex,
    [string]`$pidFile,
    [string]`$scriptDir
)

Set-Location `$repoAbs
`$lastCommit = (git rev-parse main)

while (`$true) {
    `$currentCommit = (git rev-parse main)
    if (`$currentCommit -ne `$lastCommit) {
        `$archivosCommit = git diff --name-only `$lastCommit `$currentCommit
        foreach (`$file in `$archivosCommit) {
            if (-not (Test-Path `$file)) { continue }
            `$pathAbs = (Resolve-Path `$file).Path
            foreach (`$pal in `$palabrasBuscar) {
                if (Select-String -Path `$file -Pattern `$pal -SimpleMatch -Quiet) {
                    Add-Content `$logAbs ("[{0}] Alerta: palabra '{1}' en {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),`$pal,`$pathAbs)
                }
            }
            foreach (`$pat in `$patronesRegex) {
                if (Select-String -Path `$file -Pattern `$pat -Quiet) {
                    Add-Content `$logAbs ("[{0}] Alerta: patrón '{1}' en {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),`$pat,`$pathAbs)
                }
            }
        }
        `$lastCommit = `$currentCommit
    }
    Start-Sleep -Seconds 5
}
"@

# Guardar script temporal que será lanzado con Start-Process
$tmpDir = Join-Path $scriptDir ".tmp"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$daemonFile = Join-Path $tmpDir "daemon_instance.ps1"
$daemonScript | Set-Content $daemonFile

# Iniciar como proceso real
$p = Start-Process pwsh -ArgumentList "-File `"$daemonFile`" -repoAbs `"$repoAbs`" -logAbs `"$logAbs`" -palabrasBuscar $($palabrasBuscar -join ',') -patronesRegex $($patronesRegex -join ',') -pidFile `"$pidFile`" -scriptDir `"$scriptDir`"" -PassThru

$pidDaemon = $p.Id
Add-Content $pidFile ("{0}|{1}" -f $pidDaemon,$repoAbs)

Write-Output "Demonio iniciado con PID $pidDaemon para $repoAbs"
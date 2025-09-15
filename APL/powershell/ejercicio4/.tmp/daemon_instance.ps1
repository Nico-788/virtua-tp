#!/usr/bin/env pwsh
param(
    [string]$repoAbs,
    [string]$logAbs,
    [string[]]$palabrasBuscar,
    [string[]]$patronesRegex,
    [string]$pidFile,
    [string]$scriptDir
)

Set-Location $repoAbs
$lastCommit = (git rev-parse main)

while ($true) {
    $currentCommit = (git rev-parse main)
    if ($currentCommit -ne $lastCommit) {
        $archivosCommit = git diff --name-only $lastCommit $currentCommit
        foreach ($file in $archivosCommit) {
            if (-not (Test-Path $file)) { continue }
            $pathAbs = (Resolve-Path $file).Path
            foreach ($pal in $palabrasBuscar) {
                if (Select-String -Path $file -Pattern $pal -SimpleMatch -Quiet) {
                    Add-Content $logAbs ("[{0}] Alerta: palabra '{1}' en {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$pal,$pathAbs)
                }
            }
            foreach ($pat in $patronesRegex) {
                if (Select-String -Path $file -Pattern $pat -Quiet) {
                    Add-Content $logAbs ("[{0}] Alerta: patrón '{1}' en {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$pat,$pathAbs)
                }
            }
        }
        $lastCommit = $currentCommit
    }
    Start-Sleep -Seconds 5
}

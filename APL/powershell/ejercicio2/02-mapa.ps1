#!/usr/bin/pwsh

<#
.SYNOPSIS
    Analiza rutas en una red de transporte público a partir de una matriz de adyacencia.

.DESCRIPTION
    Este script permite:
      - Identificar la estación "hub" (con más conexiones).
      - Calcular el camino más corto en tiempo entre dos estaciones usando el algoritmo de Dijkstra.
    El resultado se guarda en un archivo llamado "informe.<nombreArchivoEntrada>" en el mismo directorio.

.PARAMETER matriz
    Ruta del archivo de texto que contiene la matriz de adyacencia de la red de transporte.
    El archivo debe contener valores numéricos, en formato cuadrado y simétrico.

.PARAMETER hub
    Opción para determinar cuál estación es el hub de la red (la que tiene más conexiones directas).
    Obligatorio en el conjunto de parámetros HubTrue.

.PARAMETER camino
    Especifica las estaciones de inicio y fin para calcular el camino más corto.
    Se pasan como un array de 2 enteros, por ejemplo: -camino 1,4
    Obligatorio en el conjunto de parámetros CaminoTrue.

.PARAMETER separador
    Carácter utilizado como separador de columnas en la matriz de adyacencia.
    Por defecto es "|".
    Es opcional en ambos conjuntos de parámetros.

.EXAMPLE
    pwsh ./transporte.ps1 -hub -matriz mapa_transporte.txt
    Analiza el archivo "mapa_transporte.txt" y determina el hub de la red.

.EXAMPLE
    pwsh ./transporte.ps1 -camino 1,4 -matriz mapa_transporte.txt
    Analiza el archivo "mapa_transporte.txt" y calcula el camino más corto entre la estación 1 y 4.

.NOTES
    Compatible con PowerShell en Ubuntu.
#>

Param(
    [Parameter(Mandatory=$true, ParameterSetName="HubTrue")]
    [switch]$hub,

    [Parameter(Mandatory=$true, ParameterSetName="CaminoTrue")]
    [int[]]$camino,

    [Parameter(Mandatory=$true, ParameterSetName="HubTrue")]
    [Parameter(Mandatory=$true, ParameterSetName="CaminoTrue")]
    [string]$matriz,

    [Parameter(Mandatory=$false, ParameterSetName="HubTrue")]
    [Parameter(Mandatory=$false, ParameterSetName="CaminoTrue")]
    [string]$separador = "|",
   
    [Parameter(Mandatory=$true, ParameterSetName="HelpSet")]
    [switch]$Help
)

# --- Mostrar ayuda si se pasa -Help ---
if ($Help) {
    $scriptPath = $MyInvocation.MyCommand.Path
    $inside = $false
    Get-Content $scriptPath | ForEach-Object {
        if ($_ -match '^<#') { $inside = $true; return }
        if ($_ -match '^#>') { $inside = $false; return }
        if ($inside) { $_ }
    }
    exit
}
function Leer-Matriz {
    param($ruta, $sep)

    if (-not (Test-Path $ruta)) {
        throw "El archivo $ruta no existe."
    }

    $lineas = Get-Content $ruta
    $mat = @()
    foreach ($linea in $lineas) {
        $fila = $linea -split [regex]::Escape($sep) | ForEach-Object { $_.Trim() }
        if ($fila -contains "") {
            throw "La matriz contiene valores vacíos."
        }
        $mat += ,(@($fila | ForEach-Object { [double]$_ }))
    }

    $n = $mat.Count
    foreach ($fila in $mat) {
        if ($fila.Count -ne $n) {
            throw "La matriz no es cuadrada."
        }
    }

    for ($i=0; $i -lt $n; $i++) {
        for ($j=0; $j -lt $n; $j++) {
            if ($mat[$i][$j] -ne $mat[$j][$i]) {
                throw "La matriz no es simétrica."
            }
        }
    }

    return ,$mat
}

function Encontrar-Hub {
    param($mat)

    $n = $mat.Count
    $maxConex = -1
    $hubIndex = -1
    for ($i=0; $i -lt $n; $i++) {
        $conex = 0
        for ($j=0; $j -lt $n; $j++) {
            if ($i -ne $j -and $mat[$i][$j] -gt 0) {
                $conex++
            }
        }
        if ($conex -gt $maxConex) {
            $maxConex = $conex
            $hubIndex = $i
        }
    }

    return @{ Estacion = ($hubIndex+1); Conexiones = $maxConex }
}

function Dijkstra {
    param($mat, $origen, $destino)

    $n = $mat.Count
    $dist = @()
    $prev = @()
    $visitado = @()
    
    for ($i = 0; $i -lt $n; $i++) {
        $dist += [double]::PositiveInfinity
        $prev += -1
        $visitado += $false
    }
    
    $dist[$origen] = 0

    for ($k=0; $k -lt $n; $k++) {
        $u = -1
        $minDist = [double]::PositiveInfinity
        
        for ($i=0; $i -lt $n; $i++) {
            if (-not $visitado[$i] -and $dist[$i] -lt $minDist) {
                $minDist = $dist[$i]
                $u = $i
            }
        }
        
        if ($u -eq -1) { break }
        $visitado[$u] = $true

        for ($v=0; $v -lt $n; $v++) {
            if ($mat[$u][$v] -gt 0 -and -not $visitado[$v]) {
                $alt = $dist[$u] + $mat[$u][$v]
                if ($alt -lt $dist[$v]) {
                    $dist[$v] = $alt
                    $prev[$v] = $u
                }
            }
        }
    }

    if ($dist[$destino] -eq [double]::PositiveInfinity) {
        return @{ Tiempo = "No hay camino disponible"; Ruta = @() }
    }

    $ruta = @()
    $u = $destino
    while ($u -ne -1 -and $prev[$u] -ne $null) {
        $ruta = ,($u+1) + $ruta
        $u = $prev[$u]
    }
    # Agregar el nodo origen al inicio
    if ($u -eq $origen) {
        $ruta = ,($u+1) + $ruta
    }

    return @{ Tiempo = $dist[$destino]; Ruta = $ruta }
}

# --- Ejecución principal ---
$mat = Leer-Matriz -ruta $matriz -sep $separador
$nombreInforme = "informe.$([System.IO.Path]::GetFileName($matriz))"
$salida = @("## Informe de análisis de red de transporte")

if ($PSCmdlet.ParameterSetName -eq "HubTrue") {
    $hubInfo = Encontrar-Hub -mat $mat
    $salida += "**Hub de la red:** Estación $($hubInfo.Estacion) ($($hubInfo.Conexiones) conexiones)"
}
elseif ($PSCmdlet.ParameterSetName -eq "CaminoTrue") {
    if ($camino.Count -ne 2) {
        throw "Debe especificar exactamente dos estaciones: inicio y fin."
    }
    $inicio = $camino[0]-1
    $fin = $camino[1]-1
    $res = Dijkstra -mat $mat -origen $inicio -destino $fin
    $salida += "**Camino más corto: entre Estación $($camino[0]) y Estación $($camino[1]):**"
    $salida += "**Tiempo total:** $($res.Tiempo) minutos"
    $salida += "**Ruta:** " + ($res.Ruta -join " -> ")
}

$salida | Set-Content $nombreInforme
Write-Output "Informe generado: $nombreInforme"
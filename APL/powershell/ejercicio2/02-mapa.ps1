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
    Opción para determinar el camino más corto.
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
    [switch]$camino,

    [Parameter(Mandatory=$true, ParameterSetName="HubTrue")]
    [Parameter(Mandatory=$true, ParameterSetName="CaminoTrue")]
    [string]$matriz,

    [Parameter(Mandatory=$false, ParameterSetName="HubTrue")]
    [Parameter(Mandatory=$false, ParameterSetName="CaminoTrue")]
    [string]$separador = "|"
)

function Read-Matriz {
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

function Find-Hub {
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

function Dijsktra {
    param($mat)
    
    $n = $mat.Count
    
    # Inicializar matrices de distancia y next
    $dist = New-Object 'object[,]' $n, $n
    $next = New-Object 'object[,]' $n, $n
    
    # Copiar la matriz de adyacencia a dist
    for ($i = 0; $i -lt $n; $i++) {
        for ($j = 0; $j -lt $n; $j++) {
            if ($i -eq $j) {
                $dist[$i,$j] = 0
            }
            elseif ($mat[$i][$j] -eq 0) {
                $dist[$i,$j] = 999999  # Infinito
                $next[$i,$j] = -1
            }
            else {
                $dist[$i,$j] = $mat[$i][$j]
                $next[$i,$j] = $j
            }
        }
    }
    
    # Realizo los calculos de distancias mínimas
    for ($k = 0; $k -lt $n; $k++) {
        for ($i = 0; $i -lt $n; $i++) {
            for ($j = 0; $j -lt $n; $j++) {
                $suma = $dist[$i,$k] + $dist[$k,$j]
                if ($suma -lt $dist[$i,$j]) {
                    $dist[$i,$j] = $suma
                    $next[$i,$j] = $next[$i,$k]
                }
            }
        }
    }
    
    # Encontrar el camino más corto de todos
    $minDist = 999999
    for ($i = 0; $i -lt $n; $i++) {
        for ($j = $i + 1; $j -lt $n; $j++) {
            if ($next[$i,$j] -ne -1) {
                if ($dist[$i,$j] -lt $minDist) {
                    $minDist = $dist[$i,$j]
                }
            }
        }
    }
    
    # Recolectar todos los caminos con distancia mínima
    $resultados = @()
    for ($i = 0; $i -lt $n; $i++) {
        for ($j = $i + 1; $j -lt $n; $j++) {
            if ($next[$i,$j] -ne -1 -and $dist[$i,$j] -eq $minDist) {
                # Reconstruir el camino
                $ruta = @($i + 1)
                $actual = $i
                while ($actual -ne $j) {
                    $actual = $next[$actual,$j]
                    $ruta += ($actual + 1)
                }
                
                $resultados += @{
                    Origen = $i + 1
                    Destino = $j + 1
                    Tiempo = $dist[$i,$j]
                    Ruta = $ruta
                }
            }
        }
    }
    
    return $resultados
}

# --- Ejecución principal ---
$mat = Read-Matriz -ruta $matriz -sep $separador
$nombreInforme = "informe.$([System.IO.Path]::GetFileName($matriz))"
$salida = @("## Informe de análisis de red de transporte", "")

if ($PSCmdlet.ParameterSetName -eq "HubTrue") {
    $hubInfo = Find-Hub -mat $mat
    $salida += "**Hub de la red:** Estación $($hubInfo.Estacion) ($($hubInfo.Conexiones) conexiones)"
}
elseif ($PSCmdlet.ParameterSetName -eq "CaminoTrue") {
    $resultados = Dijsktra -mat $mat
    
    $salida += "**Camino/s más corto/s: **"
    $salida += ""
    foreach ($res in $resultados) {
        $salida += "**Entre Estación $($res.Origen) y Estación $($res.Destino):**"
        $salida += "**Tiempo total: $($res.Tiempo) minutos**"
        $salida += "**Ruta: " + ($res.Ruta -join " -> ") + "**"
        $salida += ""
    }
}

$salida | Set-Content $nombreInforme
Write-Output "Informe generado: $nombreInforme"
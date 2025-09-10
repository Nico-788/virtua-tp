Param(
    [Parameter(Mandatory=$true, ParameterSetName="shortestRoute")]
    [Parameter(Mandatory=$true, ParameterSetName="stationHub")]
    [string]$matriz,

    [Parameter(Mandatory=$true, ParameterSetName="stationHub")]
    [switch]$hub,

    [Parameter(Mandatory=$true, ParameterSetName="shortestRoute")]
    [switch]$camino,

    [Parameter(Mandatory=$false)]
    [string]$separador = "|"
)

# ==== Función para validar matriz ====
function Test-Matriz {
    param([object[][]]$mat)

    $n = $mat.Length

    # Verificar cuadrada
    foreach ($fila in $mat) {
        if ($fila.Length -ne $n) {
            throw "La matriz no es cuadrada."
        }
    }

    # Verificar simetría y valores numéricos
    for ($i=0; $i -lt $n; $i++) {
        for ($j=0; $j -lt $n; $j++) {
            $out = 0.0
            if (-not [double]::TryParse($mat[$i][$j], [ref]$out)) {
                throw "La matriz contiene un valor no numérico en ($i,$j)."
            }
            if ($mat[$i][$j] -ne $mat[$j][$i]) {
                throw "La matriz no es simétrica en ($i,$j)."
            }
        }
    }
    return $true
}

# ==== Función para encontrar el hub ====
function Find-Hub {
    param([object[][]]$mat)

    $n = $mat.Length
    $maxConex = 0
    $hub = 0

    for ($i=0; $i -lt $n; $i++) {
        $conex = 0
        for ($j=0; $j -lt $n; $j++) {
            if ($i -ne $j -and [double]$mat[$i][$j] -gt 0) {
                $conex++
            }
        }
        if ($conex -gt $maxConex) {
            $maxConex = $conex
            $hub = $i + 1
        }
    }

    return "Hub de la red: Estación $hub ($maxConex conexiones)"
}

# ==== Función Dijkstra ====
function Dijkstra {
    param([object[][]]$mat, [int]$origen, [int]$destino)

    $n = $mat.Length
    $dist = @()
    $prev = @()
    $visitado = @()
    for ($i=0; $i -lt $n; $i++) {
        $dist += 999999
        $prev += -1
        $visitado += $false
    }

    $dist[$origen] = 0

    for ($c=0; $c -lt $n; $c++) {
        # Buscar nodo no visitado con menor distancia
        $min = 999999
        $u = -1
        for ($i=0; $i -lt $n; $i++) {
            if (-not $visitado[$i] -and $dist[$i] -lt $min) {
                $min = $dist[$i]
                $u = $i
            }
        }

        if ($u -eq -1) { break }
        $visitado[$u] = $true

        # Actualizar vecinos
        for ($v=0; $v -lt $n; $v++) {
            if ($mat[$u][$v] -gt 0 -and -not $visitado[$v]) {
                $alt = $dist[$u] + [double]$mat[$u][$v]
                if ($alt -lt $dist[$v]) {
                    $dist[$v] = $alt
                    $prev[$v] = $u
                }
            }
        }
    }

    # Reconstruir camino
    $ruta = @()
    $u = $destino
    while ($u -ne -1) {
        $ruta = ,($u+1) + $ruta
        $u = $prev[$u]
    }

    return @{
        Tiempo = $dist[$destino]
        Ruta = ($ruta -join " -> ")
    }
}

# ==== MAIN ====
# Leer archivo y construir matriz
$lineas = Get-Content $matriz
$matrizDatos = @()
foreach ($linea in $lineas) {
    $fila = $linea.Split($separador)
    $matrizDatos += ,@($fila)   # forzamos que cada fila sea un array
}

# Validar
Test-Matriz $matrizDatos | Out-Null

# Salida informe
$nombreArchivo = Split-Path $matriz -Leaf
$directorio = Split-Path $matriz -Parent
$salida = Join-Path $directorio "informe.$nombreArchivo"

$resultado = "## Informe de análisis de red de transporte`n"

if ($hub) {
    $resultado += (Find-Hub $matrizDatos)
}
elseif ($camino) {
    # Ejemplo: Estación 1 hasta Estación N
    $res = Dijkstra $matrizDatos 0 ($matrizDatos.Length-1)
    $resultado += "**Camino más corto: entre Estación 1 y Estación $($matrizDatos.Length):**`n"
    $resultado += "**Tiempo total:** $($res.Tiempo) minutos`n"
    $resultado += "**Ruta:** $($res.Ruta)`n"
}

# Guardar informe
$resultado | Out-File -FilePath $salida -Encoding utf8
Write-Output "Informe generado en: $salida"
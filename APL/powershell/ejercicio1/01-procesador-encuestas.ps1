<#
.SYNOPSIS
    Script de procesador de encuestas
.DESCRIPTION
    Procesa archivos .txt con encuestas en formato:
    ID_ENCUESTA|FECHA|CANAL|TIEMPO_RESPUESTA|NOTA_SATISFACCION
.EXAMPLE
    .\01-procesador-encuestas.ps1 -Directorio C:\encuestas -Pantalla
.INPUTS
    -Directorio: Ruta del directorio con los .txt
    -Archivo: Ruta completa del archivo JSON de salida (No usar con -Pantalla)
    -Pantalla: Muestra salida por pantalla (No usar con -Archivo)
.OUTPUTS
    El resultado por pantalla o un archivo JSON de salida
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Directorio,
    [string]$Archivo = $null,
    [switch]$Pantalla
)

if (-not (Test-Path $Directorio -PathType Container)) {
    Write-Error "Error: El directorio '$Directorio' no existe o no es un directorio."
    exit 1
}

# Validamos que no se use Archivo y Pantalla al mismo tiempo
if ($Archivo -and $Pantalla) {
    Write-Error "Error: No se puede usar -Archivo y -Pantalla al mismo tiempo."
    exit 1
}

# Validamos que se especifique al menos una opción de salida
if (-not $Archivo -and -not $Pantalla) {
    Write-Error "Error: Debe especificar -Archivo o -Pantalla para la salida."
    exit 1
}

# Si se especifica archivo, validamos la extensión
if ($Archivo -and $Archivo -notmatch '\.json$') {
    Write-Error "Error: El archivo de salida debe tener extensión .json"
    exit 1
}

# Cargamos archivos con extensión .txt
$archivos = Get-ChildItem -Path $Directorio | Where-Object { -not $_.PSIsContainer -and $_.Name -like "*.txt" }

if (-not $archivos -or $archivos.Count -eq 0) {
    Write-Error "Error: No se encontraron archivos .txt en $Directorio"
    exit 1
}

# Procesamos los datos
$resultado = @{}

foreach ($file in $archivos) {
    Get-Content -LiteralPath $file | ForEach-Object {
        $campos = $_ -split "\|"
        if ($campos.Count -ge 5) {
            $fecha      = $campos[1] -split " " | Select-Object -First 1
            $canal      = $campos[2]
            $tiempo     = [double]$campos[3]
            $nota       = [double]$campos[4]

            $key = "$fecha|$canal"

            if (-not $resultado.ContainsKey($key)) {
                $resultado[$key] = [PSCustomObject]@{
                    Fecha       = $fecha
                    Canal       = $canal
                    TiempoTotal = 0
                    NotaTotal   = 0
                    Cantidad    = 0
                }
            }

            $resultado[$key].TiempoTotal += $tiempo
            $resultado[$key].NotaTotal   += $nota
            $resultado[$key].Cantidad    += 1
        }
    }
}


# Transformamos a formato JSON
$agrupado = @{}

foreach ($item in $resultado.Values) {
    if (-not $agrupado.ContainsKey($item.Fecha)) {
        $agrupado[$item.Fecha] = @{}
    }
    
    $agrupado[$item.Fecha][$item.Canal] = @{
        tiempo_respuesta_promedio   = [Math]::Round($item.TiempoTotal / $item.Cantidad, 2)
        nota_satisfaccion_promedio  = [Math]::Round($item.NotaTotal / $item.Cantidad, 2)
    }
}

# Verificamos como hay que mostrarlo
if ($Pantalla) {
    $agrupado | ConvertTo-Json -Depth 5 | Write-Output
} elseif ($Archivo) {
    $json = $agrupado | ConvertTo-Json -Depth 5
    $json | Out-File -FilePath $Archivo -Encoding UTF8
    Write-Host "Salida guardada en $Archivo"
}
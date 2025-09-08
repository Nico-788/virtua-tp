
Param(
    [Parameter(Mandatory=$true, ParameterSetName="FileOut")]
    [Parameter(Mandatory=$true, ParameterSetName="ScreenOut")]
    [string]
    $directorio,

    [Parameter(Mandatory=$true, ParameterSetName="FileOut")]
    [string]
    $archivo,

    [Parameter(Mandatory=$true, ParameterSetName="ScreenOut")]
    [switch]
    $pantalla
)

if (-not (Test-Path $directorio -PathType Container)) {
    throw "El directorio '$directorio' no existe."
}

$resultados = @{}

Get-ChildItem -Path $directorio -Filter "*.txt" | ForEach-Object {
    $archivoEncuestas = $_.FullName

    Get-Content $archivoEncuestas | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { return } #en caso de haber lineas vacías

        $campos = $_ -split "\|"
        if ($campos.Count -ne 5) { return } #pregunto si se hizo bien el split.

        $fecha     = $campos[1]
        $canal     = $campos[2]
        $tiempo    = [double]$campos[3]
        $nota      = [int]$campos[4]

        $dia = ($fecha -split " ")[0]   #saco solo la fecha

        if (-not $resultados.ContainsKey($dia)) {
            $resultados[$dia] = @{}
        }
        if (-not $resultados[$dia].ContainsKey($canal)) {
            $resultados[$dia][$canal] = @{
                tiempos = @()   #creo listas dentro de listas
                notas   = @()   #nos va a servir para el average del calculo de promedios
            }
        }

        $resultados[$dia][$canal].tiempos += $tiempo
        $resultados[$dia][$canal].notas   += $nota
    }
}

$salida = @{}

foreach ($dia in $resultados.Keys) {
    $salida[$dia] = @{}

    foreach ($canal in $resultados[$dia].Keys) {
        $tiempos = $resultados[$dia][$canal].tiempos #paso las listas a las variable tiempos
        $notas   = $resultados[$dia][$canal].notas

        $salida[$dia][$canal] = @{
            tiempo_respuesta_promedio = [math]::Round(($tiempos | Measure-Object -Average).Average, 2)
            nota_satisfaccion_promedio = [math]::Round(($notas | Measure-Object -Average).Average, 2)
        }
    }
}

$json = $salida | ConvertTo-Json -Depth 5

if ($pantalla) {
    Write-Output $json
}
elseif ($archivo) {
    $dir = Split-Path -Parent $archivo

    if (-not (Test-Path $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }

    $json | Out-File -FilePath $archivo -Encoding utf8
    Write-Host "Resultados guardados en $archivo"
}
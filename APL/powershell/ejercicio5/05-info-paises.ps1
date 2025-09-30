<#
.SYNOPSIS
    Muestra la información de países obtenida desde la API REST Countries.

.DESCRIPTION
    Consulta información de uno o varios países utilizando la API:
        https://restcountries.com/v3.1/name/{nombre}

    Si se especifica el parámetro -ttl:
        - Se guarda en un archivo cachePaises.json el resultado de la API con un tiempo de vida.
        - Si el país ya está en caché y el TTL sigue vigente, se muestra directamente.
        - Si está vencido, se elimina y se consulta la API.
        - Si está en caché pero con nuevo TTL, se actualiza.

    Si NO se especifica -ttl:
        - Se consulta primero en caché por coincidencias y se muestran.
        - Si no está en caché, se consulta en la API y se muestra.
        - Los resultados obtenidos de la API en este modo NO se guardan en caché.

.PARAMETER nombre
    País o países a consultar. Se aceptan múltiples valores, separados por coma o espacio.

.PARAMETER ttl
    (Opcional) Tiempo de vida en segundos de la información en caché.

.EXAMPLE
    ./Ejercicio5.ps1 -nombre spain,france
    Consulta España y Francia. Usa caché si existen, pero no guarda nuevas respuestas.

.EXAMPLE
    ./Ejercicio5.ps1 -nombre argentina -ttl 120
    Consulta Argentina. Guarda el resultado en caché por 120 segundos.
#>
param(
    [Parameter(Mandatory = $true)]
    [string[]]$nombre,

    [Parameter(Mandatory = $false)]
    [int]$ttl
)

$cacheFile = "cachePaises.json"

# Crear cache vacío si no existe
if (-not (Test-Path $cacheFile)) {
    @{} | ConvertTo-Json | Set-Content $cacheFile
}

# Función para convertir JSON a Hashtable
function ConvertFrom-JsonToHashtable {
    param([string]$json)
    return (ConvertFrom-Json -InputObject $json -AsHashtable)
}

# Cargar cache como Hashtable
$cache = ConvertFrom-JsonToHashtable (Get-Content $cacheFile -Raw)
if ($null -eq $cache) {
    $cache = @{}
}

$now = Get-Date
$cacheChanged = $false

foreach ($n in $nombre) {
    $foundInCache = $false

    if ($cache.ContainsKey($n)) {
        $entry = $cache[$n]
        $expiry = Get-Date $entry.expiry

        if ($expiry -gt $now) {
            # Cache válido
            Write-Host "$n encontrado en caché:"
            Write-Host "   País: $($entry.data.nombre)"
            Write-Host "   Capital: $($entry.data.capital -join ', ')"
            Write-Host "   Región: $($entry.data.region)"
            Write-Host "   Población: $($entry.data.population)"

            $foundInCache = $true

            if ($PSBoundParameters.ContainsKey('ttl')) {
                # Si se pasó ttl, actualizar expiración
                $cache[$n].expiry = ($now).AddSeconds($ttl)
                $cacheChanged = $true
                Write-Host "TTL actualizado para $n"
            }
        }
        else {
            # Cache expirado → borrar
            Write-Host "Cache expirado para $n, borrando..."
            $cache.Remove($n)
            $cacheChanged = $true
        }
    }

    if (-not $foundInCache) {
        # Consultar API
        Write-Host "Consultando API para $n..."
        try {
            $result = Invoke-RestMethod -Uri "https://restcountries.com/v3.1/translation/$n"
            $pais = $result[0]

            Write-Host "Resultado API:"
            Write-Host "   País: $($pais.name.common)"
            Write-Host "   Capital: $($pais.capital -join ', ')"
            Write-Host "   Región: $($pais.region)"
            Write-Host "   Población: $($pais.population)"

            if ($PSBoundParameters.ContainsKey('ttl')) {
                # Guardar en cache
                $dataParaCache = @{
                    nombre    = $pais.name.common
                    capital   = if ($pais.capital) { $pais.capital -join ', ' } else { 'N/A' }
                    region    = if ($pais.region) { $pais.region } else { 'N/A' }
                    population = if ($pais.population) { $pais.population } else { 'N/A' }
                }
                $expiry = ($now).AddSeconds($ttl)
                $cache[$n] = @{ data = $dataParaCache; expiry = $expiry }
                $cacheChanged = $true
            }
        }
        catch {
            Write-Host "Error al consultar API para $n"
        }
    }
}

# Guardar cache solo si hubo cambios
if ($cacheChanged) {
    $cache | ConvertTo-Json -Depth 10 | Set-Content $cacheFile
}

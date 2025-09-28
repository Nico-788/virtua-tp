<#
.SYNOPSIS
    Script para consultar información de países con caché.

.DESCRIPTION
    Este script consulta información de uno o varios países usando la API pública 
    de RestCountries. Los resultados se almacenan en un archivo de caché (JSON) 
    para evitar múltiples llamadas a la API. El tiempo de vida del caché se define 
    mediante el parámetro TTL (time-to-live).

.EXAMPLE
    .\ejercicio5.ps1 -nombre "Argentina","Chile" -ttl 60
    Consulta la información de Argentina y Chile, manteniendo los datos en caché 
    durante 60 segundos.

.INPUTS
    -nombre: Nombre o lista de nombres de países a consultar.
    -ttl:    Tiempo en segundos para considerar válido el caché.

.OUTPUTS
    Muestra en consola los datos básicos de cada país:
    - Nombre
    - Capital
    - Región
    - Población
    - Moneda
#>

param(
    [Parameter(Mandatory = $true)]
    [string[]] $nombre,   # uno o más países
    
    [Parameter(Mandatory = $true)]
    [int] $ttl            # tiempo en segundos para mantener el cache
)

# Validar TTL
if ($ttl -le 0) {
    Write-Error "El parámetro -ttl debe ser un número mayor a 0."
    exit 1
}

# Archivo de caché en carpeta temporal
$cacheFile = Join-Path -Path $env:TEMP -ChildPath "ejercicio5_cache.json"

# Inicializar caché
try {
    if (-not (Test-Path $cacheFile)) {
        @{} | ConvertTo-Json | Set-Content $cacheFile -ErrorAction Stop
    }
    $cache = Get-Content $cacheFile | ConvertFrom-Json -AsHashtable
}
catch {
    Write-Error "Error al cargar o inicializar el caché: $_"
    exit 1
}

foreach ($country in $nombre) {
    $countryKey = $country.ToLower()
    $useCache = $false
    $data = $null

    if ($cache.ContainsKey($countryKey)) {
        $entry = $cache[$countryKey]
        $lastUpdate = Get-Date $entry.lastUpdate
        if ((New-TimeSpan -Start $lastUpdate -End (Get-Date)).TotalSeconds -lt $ttl) {
            $useCache = $true
            $data = $entry.data
            Write-Host "[CACHE] Usando datos guardados para $country"
        }
    }

    if (-not $useCache) {
        try {
            $url = "https://restcountries.com/v3.1/name/$country"
            $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop

            if ($null -ne $response) {
                # Tomamos el primer resultado
                $data = [PSCustomObject]@{
                    Name      = $response[0].name.common
                    Capital   = ($response[0].capital -join ", ")
                    Region    = $response[0].region
                    Population= $response[0].population
                    Currency  = ($response[0].currencies.PSObject.Properties | ForEach-Object { "$($_.Value.name) ($($_.Name))" }) -join ", "
                }

                # Guardamos en caché
                $cache[$countryKey] = @{
                    lastUpdate = (Get-Date).ToString("o")
                    data       = $data
                }

                Write-Host "[API] Datos actualizados desde la API para $country"
            }
        }
        catch {
            Write-Error "Error al consultar API para ${country} : $_"
            continue
        }
    }

    $resText = "    País: {0}
    Capital: {1}
    Región: {2}
    Población: {3}
    Moneda: {4}
    "

    # Mostrar resultados
    Write-Output ($resText -f `
        $data.Name, $data.Capital, $data.Region, $data.Population, $data.Currency)
}   

# Guardar caché actualizado
try {
    $cache | ConvertTo-Json -Depth 5 | Set-Content $cacheFile -ErrorAction Stop
}
catch {
    Write-Error "Error al guardar el archivo de caché: $_"
}

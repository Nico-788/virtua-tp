param(
    [Parameter(Mandatory = $true)]
    [string[]] $nombre,   # uno o más países
    
    [Parameter(Mandatory = $true)]
    [int] $ttl            # tiempo en segundos para mantener el cache
)

# Archivo de caché
$cacheFile = "cache.json"

# Si no existe, lo inicializamos
if (-not (Test-Path $cacheFile)) {
    @{} | ConvertTo-Json | Set-Content $cacheFile
}

# Cargar caché como objeto hashtable
$cache = Get-Content $cacheFile | ConvertFrom-Json -AsHashtable

foreach ($country in $nombre) {
    $countryKey = $country.ToLower()

    $useCache = $false
    if ($cache.ContainsKey($countryKey)) {
        $entry = $cache[$countryKey]
        $lastUpdate = Get-Date $entry.lastUpdate
        if ((New-TimeSpan -Start $lastUpdate -End (Get-Date)).TotalSeconds -lt $ttl) {
            $useCache = $true
            $data = $entry.data
        }
    }

    if (-not $useCache) {
        try {
            $url = "https://restcountries.com/v3.1/name/$country"
            $response = Invoke-RestMethod -Uri $url -Method Get

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
            }
        }
        catch {
            Write-Host "Error al consultar API para ${country} : $_"
            continue
        }
    }

    # Mostrar resultados
    Write-Output ("País: {0} Capital: {1} Región: {2} Población: {3} Moneda: {4}" -f `
        $data.Name, $data.Capital, $data.Region, $data.Population, $data.Currency)
}

# Guardar caché actualizado
$cache | ConvertTo-Json -Depth 5 | Set-Content $cacheFile

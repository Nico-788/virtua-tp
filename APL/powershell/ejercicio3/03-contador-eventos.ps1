Param(

    [Parameter(Mandatory=$true)]
    [string]
    $directorio,
    
    [Parameter(Mandatory=$true)]
    [string[]]
    $palabras
)

$ocurrenciasPorPalabras=@{}

Get-ChildItem -Filter "*.log" | ForEach-Object {
    $currentLog = Get-Content $_.FullName
    foreach ($currentWord in $palabras) {
        $coincidenciasArchivo = 0
        
        foreach ($linea in $currentLog) {
            if ($linea -match $currentWord) {
                $coincidencias = ($linea -split $currentWord, 0, "SimpleMatch").Count - 1
                $coincidenciasArchivo += $coincidencias
            }
        }
        
        if ($coincidenciasArchivo -gt 0) {
            if (-not $ocurrenciasPorPalabras.ContainsKey($currentWord)) {
                $ocurrenciasPorPalabras[$currentWord] = 0
            }
            $ocurrenciasPorPalabras[$currentWord] += $coincidenciasArchivo
        }
    }
}

foreach ($ocurrenceKey in $ocurrenciasPorPalabras.Keys) {
    Write-Host "$ocurrenceKey : $($ocurrenciasPorPalabras[$ocurrenceKey]) ocurrencia/s" -ForegroundColor Green
}
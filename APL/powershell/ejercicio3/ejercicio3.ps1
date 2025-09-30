<#
.Synopsis
   Script de búsqueda de patrones en archivos de log
.DESCRIPTION
   Este script busca una serie de palabras pasadas como parámetros dentro de todos los archivos de extensión .log ubicados en el directorio pasado como parámetro
.EXAMPLE
   ejercicio3.ps1 -directorio "./Mi directorio" -palabras usb,hola
.INPUTS
   -directorio: Directorio donde se realizará la búsqueda
   -palabras: Array de palabras que deberán buscarse en los archivos de log
.OUTPUTS
   Muestra la cantidad de apariciones de cada palabra en el contenido de los archivos de log encontrados.
#>

Param(
    [Parameter(Mandatory=$true)]
    [String]
    $directorio,
    [Parameter(Mandatory=$true)]
    [String[]]
    $palabras
)

if((Test-Path -Path $directorio -PathType Container) -eq $false){
    Write-Error "El directorio ingresado no existe"
}

$archivos = Get-ChildItem -Path $directorio -Recurse -File | Where-Object { $_.Name -match "^.*\.log$" } | Select-Object -ExpandProperty FullName
$contenido = Get-Content $archivos

foreach($pal in $palabras){
    $apariciones = ($contenido | Select-String -Pattern $pal -AllMatches).Matches.Count
    Write-Host "${pal}: $apariciones"
}

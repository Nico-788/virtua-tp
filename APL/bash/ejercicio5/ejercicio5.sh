#!/bin/bash

opciones=$(getopt -o n:t:h --l help,nombre:,ttl: -- "$@" 2> /dev/null)

if [ $? != '0' ]
then 
    echo "Parámetros incorrectos, utilice -h o --help para ayuda"
    exit 1
fi

eval set -- "$opciones"

NOMBRES=""
TTL=0
AYUDA=false

while true
do
    case "$1" in 
        -n | --nombre)
            NOMBRES="$2"
            shift 2
            ;;
        -t | --ttl)
            TTL=$2
            shift 2
            ;;
        -h | --help)
            AYUDA=true
            shift 
            ;;
        --)
            break
            ;;
        *)
            echo Error
            exit 1
            ;;
    esac
done

IFS=','
read -a paises <<< "$NOMBRES"
unset IFS

archivos=$(ls | grep "CACHE.*\.tmp")

#Eliminamos las cachés que ya no sirven
for archivo in ${archivos[@]}
do
    archTtl="${archivo//CACHE/ttl}"
    ttlArch=$(cat "$archTtl")
    tiempo=$(stat --format=%w "$(realpath($archivo))")
    echo $tiempo
    if [ $tiempo >= $ttlArch ]
    then
        rm "$archivo"
        rm "$archTtl"
    fi
done

numeros=$(echo "$archivos" | grep -o -E '[0-9]+')
numerosEnOrden=$(echo "$numeros" | sort -n -r)
max=$(echo "$numerosEnOrden" | head -n 1)


exit 0

for pais in ${paises[@]}
do
    json=$(curl "https://restcountries.com/v3.1/name/$pais" | jq "{nombre: .[0].name.nativeName.spa.common, capital: .[0].capital, region: .[0].region, poblacion: .[0].population, moneda : .[0].currencies}")
    nombre=$(echo $json | jq '.nombre')
    nombre="${nombre//\"/}"
    capital=$(echo $json | jq '.capital')
    capital=$(echo $capital | jq 'join(",")')
    capital="${capital//\"/}"
    region=$(echo $json | jq '.region')
    region="${region//\"/}"
    poblacion=$(echo $json | jq '.poblacion')
    moneda=$(echo $json | jq '.moneda')
    moneda=$(echo $moneda | jq 'to_entries | {codigo: .[].key, nombre : .[].value.name}')
    codigo=$(echo $moneda | jq '.codigo')
    codigo="${codigo//\"/}"
    nombreMon=$(echo $moneda | jq '.nombre')
    nombreMon="${nombreMon//\"/}"
    moneda="$nombreMon ($codigo)"

    echo "País: $nombre"
    echo "Capital: $capital"
    echo "Región: $region"
    echo "Población: $poblacion"
    echo "Moneda: $moneda"



done


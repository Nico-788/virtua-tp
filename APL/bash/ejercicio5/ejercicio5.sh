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

if [ $TTL -lt 1 ]
then    
    echo "Ingrese un TTL válido"
    exit 1
fi

IFS=','
read -a paises <<< "$NOMBRES"
unset IFS

archivos=$(find ./ -maxdepth 1 -regex './CACHE[0-9]*.cache')

#Eliminamos las cachés que ya no sirven
for archivo in ${archivos[@]}
do
    archTtl="${archivo//CACHE/TTL}"
    ttlArch=$(cat "$archTtl")
    tiempoArch=$(date -r "$(realpath "$archivo")" +"%s")
    tiempoAct=$(date +"%s")
    ((tiempo=$tiempoAct - $tiempoArch))
    if [ $tiempo -ge $ttlArch ]
    then
        rm "$archivo"
        rm "$archTtl"
    else
        ((tiempo = $ttlArch - $tiempo))
        echo $tiempo > "$archTtl"
    fi
done

archivos=$(find ./ -maxdepth 1 -regex './CACHE[0-9]+.cache')
numeros=$(echo "$archivos" | grep -o -E '[0-9]+')
numerosEnOrden=$(echo "$numeros" | sort -n -r)
max=$(echo "$numerosEnOrden" | head -n 1)
((nuevo=$max + 1))
ARCH_CACHE="./CACHE$nuevo.cache"
TTL_CACHE="./TTL$nuevo.cache"

if [ ! -z "$archivos" ]
then
    for i in ${!paises[@]}
    do
        for arch in ${archivos[@]}
        do
            coincidencia=$(grep "${paises[i]}" "$arch")

            if [ -n "$coincidencia" ]
            then
                nombre=$(echo $coincidencia | jq '.nombre.common')
                nombre="${nombre//\"/}"
                capital=$(echo $coincidencia | jq '.capital')
                capital=$(echo $capital | jq 'join(",")')
                capital="${capital//\"/}"
                region=$(echo $coincidencia | jq '.region')
                region="${region//\"/}"
                poblacion=$(echo $coincidencia | jq '.poblacion')
                moneda=$(echo $coincidencia | jq '.moneda')
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

                unset paises[i]
                break
            fi
        done
    done
fi

for pais in ${paises[@]}
do
    json=$(curl --silent "https://restcountries.com/v3.1/name/$pais" | jq "{nombre: .[0].name, capital: .[0].capital, region: .[0].region, poblacion: .[0].population, moneda : .[0].currencies}")
    nombre=$(echo $json | jq '.nombre.common')
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

    echo $json >> "$ARCH_CACHE"
    echo "País: $nombre"
    echo "Capital: $capital"
    echo "Región: $region"
    echo "Población: $poblacion"
    echo "Moneda: $moneda"
done

if [ ${#paises[@]} -gt 0 ]
then
    echo "$TTL" > "$TTL_CACHE"
fi

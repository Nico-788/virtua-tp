BEGIN {
    FS = "|"
}

NR >= 1 {
    id = $1
    fecha = substr($2, 0, index($2, " ") - 1)
    canal = $3
    tiempoRes = $4
    satisfaccion = $5
    
    contadores[fecha][canal] += 1
    acumuladoresSatisfaccion[fecha][canal] += satisfaccion
    acumuladoresTiempoRes[fecha][canal] += tiempoRes
}

END{
    for (fecha in contadores){
        for(canal in contadores[fecha]){
            print fecha, canal, acumuladoresSatisfaccion[fecha][canal] / contadores[fecha][canal], acumuladoresTiempoRes[fecha][canal] / contadores[fecha][canal]
        }
    }
}
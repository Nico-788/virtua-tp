BEGIN {
    FS = "|"
    PROCINFO["sorted_in"] = "@ind_str_asc"
}

{
    fecha = $2
    sub(/ .*/, "", fecha)  #saco la hora --> sub'/<palabra>/, <reemplazo>, <variable>'
    
    tiempoRespuesta[fecha " " $3] += $4
    notaSatisfaccion[fecha " " $3] += $5
    cantidadDatosFecha[fecha " " $3]++
}

END {
    for(indice in tiempoRespuesta) {
        anteriorFecha = indice;
        break;
    }
    sub(/ .*/, "", anteriorFecha)
    
    # Crear arrays para agrupar por fecha y determinar últimos elementos
    for (fechaTipo in tiempoRespuesta) {
        split(fechaTipo, partFechaTipo, " ")
        fecha = partFechaTipo[1]
        tipo = partFechaTipo[2]
        fechas[fecha][tipo] = fechaTipo
    }
    
    print "{"
    
    # Contar fechas para saber cuál es la última
    numFechas = 0
    for (f in fechas) numFechas++
    
    contadorFechas = 0
    for (fecha in fechas) {
        contadorFechas++
        print "\t\"" fecha "\": {"
        
        # Contar tipos para esta fecha para saber cuál es el último
        numTipos = 0
        for (t in fechas[fecha]) numTipos++
        
        contadorTipos = 0
        for (tipo in fechas[fecha]) {
            contadorTipos++
            fechaTipo = fechas[fecha][tipo]
            
            promedioRespuesta = tiempoRespuesta[fechaTipo] / cantidadDatosFecha[fechaTipo]
            promedioNota = notaSatisfaccion[fechaTipo] / cantidadDatosFecha[fechaTipo]
            
            printf "\t\t\"%s\": {\n\t\t\t\"tiempo_respuesta_promedio\": %s,\n\t\t\t\"nota_satisfaccion_promedio\": %s\n\t\t\t}", tipo, promedioRespuesta, promedioNota
            
            # Solo agregar coma si no es el último tipo de esta fecha
            if (contadorTipos < numTipos) {
                print ","
            } else {
                print ""
            }
        }
        
        # Solo agregar coma después del cierre de fecha si no es la última fecha
        if (contadorFechas < numFechas) {
            print "\t},"
        } else {
            print "\t}"
        }
    }
    print "}"

}
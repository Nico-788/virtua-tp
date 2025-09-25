BEGIN {
    FS = "|"
    # Ordenamos claves en forma ascendente por fecha
    PROCINFO["sorted_in"] = "@ind_str_asc"
}

{
    fecha = $2
    sub(/ .*/, "", fecha)  # Eliminamos la hora de la fecha
    
    key = fecha " " $3
    tiempoRespuesta[key]     += $4
    notaSatisfaccion[key]    += $5
    cantidadDatosFecha[key]++
}

END {
    print "{"

    # Contamos fechas
    numFechas = 0
    for (f in tiempoRespuesta) {
        split(f, parts, " ")
        fechas[parts[1]][parts[2]] = f
    }
    for (f in fechas) {
        numFechas++
    }

    contadorFechas = 0
    for (fecha in fechas) {
        contadorFechas++
        printf "\t\"%s\": {\n", fecha

        # Contamos tipos dentro de cada fecha
        numTipos = 0
        for (t in fechas[fecha]) numTipos++

        contadorTipos = 0
        for (tipo in fechas[fecha]) {
            contadorTipos++
            fechaTipo = fechas[fecha][tipo]

            # Evitamos la division por cero
            if (cantidadDatosFecha[fechaTipo] > 0) {
                promedioRespuesta = tiempoRespuesta[fechaTipo] / cantidadDatosFecha[fechaTipo]
                promedioNota = notaSatisfaccion[fechaTipo] / cantidadDatosFecha[fechaTipo]
            } else {
                promedioRespuesta = 0
                promedioNota = 0
            }

            printf "\t\t\"%s\": {\n", tipo
            printf "\t\t\t\"tiempo_respuesta_promedio\": %.2f,\n", promedioRespuesta
            printf "\t\t\t\"nota_satisfaccion_promedio\": %.2f\n", promedioNota
            printf "\t\t}"

            # Agregamos coma si no es el último tipo
            if (contadorTipos < numTipos) {
                print ","
            } else {
                print ""
            }
        }

        # Agregamos coma si no es la última fecha
        if (contadorFechas < numFechas) {
            print "\t},"
        } else {
            print "\t}"
        }
    }

    print "}"
}

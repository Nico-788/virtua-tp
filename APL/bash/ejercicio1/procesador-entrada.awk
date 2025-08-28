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

    print "{"
    print "\t\""anteriorFecha"\": {"
    for (fechaTipo in tiempoRespuesta) {

        split(fechaTipo, partFechaTipo, " ")

        if(anteriorFecha != partFechaTipo[1]) {
            print "\t},"
            print "\t\"" partFechaTipo[1]"\": {"
            anteriorFecha =  partFechaTipo[1]
        }

        promedioRespuesta = tiempoRespuesta[fechaTipo] / cantidadDatosFecha[fechaTipo]
        promedioNota = notaSatisfaccion[fechaTipo] / cantidadDatosFecha[fechaTipo]

        print "\t\t\"" partFechaTipo[2]"\": {\n\t\t\t\"tiempo_respuesta_promedio\": "promedioRespuesta ",\n\t\t\t\"nota_satisfaccion_promedio\": "promedioNota "\n\t\t\t},"
    }
    print "\t}"
    print "}"
}
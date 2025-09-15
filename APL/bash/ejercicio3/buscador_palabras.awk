BEGIN{
    FS = " "
    IGNORECASE = 1
    split(palabras, palabrasBuscar, ",")
    for(i in palabrasBuscar){
        apariciones[i] = 0
    }
}

{


    for(i = 1; i <= NF; i++){
        for(j = 1; j <= length(palabrasBuscar); j++){
            if ($i == palabrasBuscar[j]){
                apariciones[j] += 1
            }
        }
    }
}

END{
    for (i in palabrasBuscar){
        print palabrasBuscar[i], ":", apariciones[i] 
    }
}
BEGIN {
    PROCINFO["sorted_in"] = "@ind_str_asc"
    IGNORECASE=1

    cantPalabras=split(strPalabras, palabrasValidar, ",")

    for(i=1; i<=cantPalabras;i++) {
        arrayAsPalabras[palabrasValidar[i]]=0
    }
}

{
    for(palabraActual in arrayAsPalabras) {
        if($0 ~ palabraActual) {
            arrayAsPalabras[palabraActual]++
            break;
        }
    }
}

END {
    
    for(palabraActual in arrayAsPalabras) {
        print palabraActual ": " arrayAsPalabras[palabraActual] "\n"
    }
}
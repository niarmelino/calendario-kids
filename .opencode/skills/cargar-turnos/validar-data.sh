#!/usr/bin/env bash
# Revisa que data.json tenga la forma que espera la pagina.
# Cada mensaje dice que esta mal y como se arreglarlo, en español llano.
#
#   bash validar-data.sh              revisa data.json del repo
#   bash validar-data.sh otra.json    revisa otro archivo
#
# Sale con codigo 0 si se puede publicar y 1 si hay problemas.
# Los AVISO no bloquean la carga, los PROBLEMA si.
#
# Solo necesita bash, awk y las utilidades de texto basicas.

set -u

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$DIR_SCRIPT/../../.." && pwd)"
ARCHIVO="${1:-$RAIZ/data.json}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

AVISOS="$TMP/avisos"
PROBLEMAS="$TMP/problemas"
MAPA="$TMP/mapa"
: > "$AVISOS"
: > "$PROBLEMAS"

# ---------------------------------------------------------------- como esta
# guardado el archivo

fallar() { printf 'PROBLEMA  %s\n          -> %s\n\n' "$1" "$2" >> "$PROBLEMAS"; }
avisar() { printf 'AVISO     %s\n          -> %s\n\n' "$1" "$2" >> "$AVISOS"; }

if [[ ! -f "$ARCHIVO" ]]; then
  echo "Revisando $ARCHIVO"
  echo
  printf 'PROBLEMA  No se encontró el archivo %s.\n' "$ARCHIVO"
  echo '          -> Verificá que exista y que esté en la misma carpeta que index.html.'
  echo
  echo 'Falta corregir 1 problema antes de publicar.'
  exit 1
fi

if [[ ! -r "$ARCHIVO" ]]; then
  echo "Revisando $ARCHIVO"
  echo
  printf 'PROBLEMA  No se puede leer el archivo %s.\n' "$ARCHIVO"
  echo '          -> Cerrá el programa que lo tenga abierto y probá de nuevo.'
  echo
  echo 'Falta corregir 1 problema antes de publicar.'
  exit 1
fi

echo "Revisando $ARCHIVO"
echo

# BOM UTF-8
if [[ "$(head -c 3 "$ARCHIVO" | od -An -tx1 | tr -d ' \n')" == "efbbbf" ]]; then
  fallar \
    'Al principio del archivo hay un carácter invisible que no debería estar (llamado BOM).' \
    'Volvé a guardarlo como UTF-8 sin BOM. En VS Code, abajo a la derecha tiene que decir "UTF-8" y no "UTF-8 con BOM".'
fi

# UTF-8 valido
if command -v iconv > /dev/null 2>&1; then
  if ! iconv -f UTF-8 -t UTF-8 "$ARCHIVO" > /dev/null 2>&1; then
    fallar \
      'El archivo tiene caracteres que no se pueden leer, o sea que no está guardado como UTF-8.' \
      'Guardalo con codificación UTF-8. En VS Code: abajo a la derecha → "Guardar con codificación" → UTF-8.'
  fi
else
  if LC_ALL=C grep -q $'\xef\xbf\xbd' "$ARCHIVO" 2>/dev/null; then
    fallar \
      'El archivo tiene caracteres que no se pueden leer, o sea que no está guardado como UTF-8.' \
      'Guardalo con codificación UTF-8. En VS Code: abajo a la derecha → "Guardar con codificación" → UTF-8.'
  fi
fi

# CRLF
# Se cuenta con tr en vez de con grep porque en Git Bash el grep no
# encuentra el caracter de retorno de linea.
if [[ "$(LC_ALL=C tr -dc '\r' < "$ARCHIVO" 2>/dev/null | wc -c | tr -d ' ')" -gt 0 ]]; then
  fallar \
    'El archivo está guardado con finales de línea de Windows.' \
    'El proyecto los usa de estilo Unix. En VS Code, abajo a la derecha cambiá "CRLF" por "LF" y volvé a guardar.'
fi

# ------------------------------------------------------------- estructura

cat > "$TMP/token.awk" <<'AWK_TOKEN'
function esEspacio(c) { return (c == " " || c == "\t" || c == "\r" || c == "\n") }

BEGIN {
  s = ""
  while ((getline linea) > 0) s = s linea "\n"
  n = length(s); i = 1; depth = 0; errores = 0; previo = ""; coma = 0

  while (i <= n) {
    c = substr(s, i, 1)
    if (esEspacio(c)) { i++; continue }

    if (c == "{" || c == "[") { push(c == "{" ? "o" : "a"); i++; previo = c; coma = 0; continue }

    if (c == "}" || c == "]") {
      if (coma) { falla("sobro una coma antes de cerrar"); errores++ }
      if (depth == 0) { falla("sobro un " c " de cierre"); errores++; i++; previo = c; continue }
      if ((c == "}") != (ftype[depth] == "o")) {
        falla("se abrio con " (ftype[depth] == "o" ? "{" : "[") " pero se cerro con " c); errores++
      }
      depth--; i++; previo = c; coma = 0
      if (depth == 0) raiz = "cerrada"
      continue
    }

    if (c == ",") {
      if (depth == 0) { falla("sobro una coma"); errores++; i++; previo = c; continue }
      if (previo == "{" || previo == "[") { falla("sobro una coma justo despues de abrir"); errores++ }
      if (ftype[depth] == "a") fidx[depth]++; else needKey[depth] = 1
      i++; previo = c; coma = 1; continue
    }

    if (c == ":") {
      if (depth == 0 || ftype[depth] != "o") { falla("sobro un dos puntos"); errores++; i++; previo = c; continue }
      needKey[depth] = 0; i++; previo = c; coma = 0; continue
    }

    if (c == "\"") {
      i++; txt = ""; cerrado = 0
      while (i <= n) {
        ch = substr(s, i, 1)
        if (ch == "\\") {
          esc = substr(s, i + 1, 1)
          if (esc == "n") txt = txt "\n"
          else if (esc == "t") txt = txt "\t"
          else if (esc == "r") txt = txt "\r"
          else if (esc == "b") txt = txt "b"
          else if (esc == "f") txt = txt "f"
          else txt = txt esc
          i += 2; continue
        }
        if (ch == "\"") { cerrado = 1; i++; break }
        txt = txt ch; i++
      }
      if (!cerrado) { falla("falta cerrar una comilla"); errores++; break }

      j = i
      while (j <= n && esEspacio(substr(s, j, 1))) j++
      sig = (j <= n) ? substr(s, j, 1) : ""

      if (sig == ":") {
        if (depth == 0) { falla("sobro un texto suelto antes de cualquier objeto"); errores++ }
        else { curKey[depth] = txt; needKey[depth] = 0 }
      } else {
        if (depth == 0) print "V string $ " txt
        else {
          if (ftype[depth] == "o" && needKey[depth]) { falla("falta el dos puntos despues de " txt); errores++ }
          print "V string " rutaDeValor(depth) " " txt
          if (ftype[depth] == "a") fidx[depth]++
        }
      }
      previo = "\""; coma = 0; continue
    }

    j = i; tok = ""
    while (j <= n) {
      ch = substr(s, j, 1)
      if (ch == "," || ch == "}" || ch == "]" || esEspacio(ch)) break
      tok = tok ch; j++
    }
    if (tok == "") { i++; continue }
    tipo = "otro"
    if (tok ~ /^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$/) tipo = "number"
    else if (tok == "true" || tok == "false") tipo = "boolean"
    else if (tok == "null") tipo = "null"
    if (tipo == "otro") {
      falla("el valor " tok " esta escrito sin comillas y no es un numero"); errores++
    } else {
      if (depth == 0) print "V " tipo " $ " tok
      else {
        if (ftype[depth] == "o" && needKey[depth]) { falla("falta el dos puntos despues de " curKey[depth]); errores++ }
        print "V " tipo " " rutaDeValor(depth) " " tok
        if (ftype[depth] == "a") fidx[depth]++
      }
    }
    i = j; previo = tok; coma = 0
  }

  if (depth != 0) { falla("falta cerrar " (ftype[depth] == "o" ? "{" : "[") " del ultimo nivel"); errores++ }
  if (errores == 0 && raiz != "cerrada" && depth == 0) { falla("el archivo esta vacio o incompleto"); errores++ }
  exit (errores > 0) ? 1 : 0
}

function push(t) {
  depth++; ftype[depth] = t
  if (t == "a") { fidx[depth] = 0; needKey[depth] = 0 } else { needKey[depth] = 1; curKey[depth] = "" }
  if (depth == 1) fpath[depth] = "$"
  else {
    p = depth - 1
    if (ftype[p] == "a") fpath[depth] = fpath[p] "[" fidx[p] "]"
    else fpath[depth] = fpath[p] "." curKey[p]
  }
  print "K " t " " fpath[depth]
}

function rutaDeValor(d) {
  if (ftype[d] == "a") return fpath[d] "[" fidx[d] "]"
  return fpath[d] "." curKey[d]
}

function falla(msg) { print "E " msg }
AWK_TOKEN

MAL_FORMADO=0
if ! awk -f "$TMP/token.awk" "$ARCHIVO" > "$MAPA" 2>/dev/null; then
  MAL_FORMADO=1
  awk '/^E /{
    sub(/^E /, "")
    print "PROBLEMA  El archivo no está bien formado: " $0
    print "          -> Casi siempre es una coma de más o de menos, una llave que no cierra o una comilla sin cerrar. Revisá el archivo entero, empezando por la última coma o llave que tocaste."
    print ""
  }' "$MAPA" >> "$PROBLEMAS"
fi

# ------------------------------------------------------- revision del schema

cat > "$TMP/schema.awk" <<'AWK_SCHEMA'
function fallar(q, c) { print "PROBLEMA  " q "\n          -> " c "\n" >> _PROBLEMAS }
function avisar(q, c) { print "AVISO     " q "\n          -> " c "\n" >> _AVISOS }

function esBisiesto(a) { return (a % 4 == 0 && a % 100 != 0) || a % 400 == 0 }
function diasEnMes(a, m) {
  if (m == 2) return esBisiesto(a) ? 29 : 28
  if (m == 4 || m == 6 || m == 9 || m == 11) return 30
  return 31
}
function diasDesdeEpoch(a, m, d,   t, c) {
  t = 0
  for (c = 1970; c < a; c++) t += esBisiesto(c) ? 366 : 365
  for (c = 1; c < m; c++) t += diasEnMes(a, c)
  return t + d - 1
}
# 0 = domingo. El 1 de enero de 1970 fue jueves.
function diaDeSemana(a, m, d) { return (diasDesdeEpoch(a, m, d) + 4) % 7 }

function conDe(t) {
  if (substr(t, 1, 4) == "el ") return "del " substr(t, 5)
  if (substr(t, 1, 4) == "la ") return "de la " substr(t, 5)
  if (substr(t, 1, 5) == "los ") return "de los " substr(t, 6)
  if (substr(t, 1, 5) == "las ") return "de las " substr(t, 6)
  return t
}
function mayus(s) { return toupper(substr(s, 1, 1)) substr(s, 2) }

# avisa de los datos que no se usan en un nivel, comparando contra los
# nombres permitidos de ese nivel
function avisarSobrantes(base, permitidas, conTexto, pista,   camino, pre, largo, k, x, n, marca, extra) {
  marca++
  pre = base "."
  largo = length(pre)
  for (camino in clase) {
    if (substr(camino, 1, largo) == pre) {
      k = substr(camino, largo + 1)
      if (k != "" && index(k, ".") == 0 && index(k, "[") == 0 && vistoHijo[k] != marca) {
        vistoHijo[k] = marca
        n = 0
        for (x in permitidas) if (permitidas[x] == k) n = 1
        if (!n) {
          extra = (k == "ayudante") ? " El nombre correcto es \"ayudantes\", con s al final." : ""
          avisar("En " conTexto " hay un dato \"" k "\" que no se usa para nada.", pista extra)
        }
      }
    }
  }
}

function fechaLegible(iso) {
  if (iso !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return iso
  split(iso, p, "-")
  return p[3] " de " mesLetra[p[2] + 0] " de " p[1]
}

BEGIN {
  PERMITIDAS_SEMANA[1] = "fecha";  PERMITIDAS_SEMANA[2] = "turnos"; PERMITIDAS_SEMANA[3] = "titulo"
  PERMITIDAS_TURNO[1]  = "turno";  PERMITIDAS_TURNO[2]  = "grandes"; PERMITIDAS_TURNO[3]  = "peques"
  PERMITIDAS_GRUPO[1]  = "seño";   PERMITIDAS_GRUPO[2]  = "ayudantes"
  MES[1]="enero"; MES[2]="febrero"; MES[3]="marzo"; MES[4]="abril"; MES[5]="mayo"; MES[6]="junio"
  MES[7]="julio"; MES[8]="agosto"; MES[9]="septiembre"; MES[10]="octubre"; MES[11]="noviembre"; MES[12]="diciembre"
  for (k in MES) mesLetra[k] = MES[k]
  DIAS[0]="domingo"; DIAS[1]="lunes"; DIAS[2]="martes"; DIAS[3]="miercoles"
  DIAS[4]="jueves"; DIAS[5]="viernes"; DIAS[6]="sabado"
}

# ------------------------------------------- indice: K <tipo> <ruta>
# valores: V <tipo> <ruta> <valor>
/^K /  { clase[$3] = $2; next }
/^V /  { valor[$3] = $4; clase[$3] = "v:" $2; next }

END { revisar() }

function revisar(   i, j, r, base, semana, camino, k) {
  # --- raiz
  if (!("$" in clase)) {
    fallar("El archivo no tiene la forma que se espera.", "Tiene que ser un objeto con una lista llamada \"semanas\" adentro.")
    return
  }
  if (clase["$"] != "o") {
    fallar("La parte de arriba del archivo no tiene la forma correcta.",
           "El archivo tiene que empezar con una llave \"{\" y toda la informacion va adentro de una lista llamada \"semanas\".")
    return
  }

  # --- clave semanas
  if (!("$.semanas" in clase)) {
    fallar("Falta la lista \"semanas\", que es donde van todos los turnos.",
           "El archivo tiene que verse así: { \"semanas\": [ { \"fecha\": \"2026-10-04\", \"turnos\": [ ... ] } ] }")
    return
  }
  if (clase["$.semanas"] != "a") {
    fallar("La lista \"semanas\" no es una lista.",
           "Tiene que ir entre corchetes: [ ]. Si tiene un solo par de llaves, te falta un par de corchetes.")
    return
  }

  # --- claves que sobran en la raiz
  for (camino in clase) {
    if (camino ~ /^\$\.[A-Za-z_][A-Za-z0-9_]*$/) {
      k = substr(camino, 3)
      if (k != "semanas" && !raizVisto[k]++)
        avisar("Al principio del archivo hay un dato \"" k "\" que no se usa para nada.",
               "Revisá que no haya quedado un nombre de más. Se puede borrar sin romper nada.")
    }
  }

  # --- cada semana
  for (i = 0; i < 500; i++) {
    base = "$.semanas[" i "]"
    if (!(base in clase)) break
    revisarSemana(base, i + 1)
  }
  if (!tuvoSemana) {
    avisar("No hay ninguna semana cargada.", "Agregá al menos una semana dentro de \"semanas\".")
  }
}

function revisarSemana(base, semana,   p, fecha, a, m, d, etiqueta, f, fechaOk) {
  etiqueta = "la semana " semana
  tuvoSemana = 1
  fechaOk = 0

  if (clase[base] != "o") {
    fallar(mayus(etiqueta) " no tiene la forma correcta.",
           "Cada semana es un bloque entre llaves que tiene una \"fecha\" y una lista \"turnos\".")
    return
  }

  p = base ".fecha"
  if (!(p in clase)) {
    fallar("A " etiqueta " le falta la fecha.",
           "Agregá \"fecha\": \"2026-10-04\". El formato es cuatro dígitos del año, dos del mes y dos del día.")
  } else if (clase[p] != "v:string") {
    fallar("La fecha de " etiqueta " no está escrita como texto.",
           "Ponele comillas: \"fecha\": \"2026-10-04\".")
  } else {
    fecha = valor[p]
    etiqueta = "la semana " semana " (" fecha ")"
    if (fecha !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
      fallar("La fecha de " etiqueta " no está en el formato correcto o no existe en el calendario.",
             "Escribila como AAAA-MM-DD, por ejemplo 2026-10-04. No se admiten fechas como \"31 de febrero\" ni fechas con la hora agregada.")
    } else {
      a = substr(fecha, 1, 4) + 0; m = substr(fecha, 6, 2) + 0; d = substr(fecha, 9, 2) + 0
      if (m < 1 || m > 12 || d < 1 || d > diasEnMes(a, m)) {
        fallar("La fecha " fecha " de " etiqueta " no existe en el calendario.",
               "Revisá el día y el mes. Por ejemplo, febrero no tiene 31 días.")
      } else {
        f = diaDeSemana(a, m, d)
        fechaOk = 1
        if (f != 0) {
          avisar("La fecha de " etiqueta " es " DIAS[f] ", no domingo.",
                 "El cronograma arranca los domingos, una semana por fecha. Si te equivocaste de día, corregilo; si fue a propósito, dejalo así.")
        }
      }
    }
  }

  # fechas repetidas y orden
  if (fechaOk) {
    if (fechaVista[fecha]) {
      fallar("La fecha " fecha " aparece dos veces: en la semana " fechaVista[fecha] " y en la semana " semana ".",
             "Dejá una sola de las dos. Para cambiar los turnos de una semana que ya está cargada, editá los que ya están en vez de agregar otra.")
    } else {
      fechaVista[fecha] = semana
      if (ordenPrevia != "" && fecha < ordenPrevia && !avisOrden) {
        avisOrden = 1
        fallar("Las semanas no están ordenadas de la más antigua a la más reciente.",
               "Siempre van de menor a mayor: la de fecha más chica primero. Mové la semana " ordenPrevia " más abajo, después de la " fecha ".")
      }
      ordenPrevia = fecha
    }
  }

  p = base ".titulo"
  if ((p in clase) && clase[p] == "v:string" && valor[p] ~ /^[[:space:]]*$/) {
    avisar(mayus(etiqueta) " tiene \"titulo\" pero está vacío.",
           "Completalo con el texto que quieras que diga de título, o borralo: si lo borrás, el encabezado se arma solo con la fecha.")
  }

  avisarSobrantes(base, PERMITIDAS_SEMANA, etiqueta,
                  "Cada semana solo puede tener \"fecha\", \"turnos\" y, si querés, \"titulo\".")

  p = base ".turnos"
  if (!(p in clase)) {
    fallar("A " etiqueta " le falta la lista de turnos.",
           "Agregá \"turnos\": [ ... ] con un bloque por cada franja horaria.")
  } else if (clase[p] != "a") {
    fallar("La lista \"turnos\" de " etiqueta " no es una lista.",
           "Tiene que ir entre corchetes: [ ]. Mirá cómo está escrita la primera semana del archivo y seguí ese formato.")
  } else {
    revisarTurnos(p, etiqueta)
  }
}

function revisarTurnos(base, etiquetaSemana,   j, baseT, n, etiqueta, p) {
  n = 0
  for (j = 0; j < 200; j++) {
    baseT = base "[" j "]"
    if (!(baseT in clase)) break
    n++
    if (clase[baseT] == "o") {
      etiqueta = "el turno " (j + 1) " de " etiquetaSemana
      p = baseT ".turno"
      if (!(p in clase)) {
        fallar("No dice a qué franja horaria corresponde " etiqueta ".",
               "Agregá \"turno\": \"Mañana\" o \"turno\": \"Tarde\" (con mayúscula y con la tilde en Mañana).")
      } else if (clase[p] != "v:string") {
        fallar("El nombre de la franja horaria de " etiqueta " está mal.",
               "Tiene que ser un texto: \"turno\": \"Mañana\".")
      } else if (valor[p] ~ /^[[:space:]]*$/) {
        fallar("El nombre de la franja horaria de " etiqueta " está vacío.",
               "Poné \"Mañana\" o \"Tarde\".")
      } else {
        etiqueta = "el turno \"" valor[p] "\" de " etiquetaSemana
      }
      avisarSobrantes(baseT, PERMITIDAS_TURNO, conDe(etiqueta),
                      "Cada turno solo puede tener \"turno\", \"grandes\" y \"peques\".")
      revisarGrupo(baseT ".grandes", conDe(etiqueta), "grandes")
      revisarGrupo(baseT ".peques", conDe(etiqueta), "peques")
    } else {
      fallar("El turno " (j + 1) " de " etiquetaSemana " no tiene la forma correcta.",
             "Cada turno es un bloque entre llaves con sus datos adentro.")
    }
  }
  if (n == 0) {
    avisar(mayus(etiquetaSemana) " no tiene ningún turno cargado.",
           "Si todavía no definís los turnos, agregá al menos el de Mañana.")
  }
}

function revisarGrupo(base, conTexto, etiqueta,   p, pista) {
  if (!(base in clase)) {
    avisar("En " conTexto " no está el grupo \"" etiqueta "\", así que no se van a mostrar esos seños.",
           "Si ese grupo no tiene turno esa semana, está bien que no esté. Si sí tiene, agregá \"" etiqueta "\": { \"seño\": \"...\" }.")
    return
  }
  if (clase[base] != "o") {
    fallar(mayus(conDe(conTexto)) ": el grupo \"" etiqueta "\" no tiene la forma correcta.",
           "Tiene que ir entre llaves con los datos adentro, por ejemplo \"" etiqueta "\": { \"seño\": \"Ludmi\" }.")
    return
  }

  p = base ".seño"
  if (!(p in clase)) {
    fallar("Falta el nombre del seño de \"" etiqueta "\" en " conTexto ".",
           "Agregá \"seño\" con el nombre adentro de \"" etiqueta "\".")
  } else if (clase[p] != "v:string") {
    fallar("El nombre del seño de \"" etiqueta "\" en " conTexto " está mal.",
           "Tiene que ser un texto: \"seño\": \"Ludmi\".")
  } else if (valor[p] ~ /^[[:space:]]*$/) {
    fallar("El nombre del seño de \"" etiqueta "\" en " conTexto " está vacío.",
           "Completalo con el nombre, o borrá el grupo \"" etiqueta "\" si ese día no hay turno.")
  }

  p = base ".ayudantes"
  if (p in clase) {
    if (clase[p] != "v:string") {
      fallar("El campo \"ayudantes\" de \"" etiqueta "\" en " conTexto " está mal.",
             "Tiene que ser un texto con los nombres: \"ayudantes\": \"Solange y Yani\".")
    } else if (valor[p] ~ /^[[:space:]]*$/) {
      fallar("El campo \"ayudantes\" de \"" etiqueta "\" en " conTexto " está vacío.",
             "Completalo con los nombres, o borralo del archivo. Si queda vacío, la página muestra un espacio en blanco.")
    }
  }

  pista = "Dentro de \"" etiqueta "\" solo se usan \"seño\" y \"ayudantes\"."
  avisarSobrantes(base, PERMITIDAS_GRUPO, "\"" etiqueta "\" de " conTexto, pista)
}
AWK_SCHEMA

if [[ "$MAL_FORMADO" -eq 0 ]]; then
  awk -v _AVISOS="$AVISOS" -v _PROBLEMAS="$PROBLEMAS" -f "$TMP/schema.awk" "$MAPA" > /dev/null
fi

# ------------------------------------------------------------------ reporte

N_AVISOS=$(grep -c '^AVISO' "$AVISOS" 2>/dev/null); N_AVISOS=${N_AVISOS:-0}
N_PROBLEMAS=$(grep -c '^PROBLEMA' "$PROBLEMAS" 2>/dev/null); N_PROBLEMAS=${N_PROBLEMAS:-0}

if [[ "$N_AVISOS" -gt 0 ]]; then cat "$AVISOS"; fi
if [[ "$N_PROBLEMAS" -gt 0 ]]; then cat "$PROBLEMAS"; fi

NOMBRE="$(basename "$ARCHIVO")"
if [[ "$N_PROBLEMAS" -eq 0 && "$N_AVISOS" -eq 0 ]]; then
  echo "Listo: $NOMBRE está bien y se puede publicar."
elif [[ "$N_PROBLEMAS" -eq 0 ]]; then
  echo "Listo: $NOMBRE se puede publicar. Quedan $N_AVISOS sugerencia(s) para revisar."
else
  echo "Falta corregir $N_PROBLEMAS problema(s) antes de publicar."
  exit 1
fi

exit 0

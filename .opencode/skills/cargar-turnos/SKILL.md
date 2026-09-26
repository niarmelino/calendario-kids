---
name: cargar-turnos
description: Use when the user wants to load or update the teacher shift schedule in data.json for this repo — accepts one or more dates in any format, asks whether to delete, add or merge with the weeks already loaded, asks for each week's shifts, previews a table, edits data.json on an update/{fecha} branch and opens a PR. Trigger words — cargar turnos, actualizar turnos, agregar semana, cargar semana, borrar turnos, mergear turnos, data.json, turnos de maestros, seños, update branch, update/, agregar fechas.
---

# Cargar turnos

Carga o actualiza una o varias semanas de turnos en `data.json` y las publica
como PR.

El orden importa: **se pregunta todo y se confirma antes de tocar git o el
archivo**. Si el usuario abandona a mitad de carga, no queda ninguna rama
creada ni ningún cambio en el working tree.

## Contexto del repo

- Los turnos viven solo en `data.json`. `index.html` lo hace `fetch`, filtra
  `fecha >= hoy`, ordena ascendente y genera el encabezado con
  `toLocaleDateString('es-AR')`.
- Las fechas van en ISO `YYYY-MM-DD` y son **domingos** (una semana por
  entrada). El filtro del `index.html` parsea con `T00:00:00` para no correr
  un día en horarios negativos, así que nunca escribas la fecha con hora.
- `ayudantes` es opcional en **los dos** grupos; si falta, la card muestra
  solo SEÑO.
- Los archivos van en UTF-8 sin BOM y con finales LF (ver `.gitattributes`).
  No introduzcas CRLF.
- `.opencode/skills/cargar-turnos/validar-data.sh` revisa que `data.json` tenga
  la forma correcta y avisa en español llano. Correlo en el Paso 9, antes de
  commitear. Es bash puro: no necesita Node ni Python.
- Los mensajes de commit del repo van en español, en imperativo, capitalizados
  y sin punto final.

## Paso 0 — Preflight

```bash
git status --short          # debe estar limpio
git fetch origin            # recién actualizado
gh auth status              # logueado
```

Si hay cambios sin commitear o commits sin pushear, avisá y **preguntá** si
igual querés seguir: no los descartes ni los commitees vos.

## Paso 1 — Leer el estado actual

Leé `data.json` completo. De ahí salen tres cosas: los turnos de la última
semana cargada (para proponer "¿los mismos que la semana pasada?"), la lista
de fechas ya usadas, y el estilo de formato para escribir igual.

## Paso 2 — Preguntar qué hacer con lo que ya está cargado

`data.json` ya tiene semanas cargadas. **Siempre preguntá qué querés que pase con
ellas**, antes de preguntar las fechas. Es la decisión que cambia el resultado y
no se puede deducir del pedido.

| Opción | Qué hace con las semanas que ya están | Cuándo usarla |
|---|---|---|
| **Borrar lo cargado** | Las elimina todas y deja solo lo nuevo | Recalendizar desde cero |
| **Agregar** | Las deja intactas y suma las fechas nuevas | Sumar semanas al calendario actual |
| **Merge** | Las deja intactas y, en las fechas que ya existen, cambia **solo lo que el usuario acaba de decir** | Corregir un dato sin perder lo demás |

Preguntalo con las consecuencias a la vista, y en la misma pregunta:

```
Hoy hay 3 semanas cargadas (la más reciente es la del 27 de septiembre).
¿Qué querés que haga con ellas?

1. Dejarlas y agregar las nuevas
2. Dejarlas y mezclarlas: si una fecha ya está cargada, cambio solo lo que me digas
3. Borrarlas todas y cargar solo lo nuevo
```

### Agregar vs. merge

importan únicamente cuando la fecha que pide el usuario **ya está cargada**.

- **Agregar** pisa la semana completa por lo que dijo el usuario. Si no mencionó
  los ayudantes, quedan sin ayudantes.
- **Merge** pisa únicamente los campos mencionados. Lo que no dijo —ayudantes,
  `titulo`, o un turno que no mencionó— se conserva de lo que ya estaba.

Ejemplo: la semana del 4 de octubre ya está con `{grandes: {seño: "Anita",
ayudantes: "Solange"}, peques: {seño: "Ludmi"}}`.

> El domingo 4/10, Ludmi en vez de Anita

| Opción | Resultado |
|---|---|
| Agregar | `grandes` queda `{seño: "Ludmi"}` — se pierde "Solange" |
| Merge | `grandes` queda `{seño: "Ludmi", ayudantes: "Solange"}` |

Con **merge**, mostrá el resultado final completo de las semanas que se mezclan,
no solo los campos que cambian, así se ve qué se conserva.

Si ninguna de las fechas pedidas está cargada, agregar y merge dan lo mismo:
decilo y no hagas elegir entre dos opciones que dan el mismo resultado.

**Nunca borres una semana cargada sin que el usuario lo pida explícitamente.**

## Paso 3 — Preguntar las fechas

Aceptá **una o varias** fechas en una sola respuesta. El cronograma es
semanal, así que cada fecha es un domingo.

### Interpretar el formato

El usuario va a escribir la fecha como se le ocurra. Normalizá todo a ISO.
**Nunca copies la fecha tal como la escribió.**

Aceptá, entre otros:

| El usuario escribe | Interpretalo como |
|---|---|
| `2026-10-04` | `2026-10-04` |
| `04/10/2026`, `4/10/26` | `2026-10-04` |
| `4 de octubre`, `4-oct`, `4 de octubre de 2026` | `2026-10-04` |
| `domingo 4`, `domingo 4/10` | domingo siguiente al 4 |
| `el domingo que viene`, `la semana que viene` | el próximo domingo |
| `3/10 del año que viene` | `2027-10-03` |

Reglas:

- **`dd/mm`, nunca `mm/dd`.** Es convención argentina: `4/10` es 4 de octubre,
  `10/4` es 10 de abril. No inventes el formatoUSA.
- **Sin año:** tomá la próxima ocurrencia a partir de hoy. Si la fecha de este
  año ya pasó, es el año que viene.
- **Fechas relativas** ("el que viene", "la próxima"): resolvelas contra la
  fecha real del sistema. Obtenela con `Get-Date -Format yyyy-MM-dd` y nunca la
  supongas de memoria.
- **Validá el calendario:** `31/02` no existe. Si el día no existe en ese mes,
  avisá y corregí.
- **Si no es domingo:** el cronograma es semanal. Preguntá si corrés a la
  fecha que cae domingo o si dejás la que puso.

### Ecoá la interpretación

Mostrá siempre cómo lo interpretaste, aunque parezca obvio. Es la única
chance de detectar un error antes de escribir:

```
Interpreto las fechas así:

| Lo que escribiste | Como lo guardo | ¿Es domingo? |
|-------------------|----------------|--------------|
| domingo 4/10      | 2026-10-04     | sí           |
| la semana que viene | 2026-10-11   | sí           |

¿Correcto?
```

Si algo no se puede interpretar con confianza, preguntá en vez de adivinar.
Un domingo de octubre y uno de abril se cargan en semanas distintas: adivinar
mal deja el calendario del jardín desfasado.

### Fechas repetidas

Una fecha ya cargada es un **reemplazo**, no un alta. Marcá cuál es cuál en el
preview del Paso 5 y pedí confirmación explícita para los reemplazos.

## Paso 4 — Preguntar los turnos

Por cada fecha cargada, por defecto son dos turnos, **Mañana** y **Tarde**, y
por cada uno:

- seño de Grandes (obligatorio)
- ayudantes de Grandes (opcional)
- seño de Peques (obligatorio)
- ayudantes de Peques (opcional)

Si son varias fechas, preguntá **todo en un solo mensaje** y agrupado por
fecha, así el usuario contesta de una vez en vez de ida y vuelta:

```
Semana 2026-10-04 y semana 2026-10-11. Para cada una necesito:

2026-10-04
1. Mañana — seño de Grandes
2. Mañana — ayudantes de Grandes (si no hay, "ninguno")
3. Mañana — seño de Peques
4. Mañana — ayudantes de Peques (si no hay, "ninguno")
5. Tarde — seño de Grandes
6. Tarde — ayudantes de Grandes (si no hay, "ninguno")
7. Tarde — seño de Peques
8. Tarde — ayudantes de Peques (si no hay, "ninguno")

2026-10-11
9. Mañana — seño de Grandes
... (y así con cada fecha)
```

Opciones que abrevian la ida y vuelta:

- "los mismos que la semana pasada" → copiá los valores de la última semana
  de `data.json` y mostralos igual en el preview para que los revise.
- "todas las semanas iguales a la primera" → replicá la primera semana
  cargada en el resto.

Si un turno se queda sin seño, no lo inventes: la card se renderizaría
vacía. Dejalo afuera y aclaralo en el preview.

## Paso 5 — Preview en tabla

Mostrá **siempre** tabla antes de escribir, y esperá confirmación explícita.
No avances por tu cuenta aunque los datos parezcan obvios. Con una sola
semana:

```
Semana del domingo 4 de octubre (2026-10-04)

| Turno  | Grandes seño | Grandes ayudantes | Peques seño | Peques ayudantes |
|--------|---------------|-------------------|-------------|------------------|
| Mañana | Anita         | Solange y Yani    | Ludmi       | —                |
| Tarde  | Mari          | Ana y Marian      | Juli        | Bibi             |

Se agrega como semana nueva. ¿Confirmás?
```

Con varias semanas, una tabla por fecha, **en orden cronológico de la más
antigua a la más reciente** aunque el usuario las haya dado en otro orden, y al
final un resumen de qué se agrega, qué se reemplaza y qué se borra:

```
Se agregan 2 semanas nuevas y se reemplaza 1. ¿Confirmás?
```

Si es reemplazo, mostrà los valores actuales de esa fecha para que se
comparen, y marcá `⚠ Reemplaza la semana existente`.

Si el usuario eligió borrar lo cargado, el resumen tiene que decir qué semanas
desaparecen, con su fecha, para que vea lo que está por perder antes de
confirmar.

Usá `—` para los ayudantes que no se cargaron.

## Paso 6 — Confirmación

Pedí un sí claro. Recién con eso seguí. Si el usuario corrige algo, volvé al
Paso 4 con la tabla nueva.

## Paso 7 — Crear la rama

Solo ahora, con las fechas ya confirmadas:

```bash
git checkout main
git pull --ff-only origin main
git checkout -b update/YYYY-MM-DD
```

La rama se nombra con **la primera fecha**, esté sola o acompañada de otras.
Cargar `2026-10-04`, `2026-10-11` y `2026-10-18` va a `update/2026-10-04`.

Decile el nombre de la rama al crearla, así el usuario sabe dónde está el
trabajo.

Si `git pull` trajo cambios en `data.json` que tocan las semanas que vas a
cargar, releé el archivo antes de editar.

## Paso 8 — Editar `data.json`

Las semanas van **siempre ordenadas de la más antigua a la más reciente** dentro
de `semanas`. No importa en qué orden las haya dado el usuario ni el preview:
si Van de la más antigua a la más reciente, mantenelo. El `index.html` reordena
al renderizar, pero el validador del Paso 9 marca el orden incorrecto como
`PROBLEMA` y bloquea el commit, así que un archivo desordenado no se puede
publicar.

Revisá el orden completo del archivo, no solo las semanas nuevas: si al insertar
una fecha al principio empujaste las de atrás, el archivo puede quedar
desordenado por completo. Releé las fechas de `semanas` de punta a punta antes de
terminar.

Dentro de cada semana, los turnos van Mañana antes que Tarde.

Respetá el formato existente: 2 espacios de indentación, los objetos de
`grandes` y `peques` en una línea cada uno, y newline final.

```json
    {
      "fecha": "2026-10-04",
      "turnos": [
        {
          "turno": "Mañana",
          "grandes": { "seño": "Anita", "ayudantes": "Solange y Yani" },
          "peques": { "seño": "Ludmi" }
        },
        {
          "turno": "Tarde",
          "grandes": { "seño": "Mari", "ayudantes": "Ana y Marian" },
          "peques": { "seño": "Juli", "ayudantes": "Bibi" }
        }
      ]
    }
```

Para reemplazar una fecha existente, editá solo los turnos de esa semana y
dejá la fecha como está.

Usá la herramienta `edit`, no reescribas el archivo entero: menos riesgo de
tocar lo demás.

## Paso 9 — Validar

```bash
# Windows (Git Bash)
bash .opencode/skills/cargar-turnos/validar-data.sh

# Linux / macOS
.opencode/skills/cargar-turnos/validar-data.sh
```

Sin argumentos revisa el `data.json` del repo. Con un argumento revisa ese
archivo:

```bash
bash .opencode/skills/cargar-turnos/validar-data.sh /ruta/otro.json
```

Sale con código 0 si el archivo se puede publicar y 1 si tiene problemas. **No
commitees ni pushees si sale con 1**: corregí `data.json` y volvé a correrlo.
Los `AVISO` no bloquean, pero mostráselos al usuario igual.

El script habla en español llano y cada mensaje dice qué está mal y cómo
armarlo, así que si el usuario lo corre por su cuenta puede arreglarlo sin
ayuda. Si el mensaje que te devuelve no se entiende o está mal, pasáselo
literal en vez de traducirlo.

Chequea:

- que el archivo se pueda leer como JSON, y que la raíz tenga `semanas`,
- que cada `fecha` sea ISO `YYYY-MM-DD`, una fecha real del calendario y un
  domingo,
- que no haya dos semanas con la misma fecha,
- que estén en orden cronológico, de la más antigua a la más reciente. Esto es
  `PROBLEMA`, no `AVISO`: si el orden está mal, no se puede publicar,
- que estén `turno`, `grandes.seño` y `peques.seño`, y que `ayudantes` no esté
  vacío,
- datos con el nombre mal escrito (por ejemplo `ayudante` en vez de
  `ayudantes`),
- que el archivo no tenga BOM, no esté guardado con finales de línea de
  Windows, y sea UTF-8.

Después revisá el diff a ojo:

```bash
git diff data.json
```

Y confirmá que no se modificaron semanas que no estaban en el preview.

## Paso 10 — Ofrecer la previsualización local

Con el archivo ya editado y **antes de commitear**, ofrecele al usuario
levantar el servidor para que mire el resultado en el navegador.

La página **necesita HTTP**: con doble clic (`file://`) el navegador bloquea
el `fetch` de `data.json` por CORS y se ve el mensaje de error.

```powershell
# Elegí un puerto libre; probá 8000 y si está ocupado usá 8001, 8931, etc.
$proc = Start-Process -FilePath "python" -ArgumentList "-m","http.server","8000" `
  -WorkingDirectory "<raíz del repo>" -PassThru -WindowStyle Hidden
```

Decile el link (`http://localhost:8000`) y **guardate el PID** en `$proc.Id`
para poder apagarlo después.

El `index.html` muestra las semanas con fecha `>= hoy`, así que para
previsualizar una semana cargada con fecha pasada, aclarale al usuario que no
la va a ver y por qué. Si necesita verla igual, la opción es pasarle una
fecha futura temporal, no tocar el filtro.

Cuando el usuario confirmo que se ve bien —o que ya no lo necesita— apagalo:

```powershell
Stop-Process -Id <pid> -Force
```

No dejes el servidor corriendo al terminar.

## Paso 11 — Commit, push y PR

```bash
git add data.json
git commit -m "Cargar turnos del domingo 4 de octubre"
git push -u origin update/2026-10-04
gh pr create --base main --head update/2026-10-04 --title "..." --body "..."
```

Con varias semanas, el mensaje y el título las mencionan todas: `Cargar turnos
del 4 de octubre al 18 de octubre`.

Si el `--body` tiene comillas o acentos, escribilo en un archivo temporal y
usá `--body-file` para no pelearte con el escapado de PowerShell.

Título del PR: `Cargar turnos del <fechas>`, o `Actualizar turnos del <fechas>`
si hubo reemplazos.

El cuerpo del PR tiene que llevar las tablas del preview y una línea de
verificación.

**Mostrale el link al usuario.** Es el último paso y el que más importa: sin
él, la carga no está publicada.

## Si algo sale mal

Si el usuario abandona antes del commit, dejá el repo como estaba:

```bash
git checkout main
```

y avisá que la rama quedó sin crear. Si ya habías commiteado pero no
pusheaste, no borres la rama sin preguntar.

## Qué NO hacer

- No commitees, pushees ni abras el PR sin la confirmación del Paso 6.
- No inventes seños ni fechas que el usuario no dio.
- No copies la fecha como la escribió: siempre ISO.
- No interpretes `10/4` como 4 de octubre. Es 10 de abril.
- No borres una semana que ya está cargada sin que el usuario lo pida en el
  Paso 2.
- No dejes las semanas desordenadas: siempre de la más antigua a la más
  reciente, aunque el usuario las haya dado en cualquier orden.
- No agregues archivos nuevos al repo. Esta skill solo edita `data.json` y usa
  `.opencode/skills/cargar-turnos/validar-data.sh`, que ya está.
- No dejes el servidor local corriendo al terminar.
- No dejes CRLF ni BOM al escribir.

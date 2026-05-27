# LeoUI

Librería TUI minimalista y sin dependencias para Bash 4+. Un solo
archivo (`leoui.sh`), copiar y usar: lo dejás al lado de tu
script, le hacés `source` y obtenés un set completo de
primitivas para construir programas de shell con cajas y menús.

> English version: [README.md](./README.md)

## Características

- **Primitivas de dibujo de cajas** (`╔═╗ ║ ╚═╝`) con ancho
  configurable (52 columnas por defecto).
- **Ejecutor de comandos con spinner** que propaga el código de
  salida real del comando envuelto y muestra `Okay [✔]` /
  `Error [✖]` según corresponda.
- **Menús declarativos** con anidación, sentinelas `@back` y
  `@exit`, y manejo elegante de errores.
- **Prompts, confirmaciones, pausa y selectores numerados** con
  valores por defecto, trim de whitespace y un único modelo
  visual (toda interacción ocurre dentro de la caja).
- **Auto-apertura de cajas**: cualquier llamada de dibujo
  funciona aunque te hayas olvidado de `ui_box_top`.
- **Colores auto-detectados** (verde / rojo / dim) con opción
  de desactivar.
- **Seguro ante señales**: traps de `EXIT` / `INT` / `TERM`
  cierran la caja limpiamente y matan el spinner en background,
  así Ctrl+C no deja la terminal rota.
- **Modo no-TTY**: cada helper interactivo cae en defaults
  seguros para que el mismo script funcione en CI / pipes /
  cron.

## Requisitos

- Bash 4.0 o superior (usa namerefs `local -n` y plegado de
  case `${var,,}`).
- Se recomienda una terminal UTF-8 (la librería imprime
  `║ ═ ╔ ╗ ╚ ╝ ✔ ✖`).
- `tput` es opcional. Si está presente y la terminal soporta
  ≥ 8 colores, la salida se colorea automáticamente.

## Instalación

Copiá `leoui.sh` a tu proyecto y hacele `source`:

```bash
source ./leoui.sh
ui_init "tu-nombre"          # firma en el footer
```

El sourcing es **idempotente** — está protegido por
`LEOUI_LOADED`, así que podés hacer `source` desde múltiples
archivos sin riesgo de instalar traps o estado dos veces.

## Modelo visual

Una *caja* se abre con `ui_box_top` y permanece abierta hasta
`ui_box_bottom`. Mientras la caja está abierta:

- Solo hay **una caja** visible en pantalla — `ui_box_top`
  siempre limpia la pantalla primero.
- El **footer** con la firma del autor queda renderizado
  permanentemente abajo y se redibuja después de cada operación.
- Cualquier otra función (`ui_box_line`, `ui_run`, `ui_prompt`,
  `ui_confirm`, `ui_pause`, `ui_select`, …) inserta su salida
  como una fila nueva dentro de la caja, empujando el footer
  una línea hacia abajo.
- Si llamás a un helper de dibujo **sin** una caja abierta, se
  auto-abre una caja default (titulada `Output`) para que nunca
  haya filas huérfanas.

Esto garantiza que prompts, spinners y confirmaciones suceden
*dentro* de la caja, nunca debajo.

## Ejemplo rápido

```bash
#!/usr/bin/env bash
source ./leoui.sh
ui_init "alice"

saludar() {
    ui_box_top "Saludo"
    ui_box_line "Hola mundo!"
    ui_box_paragraph "ui_box_paragraph parte oraciones largas en \
varias filas para que el texto en prosa entre en la caja sin \
que tengas que cortarlo a mano."
    ui_pause
    ui_box_bottom
}

instalar() {
    ui_box_top "Instalación"
    ui_run "Actualizando apt"   sudo apt update
    ui_run "Instalando curl"    sudo apt install -y curl
    ui_pause
    ui_box_bottom
}

confirmar() {
    ui_box_top "Confirmar"
    ui_box_line "Acción peligrosa a punto de ejecutarse."
    if ui_confirm "¿Continuar?" no; then     # default = no
        ui_box_line "Usuario dijo SÍ."
    else
        ui_box_line "Usuario dijo NO."
    fi

    local tema
    ui_select tema "Elegí un tema" "Oscuro" "Claro" "Auto"
    ui_box_line "Tema elegido: ${tema}"

    ui_pause
    ui_box_bottom
}

menu_principal() {
    local entries=(
        "Saludar|saludar"
        "Instalar|instalar"
        "Confirmar|confirmar"
        "---"
        "Salir|@exit"
    )
    ui_menu "Demo LeoUI" entries
}

menu_principal
```

Corré `examples/00_master.sh` para un tour completo y comentado
de cada función pública.

## Configuración

`ui_init` es el único punto de configuración. Todo lo demás se
lee desde variables públicas (ver la sección
[Variables](#variables-que-podés-setear)).

```bash
ui_init                    # author=LeoUI,  width=52
ui_init "alice"            # author=alice,  width=52
ui_init "alice" 64         # author=alice,  width=64
```

Para forzar la desactivación de colores, seteá `UI_COLOR=0`
**antes** de hacer source:

```bash
UI_COLOR=0 source ./leoui.sh
```

## Referencia de la API

Convención:

- `<arg>`   — argumento posicional obligatorio
- `[arg]`   — argumento posicional opcional
- `<arg>…`  — uno o más valores

### Inicialización

#### `ui_init [autor] [ancho]`

Configura la librería. Los dos parámetros son opcionales.

| Parámetro | Default  | Descripción                                              |
| --------- | -------- | -------------------------------------------------------- |
| `autor`   | `LeoUI`  | Firma mostrada a la derecha de cada footer.              |
| `ancho`   | `52`     | Ancho total de la caja en columnas. Mínimo de 30.        |

`ancho` recalcula todos los anchos derivados
(`UI_INNER_WIDTH = ancho-2`, `UI_TEXT_WIDTH = ancho-4`,
`UI_TITLE_WIDTH = ancho-22`).

```bash
ui_init "alice" 60
```

### Ciclo de vida de la caja

#### `ui_box_top <título>`

Limpia la pantalla y abre una caja nueva. El título se centra,
con 10 caracteres `═` de cada lado, y se trunca para entrar en
`UI_TITLE_WIDTH` columnas. Setea `UI_BOX_OPEN=1`.

#### `ui_box_bottom`

Cierra la caja actual (emite un newline final). No-op si no hay
caja abierta. Setea `UI_BOX_OPEN=0`.

#### `ui_clear`

Ejecuta el `clear` del sistema y resetea `UI_BOX_OPEN=0`.
Raramente necesario, ya que `ui_box_top` ya limpia.

### Filas de contenido

Las cuatro funciones auto-abren una caja default (titulada
`Output`) si no hay ninguna abierta.

#### `ui_box_line <texto>`

Añade una fila de contenido. `<texto>` se trunca duramente a
`UI_TEXT_WIDTH` columnas visibles (sin elipsis).

#### `ui_box_paragraph <texto>`

Añade `<texto>` como una o más filas, haciendo word-wrap simple
basado en whitespace para que cada fila entre en
`UI_TEXT_WIDTH`. Las palabras más largas que el ancho de línea
se emiten en su propia fila y pueden desbordar visualmente
(caso degenerado).

```bash
ui_box_paragraph "Lorem ipsum dolor sit amet, consectetur \
adipiscing elit, sed do eiusmod tempor incididunt."
```

#### `ui_box_blank`

Añade una fila vacía.

#### `ui_box_separator`

Añade un divisor horizontal renderizado como `╠═══╣` cubriendo
todo el ancho interno.

### Ejecución de comandos

#### `ui_run <msg> <cmd> [args…]`

Ejecuta `cmd args…` en background mientras anima un spinner en
una fila etiquetada con `<msg>`. Cuando el comando termina, la
fila se reemplaza por:

- `Okay  [✔]` (verde) si `rc == 0`
- `Error [✖]` (rojo)  si `rc != 0`

La función **devuelve el código de salida real** del comando,
así que podés ramificar:

```bash
if ui_run "Compilando" make -j4; then
    ui_box_line "Compilación OK."
else
    ui_box_line "Compilación falló."
fi
```

| Comportamiento  | Detalle                                                                |
| --------------- | ---------------------------------------------------------------------- |
| Stdout / stderr | Silenciados (redirigidos a `/dev/null`).                               |
| Pid en bg       | Se guarda en `_UI_RUN_PID` para que el trap EXIT/INT lo coseche.       |
| `set -e`        | Compatible — los fallos hay que protegerlos con `\|\|` si no querés que aborten. |
| Auto-apertura   | Sí — abre una caja default si no hay ninguna abierta.                  |
| Frames spinner  | `\| / - \\` rotando cada `0.1` s.                                      |

### Notificaciones

#### `ui_notify <msg>`

Añade una fila de error con formato `<msg> ... Error [✖]`
(rojo). Se inserta una fila vacía antes de la notificación para
darle aire visual. Auto-abre una caja si no hay ninguna abierta.
**No hace exit.**

#### `ui_error <msg>`

Igual que `ui_notify`, pero después cierra la caja abierta (si
la hay) y hace `exit 1`.

### Entrada interactiva

Todas las funciones interactivas se renderizan **dentro** de la
caja abierta (el borde derecho y el footer permanecen visibles
mientras el usuario tipea) y caen en defaults seguros cuando
stdin/stdout no es una TTY (logs de CI, pipes, cron, etc.).

#### `ui_prompt <pregunta> <nombre_var> [default]`

Entrada de texto libre. Guarda la respuesta en la variable cuyo
nombre se pasa en `<nombre_var>` (sin `$`).

| Parámetro     | Descripción                                                                          |
| ------------- | ------------------------------------------------------------------------------------ |
| `pregunta`    | Texto plano de la pregunta. La librería le agrega `:` (o `[default]:` si se da uno). |
| `nombre_var`  | Nombre de la variable a escribir.                                                    |
| `default`     | Default opcional; pulsar Enter lo selecciona.                                        |

Comportamiento no-TTY: silenciosamente escribe `default` (o
string vacío) en la variable sin prompt.

```bash
local nombre
ui_prompt "¿Cómo te llamás?" nombre "anonimo"
```

#### `ui_confirm <pregunta> [default]`

Prompt sí / no. Acepta `y / yes / s / si / sí` y `n / no`,
case-insensitive, con whitespace alrededor recortado. Devuelve
`0` para sí, `1` para no. Repreguntando ante input inválido.

| `default`        | Sufijo mostrado | Enter selecciona |
| ---------------- | --------------- | ---------------- |
| _omitido_ / `""` | `(y/n):`        | _ninguno, loop_  |
| `yes` / `y`      | `(Y/n):`        | sí               |
| `no`  / `n`      | `(y/N):`        | no               |

Comportamiento no-TTY: devuelve el default (`no` si no se da
uno).

```bash
if ui_confirm "¿Borrar archivos temporales?" no; then
    rm -rf /tmp/foo
fi
```

#### `ui_pause [msg]`

Espera a que el usuario presione Enter. La fila del prompt se
borra después para que la caja quede limpia.

| Parámetro | Default                          |
| --------- | -------------------------------- |
| `msg`     | `Press Enter to continue`        |

Comportamiento no-TTY: no-op (retorna inmediatamente).

#### `ui_select <nombre_var> <prompt> <opcion1> [opcion2 …]`

Selector numerado de una sola elección. Lista las opciones como
un menú numerado, lee un número del usuario y guarda el
**string elegido** (no el índice) en la variable cuyo nombre se
pasa en `<nombre_var>`.

- Si hay una caja abierta, `<prompt>` se añade como una fila
  arriba de la lista de opciones.
- Si no hay caja abierta, se abre una nueva titulada `<prompt>`
  y se cierra automáticamente al terminar.

Comportamiento no-TTY: escribe la **primera opción** en la
variable sin prompt.

```bash
local entorno
ui_select entorno "Elegí entorno" "dev" "staging" "produccion"
```

### Menús

#### `ui_menu <título> <nombre_array>`

Renderiza un menú interactivo y loopea hasta que se seleccione
una sentinela.

El array pasado por nombre contiene una entrada por fila. Cada
entrada es un único string con uno de estos formatos:

| Entrada               | Significado                                                              |
| --------------------- | ------------------------------------------------------------------------ |
| `"Etiqueta\|accion"`  | Llama a `accion` (función o comando, args separados por espacios). Después el menú se redibuja. |
| `"Etiqueta\|@back"`   | Vuelve al menú padre.                                                    |
| `"Etiqueta\|@exit"`   | Sale del programa (`exit 0`).                                            |
| `"---"`               | Fila separadora horizontal.                                              |
| `""`                  | Fila vacía.                                                              |

**Numeración.** Las entradas seleccionables se numeran `1..N`
en el orden en que aparecen. Si la **última** entrada es
`@back` o `@exit`, se numera `0`.

**Submenús.** Son simplemente funciones que llaman a `ui_menu`
otra vez. Un submenú típicamente termina con `"Volver|@back"`.

**Manejo de errores.** Cuando una acción retorna un código
distinto de cero, LeoUI muestra una notificación `Error [✖]`,
espera Enter y vuelve a renderizar el menú. **No** aborta el
programa.

**Comportamiento no-TTY.** Los menús requieren una terminal
real. En modo no-TTY, `ui_menu` emite `ui_notify "ui_menu
'<título>' requires an interactive terminal"` y devuelve `1`.

```bash
sub_menu_temas() {
    local entries=(
        "Oscuro|aplicar_oscuro"
        "Claro|aplicar_claro"
        "---"
        "Volver|@back"
    )
    ui_menu "Temas" entries
}

menu_principal() {
    local entries=(
        "Temas|sub_menu_temas"
        "Salir|@exit"
    )
    ui_menu "Principal" entries
}
```

## Soporte de colores

Los colores se auto-detectan al hacer source:

- `stdout` debe ser una TTY.
- `tput colors` debe reportar `≥ 8`.

Cuando hay soporte, la librería renderiza:

- `Okay  [✔]` en verde
- `Error [✖]` en rojo
- La firma del autor en dim

Para forzar la desactivación, seteá `UI_COLOR=0` **antes** de
hacer source de `leoui.sh`. La auto-detección lo respeta:

```bash
UI_COLOR=0 source ./leoui.sh
```

Las secuencias ANSI tienen **ancho visible cero**, así que la
alineación de columnas se preserva con o sin colores.

## Manejo de señales

Cuando se hace source en un shell **no-interactivo** (o sea, un
script — el caso típico), LeoUI instala los siguientes traps:

| Señal  | Acción                                                                |
| ------ | --------------------------------------------------------------------- |
| `EXIT` | Cierra cualquier caja abierta y cosecha el pid del spinner.           |
| `INT`  | Lo mismo, después `exit 130` (código convencional para Ctrl+C).       |
| `TERM` | Lo mismo, después `exit 143`.                                         |

Esto garantiza que apretar Ctrl+C durante un spinner o un prompt
nunca deje un proceso huérfano en background ni una caja a
medio renderizar.

Cuando se hace source en un shell **interactivo**, los traps
**no** se instalan (no queremos pisar tu sesión de shell). Si
un script necesita comportamiento distinto, puede sobrescribir
los traps después del source — el `trap` de bash es
last-write-wins.

## Modo no-TTY

La librería detecta entornos no-interactivos vía
`[[ -t 0 && -t 1 ]]`. Cuando stdin o stdout no es TTY, los
helpers interactivos degradan elegantemente para que el mismo
script pueda correr desatendido en CI, cron, pipes, redirects,
etc.:

| Función       | Comportamiento no-TTY                              |
| ------------- | -------------------------------------------------- |
| `ui_pause`    | No-op, retorna de inmediato.                       |
| `ui_prompt`   | Guarda el default (o `""`) sin preguntar.          |
| `ui_confirm`  | Devuelve el default (`no` si no se da).            |
| `ui_select`   | Elige la primera opción silenciosamente.           |
| `ui_menu`     | Emite notificación de error, devuelve `1`.         |

Los helpers de dibujo (`ui_box_top`, `ui_box_line`, `ui_run`, …)
siguen corriendo normalmente — el output capturado parece un
"log encajado" en el stream.

## Variables que podés setear

Seteá estas **antes** de hacer source de `leoui.sh` para influir
en su comportamiento. Después del source, son
populadas/sobrescritas por `ui_init`.

| Variable             | Default      | Propósito                                                            |
| -------------------- | ------------ | -------------------------------------------------------------------- |
| `UI_COLOR`           | _auto_       | `0` para forzar la desactivación de colores; si no, auto-detectado.  |
| `UI_AUTHOR`          | `LeoUI`      | Firma mostrada en el footer (también seteada por `ui_init`).         |
| `UI_BOX_TOTAL`       | `52`         | Ancho total de la caja en columnas (también seteada por `ui_init`).  |
| `UI_AUTO_BOX_TITLE`  | `Output`     | Título usado cuando un helper de dibujo auto-abre una caja.          |

También podés leer estas para inspección:

| Variable        | Significado                                                  |
| --------------- | ------------------------------------------------------------ |
| `UI_BOX_OPEN`   | `1` mientras hay una caja abierta, `0` si no.                |
| `UI_INNER_WIDTH`| `UI_BOX_TOTAL - 2` (entre los bordes laterales).             |
| `UI_TEXT_WIDTH` | `UI_BOX_TOTAL - 4` (cantidad de columnas de texto usables).  |
| `UI_TITLE_WIDTH`| Ancho visible máximo del título dentro de `ui_box_top`.      |
| `_UI_RUN_PID`   | Pid en background del job de `ui_run` corriendo actualmente. |

## Notas y limitaciones

- Las distancias se calculan usando **solo espacios** — no
  aparecen tabuladores en la salida, así que el renderizado es
  independiente del `tabstop` del usuario.
- La librería usa un único ancho fijo seteado en `ui_init`. Si
  necesitás distintos anchos en el mismo script, llamá a
  `ui_init` de nuevo con el nuevo ancho antes de abrir la
  próxima caja.
- Las cadenas de acción en menús se dividen por espacios y se
  invocan **sin `eval`**. Para pasar argumentos con espacios,
  envolvé la llamada en una función y referenciala en la
  entrada del menú.
- Usá un locale UTF-8. Bajo `LC_ALL=C`, las etiquetas de usuario
  con caracteres multibyte se contarán mal con `${#var}` (la
  librería solo maneja correctamente sus propios glifos `✔`/`✖`
  en cualquier locale).
- Caracteres anchos / CJK / emoji en el contenido del usuario
  se cuentan como una columna aunque ocupen dos visualmente; en
  ese caso la alineación de la caja se desfasa.
- `_ui_read_overlay` usa las secuencias DEC `\033[s` / `\033[u`
  de save / restore cursor, soportadas por todas las terminales
  modernas (xterm, gnome-terminal, kitty, alacritty, foot,
  wezterm, …) pero no por VT100 puros.

## Licencia

MIT

# Tablero del Equipo — Odemás

App para el celular del equipo de tienda, en un solo link + QR y sin instalar
nada: 🔥 promociones y precios · 🏷️ EOL / última pieza al 50% · 📦 novedades ·
📢 avisos · 🧾 captura de series · 💰 comisiones · 🗓️ horarios.

Es una copia multi-tienda: **cada tienda tiene sus propios datos** y solo ve los
suyos. La separación la impone la base (RLS por `store_id`), no la app.

## Qué necesitas para montarla

1. Un proyecto de **Supabase** (gratis). Ahí van los `supabase_*.sql`.
2. **GitHub Pages** apuntando a `main`. El deploy es el push, no hay panel.
3. Opcional: una cuenta de **OneSignal** para los avisos push. Sin ella la
   campana no aparece — ver `ONE_APP_ID` en `tablero.html`.

No hace falta Google Apps Script ni hoja de cálculo. **Todo vive en Supabase.**

## Las pantallas

| Archivo | Qué es |
|---|---|
| `index.html` | Menú y **login**. De aquí sale la sesión que leen las demás |
| `tablero.html` | Promos, precios, EOL, combos, avisos, apartados |
| `captura_series.html` | El asesor captura la venta: serie, SKU, seguro, foto |
| `admin.html` | Gerente: equipo, cargas, catálogo, accesorios, configuración |
| `comisiones.html` | Lo que lleva ganado cada quien |
| `horarios.html` | Horario semanal |
| `actualizar_datos.html` | Subir el Excel de inventario, catálogo y promos |
| `accesorios_tecnico.html` | Consulta para técnicos externos. **Va aparte**: no está en el menú ni en el service worker |

## Montar la base

```powershell
python armar_sql.py -v     # genera supabase_TODO.sql y dice por qué va en ese orden
```

Y se pega **entero** en el SQL Editor de Supabase. Luego se cambian `SUPABASE_URL`
y `SUPABASE_KEY` en las páginas por las del proyecto nuevo.

**No pegues los `.sql` sueltos a ojo.** No son un esquema: son la historia de
parches de una tienda, y **14 funciones están definidas en más de un archivo**
—`venta_guardar` en cuatro—. Al pegar gana la última, así que un orden mal
puesto no da error: deja corriendo una versión vieja de la función que guarda
las ventas, y eso no se ve hasta que los números no cuadran.

`armar_sql.py` conoce esas 14, comprueba que gane la buena y **se niega a
escribir** si el orden no lo cumple, diciendo cuál y por qué.

Si añades un `.sql`, méte­lo en `ORDEN` dentro del script. Un archivo que esté en
la carpeta y no en la lista también detiene la generación: no pegarlo significa
una función que no va a existir, y eso se descubre en producción.

## Alta de una tienda

1. En el menú → **Registrar tienda**, con el correo del gerente.
2. La base le pone sola su **clave de escritura** (`supabase_token_alta.sql`).
   Sin ella la app se ve entera pero no guarda nada, y todas las pantallas lo
   avisan al abrir.
3. En Admin → Configuración: el equipo, el responsable de revisar ventas y los
   códigos de reparación.
4. Para los avisos push, `tiendas.app_url` con la dirección de tu copia.

## Deploy

```powershell
python verificar.py     # tiene que decir "Todo en orden"
git add <lo que tocaste>; git commit -m "vNN — qué cambió"; git push origin main
```

**Si tocaste un `.html`, sube `VERSION` en `sw.js`.** El service worker sirve lo
que tiene en caché, así que sin ese cambio los celulares del equipo se quedan
con la versión vieja — sin error y sin aviso, solo el comportamiento de antes.
`verificar.py` detiene el commit si se te olvida; hazle caso.

Nada de `git add -A`: nombra lo que subes. Este repo es **público**.

## Antes del primer commit: `_privado/`

```
cp _privado/datos_equipo.txt.ejemplo _privado/datos_equipo.txt
```

Y escribe ahí los apellidos y números de tu equipo. `verificar.py` compara todo
lo que git va a publicar contra esa lista y **detiene el commit** si un nombre
se coló en un archivo del repo. El archivo no se sube.

Esa comprobación corre **en tu máquina**, no en GitHub Actions: allí `_privado/`
no existe y el job solo lo avisa.

## De dónde viene

De `tablero-hes1217`, la app de una sola tienda, con el historial empezado de
cero y sin lo que era de aquella tienda. Los cambios de allá **no llegan aquí**:
son dos repos y cada uno va por su lado.

# Tablero del Equipo — HES 1217 Angelópolis

App móvil para que los vendedores consulten en su celular, en un solo lugar:
🔥 Promociones vigentes · 🏷️ EOL/última pieza al 50% · 📦 Mercancía nueva · 📊 Inventario · 📢 Avisos.

Acceso por **link + QR** (sin instalar nada). Buscador y filtros por categoría.

## Archivos
- `index.html` — la app (diseño + lógica). **No se toca normalmente.**
- `datos.js` — **aquí vive toda la información.** Esto es lo que se actualiza.
- `logo_odemas.png` — branding Odemás.
- `sw.js` — service worker. Su `VERSION` es lo que hace que los celulares
  reciban un cambio; ver **Deploy**.

## Cómo se actualiza (flujo con Claude)
1. Ángel comparte el comunicado (PDF/imagen) o el export de inventario del día.
2. Claude lo digiere y actualiza `datos.js` (y la fecha de "Actualizado").
3. Se hace push a `main` → la página queda al día. **El link y el QR NO cambian.**

## Actualizar a mano (opcional)
Editar `datos.js`. Cada bloque (`promos`, `eol`, `novedades`, `inventario`, `avisos`)
es una lista de tarjetas. Copiar una entrada existente y cambiar los textos.
- Fechas: formato `AAAA-MM-DD`.
- `prioridad: "alta"` resalta la tarjeta.
- Inventario: `stock` 0 = rojo, 1-3 = naranja, 4+ = verde (semáforo automático).

## Deploy
Se publica solo: **GitHub Pages sirve lo que esté en `main`**. No hay script ni
panel que apretar — el deploy es el push.

```powershell
python verificar.py     # tiene que decir "Todo en orden"
git add -A; git commit -m "v___ — qué cambió"; git push origin main
```

Queda en https://angeljesus8-blip.github.io/tablero-hes1217/ un minuto después.

**Si tocaste un `.html`, sube `VERSION` en `sw.js`.** El service worker sirve la
copia que tiene en caché, así que sin ese cambio los celulares del equipo se
quedan con la versión vieja — sin error y sin aviso, solo el comportamiento de
antes. `verificar.py` detiene el commit si se te olvida; hazle caso.

> Hubo un `deploy.ps1` que publicaba en Netlify. Ya no: el tablero vive en
> GitHub Pages y aquel camino no subía `VERSION` ni corría `verificar.py`.

## Lo que GitHub NO guarda

Dos carpetas quedan fuera del repo a propósito, y de ellas no hay copia en
ningún otro sitio:

- `_privado\` — los nombres del equipo y el mapeo al Excel regional. Sin
  `datos_equipo.txt` el verificador falla; sin `mapeo_nombres.sql` no se puede
  repegar el mapeo y las comisiones dejan de sumarse. **Irrecuperable.**
- `eol\` — los PDF del CEA. Se pueden volver a pedir, pero cuesta.

```powershell
.\respaldar_privado.ps1              # copia a OneDrive y comprueba
.\respaldar_privado.ps1 -Revisar     # solo dice cómo está, no copia
```

Compara por **hash y no por fecha**: copiar un archivo le pone fecha nueva, así
que la fecha dice cuándo se copió, no si el contenido es el mismo. Y comprueba
después de copiar — un disco lleno o OneDrive a medio sincronizar dejan el
archivo a medias sin dar error.

Córrelo cada vez que toques `_privado\`, que es cuando entra o sale alguien del
equipo.

-- ============================================================
-- cargar_ventas quedó apuntando a una restricción que ya no existe
-- 4-ago-2026 · PENDIENTE DE APLICAR
-- ============================================================
--
-- Qué pasó
-- --------
-- Al cambiar la regla de la serie (`supabase_ventas_devolucion.sql`) se quitó
-- `UNIQUE (store_id, serie)` y se puso `UNIQUE (store_id, serie, dia_venta)`.
--
-- `cargar_ventas` hace `ON CONFLICT (store_id, serie) DO NOTHING`, y ese
-- ON CONFLICT necesita una restricción que coincida exactamente. Al no existir
-- ya, la carga de ventas falla entera:
--
--     ERROR 42P10: there is no unique or exclusion constraint matching the
--                  ON CONFLICT specification
--
-- Es una consecuencia directa del cambio anterior y no se previó: se revisó qué
-- LEE la restricción y no qué ESCRIBE contra ella.
--
-- Lo encontró `resincronizar()` en su primera ejecución, y ahí se vio para qué
-- sirve pararse: sin eso, `cargar_cortes` habría corrido detrás con las ventas
-- a medias. El corte se despeja como (total de ventas − vendido desde el
-- corte); con las ventas sin cargar, todos los cortes salen en cero y el
-- tablero enseña como "vendido" el histórico entero y el stock en cero. En piso
-- eso es dejar de vender lo que sí hay, sin ningún aviso.
--
-- Cómo se arregla
-- ---------------
-- Se reescribe SOLO el fragmento del ON CONFLICT. El resto del cuerpo de
-- `cargar_ventas` no está versionado en este repo —se aplicó directo en el
-- editor el 2-ago— así que reescribir la función entera sería inventarse el
-- resto. Esto la lee de la base, cambia esa línea y la vuelve a crear.
-- ============================================================

DO $mig$
DECLARE def text; nuevo text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO def
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'cargar_ventas';

  IF def IS NULL THEN
    RAISE EXCEPTION 'no existe public.cargar_ventas';
  END IF;

  nuevo := replace(def,
    'ON CONFLICT (store_id, serie) DO NOTHING',
    'ON CONFLICT (store_id, serie, dia_venta) DO NOTHING');

  -- Si el texto no era el esperado, no se toca nada: mejor fallar aquí que
  -- recrear la función con algo que no se ha comprobado.
  IF nuevo = def THEN
    RAISE EXCEPTION 'no se encontro el ON CONFLICT esperado en cargar_ventas';
  END IF;

  EXECUTE nuevo;
END $mig$;

-- Comprobar que quedó
select substring(pg_get_functiondef(p.oid) from 'ON CONFLICT[^\n]*') as ahora
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'cargar_ventas';
-- Esperado:  ON CONFLICT (store_id, serie, dia_venta) DO NOTHING;

-- Y después, la resincronización completa:
--   SELECT * FROM public.resincronizar('1217');
-- Los seis pasos tienen que traer un conteo. Solo entonces tiene sentido
-- comparar contra el Apps Script.

/* ============================================================
   Nota sobre `dia_venta` y ON CONFLICT

   `dia_venta` la calcula un trigger BEFORE INSERT, y en Postgres los triggers
   BEFORE corren ANTES de comprobar el conflicto, así que para cuando se evalúa
   el ON CONFLICT la columna ya tiene su valor. Por eso esto funciona sin tocar
   el INSERT.
   ============================================================ */

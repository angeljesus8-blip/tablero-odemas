-- ============================================================
--  QUITAR EL MODULO DE MR FIX DE UNA BASE QUE YA LO TIENE
-- ============================================================
--
--  Se pega UNA VEZ, y solo en una base donde el modulo llego a montarse. Las
--  bases nuevas ya no lo crean: sus cinco .sql salieron de `armar_sql.py` el
--  1-sep-2026, asi que `supabase_TODO.sql` nunca los pega.
--
--  ⚠️ EL ORDEN NO ES INDIFERENTE: PRIMERO `supabase_TODO.sql`, DESPUES ESTO.
--
--  El PASO 2 quita `tiendas.sku_reparacion`, y las funciones de login que hay
--  puestas en una base vieja todavia hacen `SELECT ... t.sku_reparacion`. Una
--  funcion no impide borrar la columna que lee —Postgres no lo cuenta como
--  dependencia—, asi que el DROP pasa sin quejarse y el login revienta con
--  «column t.sku_reparacion does not exist» la siguiente vez que alguien entre
--  a la app. Al reves —repegar primero— el login ya no la nombra y esto no
--  rompe nada.
--
--  QUE SE LLEVA: accesorios con SKU generico, reparaciones y la consulta de los
--  tecnicos externos. Cuatro tablas y sus funciones.
--
--  ⚠️ BORRA DATOS. Si en esa base se llego a capturar un accesorio o una
--  reparacion, se van con la tabla y no hay vuelta atras. En una base recien
--  montada no hay nada que perder; comprobalo con el PASO 0 antes de seguir.
--
--  Este archivo NO se llama `supabase_*.sql` a proposito: `armar_sql.py` exige
--  que todo `supabase_*.sql` de la carpeta este en su ORDEN y se pegue siempre,
--  y esto es lo contrario — se pega una vez y no se vuelve a mirar.


-- ── PASO 0 · Que hay que perder ─────────────────────────────
-- Corre esto SOLO, mira el resultado, y sigue si estas de acuerdo. Si alguna
-- fila trae un numero distinto de cero, ahi hay trabajo capturado por alguien.
--
-- Si responde «relation "public.…" does not exist», esa tabla no llego a
-- crearse: no hay nada que perder por ese lado. Salta al PASO 1, que aguanta
-- que falten — todo lo suyo lleva IF EXISTS.
SELECT 'accesorios_ventas'   AS tabla, count(*) AS filas FROM public.accesorios_ventas
UNION ALL SELECT 'reparaciones',       count(*) FROM public.reparaciones
UNION ALL SELECT 'accesorios_catalogo', count(*) FROM public.accesorios_catalogo
UNION ALL SELECT 'tecnicos_acceso',     count(*) FROM public.tecnicos_acceso;


-- ── PASO 1 · Las funciones ──────────────────────────────────
/* Se borran por su firma real, leida de `pg_proc`, y no de una lista escrita a
   mano: varias tienen doce parametros con DEFAULT y basta equivocarse en uno
   para que el DROP no encuentre nada y no diga nada. Lo que sobrevive a esto no
   es una funcion olvidada: es que su nombre no empieza como esperabamos, y el
   PASO 3 lo enseña. */
DO $$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS firma
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND (p.proname LIKE 'accesorio%' OR
            p.proname LIKE 'tecnico%'   OR
            p.proname LIKE 'reparacion%')
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || f.firma || ' CASCADE';
  END LOOP;
END $$;


-- ── PASO 2 · Las tablas y lo que colgaba de ellas ───────────
-- CASCADE se lleva politicas, indices y triggers propios. No toca `ventas` ni
-- `catalogo`: los accesorios nunca vivieron ahi, y esa separacion es justo la
-- que impedia que un cargador hundiera el Assurant y descontara stock.
DROP TABLE IF EXISTS public.accesorios_ventas   CASCADE;
DROP TABLE IF EXISTS public.reparaciones        CASCADE;
DROP TABLE IF EXISTS public.accesorios_catalogo CASCADE;
DROP TABLE IF EXISTS public.tecnicos_acceso     CASCADE;

-- La columna que solo existia para el Excel regional de Mr Fix: el nombre del
-- empleado tal como lo espera esa hoja. Sin reporte, no la lee nadie.
ALTER TABLE public.empleados DROP COLUMN IF EXISTS nombre_reporte;

-- Los codigos con los que el POS cobra una reparacion. Servian para que Captura
-- distinguiera sola una reparacion de un accesorio; ya no hay ni lo uno ni lo
-- otro, y el login dejo de entregarlo.
ALTER TABLE public.tiendas DROP COLUMN IF EXISTS sku_reparacion;


-- ── PASO 3 · Comprobar ──────────────────────────────────────
-- Las dos consultas tienen que devolver CERO filas.
SELECT tablename AS tabla_que_sobrevivio
  FROM pg_tables
 WHERE schemaname = 'public'
   AND (tablename LIKE 'accesorio%' OR tablename LIKE 'tecnico%'
        OR tablename LIKE 'reparacion%');

SELECT p.proname AS funcion_que_sobrevivio
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND (p.proname LIKE 'accesorio%' OR p.proname LIKE 'tecnico%'
        OR p.proname LIKE 'reparacion%');

-- Y que lo que se queda siga entero: 52 funciones —el tablero, la captura, el
-- inventario, los apartados—. Si el numero sale mas bajo, algo se llevo por
-- delante un CASCADE; se arregla repegando `supabase_TODO.sql`, que es
-- idempotente.
SELECT count(DISTINCT p.proname) AS funciones_que_quedan
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public';

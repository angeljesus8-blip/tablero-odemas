-- ============================================================
--  LA EVIDENCIA PARA APAGAR LA DOBLE ESCRITURA
--  17-ago-2026
-- ============================================================
--
--  Complemento de `supabase_comparacion_diaria.sql`. Aquel construyó el
--  mecanismo de medición; este arregla las tres cosas que hacían que el
--  mecanismo no midiera nada.
--
--  ------------------------------------------------------------
--  QUÉ SE ENCONTRÓ EL 17-AGO
--  ------------------------------------------------------------
--  La tabla `ventas_comparacion` tenía UNA fila: 8-ago, en_sheet 0,
--  en_supabase 0, cuadra TRUE. Y `dias_cuadrando` devolvía 1.
--
--  Ese 1 era falso por partida doble:
--
--   1. La fila es el resto de una prueba. El 8-ago hubo 9 ventas (3 normales y
--      6 entregas de preventa); la medición se corrió temprano, con el día
--      vacío, y guardó 0 contra 0.
--
--   2. **Cero contra cero cuadra trivialmente.** `dias_cuadrando` contaba ese
--      día como día bueno. Un domingo cerrado, o un día en que el Apps Script
--      devolviera lista vacía, sumaban a la racha sin haber comparado nada. Es
--      el número que decide si se apaga el flujo de ventas de la tienda, y se
--      podía llenar de días vacíos.
--
--   3. El trabajo nocturno **nunca se agendó**, y se comprobó por qué:
--      `pg_cron_instalada = false`. El bloque `DO` del archivo anterior está
--      escrito para no fallar si falta la extensión: suelta un `RAISE NOTICE` y
--      sigue. El script dijo "listo" y no agendó nada, así que pasaron nueve
--      días sin una sola medición. Un aviso en un panel que nadie vuelve a
--      mirar es lo mismo que ningún aviso.
--
--  Es el mismo fallo que el candado del Apps Script: buscar en un registro
--  vacío devuelve cero coincidencias, que es exactamente lo que se vería si
--  todo estuviera bien.
--
--  ------------------------------------------------------------
--  NO HAY QUE ESPERAR DÍAS
--  ------------------------------------------------------------
--  `comparar_ventas` acepta una fecha y le pregunta al Apps Script por
--  `modo=ventas_detalle&fecha=…`. La hoja conserva el histórico, así que los
--  días ya vividos se pueden comparar HOY, sin esperar.
--
--  Lo que hay que medir son los días desde el 5-ago (ver `p_desde` en el punto
--  3): doce días con ventas que nunca se cotejaron. Los anteriores NO, y esa
--  distinción es la mitad del trabajo — medirlos daría doce cuadres falsos.
--
--  Se pega completo en el SQL Editor. Es idempotente.
--  Después hay que CORRER el backfill a mano: ver "CÓMO SE USA" al final.
-- ============================================================


-- ── 1 · Un día sin ventas ya no suma a la racha ─────────────
--
-- Tres casos, y los tres tienen que comportarse distinto:
--
--   · día con ventas y cuadra      -> suma a la racha
--   · día con ventas y NO cuadra   -> la rompe
--   · día sin ventas (0 contra 0)  -> ni suma ni rompe: SE SALTA
--
-- Que un día vacío no rompa es tan importante como que no sume: si rompiera,
-- un domingo cerrado dejaría la racha en cero para siempre y nunca se podría
-- apagar nada.
--
-- Y el cuarto caso, el que no se ve: un día que NO SE PUDO MEDIR (`cuadra`
-- NULL, el Apps Script no contestó) SÍ rompe la racha, y por eso entra al
-- conjunto aunque venga con los contadores en NULL. No se sabe qué pasó ese
-- día, y una racha con un agujero no es evidencia de nada.
CREATE OR REPLACE FUNCTION public.dias_cuadrando(p_store text DEFAULT '1217')
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT count(*)::int FROM (
    SELECT bool_and(coalesce(cuadra, false)) OVER (ORDER BY dia DESC
                                                   ROWS BETWEEN UNBOUNDED PRECEDING
                                                            AND CURRENT ROW) AS racha
    FROM public.ventas_comparacion
    WHERE store_id = p_store
      -- los días medidos y vacíos se caen aquí; los que fallaron se quedan
      AND (cuadra IS NULL OR coalesce(en_sheet,0) + coalesce(en_supabase,0) > 0)
  ) t WHERE racha;
$$;

COMMENT ON FUNCTION public.dias_cuadrando(text) IS
  'Dias seguidos cuadrando, contando hacia atras. Los dias sin ventas se saltan '
  '(0 contra 0 cuadra trivialmente y no prueba nada); los dias que no se '
  'pudieron medir rompen la racha.';


-- ── 2 · Medir los días que ya pasaron ───────────────────────
--
-- LA PAUSA NO ES OPCIONAL. El Apps Script descarta las llamadas encimadas
-- **respondiendo 200**, así que un backfill a toda velocidad no da error: da
-- días medidos contra una lista vacía, que se leen como "faltan todas las
-- ventas" — un rojo falso justo en la medición que decide.
--
-- El umbral es inconsistente (se ha visto fallar entre 1,5 s y 5 s), por eso
-- son 3 s por defecto y por eso la función DEVUELVE UNA FILA POR DÍA en vez de
-- un "listo": hay que mirar el conteo final, no fiarse de que terminó.
--
-- Si un día sale con `error` o con `en_sheet` en 0 teniendo ventas, se vuelve
-- a correr ESE día suelto con una pausa mayor.
CREATE OR REPLACE FUNCTION public.comparar_ventas_backfill(
  p_store text    DEFAULT '1217',
  p_desde date    DEFAULT NULL,
  p_hasta date    DEFAULT NULL,
  p_pausa numeric DEFAULT 3
)
RETURNS TABLE (dia date, cuadra boolean, en_sheet integer, en_supabase integer,
               n_faltan integer, error text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_hoy   date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  v_hasta date := coalesce(p_hasta, v_hoy - 1);
  v_desde date := coalesce(p_desde, coalesce(p_hasta, v_hoy - 1) - 6);
  d       date;
  r       jsonb;
  n       integer := 0;
BEGIN
  -- El día de HOY no se mide: todavía se está capturando y daría diferencias
  -- falsas. Es el mismo motivo por el que el trabajo nocturno mide AYER.
  IF v_hasta >= v_hoy THEN
    RAISE EXCEPTION 'El dia de hoy (%) no se puede medir: no ha terminado.', v_hoy;
  END IF;
  IF v_desde > v_hasta THEN
    RAISE EXCEPTION 'El rango esta al reves: desde % hasta %.', v_desde, v_hasta;
  END IF;

  FOR d IN SELECT g::date FROM generate_series(v_desde, v_hasta, interval '1 day') g
           ORDER BY 1
  LOOP
    IF n > 0 THEN PERFORM pg_sleep(p_pausa); END IF;   -- nunca antes del primero
    n := n + 1;

    r := public.comparar_ventas_guardar(p_store, d);

    dia         := d;
    cuadra      := CASE WHEN r->>'ok' = 'true' THEN (r->>'cuadra')::boolean END;
    en_sheet    := (r->>'en_sheet')::integer;
    en_supabase := (r->>'en_supabase')::integer;
    n_faltan    := coalesce(jsonb_array_length(r->'faltan_en_supabase'), 0);
    error       := r->>'error';
    RETURN NEXT;
  END LOOP;
END $fn$;

REVOKE ALL ON FUNCTION public.comparar_ventas_backfill(text,date,date,numeric)
  FROM public, anon, authenticated;


-- ── 3 · El número que decide, sin agujeros ──────────────────
--
-- `dias_cuadrando` solo mira las filas QUE EXISTEN. Si el trabajo nocturno se
-- cae tres días, esos días no aparecen en la tabla, la racha salta el hueco y
-- se lee como tres días sin problemas. Es exactamente lo que acaba de pasar:
-- nueve días sin medir y un "1 día cuadrando" que parecía tranquilizador.
--
-- Por eso el veredicto cuenta aparte los días CON VENTAS que nadie comparó. Si
-- hay uno solo, no se apaga nada, por larga que sea la racha.
-- OJO AL REPEGAR: la firma cambió (se añadió `p_desde`) respecto de la primera
-- versión de este archivo, del 17-ago por la mañana. `CREATE OR REPLACE` solo
-- reemplaza cuando los parámetros son IDÉNTICOS; con una firma distinta deja
-- las dos y la llamada `listo_para_apagar('1217')` se vuelve ambigua. Ya pasó
-- con `venta_guardar`: PostgREST responde PGRST203 y deja de guardar.
DROP FUNCTION IF EXISTS public.listo_para_apagar(text, integer);

-- SOBRE `p_desde`: es el primer día completo con doble escritura. La fase 3 se
-- desplegó el 4-ago-2026 ("cada venta cae en los dos lados"), a mitad del día,
-- así que el primer día entero es el 5.
--
-- Pedir evidencia de días ANTERIORES no es ser más estricto, es medir otra
-- cosa: esas ventas llegaron a Supabase desde la propia hoja, vía
-- `cargar_ventas`. Compararlas sería comparar la hoja consigo misma —cuadran
-- por construcción y no prueban que la doble escritura funcione—. Es el mismo
-- cero contra cero de la fila del 8-ago, solo que más caro.
CREATE OR REPLACE FUNCTION public.listo_para_apagar(
  p_store  text    DEFAULT '1217',
  p_minimo integer DEFAULT 5,
  p_desde  date    DEFAULT '2026-08-05'
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_hoy    date    := (now() AT TIME ZONE 'America/Mexico_City')::date;
  v_racha  integer := public.dias_cuadrando(p_store);
  v_ultimo date;
  v_huecos integer;
BEGIN
  SELECT max(dia) INTO v_ultimo
    FROM public.ventas_comparacion WHERE store_id = p_store;

  -- Días con ventas normales (las entregas de preventa no van a la hoja, así
  -- que un día que solo tuvo entregas no cuenta como día sin medir).
  SELECT count(*) INTO v_huecos FROM (
    SELECT DISTINCT v.dia_venta AS d
      FROM public.ventas v
     WHERE v.store_id = p_store
       AND v.dia_venta <  v_hoy
       AND v.dia_venta >= p_desde
       AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
  ) t
  WHERE NOT EXISTS (
    SELECT 1 FROM public.ventas_comparacion c
     WHERE c.store_id = p_store AND c.dia = t.d
       AND c.cuadra IS NOT NULL          -- medido y contestado, no solo intentado
  );

  RETURN jsonb_build_object(
    'dias_cuadrando',            v_racha,
    'minimo_pedido',             p_minimo,
    'ultimo_dia_medido',         v_ultimo,
    'dias_con_ventas_sin_medir', v_huecos,
    'listo',  (v_racha >= p_minimo AND v_huecos = 0),
    'motivo', CASE
      WHEN v_huecos > 0     THEN 'hay ' || v_huecos || ' dia(s) con ventas que nadie comparo'
      WHEN v_racha < p_minimo THEN 'la racha es corta: ' || v_racha || ' de ' || p_minimo
      ELSE 'se puede apagar la doble escritura de ventas'
    END);
END $fn$;

COMMENT ON FUNCTION public.listo_para_apagar(text,integer,date) IS
  'El veredicto para apagar la doble escritura. Mira la racha Y los dias con '
  'ventas que nunca se midieron: una racha con agujeros no es evidencia. Solo '
  'cuenta desde que existe la doble escritura (5-ago-2026): antes de esa fecha '
  'comparar la hoja contra Supabase es comparar la hoja consigo misma.';


-- ── 4 · Que el trabajo nocturno quede agendado de verdad ────
--
-- Igual que antes, pero sin dar por bueno el silencio: al final de este archivo
-- hay un SELECT que dice si quedó o no. Si `pg_cron` no está habilitada,
-- hay que activarla primero en el panel:
--
--     Database -> Extensions -> buscar "pg_cron" -> Enable
--
-- y volver a pegar este archivo. No se lanza una excepción a propósito: el
-- editor corre todo en una transacción y abortaría también las funciones de
-- arriba, que sí sirven sin cron.
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('comparar_ventas_diario')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'comparar_ventas_diario');

    PERFORM cron.schedule(
      'comparar_ventas_diario',
      '0 8 * * *',                        -- 02:00 en México, la tienda ya cerró
      $sql$ SELECT public.comparar_ventas_guardar('1217'); $sql$
    );
  END IF;
END $do$;


-- ── 5 · El estado, de un vistazo ────────────────────────────
-- Envuelto en una función porque `cron.job` NO EXISTE si pg_cron está apagada,
-- y un SELECT directo contra ella reventaría justo en el caso que se quiere
-- diagnosticar.
CREATE OR REPLACE FUNCTION public.estado_comparacion(p_store text DEFAULT '1217')
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cron boolean := EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron');
  v_job  integer := 0;
BEGIN
  IF v_cron AND to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM cron.job WHERE jobname = ''comparar_ventas_diario'''
      INTO v_job;
  END IF;

  RETURN jsonb_build_object(
    'pg_cron_instalada',         v_cron,
    'trabajo_nocturno_agendado', v_job > 0,
    'dias_medidos',              (SELECT count(*) FROM public.ventas_comparacion
                                   WHERE store_id = p_store),
    'veredicto',                 public.listo_para_apagar(p_store));
END $fn$;


-- Esto es lo que hay que leer al terminar de pegar el archivo:
SELECT public.estado_comparacion('1217');


-- ============================================================
--  CÓMO SE USA
-- ============================================================
--
--  1) Habilitar pg_cron ANTES de pegar nada: Database -> Extensions -> buscar
--     "pg_cron" -> Enable. Se comprobó el 17-ago que NO estaba, y es la razón
--     de que no exista ni una medición.
--
--  2) Pegar este archivo. Mirar el SELECT final: `trabajo_nocturno_agendado`
--     tiene que decir true. Si dice false, el paso 1 no se hizo.
--
--  3) Medir los días que ya pasaron, EN DOS TANDAS. Son llamadas al Apps
--     Script con 3 s de pausa: doce de un tirón se acercan al límite de tiempo
--     del editor.
--
--       select * from public.comparar_ventas_backfill('1217','2026-08-11','2026-08-16');
--       select * from public.comparar_ventas_backfill('1217','2026-08-05','2026-08-10');
--
--     NO medir antes del 5-ago: ahí no había doble escritura que comprobar.
--
--     VERIFICAR EL CONTEO FINAL, no que haya terminado: cada fila trae su
--     `error` y sus contadores. Un día con `en_sheet` 0 teniendo ventas es una
--     llamada descartada, no un día sin ventas — se repite ese día solo, con
--     más pausa:
--
--       select * from public.comparar_ventas_backfill('1217','2026-08-12','2026-08-12',6);
--
--  3) El veredicto:
--
--       select public.listo_para_apagar('1217');
--
--     `listo: true` es lo único que autoriza a seguir con el apagado. Mientras
--     diga otra cosa, el motivo explica qué falta.
--
--  4) Ver el detalle de un día que no cuadre (qué series faltan):
--
--       select dia, en_sheet, en_supabase, faltan, sobran
--         from public.ventas_comparacion
--        where store_id = '1217' and coalesce(cuadra,false) = false
--        order by dia desc;
--
-- ============================================================
--  Odemás · Grupo Gigante — uso interno HES 1217
-- ============================================================

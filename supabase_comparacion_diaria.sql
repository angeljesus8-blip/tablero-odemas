-- ============================================================
--  COMPARACIÓN DIARIA DE VENTAS — la evidencia para apagar la hoja
--  7-ago-2026
-- ============================================================
--
--  La doble escritura de ventas es lo ÚLTIMO que queda del Apps Script, y es la
--  red de seguridad: mientras cada venta vaya a los dos lados, un día se puede
--  reconstruir. Para apagarla no basta con que "parezca que va bien": hace falta
--  ver varios días seguidos cuadrando sin diferencias.
--
--  Esto lo mide solo, cada noche, y lo deja escrito. Cuando haya una racha de
--  días limpios, esa racha ES la decisión.
--
--  ------------------------------------------------------------
--  LO QUE HABRÍA HECHO INÚTIL ESTA MEDICIÓN
--  ------------------------------------------------------------
--  `comparar_ventas` compara TODAS las ventas de Supabase contra la hoja. Pero
--  desde el 7-ago las entregas de preventa las escribe `apartado_entregar`
--  **solo en Supabase** —la hoja no se entera, por diseño—, así que cada equipo
--  entregado aparecería como "sobra en Supabase".
--
--  Con 10 apartados por entregar, el informe habría dicho "no cuadra" todos los
--  días por un motivo que es correcto. Y un indicador que siempre está en rojo
--  no es un indicador: es ruido que se acaba ignorando, justo antes de que un
--  día se ponga rojo de verdad.
--
--  Por eso las entregas de preventa se excluyen: no pasan por la doble
--  escritura y no tienen por qué estar en la hoja.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · Dónde se guarda la evidencia ────────────────────────
CREATE TABLE IF NOT EXISTS public.ventas_comparacion (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  dia        date        NOT NULL,
  en_sheet   integer,
  en_supabase integer,
  faltan     text[],      -- están en la hoja y no aquí: la doble escritura falló
  sobran     text[],      -- aquí y no en la hoja: normalmente una prueba sin borrar
  cuadra     boolean,
  error      text,        -- si no se pudo preguntar al Apps Script
  medido_en  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, dia)
);

ALTER TABLE public.ventas_comparacion ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.ventas_comparacion IS
  'Una fila por dia. Cuando haya varios dias seguidos con cuadra=true se puede '
  'apagar la doble escritura de ventas al Apps Script.';


-- ── 2 · La comparación, sin las entregas de preventa ────────
CREATE OR REPLACE FUNCTION public.comparar_ventas(p_store text, p_fecha date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $fn$
DECLARE
  v_fecha date := coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date);
  v_dmy   text;
  cuerpo  jsonb;
  sheet   text[];
  aqui    text[];
  faltan  text[];
  sobran  text[];
BEGIN
  -- El GAS espera d/M/yyyy SIN ceros a la izquierda: es como lo guarda la hoja
  -- y compara el texto letra por letra. Con '04/08/2026' no encuentra nada y
  -- devuelve lista vacía, que parecería "no hubo ventas".
  v_dmy := extract(day from v_fecha)::int || '/' ||
           extract(month from v_fecha)::int || '/' ||
           extract(year from v_fecha)::int;

  BEGIN
    SELECT r.content::jsonb INTO cuerpo
    FROM public.tiendas t,
         LATERAL extensions.http_get(
           t.gas_url || '?modo=ventas_detalle&fecha=' || v_dmy || '&t=' || t.gas_token) r
    WHERE t.store_id = p_store;
  EXCEPTION WHEN OTHERS THEN
    -- sin la URL en el mensaje: lleva el token dentro
    RETURN jsonb_build_object('ok', false, 'fecha', v_fecha,
      'error', 'no se pudo preguntar al Apps Script: ' ||
               left(regexp_replace(SQLERRM, 'https?://[^ ]+', '<url>', 'g'), 120));
  END;

  IF cuerpo IS NULL OR cuerpo ? 'error' THEN
    RETURN jsonb_build_object('ok', false, 'fecha', v_fecha,
                              'error', 'el Apps Script no devolvio ventas');
  END IF;

  SELECT coalesce(array_agg(DISTINCT x->>'serie'), '{}')
    INTO sheet
    FROM jsonb_array_elements(coalesce(cuerpo->'ventas', '[]'::jsonb)) x
   WHERE coalesce(trim(x->>'serie'), '') <> '';

  SELECT coalesce(array_agg(DISTINCT v.serie), '{}')
    INTO aqui
    FROM public.ventas v
   WHERE v.store_id = p_store AND v.dia_venta = v_fecha
     AND coalesce(trim(v.serie), '') <> ''
     -- Las entregas de preventa NO van a la hoja: las escribe apartado_entregar
     -- solo aquí, a propósito. Contarlas marcaría "no cuadra" cada vez que se
     -- entrega un equipo, y un indicador siempre en rojo deja de mirarse.
     AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id);

  SELECT coalesce(array_agg(s), '{}') INTO faltan
    FROM unnest(sheet) s WHERE NOT (s = ANY (aqui));
  SELECT coalesce(array_agg(s), '{}') INTO sobran
    FROM unnest(aqui) s WHERE NOT (s = ANY (sheet));

  RETURN jsonb_build_object(
    'ok', true,
    'fecha', v_fecha,
    'en_sheet', coalesce(array_length(sheet,1), 0),
    'en_supabase', coalesce(array_length(aqui,1), 0),
    -- faltan: están en el Sheet y no aquí. Son las que importan: significan que
    -- la doble escritura no llegó, y el inventario de Supabase muestra de más.
    'faltan_en_supabase', to_jsonb(faltan),
    -- sobran: aquí y no en el Sheet. Raro; suele ser una prueba sin borrar.
    'sobran_en_supabase', to_jsonb(sobran),
    'cuadra', (coalesce(array_length(faltan,1),0) = 0
           AND coalesce(array_length(sobran,1),0) = 0)
  );
END $fn$;


-- ── 3 · Medir un día y dejarlo escrito ──────────────────────
-- Sin parámetros: mide AYER. Es lo correcto para un trabajo nocturno — el día
-- de hoy todavía no ha terminado y compararlo daría diferencias falsas.
CREATE OR REPLACE FUNCTION public.comparar_ventas_guardar(
  p_store text DEFAULT '1217',
  p_fecha date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_fecha date := coalesce(p_fecha, ((now() AT TIME ZONE 'America/Mexico_City')::date - 1));
  r jsonb;
BEGIN
  r := public.comparar_ventas(p_store, v_fecha);

  INSERT INTO public.ventas_comparacion
    (store_id, dia, en_sheet, en_supabase, faltan, sobran, cuadra, error, medido_en)
  VALUES (
    p_store, v_fecha,
    (r->>'en_sheet')::int,
    (r->>'en_supabase')::int,
    CASE WHEN r ? 'faltan_en_supabase'
         THEN ARRAY(SELECT jsonb_array_elements_text(r->'faltan_en_supabase')) END,
    CASE WHEN r ? 'sobran_en_supabase'
         THEN ARRAY(SELECT jsonb_array_elements_text(r->'sobran_en_supabase')) END,
    -- Si no se pudo preguntar al Apps Script, `cuadra` queda NULL, NO false.
    -- "No se pudo medir" y "se midió y no cuadra" son cosas distintas, y
    -- confundirlas rompería la racha por una caída de red.
    CASE WHEN r->>'ok' = 'true' THEN (r->>'cuadra')::boolean ELSE NULL END,
    r->>'error',
    now())
  ON CONFLICT (store_id, dia) DO UPDATE
    SET en_sheet = excluded.en_sheet, en_supabase = excluded.en_supabase,
        faltan = excluded.faltan, sobran = excluded.sobran,
        cuadra = excluded.cuadra, error = excluded.error,
        medido_en = excluded.medido_en;

  RETURN r;
END $fn$;

REVOKE ALL ON FUNCTION public.comparar_ventas_guardar(text,date) FROM public, anon, authenticated;
-- No se expone: la corre el trabajo nocturno y, a mano, quien tenga el editor.


-- ── 4 · El resumen: ¿ya se puede apagar la hoja? ────────────
CREATE OR REPLACE VIEW public.ventas_comparacion_resumen AS
SELECT store_id, dia, cuadra, en_sheet, en_supabase,
       coalesce(array_length(faltan,1),0) AS n_faltan,
       coalesce(array_length(sobran,1),0) AS n_sobran,
       error, medido_en
FROM public.ventas_comparacion
ORDER BY store_id, dia DESC;

COMMENT ON VIEW public.ventas_comparacion_resumen IS
  'El historico, de mas reciente a mas viejo. Para decidir si se apaga la doble '
  'escritura: que los ultimos dias tengan cuadra=true y n_faltan=0.';

-- Cuántos días seguidos llevan cuadrando, contando hacia atrás desde el último
-- medido. Es EL número que decide si se apaga la hoja, así que se calcula una
-- vez y bien, en vez de dejar que cada quien lo cuente a ojo en la tabla.
--
-- Un día sin medir (cuadra NULL, porque el Apps Script no contestó) corta la
-- cuenta a propósito: no se sabe qué pasó ese día, y una racha con un hueco no
-- es evidencia de nada.
CREATE OR REPLACE FUNCTION public.dias_cuadrando(p_store text DEFAULT '1217')
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT count(*)::int FROM (
    SELECT cuadra,
           bool_and(coalesce(cuadra,false)) OVER (ORDER BY dia DESC
                                                  ROWS BETWEEN UNBOUNDED PRECEDING
                                                           AND CURRENT ROW) AS racha
    FROM public.ventas_comparacion WHERE store_id = p_store
  ) t WHERE racha;
$$;


-- ── 5 · Que corra solo cada noche ───────────────────────────
-- Necesita la extensión pg_cron. Si no está, habilítala en el panel de
-- Supabase: Database → Extensions → buscar "pg_cron" → Enable.
--
-- 08:00 UTC = 02:00 en México. Se elige de madrugada a propósito: la tienda ya
-- cerró y el día que se mide (ayer) está completo. Medir a media tarde daría
-- diferencias falsas por las ventas que aún faltan por capturar.
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('comparar_ventas_diario')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'comparar_ventas_diario');

    PERFORM cron.schedule(
      'comparar_ventas_diario',
      '0 8 * * *',
      $sql$ SELECT public.comparar_ventas_guardar('1217'); $sql$
    );
    RAISE NOTICE 'Agendado: comparar_ventas_diario, todos los dias a las 08:00 UTC (02:00 Mexico).';
  ELSE
    RAISE NOTICE 'pg_cron NO esta habilitada: la comparacion no se agendo.';
    RAISE NOTICE 'Habilitala en Database -> Extensions -> pg_cron, y vuelve a correr este archivo.';
  END IF;
END $do$;


-- ============================================================
--  CÓMO SE USA
-- ============================================================
--
--  Medir un día a mano (por ejemplo hoy, para probar que funciona):
--    select public.comparar_ventas_guardar('1217', current_date);
--
--  Cuantos dias seguidos lleva cuadrando (el numero que decide):
--    select public.dias_cuadrando('1217');
--
--  Ver el histórico:
--    select dia, cuadra, en_sheet, en_supabase, n_faltan, n_sobran, error
--      from public.ventas_comparacion_resumen
--     where store_id = '1217' order by dia desc limit 15;
--
--  Comprobar que el trabajo quedó agendado:
--    select jobname, schedule, active from cron.job;
--
--  ------------------------------------------------------------
--  CÓMO LEERLO — y cuándo se puede apagar la hoja
--  ------------------------------------------------------------
--   cuadra = true varios días seguidos
--     -> la doble escritura está funcionando. Con una semana limpia, y sin días
--        de venta rara en medio, se puede apagar el POST al Apps Script.
--
--   n_faltan > 0
--     -> ESAS ventas están en la hoja y NO en Supabase. Es lo grave: el
--        inventario del tablero está mostrando piezas de más. Mirar la cola de
--        Captura de Series (localStorage.odemas_sb_pend) en los celulares.
--
--   n_sobran > 0
--     -> están aquí y no en la hoja. Suele ser una prueba sin borrar. Las
--        entregas de preventa YA están excluidas y no deberían aparecer.
--
--   cuadra = NULL con error
--     -> no se pudo preguntar al Apps Script ese día. No cuenta como fallo,
--        pero tampoco suma a la racha: hay que volver a medir ese día a mano.
-- ============================================================

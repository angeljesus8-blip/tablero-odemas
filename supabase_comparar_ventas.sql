-- ============================================================
-- comparar_ventas() · ¿cuadran el Sheet y Supabase?
-- 4-ago-2026
-- ============================================================
--
-- Para qué
-- --------
-- La fase 3 escribe cada venta en los dos lados, y el plan dice que la
-- escritura al Sheet se apaga "cuando cuadren sin diferencias un par de días".
-- Eso exige comparar todos los días, y una comparación que hay que acordarse de
-- hacer a mano no se hace.
--
-- Hoy mismo, 4-ago-2026, cuatro cosas fallaron en silencio por no medirse: el
-- verificador que decía "todo en orden" sin mirar, el registro del guardián que
-- se lee igual vacío que correcto, el catálogo que llevaba dos días
-- descartándose tapado por el caché, y el inventario inflado que solo salió
-- porque Ángel preguntó. Esta función existe para que la fase 3 no sea la
-- quinta.
--
-- Cómo
-- ----
-- Postgres le pregunta al Apps Script por las ventas del día —igual que hacen
-- las `cargar_*`, con la extensión `http`— y las compara contra su propia
-- tabla. Devuelve qué series faltan de cada lado.
--
-- Qué NO compara, y por qué
-- -------------------------
-- Solo ventas CON número de serie. `leerVentasDetalle_` del Apps Script salta
-- las filas sin serie (`if(!serie) continue`), así que no hay forma de verlas
-- por aquí. Son pocas y ya están contadas en los hallazgos de la fase 1.
-- ============================================================

CREATE OR REPLACE FUNCTION public.comparar_ventas(p_store text, p_fecha date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_fecha   date := coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date);
  v_dmy     text;
  cuerpo    jsonb;
  sheet     text[];
  aqui      text[];
  faltan    text[];
  sobran    text[];
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
     AND coalesce(trim(v.serie), '') <> '';

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

REVOKE ALL ON FUNCTION public.comparar_ventas(text, date) FROM public;
GRANT EXECUTE ON FUNCTION public.comparar_ventas(text, date) TO anon, authenticated;

COMMENT ON FUNCTION public.comparar_ventas(text, date) IS
  'Pregunta al Apps Script por las ventas del dia y las compara con la tabla. '
  'Solo cuenta ventas con numero de serie: el GAS no expone las que no lo '
  'tienen. Sirve para decidir cuando se puede apagar la escritura al Sheet.';

-- ------------------------------------------------------------
--   select public.comparar_ventas('1217');            -- hoy
--   select public.comparar_ventas('1217','2026-08-03');
--
-- `cuadra: true` varios días seguidos es la señal para la fase 5. Un
-- `faltan_en_supabase` con series dentro NO es una venta perdida —está en el
-- Sheet— pero sí quiere decir que el inventario de Supabase muestra de más
-- hasta que se resincronice.
-- ============================================================

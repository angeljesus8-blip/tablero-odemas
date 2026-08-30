-- ============================================================
-- Fase 3 · Guardar una venta en Supabase (doble escritura)
-- 4-ago-2026 · APLICADO y probado el mismo día
--
-- Probado contra la base antes de conectar el cliente:
--   alta          -> {"ok":true,"id":692}
--   la misma otra vez -> {"ok":true,"duplicada":true}   (no error: reintento)
--   sin serie     -> {"ok":false,"error":"sin serie"}
--   una de las 8:30 p.m. -> dia_venta 2026-08-04 y hora 20:30 en México,
--                           NO el día siguiente, que era el riesgo real
--   filas de prueba borradas: 231 ventas antes y después
-- ============================================================
--
-- Regla que manda sobre todo lo demás
-- -----------------------------------
-- **El Sheet sigue siendo la fuente de verdad.** Esto se escribe ADEMÁS, nunca
-- en lugar de. Si esta función falla, la venta ya está guardada en el Sheet y
-- no se pierde nada; si fallara al revés, se perdería una venta, y eso ya pasó
-- el 1-ago-2026 y costó un día entero.
--
-- Por eso la función **no lanza nunca**: devuelve el problema como jsonb. Del
-- lado del cliente, un fallo aquí no puede tocar la cola de pendientes ni el
-- aviso al asesor.
--
-- Dos decisiones que no son obvias
-- --------------------------------
-- 1 · **Una serie repetida el mismo día NO es un error aquí.** La restricción
--     `ventas_serie_por_dia` existe para atrapar la doble captura humana, pero
--     en doble escritura el mismo INSERT puede llegar dos veces por un reintento
--     de red. Devolver error haría que el cliente reintentara para siempre. Se
--     responde `ok:true, duplicada:true`: la venta está, que es lo que importa.
--     Así la escritura es idempotente y se puede reintentar sin miedo.
--
-- 2 · **La fecha se arma aquí, no en el teléfono.** Llegan `fecha` y `hora` como
--     texto ('4/8/2026', '01:26 p.m.') porque es lo que guarda la cola de
--     capturas pendientes, que puede subirse horas después. Convertirlas en el
--     cliente significaría depender de la zona del aparato: una venta de las
--     8 pm acabaría con la fecha del día siguiente. Aquí se fija en hora de
--     México, igual que hace `isoVenta_` en el Apps Script.
-- ============================================================

CREATE OR REPLACE FUNCTION public.venta_guardar(
  p_store      text,
  p_serie      text,
  p_sku        text    DEFAULT NULL,
  p_desc       text    DEFAULT NULL,
  p_precio     numeric DEFAULT NULL,
  p_vendedor   text    DEFAULT NULL,
  p_seguro     boolean DEFAULT NULL,
  p_fecha      text    DEFAULT NULL,   -- '4/8/2026'  (d/M/yyyy, como la hoja)
  p_hora       text    DEFAULT NULL,   -- '01:26 p.m.'
  p_foto_url   text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cuando timestamptz;
  v_d int; v_m int; v_a int; v_h int := 12; v_min int := 0;
  m text[];
  nuevo bigint;
BEGIN
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  -- fecha: d/M/yyyy. Sin fecha reconocible se usa ahora, que es mejor que
  -- rechazar la venta: el dato existe y ya está en el Sheet.
  m := regexp_match(coalesce(p_fecha,''), '^(\d{1,2})/(\d{1,2})/(\d{4})$');
  IF m IS NULL THEN
    v_cuando := now();
  ELSE
    v_d := m[1]::int; v_m := m[2]::int; v_a := m[3]::int;
    -- hora: '1:26 p.m.' / '13:26'. Sin hora usable, mediodía: no se pasa de día
    -- en ninguna zona.
    m := regexp_match(lower(coalesce(p_hora,'')), '(\d{1,2}):(\d{2})\s*([ap])?');
    IF m IS NOT NULL THEN
      v_h := m[1]::int; v_min := m[2]::int;
      IF m[3] = 'p' AND v_h < 12 THEN v_h := v_h + 12; END IF;
      IF m[3] = 'a' AND v_h = 12 THEN v_h := 0; END IF;
    END IF;
    v_cuando := (format('%s-%s-%s %s:%s', v_a, lpad(v_m::text,2,'0'), lpad(v_d::text,2,'0'),
                        lpad(v_h::text,2,'0'), lpad(v_min::text,2,'0'))::timestamp)
                AT TIME ZONE 'America/Mexico_City';
  END IF;

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro, foto_url)
  VALUES
    (p_store, v_cuando, trim(p_serie), nullif(trim(coalesce(p_sku,'')),''),
     nullif(trim(coalesce(p_desc,'')),''), p_precio,
     nullif(trim(coalesce(p_vendedor,'')),''), p_seguro,
     nullif(trim(coalesce(p_foto_url,'')),''))
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);

EXCEPTION
  WHEN unique_violation THEN
    -- ya estaba: reintento de red, no un problema
    RETURN jsonb_build_object('ok', true, 'duplicada', true);
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text)
  TO anon, authenticated;

COMMENT ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text) IS
  'Doble escritura de la fase 3. El Sheet manda; esto escribe ADEMAS. No lanza '
  'nunca: devuelve el problema en jsonb para que un fallo aqui no pueda tocar la '
  'cola de capturas. Una serie repetida el mismo dia responde ok+duplicada, '
  'para que un reintento de red no se convierta en un bucle.';


-- ------------------------------------------------------------
-- Comprobar antes de conectar el cliente
-- ------------------------------------------------------------
--   select public.venta_guardar('1217','PRUEBA-F3-1','100304280','prueba',
--                               999,'prueba',true,'4/8/2026','01:26 p.m.');
--     → {"ok": true, "id": ...}
--
--   -- la misma otra vez: debe decir duplicada, NO error
--   select public.venta_guardar('1217','PRUEBA-F3-1','100304280','prueba',
--                               999,'prueba',true,'4/8/2026','01:26 p.m.');
--     → {"ok": true, "duplicada": true}
--
--   -- la fecha tiene que caer en el día correcto, no en el siguiente
--   select serie, dia_venta, vendida_en at time zone 'America/Mexico_City' as hora_mx
--   from public.ventas where serie = 'PRUEBA-F3-1';
--     → dia_venta 2026-08-04 y hora 13:26
--
--   delete from public.ventas where serie like 'PRUEBA-F3-%';
-- ============================================================

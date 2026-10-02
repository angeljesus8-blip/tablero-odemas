-- ============================================================
--  EL CANDADO, EXIGIDO
--  PASO 2 de 2 — NO PEGAR hasta que se cumpla lo de abajo
-- ============================================================
--
--  Va después de `supabase_candado.sql` (paso 1) y de publicar la app que manda
--  el token. Cierra TODAS las puertas a la vez, porque comparten `candado_ok_`.
--  La consulta de abajo ya mira todas las funciones y todas las tiendas: tiene
--  que dar cero para todas.
--
--  ⚠️ CUÁNDO SE PEGA
--  -----------------
--  Cuando esta consulta dé CERO filas para un día de venta completo, con la
--  app nueva ya publicada desde antes de abrir:
--
--      SELECT * FROM public.candado_sin_token
--       WHERE dia = (now() AT TIME ZONE 'America/Mexico_City')::date - 1;
--
--  Si sale algo, hay un celular con la app vieja (o alguien de fuera probando
--  la puerta, y eso también conviene saberlo antes). Mirar `ultimo`: a qué hora
--  fue la última llamada sin token ayuda a saber de quién es.
--
--  Qué cambia
--  ----------
--  Una sola cosa: el token AUSENTE deja de pasar. El equivocado ya se rechazaba
--  desde el paso 1. Se sigue contando igual, así que después de esto el
--  contador pasa a medir intentos rechazados.
--
--  Si algo sale mal
--  ----------------
--  Una venta rechazada NO se pierde: se queda en la cola del teléfono y sube
--  sola en cuanto la app se actualiza. Aun así, para volver al paso 1 basta con
--  repegar la sección 2 de `supabase_candado.sql` (la función `candado_ok_`).
-- ============================================================

CREATE OR REPLACE FUNCTION public.candado_ok_(p_store text, p_token text, p_funcion text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF coalesce(p_token, '') <> '' THEN
    RETURN public.escritura_ok_(p_store, p_token);
  END IF;

  IF EXISTS (SELECT 1 FROM public.tiendas t WHERE t.store_id = p_store) THEN
    INSERT INTO public.candado_sin_token AS c (store_id, funcion, dia, n, ultimo)
    VALUES (p_store, p_funcion, (now() AT TIME ZONE 'America/Mexico_City')::date, 1, now())
    ON CONFLICT (store_id, funcion, dia)
    DO UPDATE SET n = c.n + 1, ultimo = now();
  END IF;

  -- PASO 2: sin token, no.
  RETURN false;
END $fn$;

REVOKE ALL ON FUNCTION public.candado_ok_(text,text,text) FROM public, anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1 · Sin token ya no salen los apartados:
--
--      SELECT count(*) FROM public.apartados_lista('9999');
--      -- Esperado: 0.
--
--  2 · Y el tablero sigue viéndolos: abre el tablero en tu celular (app nueva) y
--      revisa la pestaña de apartados. Esa lleva el token; si ahí sale vacía,
--      algo no cuadra y hay que volver al paso 1.
--
--  3 · Una venta sin token se rechaza (y no se escribe nada):
--
--      SELECT public.venta_guardar('9999', 'PRUEBA-CANDADO');
--      -- Esperado: {"ok": false, "error": "sin permiso de escritura"}
-- ============================================================

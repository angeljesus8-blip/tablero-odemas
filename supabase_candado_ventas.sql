-- ============================================================
--  EL CANDADO, TAMBIÉN EN LAS VENTAS DEL DÍA
--  2-oct-2026 · va DESPUÉS de supabase_candado.sql
-- ============================================================
--
--  Qué lo trae
--  -----------
--  supabase_candado.sql dejó sin token tres lecturas, «porque no traen clientes».
--  Con una tienda real dentro eso se queda corto:
--
--    ventas_detalle → cada venta del día: serie, SKU, precio, NOMBRE DEL
--                     VENDEDOR y NÚMERO DEL EMPLEADO que la capturó. Se puede
--                     pedir por fecha.
--    ventas_hoy     → nombre de cada vendedor y sus ventas con/sin seguro: el
--                     Assurant Attach, el KPI crítico, por persona.
--    estado_datos   → cuántos SKUs y promos hay y quién y cuándo los subió.
--                     Ninguna página la llama.
--
--  Cualquiera con la clave publicable del HTML y el número de tienda (4 dígitos)
--  las leía. Son datos de las personas de la tienda y de su operación del día.
--
--  Cómo: igual que supabase_candado.sql. La función viva se RENOMBRA a
--  `<nombre>_filas_` (cuerpo intacto, sin permisos) y con el nombre de siempre se
--  pone una PUERTA con `p_token`. Quien las llamaba por dentro —`tablero_todo`
--  llama a `ventas_hoy`— se redirige a la interna, para no contar la misma
--  llamada dos veces ni dejarla sin token.
--
--  Diferencia: `ventas_detalle` lleva DOS parámetros (p_store, p_fecha). Su puerta
--  es (p_store, p_fecha DEFAULT NULL, p_token DEFAULT NULL): el token va AL FINAL
--  para que quien la llame con solo p_store y p_fecha siga resolviendo.
--
--  ⚠️ ORDEN — IMPORTA
--  -------------------
--  `candado_exigir.sql` ya está aplicado: una llamada SIN token se rechaza desde
--  el primer momento. Por eso, entre pegar este SQL y publicar la app v42, el
--  tablero y «Ventas del día» de una app vieja salen vacíos. Hoy solo la usa la
--  Demo; con tiendas reales habría que sacar la app antes y esto después. Pegar
--  este SQL e inmediatamente publicar la v42.
--
--  Una sola transacción; si ya se pegó, se detiene sin tocar nada.
-- ============================================================

BEGIN;

DO $do$
DECLARE
  n   text;
  k   int;
  sig text;
  esperada text;
  res text;
  r   record;
  llamada text := '\m(ventas_hoy|ventas_detalle|estado_datos)(\s*\()';
BEGIN
  -- ── 1 · Guardas: qué hay vivo, antes de tocar nada ─────────
  FOREACH n IN ARRAY ARRAY['ventas_hoy', 'ventas_detalle', 'estado_datos'] LOOP
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
                WHERE s.nspname = 'public' AND p.proname = n || '_filas_') THEN
      RAISE EXCEPTION '%_filas_ ya existe: este archivo ya se pegó. No se tocó nada.', n;
    END IF;

    SELECT count(*) INTO k FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
     WHERE s.nspname = 'public' AND p.proname = n;
    IF k <> 1 THEN
      RAISE EXCEPTION 'Esperaba UNA %, hay %. No se tocó nada: avísale a Claude.', n, k;
    END IF;

    SELECT pg_get_function_identity_arguments(p.oid) INTO sig
      FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
     WHERE s.nspname = 'public' AND p.proname = n;
    -- El CASE va en una asignación, no dentro del IF: plpgsql corta la condición
    -- en el primer THEN que ve, y el del CASE lo confunde con el del IF.
    esperada := CASE WHEN n = 'ventas_detalle' THEN 'p_store text, p_fecha date' ELSE 'p_store text' END;
    IF sig <> esperada THEN
      RAISE EXCEPTION '% tiene la firma (%), y esperaba (%). No se tocó nada.', n, sig, esperada;
    END IF;

    SELECT pg_get_function_result(p.oid) INTO res
      FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
     WHERE s.nspname = 'public' AND p.proname = n;
    IF res !~* '^(TABLE|SETOF)' THEN
      RAISE EXCEPTION '% devuelve % y no una tabla. No se tocó nada.', n, res;
    END IF;
  END LOOP;

  -- ── 2 · Cada una, a su interna ─────────────────────────────
  ALTER FUNCTION public.ventas_hoy(text)           RENAME TO ventas_hoy_filas_;
  ALTER FUNCTION public.ventas_detalle(text, date) RENAME TO ventas_detalle_filas_;
  ALTER FUNCTION public.estado_datos(text)         RENAME TO estado_datos_filas_;
  REVOKE ALL ON FUNCTION public.ventas_hoy_filas_(text)           FROM public, anon, authenticated;
  REVOKE ALL ON FUNCTION public.ventas_detalle_filas_(text, date) FROM public, anon, authenticated;
  REVOKE ALL ON FUNCTION public.estado_datos_filas_(text)         FROM public, anon, authenticated;

  -- ── 3 · Quien las llamaba por dentro, a las internas ───────
  -- Mismo método que supabase_candado.sql: se busca en la base, no en el repo.
  FOR r IN
    SELECT p.oid, p.proname
      FROM pg_proc p
      JOIN pg_namespace s ON s.oid = p.pronamespace
      JOIN pg_language l ON l.oid = p.prolang
     WHERE s.nspname = 'public'
       AND l.lanname IN ('sql', 'plpgsql')
       AND p.prosrc ~ llamada
  LOOP
    EXECUTE regexp_replace(pg_get_functiondef(r.oid), llamada, '\1_filas_\2', 'g');
    RAISE NOTICE 'redirigida a las internas: %', r.proname;
  END LOOP;

  -- ── 4 · Las puertas ────────────────────────────────────────
  -- Sin permiso devuelven CERO filas. Columnas copiadas de la función viva.
  FOREACH n IN ARRAY ARRAY['ventas_hoy', 'estado_datos'] LOOP
    SELECT pg_get_function_result(p.oid) INTO res
      FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
     WHERE s.nspname = 'public' AND p.proname = n || '_filas_';

    EXECUTE format($f$
      CREATE FUNCTION public.%I(p_store text, p_token text DEFAULT NULL)
      RETURNS %s
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
      AS $b$
      BEGIN
        IF NOT public.candado_ok_(p_store, p_token, %L) THEN
          RETURN;
        END IF;
        RETURN QUERY SELECT * FROM public.%I(p_store);
      END $b$
    $f$, n, res, n, n || '_filas_');

    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(text, text) FROM public', n);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(text, text) TO anon, authenticated', n);
  END LOOP;

  SELECT pg_get_function_result(p.oid) INTO res
    FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
   WHERE s.nspname = 'public' AND p.proname = 'ventas_detalle_filas_';

  EXECUTE format($f$
    CREATE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL, p_token text DEFAULT NULL)
    RETURNS %s
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
    AS $b$
    BEGIN
      IF NOT public.candado_ok_(p_store, p_token, 'ventas_detalle') THEN
        RETURN;
      END IF;
      RETURN QUERY SELECT * FROM public.ventas_detalle_filas_(p_store, p_fecha);
    END $b$
  $f$, res);

  REVOKE ALL ON FUNCTION public.ventas_detalle(text, date, text) FROM public;
  GRANT EXECUTE ON FUNCTION public.ventas_detalle(text, date, text) TO anon, authenticated;
END $do$;

NOTIFY pgrst, 'reload schema';

COMMIT;


-- ============================================================
--  COMPROBAR (las hago yo con la clave publicable)
-- ============================================================
--
--  1 · Con token inventado, ya nada:
--      ventas_hoy, ventas_detalle y estado_datos → [] (cero filas).
--  2 · Con el token de la tienda siguen dando sus filas (la Demo con PIN no
--      entra ya; se usa el login por número de empleado 100001).
--  3 · Las internas, cerradas:
--      SELECT p.proname, has_function_privilege('anon', p.oid, 'EXECUTE')
--        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE n.nspname = 'public' AND p.proname ~ '^(ventas_hoy|ventas_detalle|estado_datos)';
--      -- Esperado: las tres sin `_filas_` = true y las tres `_filas_` = false.
--  4 · Nadie llama ya a las puertas desde dentro de la base:
--      SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE n.nspname = 'public' AND p.prosrc ~ '\m(ventas_hoy|ventas_detalle|estado_datos)\s*\(';
--      -- Esperado: CERO filas.
-- ============================================================

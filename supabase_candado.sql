-- ============================================================
--  EL CANDADO DE LAS LECTURAS — copia multi-tienda (odemás)
--  2-oct-2026 · PASO 1 de 2 — PENDIENTE DE APLICAR
-- ============================================================
--
--  Qué lo trae
--  -----------
--  La clave publicable va escrita en el HTML y el repo es PÚBLICO. Con ella,
--  cualquiera puede llamar a las funciones de la base sin haber entrado a la
--  app y pasando el número de tienda (4 dígitos). Comprobado el 2-oct-2026
--  contra la tienda Demo 9999, sin token, con la clave publicable:
--
--    apartados_lista   → nombre y TELÉFONO de cada cliente con apartado
--    tablero_todo      → lo mismo, dentro del viaje único
--    inventario_vivo · catalogo_completo · promos_vigentes · eol_lista ·
--    avisos_vigentes · bundles_vigentes · eol_precio_venta
--                      → stock por SKU y circulares internas de la tienda
--
--  Con una sola tienda (la Demo) no pasaba nada. Con tiendas reales, cualquiera
--  podría leer los clientes de cualquiera —datos personales, LFPDPPP— y su
--  inventario.
--
--  Esto es el equivalente de supabase_candado.sql + supabase_candado_lecturas.sql
--  de la 1217, en UN solo archivo y adaptado a odemás. NO es una copia:
--
--  · `venta_guardar` NO se toca. En odemás ya pedía `p_token` desde el 1-sep
--    (supabase_venta_grupo.sql) y la 1217 apenas lo está cerrando. Reescribirla
--    aquí con el cuerpo de la 1217 quitaría `p_quien`/`capturado_por` de odemás.
--  · `apartados_lista` se trata igual que las siete lecturas: se RENOMBRA su
--    cuerpo vivo a `apartados_filas_` y se pone una puerta delante. No se
--    reescribe ningún cuerpo: de `inventario_vivo` hay tres versiones en el
--    repo y copiar «la última» es apostar a que es la de la base.
--
--  Qué NO cubre (a propósito, igual que la 1217)
--  ---------------------------------------------
--  `ventas_hoy` (conteo con/sin seguro por vendedor), `ventas_detalle` (serie,
--  precio, vendedor de cada venta del día) y `estado_datos` (fechas de carga)
--  siguen sin token. No traen nombre ni teléfono de clientes. `ventas_detalle`
--  es la más delicada de las tres: si se quiere cerrar, es decisión aparte.
--
--  Por qué en DOS pasos
--  --------------------
--  Exigir el token de golpe dejaría sin catálogo, promos ni apartados a cada
--  celular que siga con la app sin actualizar.
--
--  · PASO 1 (este archivo): las puertas piden `p_token`. Un token EQUIVOCADO ya
--    se rechaza. Un token AUSENTE todavía se deja pasar, pero se CUENTA en
--    `candado_sin_token`, por tienda, función y día.
--  · Se publica la app nueva, que manda el token.
--  · PASO 2 (`candado_exigir.sql`): cuando el contador lleve un día de
--    venta en cero, se pega y el token ausente también se rechaza.
--
--  ⚠️ ORDEN — IMPORTA
--  -------------------
--  1. Primero este SQL.  2. Después la app nueva.
--  Al revés, la app manda un `p_token` que la función aún no conoce, recibe
--  PGRST202 y se queda sin catálogo ni promos.
--
--  Todo va dentro de UNA transacción: si algo falla, no queda nada a medias. Y
--  si ya se pegó una vez, se detiene sin tocar nada (primer RAISE).
-- ============================================================

BEGIN;

-- ── 1 · El contador de llamadas sin token ───────────────────
-- Una fila por tienda, función y día. Solo lo escribe `candado_ok_`; nadie lo
-- lee desde la app, así que RLS sin políticas: cerrado a anon y authenticated.
CREATE TABLE IF NOT EXISTS public.candado_sin_token (
  store_id text        NOT NULL,
  funcion  text        NOT NULL,
  dia      date        NOT NULL,
  n        integer     NOT NULL DEFAULT 0,
  ultimo   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, funcion, dia)
);
ALTER TABLE public.candado_sin_token ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.candado_sin_token FROM anon, authenticated;


-- ── 2 · La guarda ───────────────────────────────────────────
-- Envuelve a `escritura_ok_`, que es la misma de las demás escrituras.
-- VOLATILE (el defecto) y NO `STABLE`: escribe en el contador, y PostgREST corre
-- las STABLE en transacción de solo lectura — daría 25006 y la app lo pintaría
-- como «sin conexión». Lo mismo vale para las puertas que la llaman.
--
-- Solo cuenta tiendas que existen: si no, cualquiera podría llenar la tabla
-- inventándose store_id.
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

  -- PASO 1: sin token todavía se deja pasar. El paso 2 cambia esta línea.
  RETURN true;
END $fn$;

REVOKE ALL ON FUNCTION public.candado_ok_(text,text,text) FROM public, anon, authenticated;


-- ── 3 · Las ocho lecturas: cada una a su interna, y una puerta ──
DO $do$
DECLARE
  nombres text[] := ARRAY['apartados_lista', 'inventario_vivo', 'catalogo_completo',
                          'promos_vigentes', 'eol_lista', 'avisos_vigentes',
                          'bundles_vigentes', 'eol_precio_venta'];
  llamada text := '\m(apartados_lista|inventario_vivo|catalogo_completo|promos_vigentes|'
               || 'eol_lista|avisos_vigentes|bundles_vigentes|eol_precio_venta)(\s*\()';
  n   text;
  k   int;
  sig text;
  res text;
  r   record;
BEGIN
  -- ── 3a · Cada una, a su interna ────────────────────────────
  FOREACH n IN ARRAY nombres LOOP
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
    IF sig <> 'p_store text' THEN
      RAISE EXCEPTION '% tiene la firma (%), y esperaba (p_store text). No se tocó nada.', n, sig;
    END IF;

    EXECUTE format('ALTER FUNCTION public.%I(text) RENAME TO %I', n, n || '_filas_');
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(text) FROM public, anon, authenticated',
                   n || '_filas_');
  END LOOP;

  -- ── 3b · Quien las llamaba por dentro, a las internas ──────
  -- `pg_get_functiondef` devuelve el CREATE OR REPLACE completo, con su
  -- SECURITY DEFINER y su search_path; al volver a ejecutarlo se conservan los
  -- permisos y el dueño. Solo cambia `inventario_vivo(` por
  -- `inventario_vivo_filas_(`, y así con las ocho. Si no, esa llamada entraría
  -- SIN token por la puerta nueva: ensuciaría el contador y en el paso 2 se
  -- rompería. Se buscan en la base, no en el repo: si hay alguna que el repo no
  -- conoce, también se arregla. El nombre de la propia interna no casa: ya
  -- termina en `_filas_`, y el patrón pide `(` detrás.
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

  -- ── 3c · La puerta, con el nombre de siempre ───────────────
  -- Sin permiso devuelve CERO filas: la app que tiene el token nunca cae aquí.
  -- Las columnas se copian de la función viva, no se escriben a mano.
  FOREACH n IN ARRAY nombres LOOP
    SELECT pg_get_function_result(p.oid) INTO res
      FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
     WHERE s.nspname = 'public' AND p.proname = n || '_filas_';
    IF res !~* '^(TABLE|SETOF)' THEN
      RAISE EXCEPTION '% devuelve % y no una tabla. No se tocó nada.', n, res;
    END IF;

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
END $do$;


-- ── 4 · tablero_todo: con token, todo; sin él, nada ─────────
-- La versión de un solo argumento SE BORRA: si se quedara al lado, seguiría
-- abierta a anon (Postgres da EXECUTE a PUBLIC al crear) y la llamada con solo
-- `p_store` sería ambigua entre las dos. Esta no se renombra porque no devuelve
-- una tabla, sino un jsonb armado a mano.
--
-- Las ocho se leen por sus internas: pasar por las puertas contaría la misma
-- llamada ocho veces en el contador. `ventas_hoy` no tiene candado, se llama
-- directo. `apartados_ok` existe para que la app distinga «no hay apartados» de
-- «no me dejaron verlos».
DROP FUNCTION public.tablero_todo(text);

CREATE FUNCTION public.tablero_todo(p_store text, p_token text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.candado_ok_(p_store, p_token, 'tablero_todo') THEN
    RETURN jsonb_build_object('ok', false, 'apartados_ok', false);
  END IF;
  RETURN jsonb_build_object(
    'inventario', (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.inventario_vivo_filas_(p_store) t),
    'eol',        (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.eol_lista_filas_(p_store) t),
    'eol_venta',  (SELECT coalesce(jsonb_object_agg(t.sku, t.precio50), '{}'::jsonb)
                     FROM public.eol_precio_venta_filas_(p_store) t),
    'promos',     (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.promos_vigentes_filas_(p_store) t),
    'bundles',    (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.bundles_vigentes_filas_(p_store) t),
    'avisos',     (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.avisos_vigentes_filas_(p_store) t),
    'apartados',  (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.apartados_lista_filas_(p_store) t),
    'apartados_ok', true,
    'ventas_hoy', (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.ventas_hoy(p_store) t)
  );
END $fn$;

REVOKE ALL ON FUNCTION public.tablero_todo(text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.tablero_todo(text,text) TO anon, authenticated;

-- Que PostgREST vea las firmas nuevas ya, y no al rato.
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ============================================================
--  COMPROBAR — pegar esto después y mirar las respuestas
-- ============================================================
--
--  1 · Cada una tiene su puerta (2 argumentos) y su interna (1):
--
--      SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
--             has_function_privilege('anon', p.oid, 'EXECUTE') AS anon
--        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE n.nspname = 'public'
--         AND p.proname ~ '^(apartados_lista|inventario_vivo|catalogo_completo|promos_vigentes|eol_lista|avisos_vigentes|bundles_vigentes|eol_precio_venta)(_filas_)?$'
--       ORDER BY 1;
--      -- Esperado: 16 filas. Las ocho sin `_filas_` con «p_store text,
--      -- p_token text» y anon = true; las ocho `_filas_` con «p_store text»
--      -- y anon = FALSE. Una interna con anon = true es una puerta abierta.
--
--  2 · Queda UNA tablero_todo, con p_token:
--
--      SELECT pg_get_function_identity_arguments(p.oid)
--        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE n.nspname = 'public' AND p.proname = 'tablero_todo';
--      -- Esperado: UNA fila, «p_store text, p_token text».
--
--  3 · Nadie llama ya a las puertas desde dentro de la base:
--
--      SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE n.nspname = 'public'
--         AND p.prosrc ~ '\m(apartados_lista|inventario_vivo|catalogo_completo|promos_vigentes|eol_lista|avisos_vigentes|bundles_vigentes|eol_precio_venta)\s*\(';
--      -- Esperado: CERO filas.
--
--  4 · Todo sigue saliendo con la app de hoy (sin token, paso 1):
--
--      SELECT count(*) FROM public.inventario_vivo('9999');
--      SELECT count(*) FROM public.apartados_lista('9999');
--      -- Esperado: los mismos números de siempre en la Demo, no un error.
--
--  5 · Con un token inventado, ya nada:
--
--      SELECT count(*) FROM public.apartados_lista('9999', 'token-inventado');
--      -- Esperado: 0.
--      SELECT public.tablero_todo('9999', 'token-inventado');
--      -- Esperado: {"ok": false, "apartados_ok": false}
--
--  6 · El contador está contando:
--
--      SELECT * FROM public.candado_sin_token ORDER BY dia DESC, funcion;
--      -- Esperado: filas de hoy (las consultas 4 cuentan). Esto es lo que hay
--      -- que mirar ANTES del paso 2: con la app nueva ya en los teléfonos, un
--      -- día de venta entero en cero.
-- ============================================================

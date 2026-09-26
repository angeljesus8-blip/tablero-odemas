-- ============================================================
--  QUIÉN CAPTURÓ LA VENTA
--  26-sep-2026 · traído de la 1217 (allá, 21-sep-2026)
-- ============================================================
--
--  Qué lo trae
--  -----------
--  En la 1217 apareció una venta de PRUEBA escrita en la base de producción, a
--  nombre de alguien que no trabaja ahí. Se pudo reconstruir todo menos lo
--  único que servía para que no se repita: QUIÉN la metió, porque
--  `public.ventas` no lo guarda. Aquí pasaría igual.
--
--  NO ES EL ARCHIVO DE LA 1217 COPIADO
--  -----------------------------------
--  En esta copia `venta_guardar` pide la clave de escritura (`p_token`, desde
--  el 1-sep-2026, ver supabase_venta_grupo.sql) y en la 1217 no. Pegar el SQL
--  de allá aquí BORRARÍA esa protección: cualquiera con la clave publicable
--  volvería a poder meter ventas en cualquier tienda. Por eso este archivo
--  parte de la versión de ESTA copia y sólo le agrega `p_quien` al final.
--
--  ⚠️ ORDEN DE APLICACIÓN — IMPORTA
--  --------------------------------
--  1. Primero se pega ESTE SQL.
--  2. Después se publica la app que manda `p_quien` al guardar (v25+).
--
--  Al revés NO: una app que manda un parámetro que la función no tiene recibe
--  PGRST202 y **deja de guardar ventas**. `p_quien` va con DEFAULT NULL para
--  que el paso 1 no rompa a las apps que ya están en la calle y todavía no lo
--  mandan: siguen guardando, sólo que sin el dato.
--
--  Lo que NO hace
--  --------------
--  No toca las ventas ya guardadas: se quedan con `capturado_por` en NULL, que
--  es la verdad —de ésas no se sabe— y no un cero disfrazado.
-- ============================================================

-- ── 1 · La columna ──────────────────────────────────────────
ALTER TABLE public.ventas
  ADD COLUMN IF NOT EXISTS capturado_por text;

COMMENT ON COLUMN public.ventas.capturado_por IS
  'Numero de empleado de quien capturo la venta en la app. NULL = captura '
  'anterior a este archivo, o app vieja que aun no manda el dato. No es el '
  'vendedor: el vendedor cobra la comision, este solo tecleo.';

-- ── 2 · venta_guardar, con quién ────────────────────────────
-- La firma cambia, así que DROP explícito de la de 14 parámetros (la de
-- supabase_venta_grupo.sql, con p_token): `CREATE OR REPLACE` dejaría las dos y
-- PostgREST respondería PGRST203 — o sea, dejaría de guardar ventas.
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean,text,text);

CREATE OR REPLACE FUNCTION public.venta_guardar(
  p_store      text,
  p_serie      text,
  p_sku        text    DEFAULT NULL,
  p_desc       text    DEFAULT NULL,
  p_precio     numeric DEFAULT NULL,
  p_vendedor   text    DEFAULT NULL,
  p_seguro     boolean DEFAULT NULL,
  p_fecha      text    DEFAULT NULL,
  p_hora       text    DEFAULT NULL,
  p_foto_url   text    DEFAULT NULL,
  p_captura_id text    DEFAULT NULL,
  p_de_exhibicion boolean DEFAULT false,
  p_grupo      text    DEFAULT NULL,
  -- La clave de escritura: ver el comentario largo en supabase_venta_grupo.sql.
  -- DEFAULT NULL para que una app vieja reciba «sin permiso» y no un 404.
  p_token      text    DEFAULT NULL,
  -- Con DEFAULT: una app en cache que aun no lo mande sigue guardando bien, y
  -- esa venta simplemente queda sin saber quien la tecleo.
  p_quien      text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cuando timestamptz;
  v_d int; v_m int; v_a int; v_h int := 12; v_min int := 0;
  m text[];
  nuevo bigint;
BEGIN
  -- Antes que nada: quien no trae la clave de la tienda, no escribe en ella.
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin permiso de escritura');
  END IF;

  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  m := regexp_match(coalesce(p_fecha,''), '^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$');
  IF m IS NOT NULL THEN
    v_d := m[1]::int; v_m := m[2]::int; v_a := m[3]::int;
    m := regexp_match(coalesce(p_hora,''), '^\s*(\d{1,2}):(\d{2})\s*([ap])');
    IF m IS NOT NULL THEN
      v_h := m[1]::int; v_min := m[2]::int;
      IF lower(m[3]) = 'p' AND v_h < 12 THEN v_h := v_h + 12; END IF;
      IF lower(m[3]) = 'a' AND v_h = 12 THEN v_h := 0; END IF;
    END IF;
    v_cuando := make_timestamp(v_a, v_m, v_d, v_h, v_min, 0) AT TIME ZONE 'America/Mexico_City';
  ELSE
    v_cuando := now();
  END IF;

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro,
     foto_url, captura_id, de_exhibicion, grupo, capturado_por)
  VALUES (p_store, v_cuando, trim(p_serie), nullif(trim(coalesce(p_sku,'')),''),
          nullif(trim(coalesce(p_desc,'')),''), p_precio,
          coalesce(nullif(trim(coalesce(p_vendedor,'')),''), '(sin nombre)'),
          p_seguro, nullif(trim(coalesce(p_foto_url,'')),''),
          nullif(trim(coalesce(p_captura_id,'')),''),
          coalesce(p_de_exhibicion, false),
          nullif(trim(coalesce(p_grupo,'')),''),
          nullif(trim(coalesce(p_quien,'')),''))
  ON CONFLICT (store_id, serie, dia_venta) DO NOTHING
  RETURNING id INTO nuevo;

  IF nuevo IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'duplicada', true);
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', nuevo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean,text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean,text,text,text)
  TO anon, authenticated;

-- ── 3 · Que se pueda VER ────────────────────────────────────
-- Guardar un dato que ninguna pantalla enseña es la forma cara de no tenerlo.
-- Los cobros de apartado no tienen quién: ahí va NULL, y NULL quiere decir
-- «de ésta no se sabe». El RETURNS TABLE cambia, así que DROP antes.
DROP FUNCTION IF EXISTS public.ventas_detalle(text, date);

CREATE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL)
RETURNS TABLE (serie text, sku text, descripcion text, precio numeric,
               vendedor text, con_seguro boolean, vendida_en timestamptz,
               captura_id text, tiene_foto boolean,
               entrega text, cobrado_en timestamptz, clase text,
               -- El numero legible del dia: 1, 2, 3… Calculado, no guardado.
               venta_num integer,
               -- Quien la tecleo. No es el vendedor.
               capturado_por text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH dia AS (
    SELECT coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date) AS d
  ),
  todo AS (
    SELECT v.serie, v.sku, v.descripcion, v.precio, v.vendedor, v.con_seguro,
           v.vendida_en, v.captura_id,
           EXISTS (SELECT 1 FROM public.venta_fotos f
                    WHERE f.store_id = v.store_id AND f.captura_id = v.captura_id) AS tiene_foto,
           (SELECT a.tipo      FROM public.apartados a WHERE a.venta_id = v.id LIMIT 1) AS entrega,
           (SELECT a.creado_en FROM public.apartados a WHERE a.venta_id = v.id LIMIT 1) AS cobrado_en,
           CASE WHEN EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
                THEN 'entrega' ELSE 'venta' END AS clase,
           -- Sin grupo, cada venta es la suya: el historico se ve igual que hoy.
           coalesce(v.grupo, 'v' || v.id::text) AS g,
           v.capturado_por
    FROM public.ventas v
    CROSS JOIN dia
    WHERE v.store_id = p_store
      AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date = dia.d

    UNION ALL

    /* Los apartados COBRADOS ese dia. Cada uno va suelto: no son articulos de
       una venta capturada en la app, sino cobros sin equipo todavia. */
    SELECT a.serie, a.sku, coalesce(c.descripcion, a.color), a.precio, a.vendedor,
           a.con_seguro, a.creado_en, NULL::text, false, a.tipo, a.creado_en, 'cobro',
           'a' || a.id::text, NULL::text
    FROM public.apartados a
    LEFT JOIN public.catalogo c ON c.store_id = a.store_id AND c.sku = a.sku
    CROSS JOIN dia
    WHERE a.store_id = p_store
      AND a.estatus <> 'Cancelado'
      AND (a.creado_en AT TIME ZONE 'America/Mexico_City')::date = dia.d
  ),
  /* El numero sale del ORDEN en que empezo cada grupo, no del id: asi «venta 1»
     es siempre la primera del dia aunque sus articulos se hayan guardado
     salteados por la cola de reintentos. */
  orden AS (
    SELECT g, min(vendida_en) AS ini FROM todo GROUP BY g
  )
  SELECT t.serie, t.sku, t.descripcion, t.precio, t.vendedor, t.con_seguro,
         t.vendida_en, t.captura_id, t.tiene_foto, t.entrega, t.cobrado_en, t.clase,
         dense_rank() OVER (ORDER BY o.ini, o.g)::int,
         t.capturado_por
  FROM todo t
  JOIN orden o ON o.g = t.g
  ORDER BY o.ini, o.g, t.vendida_en;
$$;

REVOKE ALL ON FUNCTION public.ventas_detalle(text,date) FROM public;
GRANT EXECUTE ON FUNCTION public.ventas_detalle(text,date) TO anon, authenticated;


-- ============================================================
--  COMPROBAR — pegar esto después y mirar las tres respuestas
-- ============================================================
--
--  1 · La columna existe:
--
--      SELECT column_name FROM information_schema.columns
--       WHERE table_name = 'ventas' AND column_name = 'capturado_por';
--      -- Esperado: una fila.
--
--  2 · Hay UNA sola venta_guardar, con 15 parámetros. Si salen dos, la app
--      recibirá PGRST203 y dejará de guardar: hay que borrar la vieja.
--
--      SELECT pg_get_function_identity_arguments(p.oid)
--        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE n.nspname = 'public' AND p.proname = 'venta_guardar';
--      -- Esperado: UNA fila, terminada en «, p_token text, p_quien text».
--
--  3 · La lectura del día sigue devolviendo lo de siempre y una columna más:
--
--      SELECT * FROM public.ventas_detalle('9999', current_date);
--      -- Esperado: las ventas de hoy de la tienda demo, con `capturado_por`.
-- ============================================================

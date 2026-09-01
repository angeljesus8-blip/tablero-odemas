-- ============================================================
--  AGRUPAR LOS ARTICULOS DE UNA MISMA VENTA
--  20-ago-2026
-- ============================================================
--
--  Hoy cada captura es un articulo suelto. Un cliente que se lleva un telefono
--  y un reloj sale como dos ventas, y al revisar el dia no hay forma de saber
--  que fue una sola compra.
--
--  Ahora el asesor cierra la venta a mano: lo que capture antes de cerrarla
--  queda junto.
--
--  ------------------------------------------------------------
--  LO QUE NO CAMBIA, Y ES LO IMPORTANTE
--  ------------------------------------------------------------
--  El ASSURANT se cuenta por ARTICULO, y el INVENTARIO descuenta por ARTICULO.
--  La agrupacion es SOLO de presentacion.
--
--  Esto no es un detalle: la regla de combos de la tienda dice «2 articulos =
--  1 con seguro, 4 articulos = 2 minimo». Si alguien «simplificara» contando
--  una venta con seguro en vez de dos articulos con uno, el attach cambiaria
--  solo —el KPI que se reporta con meta del 25 %— y nadie lo ataria a este
--  cambio meses despues.
--
--  Por eso `venta_guardar` es la UNICA funcion que toca el grupo, y ni
--  `inventario_vivo`, ni `ventas_hoy`, ni `cargar_cortes` lo miran siquiera.
--
--  ------------------------------------------------------------
--  EL NUMERO DE VENTA NO SE GUARDA: SE CALCULA AL LEER
--  ------------------------------------------------------------
--  La app manda un identificador de grupo, y el numero legible («venta 3») sale
--  de un `dense_rank` por dia al consultar.
--
--  Guardar el consecutivo obligaria a que alguien lo asignara, y dos telefonos
--  capturando a la vez pedirian el mismo numero. Calculado al leer no hay
--  carrera posible y el resultado es siempre coherente.
--
--  LAS VENTAS YA GUARDADAS no se reinterpretan: sin grupo, cada una es la suya
--  y se ve igual que hoy.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · El grupo ────────────────────────────────────────────
ALTER TABLE public.ventas ADD COLUMN IF NOT EXISTS grupo text;

COMMENT ON COLUMN public.ventas.grupo IS
  'Articulos de una misma venta. Lo genera la app y lo cierra el asesor a mano. '
  'Solo agrupa para verlo: el Assurant y el inventario siguen contando por '
  'articulo. NULL en las ventas anteriores al 20-ago-2026.';

CREATE INDEX IF NOT EXISTS ventas_grupo ON public.ventas (store_id, grupo);


-- ── 2 · Guardar la venta con su grupo ───────────────────────
-- La firma cambia (entra `p_grupo`): DROP de la anterior ANTES del CREATE, o
-- Postgres deja las dos y PostgREST responde PGRST203 — o sea, DEJA DE GUARDAR
-- VENTAS. Ya paso con esta misma funcion.
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean);
-- 1-sep-2026 · Y la de la firma sin `p_token`, que es la que quedo en las bases
-- montadas antes de que esta funcion pidiera la clave de escritura.
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean,text);

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
  -- Con DEFAULT: una app en cache que aun no lo mande sigue guardando bien, y
  -- esa venta simplemente queda sin agrupar.
  p_grupo      text    DEFAULT NULL,

  /* LA CLAVE DE ESCRITURA (1-sep-2026). Esta era la unica escritura que no la
     pedia: las otras 14 pasan por `escritura_ok_` desde el 4-ago. Sin ella,
     cualquiera con la clave publicable —que va escrita en el HTML, que es
     publico— podia insertar ventas en CUALQUIER tienda: descontar stock ajeno
     y acreditarle comisiones a quien quisiera. En una tienda sola se notaba
     poco; en una copia donde cada tienda tiene su `store_id`, es la puerta de
     al lado.

     Lleva DEFAULT NULL a proposito, y NO para dejar pasar a quien no lo manda:
     sin DEFAULT, una app vieja en cache recibe un 404 de PostgREST («no
     matches were found in the schema cache»), que se lee como «se cayo
     Supabase». Con DEFAULT llega hasta el IF de abajo y le contesta que no
     tiene permiso, que es lo que de verdad le pasa. */
  p_token      text    DEFAULT NULL
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
     foto_url, captura_id, de_exhibicion, grupo)
  VALUES (p_store, v_cuando, trim(p_serie), nullif(trim(coalesce(p_sku,'')),''),
          nullif(trim(coalesce(p_desc,'')),''), p_precio,
          coalesce(nullif(trim(coalesce(p_vendedor,'')),''), '(sin nombre)'),
          p_seguro, nullif(trim(coalesce(p_foto_url,'')),''),
          nullif(trim(coalesce(p_captura_id,'')),''),
          coalesce(p_de_exhibicion, false),
          nullif(trim(coalesce(p_grupo,'')),''))
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

REVOKE ALL ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean,text,text)
  TO anon, authenticated;


-- ── 3 · La lista, con el numero de venta ────────────────────
DROP FUNCTION IF EXISTS public.ventas_detalle(text, date);

CREATE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL)
RETURNS TABLE (serie text, sku text, descripcion text, precio numeric,
               vendedor text, con_seguro boolean, vendida_en timestamptz,
               captura_id text, tiene_foto boolean,
               entrega text, cobrado_en timestamptz, clase text,
               -- El numero legible del dia: 1, 2, 3… Calculado, no guardado.
               venta_num integer)
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
           coalesce(v.grupo, 'v' || v.id::text) AS g
    FROM public.ventas v
    CROSS JOIN dia
    WHERE v.store_id = p_store
      AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date = dia.d

    UNION ALL

    /* Los apartados COBRADOS ese dia. Cada uno va suelto: no son articulos de
       una venta capturada en la app, sino cobros sin equipo todavia. */
    SELECT a.serie, a.sku, coalesce(c.descripcion, a.color), a.precio, a.vendedor,
           a.con_seguro, a.creado_en, NULL::text, false, a.tipo, a.creado_en, 'cobro',
           'a' || a.id::text
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
         dense_rank() OVER (ORDER BY o.ini, o.g)::int
  FROM todo t
  JOIN orden o ON o.g = t.g
  ORDER BY o.ini, o.g, t.vendida_en;
$$;

REVOKE ALL ON FUNCTION public.ventas_detalle(text,date) FROM public;
GRANT EXECUTE ON FUNCTION public.ventas_detalle(text,date) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) La columna existe y el historico esta sin agrupar:
--       select count(*) filter (where grupo is null) as sin_grupo,
--              count(*) filter (where grupo is not null) as agrupadas
--         from public.ventas where store_id='1217';
--
--  2) La lista trae el numero de venta:
--       select venta_num, serie, descripcion, precio, clase
--         from public.ventas_detalle('1217','2026-08-16') order by venta_num;
--     Cada venta vieja tiene que salir con SU PROPIO numero: sin grupo, no se
--     agrupan entre si.
--
--  3) LO QUE DE VERDAD HAY QUE COMPROBAR — que agrupar no mueve nada.
--     Antes y despues de capturar dos articulos en una misma venta, estos dos
--     tienen que dar lo mismo que si se capturaran sueltos:
--       select * from public.ventas_hoy('1217');
--       select sku, stock from public.inventario_vivo('1217') where sku = '<el sku>';
--     El Assurant cuenta por ARTICULO: dos articulos con un seguro son 1 con y
--     1 sin, no «una venta con seguro».
--
-- ============================================================
--  Odemas · Grupo Gigante — uso interno HES 1217
-- ============================================================

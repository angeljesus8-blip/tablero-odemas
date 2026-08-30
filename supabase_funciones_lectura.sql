-- ============================================================
-- Fase 1 · Las lecturas del Apps Script, traducidas a SQL
-- 2-ago-2026 · APLICADO (comprobado el 4-ago: las siete responden en Supabase
--              con datos reales — 215 SKUs, 117 promos, las ventas históricas)
--
-- Decía "NO APLICADO TODAVÍA" dos días después de estar corriendo. Si la
-- cabecera de un archivo no se puede creer, no sirve de nada: comprobar contra
-- la base antes de fiarse.
--
-- Faltaban SEIS lecturas más que las apps sí usan. Están en
-- `supabase_funciones_lectura_resto.sql`.
-- ============================================================
--
-- Cada función de aquí tiene que devolver EXACTAMENTE lo mismo que su modo del
-- GAS. Mientras no coincidan, no se pasa a la fase 2.
--
-- Se traduce lógica que costó descubrir. Los comentarios dicen por qué es así,
-- no qué hace: sin eso, alguien lo "simplifica" y rompe algo que ya se pagó.
--
-- ------------------------------------------------------------
-- PASO 0 · Los cortes de inventario dejan de ser propiedades sueltas
-- ------------------------------------------------------------
-- En el GAS viven en Propiedades del script como dos JSON gigantes
-- (`ventaBaseline` y `exhibBaseline`). Ahí no se pueden consultar, ni auditar,
-- ni saber cuándo se tomaron. Como tabla, sí.
--
-- Por qué son DOS y no uno: el On Hand se sube a diario y reinicia su corte;
-- la exhibición se sube solo cuando se exhibe algo nuevo. Si el corte diario
-- reiniciara también el de piso, una pieza de exhibición ya vendida
-- reaparecería al día siguiente. Eso pasó y por eso están separados.

CREATE TABLE IF NOT EXISTS public.inventario_corte (
  store_id   text NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  tipo       text NOT NULL CHECK (tipo IN ('onhand','exhibicion')),
  sku        text NOT NULL,
  vendidas   integer NOT NULL DEFAULT 0 CHECK (vendidas >= 0),
  tomado_en  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, tipo, sku)
);
ALTER TABLE public.inventario_corte ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.inventario_corte IS
  'Foto del total de ventas por SKU en el momento de subir un reporte. tipo=onhand '
  'se retoma a diario con el Excel de almacén; tipo=exhibicion solo cuando se sube '
  'el piso. Lo vendido "desde el corte" es (ventas totales - vendidas).';

-- El SKU de una venta puede venir vacío: pasa cuando se captura a las prisas.
-- Son ventas reales y no se pueden perder por un dato que falta.
ALTER TABLE public.ventas ALTER COLUMN sku DROP NOT NULL;

-- ------------------------------------------------------------
-- 1 · INVENTARIO EN VIVO  ←  leerInventario_
-- ------------------------------------------------------------
-- La más delicada de todas. Se verificó CONTANDO CAJAS EN PISO que el reporte
-- On Hand NO incluye las piezas de exhibición: son cantidades independientes y
-- no se restan entre sí. Si alguien "corrige" esto restando, el tablero va a
-- mostrar menos stock del que hay y se van a perder ventas.
CREATE OR REPLACE FUNCTION public.inventario_vivo(p_store text)
RETURNS TABLE (
  sku text, descripcion text, precio numeric,
  onhand integer, vendido integer, stock integer,
  exhibicion integer, exh_vendida integer
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH vendidas AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
    GROUP BY v.sku
  )
  SELECT
    c.sku,
    c.descripcion,
    c.precio,
    coalesce(i.onhand, 0)                                            AS onhand,
    -- vendido DESDE el corte diario, no en total
    greatest(0, coalesce(vd.total,0) - coalesce(co.vendidas,0))::int AS vendido,
    -- stock vendible = solo almacén. La exhibición NO se suma ni se resta.
    greatest(0, coalesce(i.onhand,0)
              - greatest(0, coalesce(vd.total,0) - coalesce(co.vendidas,0)))::int AS stock,
    coalesce(i.exhibicion, 0)                                        AS exhibicion,
    -- vendido desde la última subida de piso, con su propio corte
    greatest(0, coalesce(vd.total,0) - coalesce(ce.vendidas,0))::int AS exh_vendida
  FROM public.catalogo c
  LEFT JOIN public.inventario i  ON i.store_id  = c.store_id AND i.sku  = c.sku
  LEFT JOIN vendidas vd          ON vd.sku      = c.sku
  LEFT JOIN public.inventario_corte co
         ON co.store_id = c.store_id AND co.sku = c.sku AND co.tipo = 'onhand'
  LEFT JOIN public.inventario_corte ce
         ON ce.store_id = c.store_id AND ce.sku = c.sku AND ce.tipo = 'exhibicion'
  WHERE c.store_id = p_store;
$$;

-- ------------------------------------------------------------
-- 2 · PRECIO DE REMATE AL 50%  ←  leerEolVenta_
-- ------------------------------------------------------------
-- Solo para los EOL en estado "listo": ya no queda nada en almacén pero SÍ
-- queda pieza de exhibición. Ese es el único caso en que la pieza de piso se
-- puede vender, y se vende a mitad de precio.
--
-- `exhib_restante` descuenta de la exhibición únicamente las ventas que se
-- pasaron del almacén — las que solo pudieron salir del piso.
CREATE OR REPLACE FUNCTION public.eol_precio_venta(p_store text)
RETURNS TABLE (sku text, precio50 numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT iv.sku,
         round(coalesce(nullif(e.precio, 0), iv.precio) / 2.0, 2) AS precio50
  FROM public.inventario_vivo(p_store) iv
  JOIN public.eol e ON e.store_id = p_store AND e.sku = iv.sku AND NOT e.pausado
  WHERE iv.stock = 0
    AND greatest(0, iv.exhibicion - greatest(0, iv.exh_vendida - iv.onhand)) > 0
    AND coalesce(nullif(e.precio, 0), iv.precio) > 0;
$$;

-- ------------------------------------------------------------
-- 3 · PROMOS VIGENTES  ←  leerPromos_
-- ------------------------------------------------------------
-- Aquí ya no hace falta isoFecha_: en la hoja las fechas eran texto y Sheets
-- convertía algunas a Date, así que "2026-08-01" se comparaba contra
-- "Sat Aug 01 2026..." y la promo nunca entraba. 117 promos quedaron invisibles
-- por eso. Con columnas DATE el problema desaparece de raíz.
--
-- La fecha de hoy va en hora de México, no UTC: con UTC las promos se caían
-- seis horas antes, desde las 6 pm de su último día.
CREATE OR REPLACE FUNCTION public.promos_vigentes(p_store text)
RETURNS TABLE (sku text, producto text, precio_reg numeric, precio_pro numeric,
               estatus text, msi text, vigente_desde date, vigente_hasta date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.sku, p.producto, p.precio_reg, p.precio_pro, p.estatus, p.msi,
         p.vigente_desde, p.vigente_hasta
  FROM public.promos p
  WHERE p.store_id = p_store
    AND (p.vigente_desde IS NULL
         OR p.vigente_desde <= (now() AT TIME ZONE 'America/Mexico_City')::date)
    AND p.vigente_hasta >= (now() AT TIME ZONE 'America/Mexico_City')::date;
$$;

-- ------------------------------------------------------------
-- 4 · COMBOS VIGENTES  ←  leerBundles_
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bundles_vigentes(p_store text)
RETURNS TABLE (id bigint, nombre text, skus text[], precio numeric,
               vigente_desde date, vigente_hasta date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT b.id, b.nombre, b.skus, b.precio, b.vigente_desde, b.vigente_hasta
  FROM public.bundles b
  WHERE b.store_id = p_store
    AND b.activo
    AND (b.vigente_desde IS NULL
         OR b.vigente_desde <= (now() AT TIME ZONE 'America/Mexico_City')::date)
    AND b.vigente_hasta >= (now() AT TIME ZONE 'America/Mexico_City')::date;
$$;

-- ------------------------------------------------------------
-- 5 · AVISOS VIGENTES  ←  leerAvisos_
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.avisos_vigentes(p_store text)
RETURNS TABLE (id bigint, titulo text, detalle text, prioridad text,
               vigente_hasta date, creado_en timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.titulo, a.detalle, a.prioridad, a.vigente_hasta, a.creado_en
  FROM public.avisos a
  WHERE a.store_id = p_store
    AND (a.vigente_hasta IS NULL
         OR a.vigente_hasta >= (now() AT TIME ZONE 'America/Mexico_City')::date)
  ORDER BY a.creado_en DESC;
$$;

-- ------------------------------------------------------------
-- 6 · LEADERBOARD DE ASSURANT  ←  leerVentasHoy_
-- ------------------------------------------------------------
-- `con_seguro` NULL son las ventas anteriores a julio-2026, cuando no existía
-- el campo: 124 de 223. Contarlas como "sin seguro" hundiría el attach rate sin
-- razón, así que se ignoran — igual que en el GAS.
CREATE OR REPLACE FUNCTION public.ventas_hoy(p_store text)
RETURNS TABLE (vendedor text, con_seguro bigint, sin_seguro bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.vendedor,
         count(*) FILTER (WHERE v.con_seguro)         AS con_seguro,
         count(*) FILTER (WHERE NOT v.con_seguro)     AS sin_seguro
  FROM public.ventas v
  WHERE v.store_id = p_store
    AND v.con_seguro IS NOT NULL
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
        = (now() AT TIME ZONE 'America/Mexico_City')::date
  GROUP BY v.vendedor;
$$;

-- ------------------------------------------------------------
-- 7 · SERIES DEL DÍA  ←  leerVentasDetalle_
-- ------------------------------------------------------------
-- Sin fecha, las de hoy. Aquí el parámetro ya es DATE de verdad: se acabó
-- mandar "2/8/2026" como texto y rezar que coincida letra por letra.
CREATE OR REPLACE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL)
RETURNS TABLE (serie text, sku text, descripcion text, precio numeric,
               vendedor text, con_seguro boolean, vendida_en timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.serie, v.sku, v.descripcion, v.precio, v.vendedor, v.con_seguro, v.vendida_en
  FROM public.ventas v
  WHERE v.store_id = p_store
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
        = coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date)
  ORDER BY v.vendida_en;
$$;

-- ------------------------------------------------------------
-- Permisos
-- ------------------------------------------------------------
-- SECURITY DEFINER + store_id explícito: la función decide qué se ve, no el
-- cliente. Igual que login_asesor.
REVOKE ALL ON FUNCTION public.inventario_vivo(text)    FROM public;
REVOKE ALL ON FUNCTION public.eol_precio_venta(text)   FROM public;
REVOKE ALL ON FUNCTION public.promos_vigentes(text)    FROM public;
REVOKE ALL ON FUNCTION public.bundles_vigentes(text)   FROM public;
REVOKE ALL ON FUNCTION public.avisos_vigentes(text)    FROM public;
REVOKE ALL ON FUNCTION public.ventas_hoy(text)         FROM public;
REVOKE ALL ON FUNCTION public.ventas_detalle(text,date) FROM public;

GRANT EXECUTE ON FUNCTION public.inventario_vivo(text)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eol_precio_venta(text)    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.promos_vigentes(text)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bundles_vigentes(text)    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.avisos_vigentes(text)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ventas_hoy(text)          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ventas_detalle(text,date) TO anon, authenticated;

/* ============================================================
   Lo que falta antes de dar esto por bueno

   Cargar los datos y comparar CADA función contra su modo del GAS con los
   mismos datos. Mientras no den idéntico, no se pasa a la fase 2.

   Los tres que más fácil van a diferir, y por qué:

   1. inventario_vivo — depende de que los cortes se carguen bien. El GAS los
      tiene como dos JSON en Propiedades del script; hay que volcarlos a
      inventario_corte tal cual, sin recalcularlos, o el "vendido desde el
      corte" saldrá distinto.

   2. eol_precio_venta — hereda lo anterior. Si el inventario difiere en un
      SKU, aquí puede aparecer o desaparecer un precio de remate.

   3. ventas_hoy — la hoja guarda la fecha como texto sin hora fiable y aquí
      es timestamptz. Al cargar hay que armar vendida_en juntando fecha y hora
      en zona de México, no en UTC.
   ============================================================ */

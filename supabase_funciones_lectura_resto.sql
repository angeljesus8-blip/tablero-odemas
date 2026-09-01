-- ============================================================
-- Fase 1 (cierre) · Las SEIS lecturas que faltaban
-- 4-ago-2026
-- ============================================================
--
-- Por qué existe este archivo
-- ---------------------------
-- `supabase_funciones_lectura.sql` tradujo siete modos del Apps Script y el
-- commit los dio por buenos: "las siete lecturas dan idéntico". Es cierto, y
-- aun así la fase 1 no estaba cerrada: **las apps usan trece lecturas, no
-- siete**. Se contó lo que se había escrito, no lo que hacía falta.
--
-- Estas son las seis que quedaban, sacadas con grep de los seis html y no de
-- memoria:
--
--   modo=todo          tablero          ← el viaje único; sin esto la fase 2
--                                         no da la velocidad que promete
--   modo=catalogo      captura_series   ← el autollenado al teclear un SKU
--   modo=apartados     tablero          ← la preventa
--   modo=eol_cloud     tablero, admin
--   modo=comisiones    comisiones, admin
--   modo=estado        captura, admin, actualizar_datos
--
-- Igual que las otras siete: SECURITY DEFINER con store_id explícito, para que
-- decida el servidor y no el cliente.
-- ============================================================


-- ------------------------------------------------------------
-- PASO 0 · Dos datos que el GAS da y el esquema no sabía guardar
-- ------------------------------------------------------------
-- `modo=estado` devuelve catBy y promoBy —quién subió el último catálogo y las
-- últimas promos— y actualizar_datos.html lo muestra en pantalla ("Por ..."),
-- que es como el gerente sabe quién tocó los precios por última vez.
--
-- En el esquema nuevo no había dónde ponerlo. Migrar sin esto no rompe nada,
-- pero borra una respuesta que hoy se puede dar. Se añade ahora, que es barato;
-- las escrituras de la fase 4 solo tendrán que llenarlo.
ALTER TABLE public.catalogo   ADD COLUMN IF NOT EXISTS subido_por text;
ALTER TABLE public.promos     ADD COLUMN IF NOT EXISTS subido_por text;

-- El GAS guarda DOS periodos de comisiones: el de venta y el de garantías, que
-- no coinciden. La tabla solo tenía uno.
ALTER TABLE public.comisiones ADD COLUMN IF NOT EXISTS periodo_gar text;


-- ------------------------------------------------------------
-- 8 · CATÁLOGO COMPLETO  ←  leerCatalogo_
-- ------------------------------------------------------------
-- Aquí se devuelven FILAS; el índice lo arma el cliente. Y tiene que armarlo
-- con cuidado, porque esto es lo que costó un producto invisible:
--
-- Hay códigos de barras comodín compartidos por varios productos —6942100000000
-- lo usan seis—. Cuando el catálogo se indexaba SOLO por código, se pisaban
-- entre sí y sobrevivía uno; los demás desaparecían y al teclear su SKU no
-- salía nada, sin ningún aviso. Por eso cada SKU lleva SIEMPRE su entrada
-- propia `sku:XXXX` además de la del código.
--
-- El upc se devuelve tal cual, como texto. Nunca como número: en la hoja, un
-- código en notación científica acabó redondeado y seis productos terminaron
-- compartiendo el mismo.
CREATE OR REPLACE FUNCTION public.catalogo_completo(p_store text)
RETURNS TABLE (sku text, descripcion text, upc text,
               precio numeric, onhand integer, vigente boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT c.sku, c.descripcion, c.upc, c.precio,
         coalesce(i.onhand, 0)::int AS onhand,
         c.vigente
  FROM public.catalogo c
  LEFT JOIN public.inventario i ON i.store_id = c.store_id AND i.sku = c.sku
  WHERE c.store_id = p_store
  ORDER BY c.sku;
$$;


-- ------------------------------------------------------------
-- 9 · LISTA DE EOL  ←  leerEolCloud_
-- ------------------------------------------------------------
-- Los EOL marcados y no pausados. Distinto de eol_precio_venta, que solo trae
-- los que YA están en remate al 50%; este trae todos los marcados.
--
-- 111 de 133 no tienen precio ni propio ni en el catálogo (fase 1, hallazgo 3).
-- Se devuelven igual, con precio NULL: el tablero los tiene que listar aunque
-- no pueda calcularles el remate. Filtrarlos aquí los haría desaparecer de la
-- pantalla sin que nadie supiera por qué.
CREATE OR REPLACE FUNCTION public.eol_lista(p_store text)
RETURNS TABLE (sku text, precio numeric, precio_efectivo numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT e.sku,
         e.precio,
         -- el que se usaría para el 50%: propio, y si no, el del catálogo
         coalesce(nullif(e.precio, 0), c.precio) AS precio_efectivo
  FROM public.eol e
  LEFT JOIN public.catalogo c ON c.store_id = e.store_id AND c.sku = e.sku
  WHERE e.store_id = p_store
    AND NOT e.pausado
  ORDER BY e.sku;
$$;


-- ------------------------------------------------------------
-- 10 · APARTADOS  ←  leerApartados_
-- ------------------------------------------------------------
-- Trae también el cupo y lo ya apartado, que en el GAS el tablero calculaba por
-- su cuenta sumando en el navegador. Contarlo aquí es lo que hace que dos
-- asesores apartando a la vez no puedan pasarse del límite: el trigger
-- apartado_cabe usa esta misma suma.
--
-- Los cancelados NO cuentan para el cupo pero SÍ se devuelven: el gerente tiene
-- que poder ver que existieron.
-- 31-ago-2026 · DROP delante. Esta función se vuelve a definir más abajo en
-- el pegado con OTRAS columnas, así que repegar el archivo entero sobre una
-- base que ya tiene la versión de después falla con «42P13: cannot change
-- return type of existing function» y deja el pegado a medias. Con el DROP,
-- el SQL se puede volver a pegar tantas veces como haga falta. El GRANT de
-- más abajo vuelve a abrirla: el DROP se lleva los permisos por delante.
DROP FUNCTION IF EXISTS public.apartados_lista(text);

CREATE OR REPLACE FUNCTION public.apartados_lista(p_store text)
RETURNS TABLE (id bigint, sku text, cliente text, telefono text,
               piezas integer, con_seguro boolean, estatus text,
               vendedor text, creado_en timestamptz,
               cupo integer, apartadas integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.sku, a.cliente, a.telefono, a.piezas, a.con_seguro,
         a.estatus, a.vendedor, a.creado_en,
         pc.cupo,
         (SELECT coalesce(sum(x.piezas), 0)::int
            FROM public.apartados x
           WHERE x.store_id = a.store_id AND x.sku = a.sku
             AND x.estatus <> 'Cancelado') AS apartadas
  FROM public.apartados a
  LEFT JOIN public.preventa_cupo pc
         ON pc.store_id = a.store_id AND pc.sku = a.sku
  WHERE a.store_id = p_store
  ORDER BY a.creado_en DESC;
$$;


-- ------------------------------------------------------------
-- 11 · COMISIONES  ←  leerComisiones_
-- ------------------------------------------------------------
-- alcance y gar_pct SÍ pueden pasar de 100: hay una ventana de 30 días para
-- comprar el seguro, así que un vendedor puede cerrar el mes por encima del
-- 100 %. Si alguien mete aquí un LEAST(...,100) "para que se vea bien", estará
-- borrando trabajo hecho de verdad.
CREATE OR REPLACE FUNCTION public.comisiones_lista(p_store text)
RETURNS TABLE (empno text, nombre text, puesto text, venta numeric,
               ppto_pct numeric, alcance numeric, gar_pct numeric,
               gar_pzas integer, gar_elegible integer, gar_monto numeric,
               periodo text, periodo_gar text, actualizado timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT k.empno, k.nombre, k.puesto, k.venta, k.ppto_pct, k.alcance,
         k.gar_pct, k.gar_pzas, k.gar_elegible, k.gar_monto,
         k.periodo, k.periodo_gar, k.updated_at
  FROM public.comisiones k
  WHERE k.store_id = p_store
  ORDER BY k.venta DESC NULLS LAST;
$$;


-- ------------------------------------------------------------
-- 12 · ESTADO DE LAS SUBIDAS  ←  modo=estado
-- ------------------------------------------------------------
-- En el GAS esto sale de Propiedades del script (catCount, catAt, promoCount…),
-- que se escriben a mano en cada subida y pueden quedar mintiendo si una subida
-- falla a medias. Aquí se cuenta la tabla: el número no puede desincronizarse
-- de los datos porque ES los datos.
--
-- `ventasGid` no se devuelve: era el id de pestaña de la hoja de Google, para
-- abrirla en el navegador. Cuando no haya hoja no significará nada.
CREATE OR REPLACE FUNCTION public.estado_datos(p_store text)
RETURNS TABLE (cat_count integer, cat_at timestamptz, cat_by text,
               cat_ref_count integer,
               promo_count integer, promo_at timestamptz, promo_by text,
               comis_at timestamptz, comis_periodo text,
               ventas_total integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    (SELECT count(*)::int FROM public.catalogo WHERE store_id = p_store AND vigente),
    (SELECT max(updated_at) FROM public.catalogo WHERE store_id = p_store),
    (SELECT subido_por FROM public.catalogo
      WHERE store_id = p_store AND subido_por IS NOT NULL
      ORDER BY updated_at DESC LIMIT 1),
    (SELECT count(*)::int FROM public.catalogo WHERE store_id = p_store AND NOT vigente),
    (SELECT count(*)::int FROM public.promos WHERE store_id = p_store),
    (SELECT max(updated_at) FROM public.promos WHERE store_id = p_store),
    (SELECT subido_por FROM public.promos
      WHERE store_id = p_store AND subido_por IS NOT NULL
      ORDER BY updated_at DESC LIMIT 1),
    (SELECT max(updated_at) FROM public.comisiones WHERE store_id = p_store),
    (SELECT periodo FROM public.comisiones
      WHERE store_id = p_store AND periodo IS NOT NULL LIMIT 1),
    (SELECT count(*)::int FROM public.ventas WHERE store_id = p_store);
$$;


-- ------------------------------------------------------------
-- 13 · TODO DE UN VIAJE  ←  modo=todo
-- ------------------------------------------------------------
-- El modo que justifica media migración. En el Apps Script el tablero no puede
-- pedir siete cosas a la vez: las llamadas encimadas se descartan RESPONDIENDO
-- 200, así que hay una cola con 1.5 s de separación y abrir el tablero cuesta
-- ~4 s. `modo=todo` se inventó para meterlo en un solo viaje.
--
-- Aquí no hay cola ni descarte, así que esto podrían ser siete llamadas en
-- paralelo. Se mantiene igualmente en una: es un viaje de red en vez de siete
-- desde un celular en la tienda, y deja el cambio del cliente en algo pequeño.
--
-- Devuelve jsonb con las mismas siete claves que el GAS, para que la fase 2 sea
-- cambiar de dónde se pide y no reescribir el tablero.
CREATE OR REPLACE FUNCTION public.tablero_todo(p_store text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'inventario', (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.inventario_vivo(p_store) t),
    'eol',        (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.eol_lista(p_store) t),
    'eol_venta',  (SELECT coalesce(jsonb_object_agg(t.sku, t.precio50), '{}'::jsonb)
                     FROM public.eol_precio_venta(p_store) t),
    'promos',     (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.promos_vigentes(p_store) t),
    'bundles',    (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.bundles_vigentes(p_store) t),
    'avisos',     (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.avisos_vigentes(p_store) t),
    'apartados',  (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.apartados_lista(p_store) t),
    'ventas_hoy', (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.ventas_hoy(p_store) t)
  );
$$;


-- ------------------------------------------------------------
-- Permisos
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION public.catalogo_completo(text) FROM public;
REVOKE ALL ON FUNCTION public.eol_lista(text)         FROM public;
REVOKE ALL ON FUNCTION public.apartados_lista(text)   FROM public;
REVOKE ALL ON FUNCTION public.comisiones_lista(text)  FROM public;
REVOKE ALL ON FUNCTION public.estado_datos(text)      FROM public;
REVOKE ALL ON FUNCTION public.tablero_todo(text)      FROM public;

GRANT EXECUTE ON FUNCTION public.catalogo_completo(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eol_lista(text)         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartados_lista(text)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.comisiones_lista(text)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.estado_datos(text)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tablero_todo(text)      TO anon, authenticated;


/* ============================================================
   Antes de dar la fase 1 por cerrada — esta vez de verdad

   Comparar CADA una de las trece contra su modo del GAS con los mismos datos.
   No vale contar las que están escritas: eso fue lo que dejó seis fuera.

   El comparador no puede llamar al GAS desde fuera: desde el 4-ago el endpoint
   exige token. Se corre desde el navegador con la sesión abierta, que ya lo
   tiene — así el token no sale a ningún lado. Ver MIGRACION_comparar.js.

   Lo que más fácil va a diferir, y por qué:

   1. catalogo — el GAS entrega un objeto ya indexado (por código y por
      `sku:XXXX`); aquí son filas. Comparar los CONJUNTOS de SKU y los valores,
      no la forma. Si falta un SKU, es el bug de los códigos comodín otra vez.

   2. estado — no puede dar idéntico a propósito: el GAS lee contadores
      guardados a mano y esto cuenta las filas. Si difieren, lo más probable es
      que el contador del GAS esté mintiendo, no que falte un dato aquí.
      Comprobarlo contra la hoja antes de "arreglar" nada.

   3. apartados — el GAS no devuelve cupo ni apartadas; se calculaban en el
      navegador. Comparar solo los campos que existen en los dos lados.
   ============================================================ */

-- ============================================================
--  VENTAS DE ACCESORIOS — el SKU generico 43739
--  18-ago-2026
-- ============================================================
--
--  Los accesorios (cargadores, micas, kits de limpieza) se venden con el SKU
--  generico 000043739 y no pasan por Captura de Series, que es para equipos con
--  numero de serie. Su reporte mensual de comisiones se llenaba a mano desde
--  fotos del POS, y en julio 24 de ~85 tickets (28%) no se pudieron resolver
--  desde la foto: acabaron en una lista para abrir uno por uno.
--
--  ------------------------------------------------------------
--  POR QUE NO VA EN LA TABLA `ventas`
--  ------------------------------------------------------------
--  Porque la rompe, y de dos formas que no darian error:
--
--    · `inventario_vivo` descuenta stock POR SKU. El 43739 no existe en el
--      catalogo, asi que cada accesorio vendido restaria de la nada — o peor,
--      si algun dia alguien da de alta ese SKU, restaria de un producto real.
--    · `ventas_hoy` calcula el Assurant del dia contando ventas. Un cargador
--      no lleva seguro Assurant, asi que cada uno hundiria el KPI que se
--      reporta con meta del 25%.
--
--  Tabla propia, aunque la pantalla se parezca.
--
--  ------------------------------------------------------------
--  DE DONDE SALE CADA DATO (medido sobre tickets reales, 17-ago)
--  ------------------------------------------------------------
--    ticket, fecha, vendedor  ->  OCR de la foto del ticket
--    precio y cantidad        ->  OCR de la LINEA del 43739, con la
--                                 comprobacion importe = precio x cantidad
--    producto                 ->  LISTA que toca el asesor. El OCR NO lo lee:
--                                 devolvio CARGATOOWTS por CARGA100WTS, y en
--                                 un ticket de 8 articulos agarro el IMEI del
--                                 MatePad en vez del accesorio.
--
--  Y el vendedor es «Atendido por», NO el numero del final del ticket: ese es
--  quien cobro en caja. En el ticket 33480 el numero del final era el del
--  gerente y quien atendio fue un asesor. La comision es de quien vendio.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · El catalogo de accesorios ───────────────────────────
--
-- Solo NOMBRES. El precio NO se fija aqui: el mismo cargador 100W se ha
-- vendido a $999, $899.10, $699 y $1,299 — 34 precios distintos entre enero y
-- julio. `precio_ref` es una ayuda para el asesor, nunca el dato que se guarda.
--
-- Esta lista es la que mata la ambiguedad que costo 19 tickets en julio: dos
-- micas distintas a $149 y dos a $299. El asesor ELIGE en vez de que nadie
-- deduzca del precio.
CREATE TABLE IF NOT EXISTS public.accesorios_catalogo (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  -- El codigo del articulo, tal como viene en el catalogo oficial. NO es
  -- decorativo: es lo que el cajero teclea en el campo «N. de serie» del
  -- ticket, asi que sirve para PRESELECCIONAR el producto tras leerlo.
  -- «CARGA100WTS» del ticket es este «43739-CARGA-100W» abreviado a mano.
  articulo   text,
  nombre     text        NOT NULL,
  precio_ref numeric(12,2),
  /* El SKU con el que se COBRA, o sea la columna «Caja» del catalogo oficial.
     No todo va con el generico: OFFICE PERSONAL se cobra con 63602 y FAMILIA
     con 57518, y los dos SI entran en el reporte de comisiones — cada uno con
     el suyo. La columna E del Excel pide precisamente esto, asi que dar por
     hecho que todo es 43739 llenaria mal una de cada dos columnas. */
  sku        text        NOT NULL DEFAULT '43739',
  orden      integer     NOT NULL DEFAULT 100,
  activo     boolean     NOT NULL DEFAULT true,
  creado_en  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store_id, nombre)
);

ALTER TABLE public.accesorios_catalogo ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.accesorios_catalogo IS
  'Productos que se venden con el SKU generico 43739. El precio de referencia '
  'es una ayuda: el real sale del ticket y varia por promocion. `articulo` es '
  'el codigo que el cajero teclea en el campo de serie, y sirve para adivinar '
  'el producto al leer el ticket.';

ALTER TABLE public.accesorios_catalogo ADD COLUMN IF NOT EXISTS articulo text;
ALTER TABLE public.accesorios_catalogo ADD COLUMN IF NOT EXISTS sku text NOT NULL DEFAULT '43739';
-- `generico` se sustituyo por `sku` el 18-ago: no era «entra o no al reporte»
-- sino «con que SKU se cobra». Se quita si quedo de la version anterior.
ALTER TABLE public.accesorios_catalogo DROP COLUMN IF EXISTS generico;

/* EL CATALOGO REAL, de los dos documentos oficiales (18-ago-2026):
     · «Productos Mr Fix 180526.pdf» — accesorios de computo
     · la tabla de accesorios Huawei (micas, cargadores, licencias)

   Sustituye a una lista que se habia puesto a ojo y estaba mal: los nombres
   verdaderos son MICA HR / MATTE / BLUE / PRIV, no «hidrogel transparente» ni
   «para tablet». La colision de $149 es entre HR y MATTE — las 19 lineas que
   en julio hubo que abrir una por una. Y hay una a $199 que no se sabia. */
INSERT INTO public.accesorios_catalogo (store_id, articulo, nombre, precio_ref, sku, orden)
VALUES
  ('1217','43739-MICAHR',        'MICA HR',                              149, '43739',  10),
  ('1217','43739-MICAMATTE',     'MICA MATTE',                           149, '43739',  20),
  ('1217','43739-MICABLUE',      'MICA BLUE',                            199, '43739',  30),
  ('1217','43739-MICAPRIV',      'MICA PRIV',                            299, '43739',  40),
  ('1217','43739-CARGA-66W',     'CARGADOR 66W',                         499, '43739',  50),
  ('1217','43739-CARGA-100W',    'CARGADOR 100W',                        999, '43739',  60),
  ('1217','W-1999',              'LICENCIA WINDOWS',                    1999, '43739',  70),
  -- Sale en los tickets (KITLIMPIEZA, $169) pero no viene en ninguno de los
  -- dos documentos oficiales. Precio confirmado por Angel el 18-ago-2026.
  ('1217','43739-KITLIMPIEZA',   'KIT DE LIMPIEZA',                      169, '43739',  80),
  ('1217','80066',               'MEMORIA OTG 32GB ADATA ANDROID',        99, '43739', 100),
  ('1217','AUV250-64G-RBK',      'MEM USB ADATA 64GB UV250',             189, '43739', 110),
  ('1217','AUSDX64GUICL10-RA1',  'TARJETA MICROSD ADATA 64GB CLASE 10',  249, '43739', 120),
  ('1217','91273',               'MEMORIA USB ADATA 128GB',              329, '43739', 130),
  ('1217','P5116',               'MOUSEPAD PC KENSIN P511 RJ/GR',        329, '43739', 140),
  ('1217','65960',               'MOUSE PAD FOAM AZUL CON DESCANSA MUNECA', 349, '43739', 150),
  ('1217','HX-MPFS-S-XL',        'MOUSEPAD HYPERX FURY S SPEED EXTRA LARGO', 399, '43739', 160),
  ('1217','80050',               'BATERIA RESPALDO ADATA 10,000 MAH',    399, '43739', 170),
  ('1217','91276',               'MICRO SD ADATA 128GB CLASE 10',        499, '43739', 180),
  ('1217','100011',              'DISCO DURO ADATA 500GB 2.5',           799, '43739', 190),
  ('1217','80065',               'DISCO DURO EXTERNO ADATA 1 TB',       2099, '43739', 200),
  ('1217','AHD710P-2TU31-CBK',   'DISCO DURO ADATA HD710 2TB',          2699, '43739', 210),
  ('1217','HDTX140XK3CA',        'DISCO DURO TOSHIBA GAMER 4TB NG',     3699, '43739', 220),
  -- Caja propia. SI van al reporte, pero cada uno con SU sku.
  ('1217','63602',               'OFFICE PERSONAL',                     2249, '63602', 300),
  ('1217','57518',               'OFFICE FAMILIA',                      2699, '57518', 310)
ON CONFLICT (store_id, nombre) DO UPDATE
  SET articulo = excluded.articulo, precio_ref = excluded.precio_ref,
      sku = excluded.sku, orden = excluded.orden, activo = true;

/* La lista que se puso a ojo antes de tener los documentos. Se da de baja, no
   se borra: si alguna venta se guardo con esos nombres, se quedaria apuntando
   a un producto inexistente. */
UPDATE public.accesorios_catalogo SET activo = false
 WHERE store_id = '1217'
   AND nombre IN ('Mica hidrogel transparente','Mica hidrogel mate',
                  'Mica de privacidad','Mica para tablet','Cargador 66W',
                  'Cargador 100W','Kit de limpieza');


-- ── 2 · Las ventas ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.accesorios_ventas (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  vendida_en timestamptz NOT NULL DEFAULT now(),
  -- El dia en hora de Mexico, para el reporte mensual. Se deriva con trigger,
  -- igual que `dia_venta` en `ventas`: puesto a mano se desincroniza y la
  -- restriccion de abajo dejaria de proteger sin avisar.
  dia        date,
  ticket     text        NOT NULL,
  producto   text        NOT NULL,
  -- El SKU con el que se cobro. Va a la columna E del Excel. Se guarda AQUI y
  -- no se saca del catalogo al exportar: si manana cambia el SKU de un
  -- producto, las ventas viejas tienen que seguir diciendo con cual se
  -- cobraron — el reporte de julio no se reescribe.
  sku        text        NOT NULL DEFAULT '43739',
  cantidad   integer     NOT NULL DEFAULT 1 CHECK (cantidad > 0),
  precio     numeric(12,2) NOT NULL CHECK (precio >= 0),
  importe    numeric(12,2) NOT NULL CHECK (importe >= 0),
  vendedor   text        NOT NULL,
  capturado_por text,                    -- empno de quien la registro
  captura_id text,                       -- id de la app; liga la foto
  ocr_texto  text,                       -- lo que leyo, para poder revisar
  creado_en  timestamptz NOT NULL DEFAULT now(),
  -- Un ticket no se captura dos veces con el mismo producto. Es el riesgo real:
  -- dos asesores registrando la misma venta al cerrar el dia.
  UNIQUE (store_id, ticket, producto)
);

ALTER TABLE public.accesorios_ventas ADD COLUMN IF NOT EXISTS sku text NOT NULL DEFAULT '43739';

ALTER TABLE public.accesorios_ventas ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS accesorios_ventas_dia
  ON public.accesorios_ventas (store_id, dia DESC);

CREATE OR REPLACE FUNCTION public.accesorios_dia_()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.dia := (NEW.vendida_en AT TIME ZONE 'America/Mexico_City')::date;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS accesorios_dia_trg ON public.accesorios_ventas;
CREATE TRIGGER accesorios_dia_trg
  BEFORE INSERT OR UPDATE OF vendida_en ON public.accesorios_ventas
  FOR EACH ROW EXECUTE FUNCTION public.accesorios_dia_();

COMMENT ON TABLE public.accesorios_ventas IS
  'Ventas del SKU generico 43739 para el reporte mensual de comisiones. NO va '
  'en `ventas`: ahi contaminaria inventario_vivo (descuenta por SKU) y '
  'ventas_hoy (el Assurant). `vendedor` es «Atendido por» del ticket, no el '
  'numero del final, que es quien cobro en caja.';


-- ── 3 · Guardar ─────────────────────────────────────────────
/* La firma cambio (entro `p_sku`), asi que hay que soltar la VIEJA antes de
   crear la nueva: sin eso Postgres deja las dos conviviendo y PostgREST
   responde PGRST203.

   Y la nueva va con CREATE OR REPLACE, no con CREATE a secas. Con CREATE, este
   archivo solo se podia pegar UNA vez: al repegarlo fallaba con «already
   exists with same argument types», porque el DROP de arriba solo apunta a la
   firma vieja. Un archivo que dice ser idempotente y no lo es se descubre a
   mitad de un pegado, con parte aplicada y parte no. */
DROP FUNCTION IF EXISTS public.accesorio_guardar(text,text,text,text,integer,numeric,text,date,text,text,text,text);
CREATE OR REPLACE FUNCTION public.accesorio_guardar(
  p_store      text,
  p_token      text,
  p_ticket     text,
  p_producto   text,
  p_sku        text,
  p_cantidad   integer,
  p_precio     numeric,
  p_vendedor   text,
  p_fecha      date    DEFAULT NULL,   -- del ticket; si no viene, hoy
  p_hora       text    DEFAULT NULL,   -- '7:33 PM'
  p_quien      text    DEFAULT NULL,
  p_captura_id text    DEFAULT NULL,
  p_ocr        text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cuando timestamptz;
  v_h int := 12; v_m int := 0;
  mm text[];
  nuevo bigint;
  v_importe numeric;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_ticket),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'falta el numero de ticket');
  END IF;
  IF coalesce(trim(p_producto),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'falta el producto');
  END IF;
  IF coalesce(p_precio, 0) <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'falta el precio');
  END IF;
  IF coalesce(trim(p_vendedor),'') = '' THEN
    -- Sin vendedor la venta no sirve: el reporte es POR EMPLEADO y la comision
    -- es de alguien. Guardarla «para arreglarla luego» es perderla.
    RETURN jsonb_build_object('ok', false, 'error', 'falta quien la vendio');
  END IF;

  -- La hora es cosmetica (para ordenar); si no se entiende, mediodia.
  mm := regexp_match(coalesce(p_hora,''), '^\s*(\d{1,2}):(\d{2})\s*([APap])');
  IF mm IS NOT NULL THEN
    v_h := mm[1]::int; v_m := mm[2]::int;
    IF upper(mm[3]) = 'P' AND v_h < 12 THEN v_h := v_h + 12; END IF;
    IF upper(mm[3]) = 'A' AND v_h = 12 THEN v_h := 0; END IF;
  END IF;
  v_cuando := (make_timestamp(
                 extract(year  from coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date))::int,
                 extract(month from coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date))::int,
                 extract(day   from coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date))::int,
                 v_h, v_m, 0) AT TIME ZONE 'America/Mexico_City');

  v_importe := round(p_precio * greatest(1, coalesce(p_cantidad,1)), 2);

  INSERT INTO public.accesorios_ventas
    (store_id, vendida_en, ticket, producto, sku, cantidad, precio, importe,
     vendedor, capturado_por, captura_id, ocr_texto)
  VALUES (p_store, v_cuando, trim(p_ticket), trim(p_producto),
          coalesce(nullif(trim(coalesce(p_sku,'')),''), '43739'),
          greatest(1, coalesce(p_cantidad,1)), p_precio, v_importe,
          trim(p_vendedor), nullif(trim(coalesce(p_quien,'')),''),
          nullif(trim(coalesce(p_captura_id,'')),''),
          left(coalesce(p_ocr,''), 4000))
  ON CONFLICT (store_id, ticket, producto) DO NOTHING
  RETURNING id INTO nuevo;

  IF nuevo IS NULL THEN
    -- Ya estaba. Se dice, no se calla: quien la captura tiene que saber que no
    -- la esta duplicando, y tampoco creer que guardo algo nuevo.
    RETURN jsonb_build_object('ok', true, 'duplicada', true,
      'error', 'ese ticket ya tiene registrado ese producto');
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', nuevo, 'importe', v_importe);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 4 · Leer ────────────────────────────────────────────────
/* Estas dos NO cambian de firma, cambian lo que DEVUELVEN, y Postgres no deja
   cambiar el tipo de retorno con CREATE OR REPLACE. El DROP acierta la firma
   —es la misma— asi que repegar el archivo funciona siempre. */
DROP FUNCTION IF EXISTS public.accesorios_catalogo_lista(text);
DROP FUNCTION IF EXISTS public.accesorios_lista(text,date,date);
CREATE FUNCTION public.accesorios_catalogo_lista(p_store text)
RETURNS TABLE (id bigint, nombre text, precio_ref numeric, articulo text, sku text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT c.id, c.nombre, c.precio_ref, c.articulo, c.sku
  FROM public.accesorios_catalogo c
  WHERE c.store_id = p_store AND c.activo
  ORDER BY c.orden, c.nombre;
$$;

-- Las ventas de un rango. Sin rango: el mes en curso, que es como se entrega
-- el reporte.
CREATE FUNCTION public.accesorios_lista(
  p_store text, p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL
) RETURNS TABLE (id bigint, dia date, ticket text, sku text, producto text,
                 cantidad integer, precio numeric, importe numeric,
                 vendedor text, captura_id text, tiene_foto boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.dia, a.ticket, a.sku, a.producto, a.cantidad, a.precio, a.importe,
         a.vendedor, a.captura_id,
         EXISTS (SELECT 1 FROM public.venta_fotos f
                  WHERE f.store_id = a.store_id AND f.captura_id = a.captura_id)
  FROM public.accesorios_ventas a
  WHERE a.store_id = p_store
    AND a.dia >= coalesce(p_desde, date_trunc('month',
          (now() AT TIME ZONE 'America/Mexico_City'))::date)
    AND a.dia <= coalesce(p_hasta, (now() AT TIME ZONE 'America/Mexico_City')::date)
  ORDER BY a.dia, a.vendida_en;
$$;

CREATE OR REPLACE FUNCTION public.accesorio_eliminar(
  p_store text, p_token text, p_id bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  DELETE FROM public.accesorios_ventas WHERE store_id = p_store AND id = p_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'borradas', n);
END $fn$;


-- ── 5 · Mantener el catalogo (Admin) ────────────────────────
CREATE OR REPLACE FUNCTION public.accesorio_catalogo_guardar(
  p_store text, p_token text, p_nombre text,
  p_precio numeric DEFAULT NULL, p_orden integer DEFAULT 100
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_nombre),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'falta el nombre');
  END IF;
  INSERT INTO public.accesorios_catalogo (store_id, nombre, precio_ref, orden)
  VALUES (p_store, trim(p_nombre), p_precio, coalesce(p_orden,100))
  ON CONFLICT (store_id, nombre) DO UPDATE
    SET precio_ref = excluded.precio_ref, orden = excluded.orden, activo = true;
  RETURN jsonb_build_object('ok', true);
END $fn$;

CREATE OR REPLACE FUNCTION public.accesorio_catalogo_baja(
  p_store text, p_token text, p_id bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  /* Se da de baja, NO se borra: las ventas guardan el nombre del producto como
     texto, y borrar la fila del catalogo dejaria ventas apuntando a algo que
     ya no existe cuando alguien quiera cruzarlas. */
  UPDATE public.accesorios_catalogo SET activo = false
   WHERE store_id = p_store AND id = p_id;
  RETURN jsonb_build_object('ok', true);
END $fn$;


-- ── 6 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.accesorio_guardar(text,text,text,text,text,integer,numeric,text,date,text,text,text,text) FROM public;
REVOKE ALL ON FUNCTION public.accesorios_lista(text,date,date)            FROM public;
REVOKE ALL ON FUNCTION public.accesorios_catalogo_lista(text)             FROM public;
REVOKE ALL ON FUNCTION public.accesorio_eliminar(text,text,bigint)        FROM public;
REVOKE ALL ON FUNCTION public.accesorio_catalogo_guardar(text,text,text,numeric,integer) FROM public;
REVOKE ALL ON FUNCTION public.accesorio_catalogo_baja(text,text,bigint)   FROM public;

GRANT EXECUTE ON FUNCTION public.accesorio_guardar(text,text,text,text,text,integer,numeric,text,date,text,text,text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accesorios_lista(text,date,date)            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accesorios_catalogo_lista(text)             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accesorio_eliminar(text,text,bigint)        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accesorio_catalogo_guardar(text,text,text,numeric,integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accesorio_catalogo_baja(text,text,bigint)   TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) El catalogo arranca con los siete conocidos:
--       select nombre, precio_ref from public.accesorios_catalogo
--        where store_id='1217' order by orden;
--
--  2) Guardar una de prueba y verla:
--       select public.accesorio_guardar('1217', '<token>', 'PRUEBA1',
--              'Cargador 100W', 1, 999, 'Fuentes, Maria');
--       select * from public.accesorios_lista('1217');
--
--  3) Que NO se pueda duplicar el mismo ticket con el mismo producto:
--       select public.accesorio_guardar('1217', '<token>', 'PRUEBA1',
--              'Cargador 100W', 1, 999, 'Fuentes, Maria');
--     Tiene que responder duplicada=true, no un error.
--
--  4) Borrar la prueba:
--       delete from public.accesorios_ventas where ticket = 'PRUEBA1';
--
--  5) LO QUE MAS IMPORTA — que esto NO toque el inventario ni el Assurant.
--     Antes y despues de la prueba, los dos tienen que dar lo mismo:
--       select count(*) from public.inventario_vivo('1217') where stock > 0;
--       select * from public.ventas_hoy('1217');
--
-- ============================================================
--  Odemas · Grupo Gigante — uso interno HES 1217
-- ============================================================

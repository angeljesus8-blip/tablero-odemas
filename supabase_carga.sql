-- ============================================================
-- Fase 1 · Carga de datos — APLICADO el 2-ago-2026
-- ============================================================
--
-- ✅ LAS SEIS ESTÁN AQUÍ (completado el 4-ago-2026)
--
-- cargar_catalogo · cargar_resto · cargar_ventas · cargar_cortes ·
-- cargar_apartados_comisiones · rescatar_sin_upc
--
-- Las cuatro últimas se sacaron de la base con `pg_get_functiondef` y están al
-- final del archivo, tal cual corren. Hasta hoy solo existían dentro de
-- Supabase: el mismo agujero que tenía el respaldo del Apps Script, y ya había
-- costado caro — el 4-ago hubo que parchear `cargar_ventas` leyéndola de la
-- base y reemplazando texto, porque no había copia que editar.
--
-- **Si se cambia una en el editor, hay que traerla aquí.** Para eso:
--
--     select pg_get_functiondef(p.oid)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.proname like 'cargar%';
--
-- `cargar_ventas` ya incluye el arreglo del ON CONFLICT del 4-ago, y
-- `cargar_catalogo` el de `vigente`.
-- ============================================================
--
-- Cómo se mueven los datos, y por qué así
-- ---------------------------------------
-- La hoja está en Google y Supabase no puede leerla. Exportar a CSV y volver a
-- importar es manual, se hace mal y no se puede repetir.
--
-- En vez de eso, **Postgres llama al Apps Script él mismo** con la extensión
-- `http`. El GAS ya devuelve JSON y responde con Access-Control-Allow-Origin:*,
-- así que sirve igual a una app que a la base de datos.
--
-- Lo bueno de este camino:
--   · el token sale de public.tiendas y no pasa por ningún lado
--   · se puede repetir tantas veces como haga falta, es idempotente
--   · no hay archivos intermedios que se puedan quedar viejos
--
-- Requisitos (ya aplicados):
--   CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;
--
-- OJO con el timeout: la extensión corta a los 5 s por defecto y `modo=todo`
-- tarda más. Hay que subirlo EN LA MISMA SESIÓN de la llamada:
--   SELECT extensions.http_set_curlopt('CURLOPT_TIMEOUT','60');
-- No se guarda entre sesiones.
--
-- ============================================================

-- ------------------------------------------------------------
-- 1 · CATÁLOGO  ←  modo=catalogo
-- ------------------------------------------------------------
-- Devuelve {upc: {s,d,o,p}} indexado por UPC. Dos consecuencias:
--   · un SKU con dos códigos de barras sale DOS VECES → hay que deduplicar o
--     el INSERT truena con "ON CONFLICT cannot affect row a second time"
--   · los que vienen de Catalogo_ref llegan con o y p vacíos: son los agotados
--     que el cliente sigue pidiendo → vigente = false
CREATE OR REPLACE FUNCTION public.cargar_catalogo(p_store text) RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE cuerpo jsonb; n int; dups int;
BEGIN
  SELECT r.content::jsonb INTO cuerpo
  FROM public.tiendas t,
       LATERAL extensions.http_get(t.gas_url || '?modo=catalogo&t=' || t.gas_token) r
  WHERE t.store_id = p_store;

  IF cuerpo IS NULL OR cuerpo ? 'error' THEN RETURN 'la nube no devolvio catalogo'; END IF;

  WITH plano AS (
    SELECT trim(j.value->>'s') AS sku
    FROM jsonb_each(cuerpo) j WHERE trim(coalesce(j.value->>'s','')) <> ''
  )
  SELECT count(*) - count(DISTINCT sku) INTO dups FROM plano;

  INSERT INTO public.catalogo (store_id, sku, descripcion, upc, precio, vigente)
  SELECT p_store, u.sku, u.descripcion, u.upc, u.precio, u.vigente
  FROM (
    SELECT DISTINCT ON (sku) * FROM (
      SELECT trim(j.value->>'s') AS sku,
             coalesce(j.value->>'d','') AS descripcion,
             nullif(trim(j.key),'') AS upc,
             nullif(regexp_replace(coalesce(j.value->>'p',''),'[^0-9.]','','g'),'')::numeric AS precio,
             (coalesce(nullif(trim(j.value->>'o'),''),'') <> '') AS vigente
      FROM jsonb_each(cuerpo) j
      WHERE trim(coalesce(j.value->>'s','')) <> ''
    ) p ORDER BY sku, vigente DESC, precio DESC NULLS LAST, upc
  ) u
  ON CONFLICT (store_id, sku) DO UPDATE
    SET descripcion = excluded.descripcion,
        upc         = coalesce(excluded.upc, public.catalogo.upc),
        precio      = coalesce(excluded.precio, public.catalogo.precio),
        -- 4-ago-2026: aquí decía `public.catalogo.vigente OR excluded.vigente`,
        -- y con ese OR un SKU marcado vigente NO volvía a false nunca. Al
        -- agotarse un producto y salir del Excel del día, en Supabase seguía
        -- "vigente" para siempre: la carga solo podía sumar vigentes, jamás
        -- quitarlos. Se vio al resincronizar — 71 aquí contra 64 en el GAS.
        -- El DISTINCT ON de arriba ya ordena por vigente DESC, así que la fila
        -- que llega es la correcta para ese SKU en esta carga: debe MANDAR.
        vigente     = excluded.vigente,
        updated_at  = now();

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n || ' SKUs cargados · ' || dups || ' duplicados por UPC descartados';
EXCEPTION WHEN OTHERS THEN
  -- sin la URL: lleva el token dentro
  RETURN 'ERROR ' || SQLSTATE || ': ' || left(regexp_replace(SQLERRM,'https?://[^ ]+','<url>','g'), 160);
END $fn$;

-- ------------------------------------------------------------
-- 2 · EL RESTO  ←  modo=todo (un solo viaje)
-- ------------------------------------------------------------
-- CUIDADO: modo=todo devuelve bundles y avisos YA FILTRADOS por vigencia. Si
-- llegan vacíos no es que falle la carga: es que hoy no hay ninguno vigente.
-- Los vencidos no se pueden recuperar por esta vía — el GAS no los expone.
CREATE OR REPLACE FUNCTION public.cargar_resto(p_store text) RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE d jsonb; a int; b int; c int; e int; f int;
BEGIN
  SELECT r.content::jsonb INTO d
  FROM public.tiendas t,
       LATERAL extensions.http_get(t.gas_url || '?modo=todo&t=' || t.gas_token) r
  WHERE t.store_id = p_store;
  IF d IS NULL OR d ? 'error' THEN RETURN 'la nube no devolvio datos'; END IF;

  -- Solo se toman o (on hand) y e (exhibición). v y ev son calculados: aquí los
  -- vuelve a sacar inventario_vivo a partir de inventario_corte.
  INSERT INTO public.inventario (store_id, sku, onhand, exhibicion)
  SELECT p_store, j.key,
         greatest(0, coalesce((j.value->>'o')::int, 0)),
         greatest(0, coalesce((j.value->>'e')::int, 0))
  FROM jsonb_each(d->'inventario') j
  WHERE trim(j.key) <> ''
    AND EXISTS (SELECT 1 FROM public.catalogo c WHERE c.store_id=p_store AND c.sku=j.key)
  ON CONFLICT (store_id, sku) DO UPDATE
    SET onhand = excluded.onhand, exhibicion = excluded.exhibicion, updated_at = now();
  GET DIAGNOSTICS a = ROW_COUNT;

  INSERT INTO public.promos (store_id, sku, producto, precio_reg, precio_pro, estatus, msi, vigente_desde, vigente_hasta)
  SELECT p_store, j.key, coalesce(j.value->>'d',''),
         nullif(regexp_replace(coalesce(j.value->>'pr',''),'[^0-9.]','','g'),'')::numeric,
         nullif(regexp_replace(coalesce(j.value->>'pp',''),'[^0-9.]','','g'),'')::numeric,
         nullif(j.value->>'est',''), nullif(j.value->>'msi',''),
         nullif(j.value->>'d1','')::date, nullif(j.value->>'d2','')::date
  FROM jsonb_each(d->'promos') j
  WHERE trim(j.key) <> '' AND nullif(j.value->>'d2','') IS NOT NULL
  ON CONFLICT (store_id, sku) DO UPDATE
    SET producto=excluded.producto, precio_reg=excluded.precio_reg, precio_pro=excluded.precio_pro,
        estatus=excluded.estatus, msi=excluded.msi, vigente_desde=excluded.vigente_desde,
        vigente_hasta=excluded.vigente_hasta, updated_at=now();
  GET DIAGNOSTICS b = ROW_COUNT;

  INSERT INTO public.eol (store_id, sku, precio)
  SELECT DISTINCT ON (x->>'sku') p_store, x->>'sku',
         nullif(regexp_replace(coalesce(x->>'precio',''),'[^0-9.]','','g'),'')::numeric
  FROM jsonb_array_elements(d->'eol') x
  WHERE trim(coalesce(x->>'sku','')) <> ''
  ORDER BY x->>'sku'
  ON CONFLICT (store_id, sku) DO UPDATE SET precio=excluded.precio, updated_at=now();
  GET DIAGNOSTICS c = ROW_COUNT;

  -- skus llega como "a,b,c" y aquí es text[] de verdad
  DELETE FROM public.bundles WHERE store_id = p_store;
  INSERT INTO public.bundles (store_id, nombre, skus, precio, vigente_desde, vigente_hasta, activo)
  SELECT p_store, x->>'nombre',
         string_to_array(regexp_replace(coalesce(x->>'skus',''), '\s', '', 'g'), ','),
         nullif(regexp_replace(coalesce(x->>'precio',''),'[^0-9.]','','g'),'')::numeric,
         nullif(x->>'d1','')::date, nullif(x->>'d2','')::date, true
  FROM jsonb_array_elements(d->'bundles') x
  WHERE nullif(x->>'d2','') IS NOT NULL AND nullif(x->>'precio','') IS NOT NULL;
  GET DIAGNOSTICS e = ROW_COUNT;

  DELETE FROM public.avisos WHERE store_id = p_store;
  INSERT INTO public.avisos (store_id, titulo, detalle, prioridad, vigente_hasta)
  SELECT p_store, x->>'titulo', nullif(x->>'detalle',''),
         coalesce(nullif(x->>'prioridad',''),'normal'), nullif(x->>'d2','')::date
  FROM jsonb_array_elements(d->'avisos') x
  WHERE trim(coalesce(x->>'titulo','')) <> '';
  GET DIAGNOSTICS f = ROW_COUNT;

  RETURN 'inventario=' || a || ' promos=' || b || ' eol=' || c || ' bundles=' || e || ' avisos=' || f;
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERROR ' || SQLSTATE || ': ' || left(regexp_replace(SQLERRM,'https?://[^ ]+','<url>','g'), 170);
END $fn$;

-- ------------------------------------------------------------
-- Cómo se corre
-- ------------------------------------------------------------
--   SELECT extensions.http_set_curlopt('CURLOPT_TIMEOUT','60');
--   SELECT public.cargar_catalogo('1217');
--   SELECT public.cargar_resto('1217');

/* ============================================================
   Resultado del 2-ago-2026

     catálogo    214 SKUs  (1 duplicado por UPC descartado)
     inventario  214
     promos      117   ← las mismas 117 de la hoja
     eol         133   ← las mismas 133
     bundles       0
     avisos        0

   Los ceros NO son un fallo: se comprobó pidiéndole a `modo=todo` sus propios
   conteos y el Apps Script también devuelve 0 y 0. **Los 20 combos de la hoja
   están todos vencidos**, así que hoy el equipo no ve ninguno en el tablero.
   Eso es un asunto de la tienda, no de la migración.

   El GAS reporta 215 SKUs de inventario y aquí hay 214: la diferencia es el
   producto que está con dos códigos de barras.

   FALTA:
     · ventas — no hay modo que las devuelva todas; ventas_detalle da un día
       por llamada. Hace falta un modo de exportación en el Apps Script.
     · apartados (9) y comisiones (4)
     · inventario_corte — depende de las ventas: el corte es
       (ventas totales del SKU − lo vendido desde el corte), y sin ventas
       cargadas no se puede calcular.
   ============================================================ */

-- ------------------------------------------------------------
-- 3 · VENTAS  ←  modo=exportar&hoja=Ventas
-- ------------------------------------------------------------
-- La fecha viene ya resuelta en _iso desde el Apps Script, que SI conoce la
-- zona horaria. Armarla aqui haria que una venta de las 8 pm se guardara con
-- la fecha del dia siguiente.
--   con_seguro NULL a proposito: son las anteriores a julio-2026, cuando el
--   campo no existia. Contarlas como "sin seguro" hundiria el attach rate.
--   (funcion cargar_ventas — ver historial de git para el cuerpo completo)

-- ------------------------------------------------------------
-- 4 · CORTES DE INVENTARIO  ←  modo=inventario   ¡VA DESPUES DE LAS VENTAS!
-- ------------------------------------------------------------
-- El GAS no guarda el corte: guarda cuantas ventas habia cuando se tomo, y
-- reporta v = (ventas totales de ahora) - corte. Aqui se despeja al reves:
--     corte = total de ventas - v
-- Por eso este paso NO puede ir antes de cargar_ventas: sin ventas cargadas el
-- total es cero y todos los cortes saldrian en cero, con lo que el tablero
-- mostraria como "vendido" todo el historico y el stock en cero.

-- ------------------------------------------------------------
-- 5 · SKUs SIN CODIGO DE BARRAS  ←  rescatar_sin_upc()
-- ------------------------------------------------------------
-- BUG ENCONTRADO AL MIGRAR: leerCatalogo_ indexa por UPC y hace
--     if (upc) out[upc] = {...}
-- asi que un SKU de Catalogo_ref SIN codigo de barras no sale nunca en
-- modo=catalogo. Como Captura de Series se alimenta de ahi, ese producto no se
-- autocompleta al teclear su SKU.
--
-- El 2-ago-2026 habia uno: 100270551, HUAWEI MatePad 11.5" 8/256GB.
-- modo=inventario si lo conoce, asi que se rescata de ahi.
--
-- OJO: en el editor de Supabase, un INSERT ... WITH que va despues de otro
-- SELECT no se ejecuta. Metido dentro de una funcion plpgsql si corre.

/* ============================================================
   PARIDAD — 2-ago-2026

   inventario_vivo('1217') contra modo=inventario del Apps Script:

     gas=215  supabase=215
     difieren: onhand=0  vendido=0  exhibicion=0  exh_vendida=0
     solo_en_gas=0  solo_en_supabase=0

   Identicos en los 215 SKUs, incluidos los dos cortes. Es la funcion mas
   delicada del sistema y la que se verifico contando cajas en piso.

   Cargado hasta ahora:
     catalogo 215 · inventario 214 · promos 117 · eol 133 · ventas 220
     cortes onhand 215 · cortes exhibicion 215
     bundles 0 y avisos 0 (el GAS tambien devuelve 0: estan vencidos)

   FALTA: apartados (9), comisiones (4), y comparar las otras seis funciones.
   ============================================================ */

-- ------------------------------------------------------------
-- 6 · APARTADOS Y COMISIONES  <-  modo=exportar
-- ------------------------------------------------------------
-- El esquema de apartados NO tenia color, precio ni transaccion, y la hoja si.
-- Migrar asi habria perdido el numero de ticket del POS, que es el enlace entre
-- el apartado y la venta. Se agregaron antes de cargar:
--   ALTER TABLE public.apartados
--     ADD COLUMN IF NOT EXISTS color text,
--     ADD COLUMN IF NOT EXISTS precio numeric(12,2),
--     ADD COLUMN IF NOT EXISTS transaccion text;
--
-- Leccion: consultar information_schema ANTES de escribir el INSERT. Asumir las
-- columnas costo dos intentos y por poco cuesta datos.

/* ============================================================
   FASE 1 CERRADA — 2-ago-2026

   Cargado:
     catalogo 215 · inventario 214 · promos 117 · eol 133
     ventas 220 · apartados 9 · comisiones 4
     cortes onhand 215 · cortes exhibicion 215
     bundles 0 y avisos 0 — el GAS tambien devuelve 0, estan vencidos

   PARIDAD contra el Apps Script, funcion por funcion:

     inventario_vivo   gas=215  mio=215  difieren=0  (onhand, vendido,
                                                      exhibicion, exh_vendida)
     eol_precio_venta  gas=3    mio=3    difieren=0
     ventas_hoy        gas=3    mio=3    difieren=0
     ventas_detalle    gas=4    mio=4    difieren=0
     promos_vigentes   gas=117  mio=117

   Las siete lecturas devuelven lo mismo que el Apps Script con los mismos
   datos. Se puede pasar a la fase 2.
   ============================================================ */


-- ============================================================
-- Definiciones extraídas de Supabase el 4-ago-2026
-- ============================================================
-- Sacadas con pg_get_functiondef y pegadas tal cual. Son las que estaban
-- corriendo sin copia en ningún lado; ese fue el agujero que obligó a parchear
-- `cargar_ventas` leyéndola de la base cuando se rompió su ON CONFLICT.
--
-- Ojo: `cargar_ventas` YA lleva aquí el arreglo del 4-ago
-- (ON CONFLICT (store_id, serie, dia_venta), antes solo store_id+serie).
-- ============================================================

CREATE OR REPLACE FUNCTION public.rescatar_sin_upc(p_store text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE d jsonb; n int; faltan int;
BEGIN
  SELECT r.content::jsonb INTO d
  FROM public.tiendas t,
       LATERAL extensions.http_get(t.gas_url || '?modo=inventario&t=' || t.gas_token) r
  WHERE t.store_id = p_store;
  IF d IS NULL THEN RETURN 'sin respuesta'; END IF;

  SELECT count(*) INTO faltan
  FROM jsonb_each(d) j
  WHERE trim(j.key) <> ''
    AND NOT EXISTS (SELECT 1 FROM public.catalogo c WHERE c.store_id=p_store AND c.sku=j.key);

  INSERT INTO public.catalogo (store_id, sku, descripcion, upc, precio, vigente)
  SELECT p_store, j.key, coalesce(j.value->>'d',''), NULL,
         nullif(regexp_replace(coalesce(j.value->>'p',''),'[^0-9.]','','g'),'')::numeric,
         (coalesce(nullif(trim(j.value->>'o'),''),'0') <> '0')
  FROM jsonb_each(d) j
  WHERE trim(j.key) <> ''
    AND NOT EXISTS (SELECT 1 FROM public.catalogo c WHERE c.store_id=p_store AND c.sku=j.key)
  ON CONFLICT (store_id, sku) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;

  RETURN 'faltaban ' || faltan || ' · insertados ' || n;
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERROR ' || SQLSTATE || ': ' || left(regexp_replace(SQLERRM,'https?://[^ ]+','<url>','g'), 170);
END $function$;


CREATE OR REPLACE FUNCTION public.cargar_ventas(p_store text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE d jsonb; n int; sin_fecha int; sin_sku int;
BEGIN
  SELECT r.content::jsonb INTO d
  FROM public.tiendas t,
       LATERAL extensions.http_get(t.gas_url || '?modo=exportar&hoja=Ventas&t=' || t.gas_token) r
  WHERE t.store_id = p_store;
  IF d IS NULL OR d ? 'error' THEN RETURN 'la nube no devolvio ventas'; END IF;

  SELECT count(*) FILTER (WHERE coalesce(x->>'_iso','') = ''),
         count(*) FILTER (WHERE trim(coalesce(x->>'SKU','')) = '')
    INTO sin_fecha, sin_sku
  FROM jsonb_array_elements(d->'filas') x;

  INSERT INTO public.ventas (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro, foto_url)
  SELECT p_store,
         (x->>'_iso')::timestamptz,
         trim(x->>'Numero de serie'),
         nullif(trim(coalesce(x->>'SKU','')), ''),
         nullif(trim(coalesce(x->>'Descripcion','')), ''),
         nullif(regexp_replace(coalesce(x->>'Precio',''),'[^0-9.]','','g'),'')::numeric,
         trim(coalesce(x->>'Vendedor','')),
         -- vacio = venta anterior a julio-2026, cuando el campo no existia.
         -- NULL a proposito: contarlas como "sin seguro" hundiria el attach.
         CASE lower(trim(coalesce(x->>'Seguro','')))
           WHEN 'si' THEN true WHEN 'no' THEN false ELSE NULL END,
         nullif(trim(coalesce(x->>'Foto','')), '')
  FROM jsonb_array_elements(d->'filas') x
  WHERE trim(coalesce(x->>'Numero de serie','')) <> ''
    AND coalesce(x->>'_iso','') <> ''
    AND trim(coalesce(x->>'Vendedor','')) <> ''
  ON CONFLICT (store_id, serie, dia_venta) DO NOTHING;

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n || ' ventas cargadas · ' || sin_fecha || ' sin fecha usable · ' || sin_sku || ' sin SKU';
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERROR ' || SQLSTATE || ': ' || left(regexp_replace(SQLERRM,'https?://[^ ]+','<url>','g'), 170);
END $function$;



CREATE OR REPLACE FUNCTION public.cargar_cortes(p_store text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE d jsonb; a int; b int;
BEGIN
  SELECT r.content::jsonb INTO d
  FROM public.tiendas t,
       LATERAL extensions.http_get(t.gas_url || '?modo=inventario&t=' || t.gas_token) r
  WHERE t.store_id = p_store;
  IF d IS NULL OR d ? 'error' THEN RETURN 'la nube no devolvio inventario'; END IF;

  -- El GAS no guarda el corte: guarda cuantas ventas habia CUANDO se tomo, y
  -- reporta v = (ventas totales de ahora) - corte. Aqui se despeja al reves,
  -- con las ventas ya cargadas:  corte = total - v.
  -- Por eso este paso va DESPUES de cargar_ventas y no antes.
  WITH totales AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      -- MISMO filtro que inventario_vivo: las entregas de preventa no cuentan,
      -- el POS ya desconto esas piezas. Si uno cambia, el otro tambien.
      -- Ver supabase_inventario_preventa.sql (7-ago-2026).
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
    GROUP BY v.sku
  ), reportado AS (
    SELECT j.key AS sku,
           coalesce((j.value->>'v')::int, 0)  AS v,
           coalesce((j.value->>'ev')::int, 0) AS ev
    FROM jsonb_each(d) j
    WHERE trim(j.key) <> ''
  )
  INSERT INTO public.inventario_corte (store_id, tipo, sku, vendidas)
  SELECT p_store, 'onhand', r.sku, greatest(0, coalesce(t.total,0) - r.v)
  FROM reportado r LEFT JOIN totales t ON t.sku = r.sku
  ON CONFLICT (store_id, tipo, sku) DO UPDATE
    SET vendidas = excluded.vendidas, tomado_en = now();
  GET DIAGNOSTICS a = ROW_COUNT;

  WITH totales AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      -- MISMO filtro que inventario_vivo: las entregas de preventa no cuentan,
      -- el POS ya desconto esas piezas. Si uno cambia, el otro tambien.
      -- Ver supabase_inventario_preventa.sql (7-ago-2026).
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
    GROUP BY v.sku
  ), reportado AS (
    SELECT j.key AS sku, coalesce((j.value->>'ev')::int, 0) AS ev
    FROM jsonb_each(d) j WHERE trim(j.key) <> ''
  )
  INSERT INTO public.inventario_corte (store_id, tipo, sku, vendidas)
  SELECT p_store, 'exhibicion', r.sku, greatest(0, coalesce(t.total,0) - r.ev)
  FROM reportado r LEFT JOIN totales t ON t.sku = r.sku
  ON CONFLICT (store_id, tipo, sku) DO UPDATE
    SET vendidas = excluded.vendidas, tomado_en = now();
  GET DIAGNOSTICS b = ROW_COUNT;

  RETURN 'corte onhand=' || a || ' · corte exhibicion=' || b;
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERROR ' || SQLSTATE || ': ' || left(regexp_replace(SQLERRM,'https?://[^ ]+','<url>','g'), 170);
END $function$;


CREATE OR REPLACE FUNCTION public.cargar_apartados_comisiones(p_store text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE d jsonb; a int; c int;
BEGIN
  SELECT r.content::jsonb INTO d
  FROM public.tiendas t,
       LATERAL extensions.http_get(t.gas_url || '?modo=exportar&hoja=Apartados&t=' || t.gas_token) r
  WHERE t.store_id = p_store;
  IF d IS NULL OR d ? 'error' THEN RETURN 'la nube no devolvio apartados'; END IF;

  DELETE FROM public.apartados WHERE store_id = p_store;
  INSERT INTO public.apartados (store_id, sku, color, cliente, telefono, precio, con_seguro,
                                vendedor, estatus, transaccion, piezas, creado_en)
  SELECT p_store,
         trim(coalesce(x->>'SKU','')),
         nullif(trim(coalesce(x->>'Color','')),''),
         trim(coalesce(x->>'Cliente','')),
         nullif(trim(coalesce(x->>'Telefono','')),''),
         nullif(regexp_replace(coalesce(x->>'Precio',''),'[^0-9.]','','g'),'')::numeric,
         CASE lower(trim(coalesce(x->>'Seguro',''))) WHEN 'si' THEN true WHEN 'no' THEN false ELSE NULL END,
         trim(coalesce(x->>'Vendedor','')),
         coalesce(nullif(trim(x->>'Estatus'),''),'Apartado'),
         nullif(trim(coalesce(x->>'Transaccion','')),''),
         1,
         -- la hoja guarda 'yyyy-MM-dd HH:mm', ya en hora de Mexico
         (nullif(trim(x->>'Fecha'),'') || ' America/Mexico_City')::timestamptz
  FROM jsonb_array_elements(d->'filas') x
  WHERE trim(coalesce(x->>'SKU','')) <> '';
  GET DIAGNOSTICS a = ROW_COUNT;

  SELECT r.content::jsonb INTO d
  FROM public.tiendas t,
       LATERAL extensions.http_get(t.gas_url || '?modo=exportar&hoja=Comisiones&t=' || t.gas_token) r
  WHERE t.store_id = p_store;
  IF d IS NULL OR d ? 'error' THEN RETURN 'apartados=' || a || ' pero comisiones fallo'; END IF;

  DELETE FROM public.comisiones WHERE store_id = p_store;
  INSERT INTO public.comisiones (store_id, empno, nombre, puesto, venta, ppto_pct, alcance,
                                 gar_pct, gar_pzas, gar_elegible, gar_monto)
  SELECT p_store,
         nullif(trim(coalesce(x->>'EmpNo','')),''),
         trim(coalesce(x->>'Nombre','')),
         nullif(trim(coalesce(x->>'Puesto','')),''),
         coalesce(nullif(regexp_replace(coalesce(x->>'Venta',''),'[^0-9.]','','g'),'')::numeric, 0),
         coalesce(nullif(regexp_replace(coalesce(x->>'PptoPct',''),'[^0-9.]','','g'),'')::numeric, 0),
         coalesce(nullif(regexp_replace(coalesce(x->>'Alcance',''),'[^0-9.]','','g'),'')::numeric, 0),
         nullif(regexp_replace(coalesce(x->>'GarantiaPct',''),'[^0-9.]','','g'),'')::numeric,
         nullif(regexp_replace(coalesce(x->>'GarantiaPzas',''),'[^0-9.]','','g'),'')::int,
         nullif(regexp_replace(coalesce(x->>'GarantiaElegible',''),'[^0-9.]','','g'),'')::int,
         nullif(regexp_replace(coalesce(x->>'GarantiaMonto',''),'[^0-9.]','','g'),'')::numeric
  FROM jsonb_array_elements(d->'filas') x
  WHERE trim(coalesce(x->>'Nombre','')) <> '';
  GET DIAGNOSTICS c = ROW_COUNT;

  RETURN 'apartados=' || a || ' comisiones=' || c;
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERROR ' || SQLSTATE || ': ' || left(regexp_replace(SQLERRM,'https?://[^ ]+','<url>','g'), 170);
END $function$;

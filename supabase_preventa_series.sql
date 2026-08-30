-- ============================================================
--  PREVENTA NATIVA EN SUPABASE — apartados, series y entrega
--  Etapa 1 de "apagar la hoja" (fase 4 del MIGRACION_PLAN, adelantada)
--  7-ago-2026
-- ============================================================
--
--  QUE CAMBIA
--  ----------
--  Hasta hoy los apartados vivian SOLO en la hoja: `agregarApartado_`
--  (GAS_Codigo.gs, l. 559) hace appendRow y nada mas. El Apps Script NUNCA
--  escribio en Supabase. Los 9 apartados que hay en la tabla son el volcado
--  manual del 2-ago y ahi se quedaron congelados.
--
--  Efecto colateral que esto destapa: el trigger `apartado_cabe` que se
--  corrigio el 5-ago para frenar el doble apartado NUNCA SE HA DISPARADO,
--  porque nadie inserta en la tabla que vigila. El cupo real lo estaba
--  sosteniendo solo el numero del navegador.
--
--  A partir de aqui la tabla `apartados` es la unica verdad y la hoja deja de
--  recibir preventa.
--
--  EL ORDEN IMPORTA: correr `resincronizar('1217')` ANTES de esto, para traer
--  los apartados que la hoja tenga desde el 2-ago. Si se hace despues, la
--  resincronizacion pisa las series recien asignadas con las filas de la hoja,
--  que no las tienen.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
-- ============================================================


-- ── 1 · Las columnas que faltaban ───────────────────────────
-- `serie` es el numero de serie del equipo fisico ligado a ese cliente.
-- Se separa `asignado_en` de `entregado_en` a proposito: asignar es apartar la
-- pieza al recibir la caja, entregar es que salio de la tienda. Con una sola
-- fecha no se puede saber cuanta mercancia esta comprometida pero todavia en
-- bodega, que es justo lo que hay que saber cuando llega el embarque.
--
-- `entregado_por` NO es lo mismo que `vendedor`: la venta se acredita a quien
-- hizo la preventa, pero quien puso el equipo en las manos del cliente puede
-- ser otro, y es la primera pregunta que se hace cuando hay un reclamo.
ALTER TABLE public.apartados
  ADD COLUMN IF NOT EXISTS serie         text,
  ADD COLUMN IF NOT EXISTS asignado_en   timestamptz,
  ADD COLUMN IF NOT EXISTS entregado_en  timestamptz,
  ADD COLUMN IF NOT EXISTS entregado_por text,
  ADD COLUMN IF NOT EXISTS venta_id      bigint;


-- ── 2 · Una serie no puede estar en dos apartados ───────────
-- Es EL error que no se puede permitir: dos clientes con la misma pieza
-- prometida se descubre con los dos enfrente del mostrador. Los cancelados
-- quedan fuera del indice: si un apartado se cae, su serie se libera para otro.
CREATE UNIQUE INDEX IF NOT EXISTS apartados_serie_unica
  ON public.apartados (store_id, serie)
  WHERE serie IS NOT NULL AND estatus <> 'Cancelado';


-- ── 3 · La guardia de escritura ─────────────────────────────
-- Mismo candado que ya protege al Apps Script desde el 4-ago: el token de
-- tienda, que llega en la sesion (login_asesor/login_empleado lo devuelven como
-- `gas_token`). No es peor que hoy ni mejor: es EL MISMO secreto compartido,
-- movido de puerta. La anon key por si sola no basta para escribir.
--
-- Se llama `gas_token` porque asi se llama la columna hoy. Al retirar el Apps
-- Script (etapa 5) se renombra a `write_token`; renombrarla ahora obligaria a
-- tocar el login y las seis apps en el mismo movimiento, y esto tiene que poder
-- entrar solo.
CREATE OR REPLACE FUNCTION public.escritura_ok_(p_store text, p_token text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tiendas t
     WHERE t.store_id = p_store
       AND coalesce(t.activo, true) = true
       AND length(coalesce(p_token,'')) >= 8
       AND p_token = t.gas_token
  );
$$;


-- ── 4 · Guardar un apartado  ←  reemplaza modo=apartado_add ──
-- Devuelve el error en jsonb en vez de lanzarlo: el asesor tiene al cliente
-- enfrente y necesita leer que paso, no un 500 del PostgREST.
CREATE OR REPLACE FUNCTION public.apartado_guardar(
  p_store       text,
  p_token       text,
  p_sku         text,
  p_color       text    DEFAULT NULL,   -- producto entero, ver MAPA cadena 2-bis
  p_cliente     text    DEFAULT NULL,
  p_telefono    text    DEFAULT NULL,
  p_precio      numeric DEFAULT NULL,
  p_seguro      boolean DEFAULT false,
  p_vendedor    text    DEFAULT NULL,
  p_transaccion text    DEFAULT NULL    -- ticket del POS: el enlace con la venta
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE nuevo bigint;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_cliente),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin cliente');
  END IF;
  IF coalesce(trim(p_sku),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin sku');
  END IF;

  INSERT INTO public.apartados
    (store_id, sku, color, cliente, telefono, precio, con_seguro,
     vendedor, transaccion, piezas, estatus)
  VALUES
    (p_store, trim(p_sku), nullif(trim(coalesce(p_color,'')),''),
     trim(p_cliente), nullif(trim(coalesce(p_telefono,'')),''), p_precio,
     coalesce(p_seguro, false), nullif(trim(coalesce(p_vendedor,'')),''),
     nullif(trim(coalesce(p_transaccion,'')),''), 1, 'Apartado')
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);

EXCEPTION
  -- El trigger apartado_cabe lanza esto cuando el SKU llego a su cupo. Es un
  -- resultado esperado, no una averia: se traduce a algo que el asesor entienda.
  WHEN raise_exception THEN
    RETURN jsonb_build_object('ok', false, 'error', left(SQLERRM, 140));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 5 · Asignar la serie  ←  al recibir el embarque ─────────
-- Idempotente a proposito: volver a escanear la MISMA serie en el MISMO
-- apartado responde ok, no error. Un asesor que no vio el toast escanea otra
-- vez, y eso no puede ser un fallo.
CREATE OR REPLACE FUNCTION public.apartado_serie(
  p_store text,
  p_token text,
  p_id    bigint,
  p_serie text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE a public.apartados%ROWTYPE; ocupada text;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  SELECT * INTO a FROM public.apartados
   WHERE id = p_id AND store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'apartado no encontrado');
  END IF;
  IF a.estatus = 'Cancelado' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'el apartado esta cancelado');
  END IF;
  IF a.estatus = 'Entregado' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ya se entrego, la serie no se cambia');
  END IF;

  -- ya la tiene: reintento, no problema
  IF a.serie IS NOT NULL AND trim(a.serie) = trim(p_serie) THEN
    RETURN jsonb_build_object('ok', true, 'id', a.id, 'serie', a.serie, 'repetida', true);
  END IF;

  -- la pieza ya esta prometida a otro cliente
  SELECT cliente INTO ocupada FROM public.apartados
   WHERE store_id = p_store AND serie = trim(p_serie)
     AND estatus <> 'Cancelado' AND id <> p_id
   LIMIT 1;
  IF ocupada IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa serie ya es de ' || ocupada);
  END IF;

  UPDATE public.apartados
     SET serie = trim(p_serie), asignado_en = now(),
         estatus = CASE WHEN estatus = 'Apartado' THEN 'Asignado' ELSE estatus END
   WHERE id = p_id AND store_id = p_store;

  RETURN jsonb_build_object('ok', true, 'id', p_id, 'serie', trim(p_serie),
                            'estatus', 'Asignado');
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'esa serie ya esta asignada');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 6 · Entregar  ←  cuando el cliente se lleva el equipo ───
-- Hace DOS cosas en una transaccion: registra la venta y cierra el apartado.
-- Separarlas dejaria entregas sin venta si falla la segunda llamada, y eso no
-- da error: da inventario que no baja.
--
-- La venta se acredita al VENDEDOR DEL APARTADO, no a quien entrega —decidido
-- el 7-ago-2026—. Con la fecha de HOY, que es cuando el equipo sale. Ojo al
-- comparar con el POS: ahi el ticket se cobro semanas antes, asi que estas
-- piezas caen en meses distintos en un reporte y en el otro. Es esperado.
-- DROP explícito: si una versión anterior quedó con otra lista de parámetros,
-- CREATE OR REPLACE no la sustituye —crea una sobrecarga—, y PostgREST tendría
-- dos candidatas y elegiría mal sin avisar.
DROP FUNCTION IF EXISTS public.apartado_entregar(text,text,bigint,text);
DROP FUNCTION IF EXISTS public.apartado_entregar(text,text,bigint,text,text);

CREATE FUNCTION public.apartado_entregar(
  p_store text,
  p_token text,
  p_id    bigint,
  p_serie text DEFAULT NULL,    -- si viene, tiene que coincidir con la asignada
  p_quien text DEFAULT NULL     -- quién entrega, que no es quién vendió
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  a       public.apartados%ROWTYPE;
  v_serie text;
  v_desc  text;
  nuevo   bigint;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;

  SELECT * INTO a FROM public.apartados
   WHERE id = p_id AND store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'apartado no encontrado');
  END IF;
  IF a.estatus = 'Cancelado' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'el apartado esta cancelado');
  END IF;

  -- Ya entregado: no se vuelve a registrar la venta. Un doble toque del boton
  -- con mala señal no puede convertirse en dos ventas.
  IF a.estatus = 'Entregado' THEN
    RETURN jsonb_build_object('ok', true, 'id', a.id, 'serie', a.serie,
                              'venta_id', a.venta_id, 'ya_entregado', true);
  END IF;

  v_serie := nullif(trim(coalesce(p_serie, a.serie, '')), '');
  IF v_serie IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie: asignala antes de entregar');
  END IF;
  -- Escanear al entregar es la verificacion de que sale LA pieza de ese cliente
  -- y no otra del mismo color. Si no coincide, se para aqui.
  IF a.serie IS NOT NULL AND trim(a.serie) <> v_serie THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa no es su pieza: tiene asignada la ' || a.serie);
  END IF;

  -- La descripcion sale del catalogo. Si el SKU todavia no esta cargado —el
  -- caso de la Pura 90S el 7-ago— se usa el texto del apartado, que desde el
  -- 4-ago trae el producto entero. Vale mas eso que una venta sin descripcion.
  SELECT c.descripcion INTO v_desc
    FROM public.catalogo c
   WHERE c.store_id = p_store AND c.sku = a.sku;
  v_desc := nullif(trim(coalesce(nullif(trim(coalesce(v_desc,'')),''), a.color, '')), '');

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro)
  VALUES
    (p_store, now(), v_serie, a.sku, v_desc, a.precio,
     coalesce(nullif(trim(coalesce(a.vendedor,'')),''), 'preventa'),
     coalesce(a.con_seguro, false))
  RETURNING id INTO nuevo;

  UPDATE public.apartados
     SET estatus = 'Entregado', serie = v_serie, entregado_en = now(),
         entregado_por = nullif(trim(coalesce(p_quien,'')),''),
         asignado_en = coalesce(asignado_en, now()), venta_id = nuevo
   WHERE id = p_id AND store_id = p_store;

  RETURN jsonb_build_object('ok', true, 'id', p_id, 'serie', v_serie,
                            'venta_id', nuevo, 'estatus', 'Entregado');

EXCEPTION
  -- La restriccion de ventas es "misma serie no dos veces el mismo dia"
  -- (supabase_ventas_devolucion.sql). Si salta aqui, esa serie ya se vendio hoy:
  -- casi siempre significa que alguien la capturo tambien por Captura de Series.
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa serie ya se registro como vendida hoy');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 7 · Cancelar / corregir estatus  ←  modo=apartado_estatus ─
-- Cancelar un apartado ya entregado NO borra la venta: la pieza salio de la
-- tienda y el inventario tiene que seguir reflejandolo. Se rechaza y punto.
CREATE OR REPLACE FUNCTION public.apartado_estatus(
  p_store   text,
  p_token   text,
  p_id      bigint,
  p_estatus text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE a public.apartados%ROWTYPE;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_estatus NOT IN ('Apartado','Asignado','Cancelado') THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'estatus invalido: Entregado se pone con apartado_entregar');
  END IF;

  SELECT * INTO a FROM public.apartados WHERE id = p_id AND store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'apartado no encontrado');
  END IF;
  IF a.estatus = 'Entregado' THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'ya se entrego: para revertirlo hay que anular la venta');
  END IF;

  UPDATE public.apartados
     SET estatus = p_estatus,
         -- al cancelar se suelta la serie, para que la pieza vuelva a estar
         -- disponible para otro cliente
         serie       = CASE WHEN p_estatus = 'Cancelado' THEN NULL ELSE serie END,
         asignado_en = CASE WHEN p_estatus = 'Cancelado' THEN NULL ELSE asignado_en END
   WHERE id = p_id AND store_id = p_store;

  RETURN jsonb_build_object('ok', true, 'id', p_id, 'estatus', p_estatus);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 8 · La lectura, ampliada ────────────────────────────────
-- OJO: la version que hay en produccion YA devuelve color, precio y transaccion
-- (se amplio en el editor el 4-ago y el .sql del repo se quedo atras). Esta
-- version incluye esos tres MAS los cuatro campos nuevos. Si se pega la del
-- repo viejo encima, se cae el numero de ticket sin que nada avise.
DROP FUNCTION IF EXISTS public.apartados_lista(text);

CREATE FUNCTION public.apartados_lista(p_store text)
RETURNS TABLE (id bigint, sku text, cliente text, telefono text,
               piezas integer, con_seguro boolean, estatus text,
               vendedor text, creado_en timestamptz,
               color text, precio numeric, transaccion text,
               serie text, asignado_en timestamptz, entregado_en timestamptz,
               entregado_por text, venta_id bigint,
               cupo integer, apartadas integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.sku, a.cliente, a.telefono, a.piezas, a.con_seguro,
         a.estatus, a.vendedor, a.creado_en,
         a.color, a.precio, a.transaccion,
         a.serie, a.asignado_en, a.entregado_en, a.entregado_por, a.venta_id,
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


-- ── 9 · Permisos ────────────────────────────────────────────
-- escritura_ok_ NO se expone: es la guardia, no una funcion de la app.
REVOKE ALL ON FUNCTION public.escritura_ok_(text,text) FROM public, anon, authenticated;

REVOKE ALL ON FUNCTION public.apartados_lista(text)                        FROM public;
REVOKE ALL ON FUNCTION public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text) FROM public;
REVOKE ALL ON FUNCTION public.apartado_serie(text,text,bigint,text)        FROM public;
REVOKE ALL ON FUNCTION public.apartado_entregar(text,text,bigint,text,text) FROM public;
REVOKE ALL ON FUNCTION public.apartado_estatus(text,text,bigint,text)      FROM public;

GRANT EXECUTE ON FUNCTION public.apartados_lista(text)                        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_serie(text,text,bigint,text)        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_entregar(text,text,bigint,text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_estatus(text,text,bigint,text)      TO anon, authenticated;


-- ── 10 · Que resincronizar deje de pisar los apartados ──────
-- ESTE PASO NO ES OPCIONAL y es el que menos se ve venir.
--
-- `cargar_apartados_comisiones` —que corre dentro de `resincronizar()`— hace
-- DELETE FROM apartados y los reinserta desde la hoja. Tenía sentido cuando la
-- hoja era la verdad. A partir de ahora es al revés: correr `resincronizar()`
-- borraría TODAS las series asignadas, las entregas y los apartados nuevos, y
-- los sustituiría por la foto de una hoja que ya nadie escribe.
--
-- No avisaría de nada. `resincronizar` diría "los seis pasos en verde" y el
-- tablero mostraría los apartados sin serie, como si el embarque no hubiera
-- llegado.
--
-- Se queda cargando solo comisiones. El nombre se conserva porque
-- `resincronizar()` la llama por nombre; se limpia en la etapa 5.
CREATE OR REPLACE FUNCTION public.cargar_apartados_comisiones(p_store text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE d jsonb; c int;
BEGIN
  -- Los apartados YA NO se traen de la hoja: desde el 7-ago-2026 esta tabla es
  -- la fuente, no la copia. Ver supabase_preventa_series.sql, paso 10.
  SELECT r.content::jsonb INTO d
  FROM public.tiendas t,
       LATERAL extensions.http_get(t.gas_url || '?modo=exportar&hoja=Comisiones&t=' || t.gas_token) r
  WHERE t.store_id = p_store;
  IF d IS NULL OR d ? 'error' THEN RETURN 'la nube no devolvio comisiones'; END IF;

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

  RETURN 'apartados=(ya no se cargan: viven aqui) comisiones=' || c;
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERROR ' || SQLSTATE || ': ' || left(regexp_replace(SQLERRM,'https?://[^ ]+','<url>','g'), 170);
END $function$;


-- ============================================================
--  COMPROBAR ANTES DE CONECTAR LAS APPS
--  (pegar de a poco; el bloque de arriba ya quedo aplicado)
-- ============================================================
--
--  0) Que la lectura traiga los campos nuevos y no haya perdido los viejos:
--       select id, cliente, transaccion, serie, estatus
--         from public.apartados_lista('1217') limit 3;
--     -> transaccion NO puede venir vacia. Si viene, se piso la funcion buena.
--
--  1) Sin token no se escribe:
--       select public.apartado_serie('1217','', 38, 'PRUEBA-1');
--     -> {"ok": false, "error": "no_autorizado"}
--
--  2) Con token (sacarlo de: select gas_token from tiendas where store_id='1217')
--       select public.apartado_serie('1217','<TOKEN>', 38, 'PRUEBA-1');
--     -> {"ok": true, ..., "estatus": "Asignado"}
--
--  3) La misma serie otra vez en el MISMO apartado: repetida, no error
--       select public.apartado_serie('1217','<TOKEN>', 38, 'PRUEBA-1');
--     -> {"ok": true, ..., "repetida": true}
--
--  4) La misma serie en OTRO apartado: tiene que negarse
--       select public.apartado_serie('1217','<TOKEN>', 37, 'PRUEBA-1');
--     -> {"ok": false, "error": "esa serie ya es de Jesus manuel"}
--
--  5) Entregar con una serie que no es la suya: tiene que negarse
--       select public.apartado_entregar('1217','<TOKEN>', 38, 'OTRA-COSA');
--     -> {"ok": false, "error": "esa no es su pieza: tiene asignada la PRUEBA-1"}
--
--  6) Entregar bien -> crea la venta con el vendedor del apartado
--       select public.apartado_entregar('1217','<TOKEN>', 38, 'PRUEBA-1');
--       select serie, sku, vendedor, con_seguro, dia_venta, descripcion
--         from public.ventas where serie = 'PRUEBA-1';
--     -> vendedor 'Maria' (el de la preventa), NO quien entrego
--
--  7) Entregar otra vez: NO puede crear una segunda venta
--       select public.apartado_entregar('1217','<TOKEN>', 38, 'PRUEBA-1');
--     -> {"ok": true, ..., "ya_entregado": true}
--       select count(*) from public.ventas where serie = 'PRUEBA-1';   -- 1
--
--  8) Deshacer la prueba:
--       delete from public.ventas where serie = 'PRUEBA-1';
--       update public.apartados
--          set estatus='Apartado', serie=NULL, asignado_en=NULL,
--              entregado_en=NULL, venta_id=NULL
--        where id = 38;
-- ============================================================

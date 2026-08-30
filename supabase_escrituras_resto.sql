-- ============================================================
--  ESCRITURAS QUE FALTABAN — EOL, avisos, combos y borrar venta
--  Etapa 2 de "apagar la hoja"
--  7-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql: usa su guardia `escritura_ok_`.
--  Correr ESE primero.
--
--  ------------------------------------------------------------
--  LO QUE ESTE ARCHIVO ARREGLA, Y NO ES UNA MEJORA: ES UNA FUGA
--  ------------------------------------------------------------
--  Borrar una captura en Captura de Series avisa al Apps Script
--  (`gasEnviar({tipo:'eliminar'})`, captura_series.html l. 806) y **no le dice
--  nada a Supabase**. La venta desaparece de la hoja y se queda en la tabla.
--
--  Eso importa porque desde la fase 2 el tablero lee `inventario_vivo`, que
--  descuenta lo vendido de la tabla `ventas` DE SUPABASE. Una venta borrada en
--  la hoja sigue descontando pieza en el tablero: **el tablero muestra menos
--  stock del que hay en bodega**, para siempre, en ese SKU. Nadie recibe un
--  error; solo se ve un producto agotado que sí está.
--
--  Es el reverso exacto del incidente del 4-ago —cuando el tablero mostraba una
--  pieza de MÁS por cada venta del día— y por la misma causa de fondo: leer de
--  un lado lo que se escribe en el otro. La doble escritura cerró el alta; el
--  borrado se quedó fuera.
--
--  Para poder borrar hace falta saber QUÉ fila borrar, y ahí estaba el hueco:
--  la app identifica cada captura con su `id` propio ('i' + timestamp) y la
--  tabla `ventas` no lo guardaba. Por eso el paso 1 es una columna nueva.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
-- ============================================================


-- ── 1 · El enlace entre la captura y la fila ────────────────
-- `captura_id` es el id que genera Captura de Series. Es lo único que permite
-- volver a encontrar la venta para borrarla: la serie no basta —una devolución
-- puede repetirla otro día— y la fecha tampoco.
ALTER TABLE public.ventas
  ADD COLUMN IF NOT EXISTS captura_id text;

-- Parcial: las ventas históricas cargadas de la hoja no traen captura_id y no
-- deben chocar entre sí por ser todas NULL.
CREATE UNIQUE INDEX IF NOT EXISTS ventas_captura_unica
  ON public.ventas (store_id, captura_id)
  WHERE captura_id IS NOT NULL;


-- ── 2 · venta_guardar, ahora con captura_id ─────────────────
-- El parámetro va AL FINAL y con DEFAULT: PostgREST resuelve por nombre, así
-- que una app vieja que no lo mande sigue funcionando igual. Sin esa
-- precaución, publicar esto rompería la captura de todos los celulares que aún
-- no se hayan actualizado.
--
-- ⚠️ EL DROP DE ABAJO NO ES OPCIONAL, y esto se aprendió rompiéndolo.
--
-- `CREATE OR REPLACE` solo reemplaza si la lista de parámetros es IDÉNTICA. Al
-- agregar uno, Postgres no sustituye: crea una SEGUNDA función con el mismo
-- nombre. Y entonces PostgREST recibe una llamada de diez parámetros, ve dos
-- candidatas y responde PGRST203 «could not choose the best candidate» — o sea
-- que la captura deja de guardar en Supabase para TODOS los celulares que aún
-- no se actualizaron, que son justo los que este DEFAULT venía a proteger.
--
-- Pasó de verdad el 7-ago-2026, entre que se aplicó este archivo y que se
-- comprobó. Las ventas no se perdieron —la cola de Captura de Series las
-- retuvo y las reintentó— pero durante ese rato el inventario de Supabase se
-- quedó atrás, que es lo que infla el stock del tablero.
--
-- Regla: si cambia la firma, DROP explícito de la firma vieja. Siempre.
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text);

CREATE OR REPLACE FUNCTION public.venta_guardar(
  p_store      text,
  p_serie      text,
  p_sku        text    DEFAULT NULL,
  p_desc       text    DEFAULT NULL,
  p_precio     numeric DEFAULT NULL,
  p_vendedor   text    DEFAULT NULL,
  p_seguro     boolean DEFAULT NULL,
  p_fecha      text    DEFAULT NULL,   -- '4/8/2026'  (d/M/yyyy, como la hoja)
  p_hora       text    DEFAULT NULL,   -- '01:26 p.m.'
  p_foto_url   text    DEFAULT NULL,
  p_captura_id text    DEFAULT NULL    -- el id de la app, para poder borrarla
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cuando timestamptz;
  v_d int; v_m int; v_a int; v_h int := 12; v_min int := 0;
  m text[];
  nuevo bigint;
BEGIN
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  -- fecha: d/M/yyyy. Sin fecha reconocible se usa ahora, que es mejor que
  -- rechazar la venta: el dato existe y ya está en el Sheet.
  m := regexp_match(coalesce(p_fecha,''), '^(\d{1,2})/(\d{1,2})/(\d{4})$');
  IF m IS NULL THEN
    v_cuando := now();
  ELSE
    v_d := m[1]::int; v_m := m[2]::int; v_a := m[3]::int;
    -- hora: '1:26 p.m.' / '13:26'. Sin hora usable, mediodía: no se pasa de día
    -- en ninguna zona.
    m := regexp_match(lower(coalesce(p_hora,'')), '(\d{1,2}):(\d{2})\s*([ap])?');
    IF m IS NOT NULL THEN
      v_h := m[1]::int; v_min := m[2]::int;
      IF m[3] = 'p' AND v_h < 12 THEN v_h := v_h + 12; END IF;
      IF m[3] = 'a' AND v_h = 12 THEN v_h := 0; END IF;
    END IF;
    v_cuando := (format('%s-%s-%s %s:%s', v_a, lpad(v_m::text,2,'0'), lpad(v_d::text,2,'0'),
                        lpad(v_h::text,2,'0'), lpad(v_min::text,2,'0'))::timestamp)
                AT TIME ZONE 'America/Mexico_City';
  END IF;

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro,
     foto_url, captura_id)
  VALUES
    (p_store, v_cuando, trim(p_serie), nullif(trim(coalesce(p_sku,'')),''),
     nullif(trim(coalesce(p_desc,'')),''), p_precio,
     nullif(trim(coalesce(p_vendedor,'')),''), p_seguro,
     nullif(trim(coalesce(p_foto_url,'')),''),
     nullif(trim(coalesce(p_captura_id,'')),''))
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);

EXCEPTION
  WHEN unique_violation THEN
    -- ya estaba: reintento de red, no un problema
    RETURN jsonb_build_object('ok', true, 'duplicada', true);
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

GRANT EXECUTE ON FUNCTION
  public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text)
  TO anon, authenticated;


-- ── 3 · Borrar una venta  ←  reemplaza tipo:'eliminar' ──────
-- Borra de verdad, no marca. Es lo mismo que hace la hoja al quitar la fila, y
-- el inventario tiene que volver a contar esa pieza como disponible.
CREATE OR REPLACE FUNCTION public.venta_eliminar(
  p_store      text,
  p_token      text,
  p_captura_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_captura_id),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin id');
  END IF;

  -- Una venta ligada a un apartado entregado NO se borra por aquí: el equipo
  -- salió de la tienda y el apartado seguiría apuntando a una fila que ya no
  -- existe. Se cancela desde la preventa, que sabe deshacer las dos cosas.
  IF EXISTS (SELECT 1 FROM public.apartados a
              JOIN public.ventas v ON v.id = a.venta_id
             WHERE v.store_id = p_store AND v.captura_id = trim(p_captura_id)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa venta es la entrega de un apartado: deshazla desde Preventa');
  END IF;

  DELETE FROM public.ventas
   WHERE store_id = p_store AND captura_id = trim(p_captura_id);
  GET DIAGNOSTICS n = ROW_COUNT;

  -- Cero borradas NO es un error: la captura pudo no haber llegado nunca
  -- (quedó en la cola y se borró antes de subir). Se responde ok y se dice
  -- cuántas, para que la app no invente un fallo que no existe.
  RETURN jsonb_build_object('ok', true, 'borradas', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 4 · EOL  ←  reemplaza eol_add / eol_del ─────────────────
-- La hoja guarda una tercera columna 'si'/'no' que la lectura usa para filtrar;
-- aquí eso es `pausado`, al revés. 'si' (activo) = pausado false.
--
-- Si no llega precio, se busca en el catálogo: es lo que hace `agregarEol_` en
-- el Apps Script recorriendo la hoja Catalogo. Sin esa búsqueda, el EOL entra
-- con precio vacío y `eol_precio_venta` no puede calcular el 50 % — o sea, el
-- producto aparece marcado pero sin precio de venta, que es peor que no estar.
CREATE OR REPLACE FUNCTION public.eol_guardar(
  p_store  text,
  p_token  text,
  p_sku    text,
  p_precio numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE v_precio numeric;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_sku),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin sku');
  END IF;

  -- Ya estaba: se responde `existe` y NO se toca. Es lo que hace `agregarEol_`
  -- en el Apps Script, y Admin lo muestra como "Ya existe este SKU". Cambiarlo
  -- por un upsert silencioso pisaría el precio que alguien puso a mano sin que
  -- se viera, y el precio del EOL es lo que decide cuánto se cobra en piso.
  IF EXISTS (SELECT 1 FROM public.eol e
              WHERE e.store_id = p_store AND e.sku = trim(p_sku)) THEN
    RETURN jsonb_build_object('ok', true, 'existe', true, 'sku', trim(p_sku));
  END IF;

  v_precio := p_precio;
  IF v_precio IS NULL THEN
    SELECT c.precio INTO v_precio FROM public.catalogo c
     WHERE c.store_id = p_store AND c.sku = trim(p_sku);
  END IF;

  INSERT INTO public.eol (store_id, sku, precio, pausado)
  VALUES (p_store, trim(p_sku), v_precio, false);

  RETURN jsonb_build_object('ok', true, 'sku', trim(p_sku), 'precio', v_precio);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

CREATE OR REPLACE FUNCTION public.eol_eliminar(
  p_store text,
  p_token text,
  p_sku   text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  DELETE FROM public.eol WHERE store_id = p_store AND sku = trim(coalesce(p_sku,''));
  GET DIAGNOSTICS n = ROW_COUNT;
  -- Igual que en la hoja: quitar algo que no estaba no es un fallo.
  RETURN jsonb_build_object('ok', true, 'borradas', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 5 · Avisos  ←  reemplaza aviso_add / aviso_del ──────────
-- Sin fecha de fin, siete días: es lo que hace `guardarAviso_`. Un aviso sin
-- caducidad se queda en la pantalla de todos hasta que alguien se acuerda de
-- borrarlo, y nadie se acuerda.
--
-- LA COLUMNA `tipo` FALTABA, y no es cosmética: el tablero la pinta como
-- etiqueta azul (cardAviso, tablero.html l. 1354) para distinguir un CEA/LEA
-- oficial de un recado interno. La hoja la guardaba (columna 7) y
-- `leerAvisos_` la devolvía; el esquema de Supabase se quedó sin ella.
--
-- O sea que esto ya estaba roto ANTES de esta etapa: desde que las lecturas se
-- movieron a Supabase (fase 2), `_deSupabase` no tenía de dónde sacarla y
-- ponía 'manual' fijo. Los avisos oficiales llevan desde entonces sin su
-- etiqueta. Nadie lo reportó porque un aviso sin distintivo se sigue leyendo
-- igual — solo pierde la señal de que viene de corporativo.
ALTER TABLE public.avisos
  ADD COLUMN IF NOT EXISTS tipo text NOT NULL DEFAULT 'manual';

-- La lectura tiene que devolverla, o la columna nueva no llega a nadie.
DROP FUNCTION IF EXISTS public.avisos_vigentes(text);

CREATE FUNCTION public.avisos_vigentes(p_store text)
RETURNS TABLE (id bigint, titulo text, detalle text, prioridad text,
               vigente_hasta date, creado_en timestamptz, tipo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.titulo, a.detalle, a.prioridad, a.vigente_hasta, a.creado_en, a.tipo
  FROM public.avisos a
  WHERE a.store_id = p_store
    AND (a.vigente_hasta IS NULL
         OR a.vigente_hasta >= (now() AT TIME ZONE 'America/Mexico_City')::date)
  ORDER BY a.creado_en DESC;
$$;

REVOKE ALL ON FUNCTION public.avisos_vigentes(text) FROM public;
GRANT EXECUTE ON FUNCTION public.avisos_vigentes(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.aviso_guardar(
  p_store     text,
  p_token     text,
  p_titulo    text,
  p_detalle   text DEFAULT NULL,
  p_prioridad text DEFAULT 'normal',
  p_hasta     date DEFAULT NULL,
  p_tipo      text DEFAULT 'manual'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE nuevo bigint;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_titulo),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin titulo');
  END IF;

  INSERT INTO public.avisos (store_id, titulo, detalle, prioridad, vigente_hasta, tipo)
  VALUES (p_store, trim(p_titulo), nullif(trim(coalesce(p_detalle,'')),''),
          coalesce(nullif(trim(coalesce(p_prioridad,'')),''), 'normal'),
          coalesce(p_hasta, ((now() AT TIME ZONE 'America/Mexico_City')::date + 7)),
          coalesce(nullif(trim(coalesce(p_tipo,'')),''), 'manual'))
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

CREATE OR REPLACE FUNCTION public.aviso_eliminar(
  p_store text,
  p_token text,
  p_id    bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  DELETE FROM public.avisos WHERE store_id = p_store AND id = p_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no encontrado');
  END IF;
  RETURN jsonb_build_object('ok', true);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 6 · Combos  ←  bundle_add / bundle_del / bundle_clear ───
-- Los combos están retirados de la vista desde julio (ver MAPA, l. 440), pero
-- las escrituras se reponen igual: si se retiran del plan, el día que vuelvan
-- habrá que reconstruirlas con el Apps Script ya apagado, y ahí ya no habrá de
-- dónde copiar la lógica.
--
-- `skus` es un array de verdad en Supabase y "a,b,c" en la hoja. La conversión
-- se hace AQUÍ y no en el cliente, para que solo exista en un sitio.
CREATE OR REPLACE FUNCTION public.bundle_guardar(
  p_store  text,
  p_token  text,
  p_nombre text,
  p_skus   text,            -- "a,b,c" como lo manda admin.html
  p_precio numeric,
  p_desde  date DEFAULT NULL,
  p_hasta  date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE nuevo bigint; v_skus text[];
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_nombre),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin nombre');
  END IF;

  SELECT array_agg(s) INTO v_skus
    FROM (SELECT trim(x) AS s
            FROM unnest(string_to_array(coalesce(p_skus,''), ',')) x
           WHERE trim(x) <> '') t;
  IF v_skus IS NULL OR array_length(v_skus,1) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin skus');
  END IF;

  INSERT INTO public.bundles (store_id, nombre, skus, precio, vigente_desde, vigente_hasta, activo)
  VALUES (p_store, trim(p_nombre), v_skus, p_precio, p_desde,
          -- vigente_hasta es NOT NULL en el esquema; sin fecha, 30 días
          coalesce(p_hasta, ((now() AT TIME ZONE 'America/Mexico_City')::date + 30)), true)
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

CREATE OR REPLACE FUNCTION public.bundle_eliminar(
  p_store text,
  p_token text,
  p_id    bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  DELETE FROM public.bundles WHERE store_id = p_store AND id = p_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('ok', n > 0, 'borradas', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

CREATE OR REPLACE FUNCTION public.bundle_limpiar(
  p_store text,
  p_token text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  DELETE FROM public.bundles WHERE store_id = p_store;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'borradas', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 7 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.venta_eliminar(text,text,text)                   FROM public;
REVOKE ALL ON FUNCTION public.eol_guardar(text,text,text,numeric)              FROM public;
REVOKE ALL ON FUNCTION public.eol_eliminar(text,text,text)                     FROM public;
REVOKE ALL ON FUNCTION public.aviso_guardar(text,text,text,text,text,date,text) FROM public;
REVOKE ALL ON FUNCTION public.aviso_eliminar(text,text,bigint)                 FROM public;
REVOKE ALL ON FUNCTION public.bundle_guardar(text,text,text,text,numeric,date,date) FROM public;
REVOKE ALL ON FUNCTION public.bundle_eliminar(text,text,bigint)                FROM public;
REVOKE ALL ON FUNCTION public.bundle_limpiar(text,text)                        FROM public;

GRANT EXECUTE ON FUNCTION public.venta_eliminar(text,text,text)                   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eol_guardar(text,text,text,numeric)              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eol_eliminar(text,text,text)                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aviso_guardar(text,text,text,text,text,date,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aviso_eliminar(text,text,bigint)                 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bundle_guardar(text,text,text,text,numeric,date,date) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bundle_eliminar(text,text,bigint)                TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bundle_limpiar(text,text)                        TO anon, authenticated;


-- ============================================================
--  COMPROBAR ANTES DE CONECTAR LAS APPS
-- ============================================================
--
--  Token:  select gas_token from public.tiendas where store_id='1217';
--
--  1) La columna nueva no rompió la captura. Una venta SIN captura_id, como
--     las que manda la app vieja, tiene que seguir entrando:
--       select public.venta_guardar('1217','PRUEBA-E2-1','100304280','prueba',
--                                   999,'prueba',true,null,null);
--     -> {"ok": true, "id": ...}
--
--  2) Y una CON captura_id:
--       select public.venta_guardar('1217','PRUEBA-E2-2','100304280','prueba',
--                                   999,'prueba',true,null,null,null,'iPRUEBA1');
--     -> {"ok": true, "id": ...}
--
--  3) Borrarla por su id de captura:
--       select public.venta_eliminar('1217','<TOKEN>','iPRUEBA1');
--     -> {"ok": true, "borradas": 1}
--
--  4) Borrar algo que no existe NO es un error (la captura pudo no haber
--     subido nunca):
--       select public.venta_eliminar('1217','<TOKEN>','iNOEXISTE');
--     -> {"ok": true, "borradas": 0}
--
--  5) Sin token no se borra nada:
--       select public.venta_eliminar('1217','','iPRUEBA1');
--     -> {"ok": false, "error": "no_autorizado"}
--
--  6) EOL sin precio lo saca del catálogo:
--       select public.eol_guardar('1217','<TOKEN>','100304280');
--     -> "precio" NO puede venir null si ese SKU tiene precio en catalogo
--       select public.eol_eliminar('1217','<TOKEN>','100304280');
--
--  7) Limpiar las pruebas:
--       delete from public.ventas where serie like 'PRUEBA-E2-%';
-- ============================================================

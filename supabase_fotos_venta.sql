-- ============================================================
--  FOTOS DE VENTA — de Google Drive a la base
--  Etapa 4 de "apagar la hoja"
--  7-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql (guardia `escritura_ok_`).
--
--  ------------------------------------------------------------
--  POR QUÉ ESTO NO ES SOLO "MOVER LAS FOTOS DE SITIO"
--  ------------------------------------------------------------
--  Antes de tocar nada se miró quién las usa, y la respuesta fue: NADIE. Ninguna
--  pantalla las muestra —`ventas_detalle` ni siquiera devolvía el campo— y la
--  única forma de ver una era abrir la hoja de cálculo y pinchar el enlace de
--  Drive. Encima `venta_guardar` aceptaba `p_foto_url` y el cliente nunca se lo
--  mandaba: las ventas que ya están en Supabase no tienen foto ninguna.
--
--  O sea que se estaban sacando, comprimiendo y subiendo fotos que se borraban
--  a los 7 días sin que nadie las hubiera visto.
--
--  Para lo que sirven —confirmado con Ángel el 7-ago— es para **verificar una
--  serie dudosa**: cuando un número no cuadra o hay un reclamo, poder mirar la
--  foto de esa caja. Así que además de guardarlas hay que poder ABRIRLAS desde
--  el panel de Ventas del día. Guardarlas mejor y que siguieran sin verse habría
--  sido trabajo para nada.
--
--  ------------------------------------------------------------
--  POR QUÉ EN LA BASE Y NO EN STORAGE
--  ------------------------------------------------------------
--  Storage es lo canónico para archivos, pero subir desde el celular obliga a
--  abrir el bucket a la anon key, que está en el HTML y es pública: cualquiera
--  que la lea podría subir archivos hasta llenarlo. Cerrar eso bien pide una
--  Edge Function, que es justo lo que se dejó para el final.
--
--  Aquí la foto entra por una RPC con el MISMO token de tienda que protege todo
--  lo demás. Sobre el tamaño: a ~10 ventas al día y ~150 KB por foto, los 31
--  días de retención salen a unos 46 MB. Con 7 días eran 10 MB.
--
--  RETENCIÓN: 31 DÍAS (24-ago-2026). Eran 7, y 7 es lo que dura una serie
--  dudosa: se reclama en caliente o no se reclama. Pero la misma tabla guarda
--  desde el 18-ago los tickets de accesorio y ahora los de reparación, que son
--  la evidencia de un CORTE MENSUAL, y con 7 días los de la primera semana ya
--  no existían al cotejarlo. Una evidencia que caduca antes de que llegue el
--  momento de usarla no es evidencia.
--
--  ⚠️ 31 días cubren el mes EN CURSO, no el anterior. Un ticket del 1 de mes
--  mirado el 10 del siguiente ya no está. Es una decisión tomada —el cotejo se
--  hace dentro del mes—, no un descuido: si algún día hay que revisar un mes
--  cerrado, esto es lo primero que hay que subir.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
-- ============================================================


-- ── 1 · La tabla ────────────────────────────────────────────
-- Aparte de `ventas` a propósito: esa tabla se consulta en cada carga del
-- tablero, y arrastrar un bytea de 150 KB por fila en cada `SELECT *` la
-- volvería lenta para todos. Aquí la foto solo se toca cuando alguien la pide.
--
-- Se liga por `captura_id`, el id que genera Captura de Series, y NO por el id
-- de la venta: la foto se sube en el mismo momento que la venta y no hay forma
-- de saber el id que le tocó sin una segunda consulta.
CREATE TABLE IF NOT EXISTS public.venta_fotos (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  captura_id text        NOT NULL,
  imagen     bytea       NOT NULL,
  mime       text        NOT NULL DEFAULT 'image/jpeg',
  bytes      integer     NOT NULL,
  creada_en  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, captura_id)
);

ALTER TABLE public.venta_fotos ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS venta_fotos_edad ON public.venta_fotos (store_id, creada_en);

COMMENT ON TABLE public.venta_fotos IS
  'Fotos de captura, 7 dias de retencion. Sirven para verificar una serie '
  'dudosa. Se borran solas: cada guardado limpia las viejas.';


-- ── 2 · Guardar  ←  reemplaza guardarFoto_ (Drive) ──────────
-- La imagen llega en base64 SIN el prefijo `data:image/jpeg;base64,`. El cliente
-- lo quita antes: mandarlo entero haría que `decode` guardara basura al
-- principio del JPEG y la foto no abriría — y eso solo se descubre el día que
-- alguien intenta mirarla, que es justo el día que importa.
CREATE OR REPLACE FUNCTION public.venta_foto_guardar(
  p_store      text,
  p_token      text,
  p_captura_id text,
  p_imagen_b64 text,
  p_mime       text DEFAULT 'image/jpeg'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE datos bytea; n int; viejas int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_captura_id),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin id de captura');
  END IF;
  IF coalesce(p_imagen_b64,'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin imagen');
  END IF;

  BEGIN
    datos := decode(p_imagen_b64, 'base64');
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'la imagen no es base64 valido');
  END;

  n := octet_length(datos);
  -- Tope de 1,5 MB. El cliente comprime a ~150 KB, así que esto no estorba a una
  -- foto normal: está para que la anon key no pueda usarse para llenar la base
  -- subiendo archivos grandes.
  IF n > 1572864 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'la imagen pesa mas de 1.5 MB');
  END IF;

  INSERT INTO public.venta_fotos (store_id, captura_id, imagen, mime, bytes)
  VALUES (p_store, trim(p_captura_id), datos,
          coalesce(nullif(trim(p_mime),''), 'image/jpeg'), n)
  ON CONFLICT (store_id, captura_id) DO UPDATE
    SET imagen = excluded.imagen, mime = excluded.mime,
        bytes = excluded.bytes, creada_en = now();

  -- Limpieza oportunista: las de más de 7 días se van con cada foto nueva.
  -- Se hace aquí y no con un cron a propósito: un trabajo programado es una
  -- pieza más que puede estar apagada sin que nadie lo note, y esto se ejecuta
  -- justo cuando hay algo que limpiar. Si un día dejan de subirse fotos, las
  -- últimas se quedan — 10 MB parados, que no molestan a nadie.
  DELETE FROM public.venta_fotos
   WHERE store_id = p_store AND creada_en < now() - interval '31 days';
  GET DIAGNOSTICS viejas = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'bytes', n, 'borradas', viejas);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 3 · Leer  ←  lo que hoy NO existe ───────────────────────
-- Devuelve la foto en base64 para pintarla en un <img>. Pide token: una foto de
-- captura puede tener a la vista el ticket o la caja de un cliente.
CREATE OR REPLACE FUNCTION public.venta_foto_leer(
  p_store      text,
  p_token      text,
  p_captura_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE f public.venta_fotos%ROWTYPE;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;

  SELECT * INTO f FROM public.venta_fotos
   WHERE store_id = p_store AND captura_id = trim(coalesce(p_captura_id,''));
  IF NOT FOUND THEN
    -- No es un error: puede ser una venta capturada sin foto, o una de hace más
    -- de 7 días. La app lo dice con esas palabras en vez de "fallo al cargar".
    RETURN jsonb_build_object('ok', false, 'error', 'sin foto');
  END IF;

  RETURN jsonb_build_object('ok', true, 'mime', f.mime,
                            'b64', encode(f.imagen, 'base64'),
                            'creada_en', f.creada_en);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 4 · Ventas del día, ahora diciendo si hay foto ──────────
-- Sin esto el panel no sabe en qué venta pintar el botón de la lupa, y habría
-- que pedir la foto de todas para averiguarlo.
--
-- Se devuelve `captura_id` además: es la llave con la que se pide la foto.
DROP FUNCTION IF EXISTS public.ventas_detalle(text, date);

CREATE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL)
RETURNS TABLE (serie text, sku text, descripcion text, precio numeric,
               vendedor text, con_seguro boolean, vendida_en timestamptz,
               captura_id text, tiene_foto boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.serie, v.sku, v.descripcion, v.precio, v.vendedor, v.con_seguro,
         v.vendida_en, v.captura_id,
         EXISTS (SELECT 1 FROM public.venta_fotos f
                  WHERE f.store_id = v.store_id AND f.captura_id = v.captura_id)
  FROM public.ventas v
  WHERE v.store_id = p_store
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
        = coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date)
  ORDER BY v.vendida_en;
$$;


-- ── 5 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.venta_foto_guardar(text,text,text,text,text) FROM public;
REVOKE ALL ON FUNCTION public.venta_foto_leer(text,text,text)              FROM public;
REVOKE ALL ON FUNCTION public.ventas_detalle(text,date)                    FROM public;

GRANT EXECUTE ON FUNCTION public.venta_foto_guardar(text,text,text,text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.venta_foto_leer(text,text,text)              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ventas_detalle(text,date)                    TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--  Token:  select gas_token from public.tiendas where store_id='1217';
--
--  1) Sin token no se guarda ni se lee:
--       select public.venta_foto_guardar('1217','','iX','AAAA');
--       select public.venta_foto_leer('1217','','iX');
--     -> las dos: no_autorizado
--
--  2) Guardar y leer una de prueba (un GIF de 1x1 en base64):
--       select public.venta_foto_guardar('1217','<TOKEN>','iPRUEBAFOTO',
--         'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7','image/gif');
--     -> {"ok": true, "bytes": 43, ...}
--       select public.venta_foto_leer('1217','<TOKEN>','iPRUEBAFOTO');
--     -> ok:true y el mismo b64 que se mandó
--
--  3) Una imagen que no es base64 se rechaza con un mensaje legible:
--       select public.venta_foto_guardar('1217','<TOKEN>','iX','no soy base64 %%%');
--     -> {"ok": false, "error": "la imagen no es base64 valido"}
--
--  4) ventas_detalle trae los campos nuevos SIN perder los viejos:
--       select serie, vendedor, captura_id, tiene_foto
--         from public.ventas_detalle('1217') limit 5;
--     -> `serie` y `vendedor` NO pueden venir vacíos
--
--  5) Limpiar la prueba:
--       delete from public.venta_fotos where captura_id = 'iPRUEBAFOTO';
-- ============================================================

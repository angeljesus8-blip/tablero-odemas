-- ============================================================
--  CAMBIO DE PRECIO DE LISTA — un CEA que baja (o sube) el precio
--  REGULAR, que no es una promoción
--  26-sep-2026
-- ============================================================
--
--  El caso: CEA HUAWEI 273 BAJA DE PRECIO EN MATEPAD (15-sep-2026). Siete
--  MatePad cambian de precio regular «a partir del 15 de septiembre», sin
--  fecha de fin, porque es permanente. Pero el catálogo sale del Informe de
--  Artículos Totales de Sonar, y Sonar tarda en traer el precio nuevo.
--
--  La única puerta que había era Promos, y por ahí entró: como promoción del
--  20 al 30 de septiembre —una fecha de fin inventada, porque Promos la
--  exige—. El 1 de octubre la «promo» se vencía y la app volvía a cobrar
--  $6,999 donde el precio real es $4,999. Y el equipo lo veía tachado, como
--  oferta, cuando no lo es.
--
--  ------------------------------------------------------------
--  CÓMO FUNCIONA: el precio nuevo va AL CATÁLOGO, y Sonar no lo pisa
--  ------------------------------------------------------------
--  El precio del catálogo lo leen muchos: el inventario del tablero, la mitad
--  del EOL, la lista de Captura, el guardado de la venta. Cambiar cada lectura
--  era dejar alguna vieja. Así que no se toca ninguna: se cambia el DATO.
--
--  Un trigger en `catalogo` mira cada escritura. Si el SKU tiene un cambio de
--  lista vigente (desde ≤ hoy, hora de México) y lo que llega es el precio
--  ANTERIOR —o nada—, se guarda el NUEVO. Así la carga diaria de Sonar, que
--  todavía trae el precio viejo, no lo regresa.
--
--  Y se retira solo: en cuanto Sonar trae OTRO precio —el nuevo, o uno
--  distinto de los dos—, manda Sonar. No hay que acordarse de quitarlo, y si
--  la cadena corrige el precio otra vez, gana lo que diga el informe.
--
--  El trigger cubre a TODOS los que escriben en `catalogo`, los de hoy y los
--  que se agreguen: no depende de que cada función de carga se acuerde.
--
--  ------------------------------------------------------------
--  LAS PROMOS QUE ERAN ESTE MISMO CEA
--  ------------------------------------------------------------
--  Al registrar un cambio se quitan las promociones que son exactamente ese
--  CEA subido por la puerta equivocada: mismo SKU, precio regular = el anterior
--  y precio de promoción = el nuevo. Una promo con cualquier otra cifra no se
--  toca: es otra cosa, y decidir sobre ella no le toca a esta función.
--
--  Depende de supabase_preventa_series.sql (guardia `escritura_ok_`).
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · La tabla ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.precio_lista (
  store_id        text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku             text        NOT NULL,
  producto        text        NOT NULL DEFAULT '',
  precio_anterior numeric(12,2),
  precio_nuevo    numeric(12,2) NOT NULL CHECK (precio_nuevo > 0),
  desde           date        NOT NULL,
  cea             text,
  msi             text,
  subido_por      text,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, sku)
);
-- Sin políticas: nadie la lee ni la escribe directo. Entra por la función de
-- abajo y actúa por el trigger.
ALTER TABLE public.precio_lista ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.precio_lista FROM anon, authenticated;


-- ── 2 · El trigger: Sonar no regresa el precio viejo ─────────
-- «Hoy» en México, no en UTC: de 6 p. m. a medianoche UTC ya es mañana, y un
-- cambio «a partir del 15» se aplicaría el 14 por la tarde.
CREATE OR REPLACE FUNCTION public.catalogo_precio_lista_()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE pl public.precio_lista%ROWTYPE;
BEGIN
  SELECT * INTO pl FROM public.precio_lista
   WHERE store_id = NEW.store_id AND sku = NEW.sku
     AND desde <= (now() AT TIME ZONE 'America/Mexico_City')::date;
  IF FOUND AND (NEW.precio IS NULL OR NEW.precio = pl.precio_anterior) THEN
    NEW.precio := pl.precio_nuevo;
  END IF;
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS catalogo_precio_lista ON public.catalogo;
CREATE TRIGGER catalogo_precio_lista
  BEFORE INSERT OR UPDATE OF precio ON public.catalogo
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_precio_lista_();


-- ── 3 · Registrar un cambio de precio de lista ──────────────
-- p_filas: [{sku, desc, pa, pn, d1, msi}] — pa = precio regular anterior,
-- pn = precio regular nuevo, d1 = desde (AAAA-MM-DD). p_cea = "CEA 273".
--
-- Devuelve cuántos se guardaron, cuántos ya se aplicaron al catálogo, cuántos
-- no están en el catálogo (se aplicarán cuando Sonar los traiga) y cuántas
-- promos-espejo se quitaron. Las filas malas se APARTAN y se cuentan, igual
-- que en carga_promos.
CREATE OR REPLACE FUNCTION public.carga_precio_lista(
  p_store text,
  p_token text,
  p_filas jsonb,
  p_by    text DEFAULT NULL,
  p_cea   text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int; sin_fecha int; sin_precio int; aplicados int; sin_cat int; espejo int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin filas');
  END IF;

  CREATE TEMP TABLE _pl ON COMMIT DROP AS
  SELECT DISTINCT ON (sku) * FROM (
    SELECT trim(x->>'sku') AS sku,
           coalesce(x->>'desc','') AS producto,
           nullif(regexp_replace(coalesce(x->>'pa',''),'[^0-9.]','','g'),'')::numeric AS precio_anterior,
           nullif(regexp_replace(coalesce(x->>'pn',''),'[^0-9.]','','g'),'')::numeric AS precio_nuevo,
           nullif(trim(coalesce(x->>'d1','')),'')::date AS desde,
           nullif(trim(coalesce(x->>'msi','')),'') AS msi
    FROM jsonb_array_elements(p_filas) x
    WHERE trim(coalesce(x->>'sku','')) <> ''
  ) p ORDER BY sku;

  SELECT count(*) INTO sin_fecha  FROM _pl WHERE desde IS NULL;
  SELECT count(*) INTO sin_precio FROM _pl WHERE desde IS NOT NULL AND coalesce(precio_nuevo, 0) <= 0;

  INSERT INTO public.precio_lista (store_id, sku, producto, precio_anterior, precio_nuevo,
                                   desde, cea, msi, subido_por)
  SELECT p_store, sku, producto, precio_anterior, precio_nuevo, desde,
         nullif(trim(coalesce(p_cea,'')),''), msi, nullif(trim(coalesce(p_by,'')),'')
  FROM _pl
  WHERE desde IS NOT NULL AND coalesce(precio_nuevo, 0) > 0
  ON CONFLICT (store_id, sku) DO UPDATE
    SET producto        = excluded.producto,
        precio_anterior = excluded.precio_anterior,
        precio_nuevo    = excluded.precio_nuevo,
        desde           = excluded.desde,
        cea             = excluded.cea,
        msi             = excluded.msi,
        subido_por      = coalesce(excluded.subido_por, public.precio_lista.subido_por),
        updated_at      = now();
  GET DIAGNOSTICS n = ROW_COUNT;

  -- Aplicarlo YA a lo que está en el catálogo: reescribir el precio con su
  -- propio valor dispara el trigger, que decide con la misma regla de siempre.
  UPDATE public.catalogo c SET precio = c.precio
   WHERE c.store_id = p_store
     AND c.sku IN (SELECT sku FROM _pl WHERE desde IS NOT NULL AND coalesce(precio_nuevo,0) > 0);

  SELECT count(*) INTO aplicados
    FROM public.catalogo c JOIN _pl ON _pl.sku = c.sku
   WHERE c.store_id = p_store AND c.precio = _pl.precio_nuevo;
  SELECT count(*) INTO sin_cat
    FROM _pl
   WHERE desde IS NOT NULL AND coalesce(precio_nuevo,0) > 0
     AND NOT EXISTS (SELECT 1 FROM public.catalogo c WHERE c.store_id = p_store AND c.sku = _pl.sku);

  -- Las promos que son este mismo CEA subido por Promos: cifras idénticas.
  DELETE FROM public.promos pr
   USING _pl
   WHERE pr.store_id = p_store AND pr.sku = _pl.sku
     AND _pl.desde IS NOT NULL AND coalesce(_pl.precio_nuevo,0) > 0
     AND pr.precio_reg = _pl.precio_anterior
     AND pr.precio_pro = _pl.precio_nuevo;
  GET DIAGNOSTICS espejo = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'guardados', n, 'aplicados', aplicados,
                            'sin_catalogo', sin_cat, 'promos_quitadas', espejo,
                            'sin_fecha', sin_fecha, 'sin_precio', sin_precio);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.catalogo_precio_lista_() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.carga_precio_lista(text,text,jsonb,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.carga_precio_lista(text,text,jsonb,text,text) TO anon, authenticated;

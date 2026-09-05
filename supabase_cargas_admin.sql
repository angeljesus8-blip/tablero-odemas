-- ============================================================
--  LAS CARGAS DE ADMIN — catálogo, inventario, exhibición,
--  promos, comisiones y catálogo_ref, directo a Supabase
--  Etapa 3 de "apagar la hoja"
--  7-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql (guardia `escritura_ok_`) y de
--  supabase_inventario_preventa.sql (el filtro de las entregas). Correr esos
--  primero.
--
--  ------------------------------------------------------------
--  SUBIR EL CATÁLOGO NO ES GUARDAR UNA TABLA: ES TOMAR EL CORTE
--  ------------------------------------------------------------
--  `actualizarCatalogo_` (GAS_Codigo.gs, l. 203-215) hace algo que no se ve en
--  su nombre: además de reescribir el catálogo, **cuenta las ventas por SKU en
--  ese instante** y las guarda como `ventaBaseline`. Todo el cálculo del stock
--  cuelga de ese número:
--
--      stock = On Hand del informe − (ventas de ahora − ventas al subirlo)
--
--  Si el corte se toma en otro momento, o contando distinto, el tablero miente
--  sobre el stock y no se entera nadie hasta que falta mercancía. Es el riesgo 1
--  del plan de migración y la función que se verificó CONTANDO CAJAS EN PISO.
--
--  Por eso el corte se toma AQUÍ DENTRO, en la misma transacción que escribe el
--  On Hand. Hacerlo en dos llamadas dejaría una ventana en la que una venta
--  cabe entre el corte y la escritura, y esa pieza se contaría dos veces.
--
--  La exhibición lleva su PROPIO corte, y eso también es a propósito: es
--  ocasional, no diaria. Con un corte compartido, una pieza de piso ya vendida
--  reaparecería con el On Hand del día siguiente.
--
--  ------------------------------------------------------------
--  EL FILTRO DE PREVENTA VA TAMBIÉN AQUÍ
--  ------------------------------------------------------------
--  Los cortes cuentan ventas, así que tienen que contar con el MISMO criterio
--  que `inventario_vivo`: sin las entregas de preventa, que el POS ya descontó.
--  Si uno excluye y el otro no, cada entrega resta una venta normal del conteo.
--  Ver supabase_inventario_preventa.sql.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
-- ============================================================


-- ── 1 · Catálogo + inventario + corte  ←  tipo:'catalogo' ───
-- p_filas: [{upc, sku, desc, onhand, precio}, ...] tal cual lo arma
-- actualizar_datos.html al parsear el Excel.
--
-- `vigente` = el SKU trae On Hand en el informe. Es la misma regla que usa el
-- Apps Script (el campo `o` no vacío) y la que separa lo que hay en tienda de
-- lo que solo se conserva como referencia.
CREATE OR REPLACE FUNCTION public.carga_catalogo(
  p_store text,
  p_token text,
  p_filas jsonb,
  p_by    text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int; n_inv int; n_corte int; n_cero int := 0; n_con_stock int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' OR jsonb_array_length(p_filas) = 0 THEN
    -- Un Excel que se parseó mal llega como lista vacía. Aceptarlo borraría el
    -- catálogo entero y dejaría el tablero en blanco, y el gerente vería
    -- "actualizado ✓". Se rechaza: mejor no subir nada que subir la nada.
    RETURN jsonb_build_object('ok', false, 'error', 'el archivo no trajo ninguna fila');
  END IF;

  CREATE TEMP TABLE _carga (
    sku text, descripcion text, upc text, precio numeric, onhand int
  ) ON COMMIT DROP;

  -- La subconsulta NO es adorno: `DISTINCT ON` no puede referirse a los alias de
  -- salida del propio SELECT —eso solo lo permite ORDER BY—, así que
  -- `DISTINCT ON (sku)` sobre columnas sin nombre falla con
  -- «42703: column "sku" does not exist». Pasó el 7-ago-2026 al subir el primer
  -- informe de verdad. Se nombran los campos dentro y se filtra fuera.
  INSERT INTO _carga (sku, descripcion, upc, precio, onhand)
  SELECT DISTINCT ON (sku) sku, descripcion, upc, precio, onhand
  FROM (
    SELECT trim(x->>'sku') AS sku,
           coalesce(x->>'desc','') AS descripcion,
           nullif(trim(coalesce(x->>'upc','')),'') AS upc,
           nullif(regexp_replace(coalesce(x->>'precio',''),'[^0-9.]','','g'),'')::numeric AS precio,
           -- `inventario.onhand` tiene CHECK (onhand >= 0). Un negativo en el
           -- Excel —pasa cuando el POS arrastra un ajuste— reventaría el INSERT
           -- y tumbaría la carga ENTERA, con el gerente delante y sin saber por
           -- qué. Un stock negativo no significa nada en piso: es cero.
           greatest(0, coalesce(nullif(regexp_replace(coalesce(x->>'onhand',''),'[^0-9-]','','g'),'')::int, 0)) AS onhand
    FROM jsonb_array_elements(p_filas) x
    WHERE trim(coalesce(x->>'sku','')) <> ''
  ) p
  -- Un mismo SKU puede venir en varias filas del Excel (varios UPC). Gana la
  -- que trae On Hand, y entre esas la de precio más alto: es el criterio que ya
  -- usaba `cargar_catalogo` y evita quedarse con una fila vacía por azar.
  ORDER BY sku, onhand DESC, precio DESC NULLS LAST;

  GET DIAGNOSTICS n = ROW_COUNT;

  -- Lo que ya no viene en el informe deja de ser vigente. NO se borra: los
  -- agotados siguen en el catálogo como referencia —el cliente los pide y se
  -- traen de otra tienda— y borrarlos los sacaría del buscador.
  -- El 4-ago esto estuvo mal en `cargar_catalogo` con un OR que impedía volver
  -- a false: un SKU marcado vigente lo era para siempre.
  UPDATE public.catalogo c SET vigente = false, updated_at = now()
   WHERE c.store_id = p_store AND c.vigente
     AND NOT EXISTS (SELECT 1 FROM _carga g WHERE g.sku = c.sku AND g.onhand <> 0);

  -- `subido_por` alimenta el "Por Fulano" de la pantalla de estado. Se le
  -- pasaba p_by y solo se devolvia en la respuesta: la columna se quedaba en
  -- NULL y esa linea decia siempre un guion. Encontrado el 7-ago al comprobar
  -- por que no se movia cat_at.
  INSERT INTO public.catalogo (store_id, sku, descripcion, upc, precio, vigente, subido_por)
  SELECT p_store, g.sku, g.descripcion, g.upc, g.precio, (g.onhand <> 0),
         nullif(trim(coalesce(p_by,'')),'')
  FROM _carga g
  ON CONFLICT (store_id, sku) DO UPDATE
    SET descripcion = excluded.descripcion,
        upc         = coalesce(excluded.upc, public.catalogo.upc),
        precio      = coalesce(excluded.precio, public.catalogo.precio),
        vigente     = excluded.vigente,
        subido_por  = coalesce(excluded.subido_por, public.catalogo.subido_por),
        updated_at  = now();

  -- On Hand. La exhibición NO se toca aquí: tiene su propia carga y su propio
  -- corte, porque se sube en otro momento.
  INSERT INTO public.inventario (store_id, sku, onhand)
  SELECT p_store, g.sku, g.onhand FROM _carga g
  ON CONFLICT (store_id, sku) DO UPDATE
    SET onhand = excluded.onhand;

  /* ── Lo que YA NO viene en el archivo se pone en cero ──────
     5-sep-2026, encontrado en la tienda de origen: tres articulos agotados
     seguian ofreciendose con stock. El archivo es el ON HAND del dia; cuando
     un articulo se acaba, deja de venir. Hasta hoy esta carga solo tocaba los
     SKUs presentes, asi que al ausente le quedaba el numero del ultimo dia que
     aparecio — y `inventario_vivo` lo enseñaba igual, porque no mira si el
     catalogo sigue vigente. El asesor prometia una pieza que no existe.

     SOLO `onhand`. La columna `exhibicion` vive en esta misma tabla y se sube
     por separado y de higos a brevas (`carga_exhibicion`): tocarla aqui
     borraria el piso entero en cada carga diaria. Un articulo agotado en bodega
     que conserve su pieza de muestra tiene que seguir viendose —0 en stock, 1
     en piso—, que es justo lo que distingue `inventario_vivo`.

     LA SALVAGUARDA: si el archivo trae menos de la mitad de los SKUs que ya
     tienen existencia, no se pone nada en cero. Una carga completa que se acaba
     de subir no puede encoger a la mitad de un dia para otro; si encoge, lo que
     se subio fue un pedazo —una categoria, un archivo filtrado— y ponerle cero
     al resto vaciaria la tienda entera sin que nadie lo pidiera. Se avisa en la
     respuesta y no se toca nada. */
  SELECT count(*) INTO n_con_stock FROM public.inventario i
   WHERE i.store_id = p_store AND coalesce(i.onhand,0) > 0;

  IF n_con_stock > 0 AND (SELECT count(*) FROM _carga WHERE onhand > 0) * 2 < n_con_stock THEN
    n_cero := -1;   -- lo lee la app: archivo sospechosamente corto
  ELSE
    UPDATE public.inventario i SET onhand = 0
     WHERE i.store_id = p_store
       AND coalesce(i.onhand,0) <> 0
       AND NOT EXISTS (SELECT 1 FROM _carga g WHERE g.sku = i.sku);
    GET DIAGNOSTICS n_cero = ROW_COUNT;
  END IF;
  GET DIAGNOSTICS n_inv = ROW_COUNT;

  -- EL CORTE. Va aquí dentro, en la misma transacción que el On Hand: si se
  -- hiciera en otra llamada, una venta que entre en medio se contaría dos veces.
  -- El filtro de entregas de preventa es el MISMO que usa inventario_vivo.
  -- Solo ventas de BODEGA (17-ago-2026). Una venta marcada como pieza de
  -- exhibición no debe entrar aquí: si entrara, el corte de On Hand quedaría
  -- alto y la siguiente venta de bodega no descontaría stock. Ver
  -- `supabase_venta_exhibicion.sql`.
  INSERT INTO public.inventario_corte (store_id, tipo, sku, vendidas)
  SELECT p_store, 'onhand', g.sku, public.corte_tomar_(p_store, 'onhand', g.sku)
  FROM _carga g
  ON CONFLICT (store_id, tipo, sku) DO UPDATE
    SET vendidas = excluded.vendidas, tomado_en = now();
  GET DIAGNOSTICS n_corte = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'skus', n, 'inventario', n_inv,
                            'corte', n_corte, 'by', coalesce(p_by,''),
                            -- -1 = no se puso nada en cero porque el archivo
                            -- venia demasiado corto. La app lo enseña.
                            'agotados', n_cero);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 2 · Exhibición + su corte  ←  tipo:'exhibicion' ─────────
-- p_filas: [{sku, exhibe}, ...]
CREATE OR REPLACE FUNCTION public.carga_exhibicion(
  p_store text,
  p_token text,
  p_filas jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin filas');
  END IF;

  /* Que las filas traigan el campo que esta funcion lee (2-sep-2026).

     El campo se llama `exhibe`. Una carga que lo mande con otro nombre —pasó
     llamándolo `exhibicion`— entra por el coalesce de abajo como CERO en todo,
     y esto respondía `ok: true, skus: 4`: cuatro SKUs guardados con cero
     piezas en el aparador. O sea que decía que sí y dejaba el piso vacío.

     Se RECHAZA en vez de avisar: si ninguna fila trae el campo, esta carga no
     puede hacer nada útil, y lo que sí puede hacer es borrar la exhibición que
     ya estaba puesta.

     Una carga legítima que quiera vaciar el aparador manda `exhibe: 0`, que sí
     trae la clave y pasa. La diferencia entre «ponlo en cero» y «no sé de qué
     me hablas» tiene que notarse. */
  IF jsonb_array_length(p_filas) > 0 AND NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(p_filas) x WHERE x ? 'exhibe') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'ninguna fila trae el campo `exhibe`: se guardarían ceros y se '
               'borraría la exhibición que ya está puesta');
  END IF;

  CREATE TEMP TABLE _exh (sku text PRIMARY KEY, exhibe int) ON COMMIT DROP;
  INSERT INTO _exh (sku, exhibe)
  SELECT DISTINCT ON (trim(x->>'sku'))
         trim(x->>'sku'),
         coalesce(nullif(regexp_replace(coalesce(x->>'exhibe',''),'[^0-9-]','','g'),'')::int, 0)
  FROM jsonb_array_elements(p_filas) x
  WHERE trim(coalesce(x->>'sku','')) <> '';

  -- Lo que no viene en la subida de piso queda en cero: es una foto completa
  -- del piso, no un parche. Un SKU que se retiró de exhibición y no se pusiera
  -- a cero seguiría contando como pieza de muestra para siempre.
  UPDATE public.inventario i SET exhibicion = 0
   WHERE i.store_id = p_store AND coalesce(i.exhibicion,0) <> 0
     AND NOT EXISTS (SELECT 1 FROM _exh e WHERE e.sku = i.sku);

  INSERT INTO public.inventario (store_id, sku, exhibicion)
  SELECT p_store, e.sku, e.exhibe FROM _exh e
  ON CONFLICT (store_id, sku) DO UPDATE SET exhibicion = excluded.exhibicion;
  GET DIAGNOSTICS n = ROW_COUNT;

  -- Corte PROPIO, independiente del de On Hand. Ver la cabecera.
  -- Y solo con las ventas DE EXHIBICIÓN (17-ago-2026): si contara todas, el
  -- corte quedaría siempre por encima de las marcadas y el aparador no bajaría
  -- nunca — la marca no serviría de nada, sin dar ningún error.
  INSERT INTO public.inventario_corte (store_id, tipo, sku, vendidas)
  SELECT p_store, 'exhibicion', e.sku, public.corte_tomar_(p_store, 'exhibicion', e.sku)
  FROM _exh e
  ON CONFLICT (store_id, tipo, sku) DO UPDATE
    SET vendidas = excluded.vendidas, tomado_en = now();

  RETURN jsonb_build_object('ok', true, 'skus', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 3 · Catálogo de referencia  ←  tipo:'catalogo_ref' ──────
-- Los agotados que el cliente sigue pidiendo y se traen de otra tienda. Entran
-- como NO vigentes y sin tocar el precio de los que ya están: este archivo no
-- trae precios, y escribir NULL encima borraría el último precio conocido.
CREATE OR REPLACE FUNCTION public.carga_catalogo_ref(
  p_store text,
  p_token text,
  p_filas jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin filas');
  END IF;

  INSERT INTO public.catalogo (store_id, sku, descripcion, upc, vigente)
  SELECT DISTINCT ON (trim(x->>'sku'))
         p_store, trim(x->>'sku'), coalesce(x->>'desc',''),
         nullif(trim(coalesce(x->>'upc','')),''), false
  FROM jsonb_array_elements(p_filas) x
  WHERE trim(coalesce(x->>'sku','')) <> ''
  ON CONFLICT (store_id, sku) DO UPDATE
    SET descripcion = excluded.descripcion,
        upc         = coalesce(excluded.upc, public.catalogo.upc),
        -- vigente NO se toca: si ese SKU sí está en el informe del día, es
        -- vigente, y este archivo no sabe nada de eso.
        updated_at  = now();
  GET DIAGNOSTICS n = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'skus', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 4 · Promos  ←  tipo:'promos' ────────────────────────────
-- MEZCLA, no reemplaza: `actualizarPromos_` conserva las promos anteriores y
-- encima pone las del CEA nuevo. Un CEA trae solo las promos de esa quincena, y
-- reemplazar borraría las que siguen vigentes de la anterior.
--
-- LA TABLA TIENE DOS CANDADOS QUE LA HOJA NO TENÍA, y cualquiera de los dos
-- tumba la carga entera si se le manda una fila que no cumple:
--
--   · `vigente_hasta` es NOT NULL — sin fecha no hay promo
--   · CHECK (precio_pro < precio_reg)
--
-- En la hoja esas filas entraban sin más y luego no se veían. Aquí reventarían
-- el INSERT completo y el gerente vería "no se pudo subir" sin saber que fue por
-- una fila de 117. Así que se APARTAN y se CUENTAN: las buenas entran, y la
-- respuesta dice cuántas se quedaron fuera y por qué. Descartarlas en silencio
-- sería peor — una promo que no aparece es un precio que el asesor no cobra.
CREATE OR REPLACE FUNCTION public.carga_promos(
  p_store text,
  p_token text,
  p_filas jsonb,
  p_by    text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int; sin_fecha int; precio_malo int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin filas');
  END IF;

  CREATE TEMP TABLE _pro ON COMMIT DROP AS
  SELECT DISTINCT ON (sku) * FROM (
    SELECT trim(x->>'sku') AS sku,
           coalesce(x->>'desc','') AS producto,
           nullif(regexp_replace(coalesce(x->>'pr',''),'[^0-9.]','','g'),'')::numeric AS precio_reg,
           nullif(regexp_replace(coalesce(x->>'pp',''),'[^0-9.]','','g'),'')::numeric AS precio_pro,
           nullif(trim(coalesce(x->>'est','')),'') AS estatus,
           nullif(trim(coalesce(x->>'msi','')),'') AS msi,
           nullif(trim(coalesce(x->>'d1','')),'')::date AS vigente_desde,
           nullif(trim(coalesce(x->>'d2','')),'')::date AS vigente_hasta
    FROM jsonb_array_elements(p_filas) x
    WHERE trim(coalesce(x->>'sku','')) <> ''
  ) p ORDER BY sku, vigente_hasta DESC NULLS LAST;

  SELECT count(*) INTO sin_fecha   FROM _pro WHERE vigente_hasta IS NULL;
  SELECT count(*) INTO precio_malo FROM _pro
   WHERE vigente_hasta IS NOT NULL
     AND precio_pro IS NOT NULL AND precio_reg IS NOT NULL
     AND precio_pro >= precio_reg;

  INSERT INTO public.promos (store_id, sku, producto, precio_reg, precio_pro,
                             estatus, msi, vigente_desde, vigente_hasta, subido_por)
  SELECT p_store, sku, producto, precio_reg, precio_pro,
         estatus, msi, vigente_desde, vigente_hasta,
         nullif(trim(coalesce(p_by,'')),'')
  FROM _pro
  WHERE vigente_hasta IS NOT NULL
    AND (precio_pro IS NULL OR precio_reg IS NULL OR precio_pro < precio_reg)
    -- la vigencia al revés también tiene CHECK
    AND (vigente_desde IS NULL OR vigente_desde <= vigente_hasta)
  ON CONFLICT (store_id, sku) DO UPDATE
    SET producto      = excluded.producto,
        precio_reg    = excluded.precio_reg,
        precio_pro    = excluded.precio_pro,
        estatus       = excluded.estatus,
        msi           = excluded.msi,
        vigente_desde = excluded.vigente_desde,
        vigente_hasta = excluded.vigente_hasta,
        subido_por    = coalesce(excluded.subido_por, public.promos.subido_por),
        updated_at    = now();
  GET DIAGNOSTICS n = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'promos', n,
                            'sin_fecha', sin_fecha, 'precio_invalido', precio_malo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 5 · Comisiones  ←  tipo:'comisiones' ────────────────────
-- Esta SÍ reemplaza: el reporte trae el mes completo cada vez.
--
-- `alcance` y `gar_pct` PUEDEN pasar de 100 y no se recortan. Hay una ventana de
-- 30 días para comprar el seguro, así que un vendedor puede cerrar por encima
-- del 100 %. Un LEAST(...,100) "para que se vea bien" borraría trabajo hecho.
CREATE OR REPLACE FUNCTION public.carga_comisiones(
  p_store   text,
  p_token   text,
  p_filas   jsonb,
  p_periodo text DEFAULT NULL,
  -- El periodo de garantías es OTRO campo y otra ventana de fechas: lo pinta
  -- comisiones.html (l. 132). Sin él esa pantalla muestra un guion, y el equipo
  -- no sabe a qué semana corresponde su attach.
  p_periodo_gar text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' OR jsonb_array_length(p_filas) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'el reporte no trajo ninguna fila');
  END IF;

  DELETE FROM public.comisiones WHERE store_id = p_store;

  INSERT INTO public.comisiones (store_id, empno, nombre, puesto, venta, ppto_pct,
                                 alcance, gar_pct, gar_pzas, gar_elegible, gar_monto,
                                 periodo, periodo_gar)
  SELECT p_store,
         nullif(trim(coalesce(x->>'empNo','')),''),
         trim(coalesce(x->>'nombre','')),
         nullif(trim(coalesce(x->>'puesto','')),''),
         coalesce(nullif(regexp_replace(coalesce(x->>'venta',''),'[^0-9.]','','g'),'')::numeric, 0),
         coalesce(nullif(regexp_replace(coalesce(x->>'pptoPct',''),'[^0-9.]','','g'),'')::numeric, 0),
         coalesce(nullif(regexp_replace(coalesce(x->>'alcance',''),'[^0-9.]','','g'),'')::numeric, 0),
         nullif(regexp_replace(coalesce(x->>'garantiaPct',''),'[^0-9.]','','g'),'')::numeric,
         nullif(regexp_replace(coalesce(x->>'garantiaPzas',''),'[^0-9.]','','g'),'')::int,
         nullif(regexp_replace(coalesce(x->>'garantiaElegible',''),'[^0-9.]','','g'),'')::int,
         nullif(regexp_replace(coalesce(x->>'garantiaMonto',''),'[^0-9.]','','g'),'')::numeric,
         nullif(trim(coalesce(p_periodo,'')),''),
         nullif(trim(coalesce(p_periodo_gar,'')),'')
  FROM jsonb_array_elements(p_filas) x
  WHERE trim(coalesce(x->>'nombre','')) <> '';
  GET DIAGNOSTICS n = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'empleados', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 6 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.carga_catalogo(text,text,jsonb,text)   FROM public;
REVOKE ALL ON FUNCTION public.carga_exhibicion(text,text,jsonb)      FROM public;
REVOKE ALL ON FUNCTION public.carga_catalogo_ref(text,text,jsonb)    FROM public;
REVOKE ALL ON FUNCTION public.carga_promos(text,text,jsonb,text)          FROM public;
REVOKE ALL ON FUNCTION public.carga_comisiones(text,text,jsonb,text,text) FROM public;

GRANT EXECUTE ON FUNCTION public.carga_catalogo(text,text,jsonb,text)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carga_exhibicion(text,text,jsonb)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carga_catalogo_ref(text,text,jsonb)    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carga_promos(text,text,jsonb,text)          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carga_comisiones(text,text,jsonb,text,text) TO anon, authenticated;


-- ── 7 · resincronizar() deja de poder pisar lo nuevo ────────
-- ESTE PASO ES OBLIGATORIO, y es el más peligroso del archivo si se salta.
--
-- `resincronizar()` trae de la HOJA el catálogo, el inventario, los cortes, las
-- promos y las comisiones. Desde hoy la hoja ya no recibe ninguna de esas
-- cargas, así que correrlo reemplazaría los datos buenos por una foto vieja —el
-- catálogo entero, 227 filas— y terminaría diciendo "los seis pasos en verde".
--
-- Es el mismo caso que `cargar_apartados_comisiones` el 7-ago, pero sobre el
-- inventario. Se desactiva entera en vez de borrarla: si alguien la llama por
-- costumbre, tiene que enterarse de que ya no debe.
CREATE OR REPLACE FUNCTION public.resincronizar(p_store text)
RETURNS TABLE (paso int, que text, resultado text)
LANGUAGE plpgsql AS $fn$
BEGIN
  paso := 1;
  que  := 'resincronizar';
  resultado := 'DESACTIVADA (7-ago-2026). La hoja ya no recibe cargas: '
            || 'catalogo, inventario, promos y comisiones se suben directo a '
            || 'Supabase desde Admin. Correr esto reemplazaria los datos buenos '
            || 'por la ultima foto de la hoja. Ver supabase_cargas_admin.sql.';
  RETURN NEXT;
END $fn$;


-- ============================================================
--  COMPROBAR — hacerlo, y en este orden
-- ============================================================
--
--  1) Sin token no se carga nada:
--       select public.carga_catalogo('1217','', '[{"sku":"1","desc":"x"}]'::jsonb);
--     -> {"ok": false, "error": "no_autorizado"}
--
--  2) Un archivo vacío se RECHAZA (si se aceptara, borraría el catálogo):
--       select public.carga_catalogo('1217','<TOKEN>', '[]'::jsonb);
--     -> {"ok": false, "error": "el archivo no trajo ninguna fila"}
--
--  3) resincronizar ya no hace nada:
--       select * from public.resincronizar('1217');
--     -> un solo renglon que dice DESACTIVADA
--
--  4) LA PRUEBA DE VERDAD, y no se salta: subir el informe del día desde
--     actualizar_datos.html y comprobar que el inventario NO cambió de forma
--     rara. Antes de subirlo:
--
--       CREATE TEMP TABLE inv_antes AS SELECT * FROM public.inventario_vivo('1217');
--
--     Después de subirlo, en la MISMA pestaña del editor:
--
--       SELECT a.sku, a.onhand AS antes, b.onhand AS ahora,
--              a.stock AS stock_antes, b.stock AS stock_ahora
--         FROM inv_antes a JOIN public.inventario_vivo('1217') b USING (sku)
--        WHERE a.onhand <> b.onhand OR a.stock <> b.stock
--        ORDER BY abs(a.stock - b.stock) DESC LIMIT 20;
--
--     Lo que se espera: cambios que se expliquen por las ventas del día y por
--     la mercancía que entró. Lo que NO se espera: que el stock se vaya a cero
--     en muchos SKU a la vez, o que salten SKUs que no se movieron. Si sale
--     algo así, el corte se tomó mal — parar y avisar.
-- ============================================================

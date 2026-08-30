-- ============================================================
--  MANTENER EL CATALOGO DE ACCESORIOS DESDE LA APP
--  20-ago-2026
-- ============================================================
--
--  Los 23 productos del SKU generico se sembraron a mano en
--  `supabase_accesorios.sql`. Desde entonces, dar de alta uno nuevo —y Mr Fix
--  mete producto cada tanto— obliga a escribir SQL. Con esto lo hace el gerente
--  desde Captura de Series.
--
--  ------------------------------------------------------------
--  POR QUE NO BASTABA CON PONERLE PANTALLA A LO QUE YA HABIA
--  ------------------------------------------------------------
--  `accesorio_catalogo_guardar` YA EXISTIA, escrita el 18-ago. Pero es del dia
--  ANTES de que el catalogo tuviera `articulo` y `sku`, y solo inserta
--  (store_id, nombre, precio_ref, orden). Un producto dado de alta con ella:
--
--    · queda SIN `articulo` — el codigo que el cajero teclea en «N. de serie».
--      `accAdivinar` se salta las filas sin codigo, asi que ese producto NUNCA
--      se propone al leer un ticket. Pareceria que el OCR empeoro.
--
--    · queda con `sku` = 43739 por omision — cierto para micas y cargadores,
--      falso para los Office (63602 y 57518), que van al reporte con SU sku.
--      La columna E del Excel saldria mal.
--
--  Ninguna de las dos cosas da error. Por eso se rehace la funcion en vez de
--  llamarla desde un boton nuevo.
--
--  ------------------------------------------------------------
--  QUIEN PUEDE
--  ------------------------------------------------------------
--  Gerente y subgerente, MISMO portero que corregir una venta y que el Excel
--  del mes (`puede_gestionar_`). No es celo: el precio de referencia ordena la
--  lista al capturar, y el `sku` decide con que codigo entra al reporte de
--  comisiones de todo el equipo.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · Un articulo no puede repetirse ──────────────────────
-- `accAdivinar` gana por prefijo mas largo y CALLA si hay empate. Dos filas con
-- el mismo codigo empatan siempre: el producto deja de proponerse y no hay nada
-- que lo explique. Se comprueba en la funcion (mensaje claro), y el indice lo
-- sostiene por si alguien escribe SQL a mano.
CREATE UNIQUE INDEX IF NOT EXISTS accesorios_catalogo_articulo_uniq
  ON public.accesorios_catalogo (store_id, upper(articulo))
  WHERE articulo IS NOT NULL AND activo;


-- ── 2 · La lista para administrar ───────────────────────────
-- Distinta de `accesorios_catalogo_lista`, que es la de capturar: aquella trae
-- SOLO los activos —quien esta capturando no debe poder elegir un producto
-- retirado— y esta los trae TODOS, porque dar de baja se deshace.
--
-- `usos` es lo que de verdad hace falta antes de tocar nada: las ventas guardan
-- el nombre del producto como TEXTO, asi que renombrar no arrastra el historico.
-- Se ensena el numero y decide quien edita.
DROP FUNCTION IF EXISTS public.accesorios_catalogo_admin(text,text,text);

CREATE FUNCTION public.accesorios_catalogo_admin(
  p_store text, p_token text, p_quien text DEFAULT NULL
) RETURNS TABLE (id bigint, articulo text, nombre text, precio_ref numeric,
                 sku text, orden integer, activo boolean, usos integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN RETURN; END IF;
  IF coalesce(trim(p_quien),'') <> '' AND NOT public.puede_gestionar_(p_store, trim(p_quien)) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT c.id, c.articulo, c.nombre, c.precio_ref, c.sku, c.orden, c.activo,
         (SELECT count(*)::int FROM public.accesorios_ventas v
           WHERE v.store_id = c.store_id AND v.producto = c.nombre)
  FROM public.accesorios_catalogo c
  WHERE c.store_id = p_store
  ORDER BY c.activo DESC, c.orden, c.nombre;
END $fn$;


-- ── 3 · Alta y edicion ──────────────────────────────────────
-- La firma cambia (entran p_id, p_articulo, p_sku, p_quien): DROP de la vieja
-- ANTES del CREATE, o Postgres deja las dos y PostgREST responde PGRST203.
DROP FUNCTION IF EXISTS public.accesorio_catalogo_guardar(text,text,text,numeric,integer);

CREATE OR REPLACE FUNCTION public.accesorio_catalogo_guardar(
  p_store    text,
  p_token    text,
  p_nombre   text,
  p_precio   numeric DEFAULT NULL,
  p_orden    integer DEFAULT 100,
  -- NULL da de alta; con id, edita esa fila. Va aparte del nombre a proposito:
  -- la version anterior hacia upsert POR NOMBRE, de modo que corregirle una
  -- letra a un producto no lo renombraba, creaba otro.
  p_id       bigint  DEFAULT NULL,
  p_articulo text    DEFAULT NULL,
  p_sku      text    DEFAULT NULL,
  p_quien    text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_nombre   text := trim(coalesce(p_nombre,''));
  v_articulo text := nullif(upper(trim(coalesce(p_articulo,''))),'');
  v_sku      text := nullif(trim(coalesce(p_sku,'')),'');
  v_id       bigint;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_quien),'') <> '' AND NOT public.puede_gestionar_(p_store, trim(p_quien)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'solo el gerente o el subgerente pueden tocar el catalogo');
  END IF;

  IF v_nombre = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'falta el nombre del producto');
  END IF;
  IF p_precio IS NOT NULL AND p_precio < 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'el precio no puede ser negativo');
  END IF;

  -- El nombre es la llave con la que se guarda cada venta: dos productos con el
  -- mismo nombre serian indistinguibles en el reporte.
  IF EXISTS (SELECT 1 FROM public.accesorios_catalogo c
              WHERE c.store_id = p_store AND upper(c.nombre) = upper(v_nombre)
                AND (p_id IS NULL OR c.id <> p_id)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'ya hay un producto que se llama asi');
  END IF;

  -- Ver el indice de arriba: repetir codigo deja a los dos sin proponerse.
  IF v_articulo IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.accesorios_catalogo c
        WHERE c.store_id = p_store AND c.activo AND upper(c.articulo) = v_articulo
          AND (p_id IS NULL OR c.id <> p_id)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'ese codigo de articulo ya lo tiene otro producto');
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.accesorios_catalogo (store_id, articulo, nombre, precio_ref, sku, orden)
    VALUES (p_store, v_articulo, v_nombre, p_precio,
            coalesce(v_sku, '43739'), coalesce(p_orden, 100))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.accesorios_catalogo
       SET articulo = v_articulo, nombre = v_nombre, precio_ref = p_precio,
           sku = coalesce(v_sku, '43739'), orden = coalesce(p_orden, 100),
           activo = true
     WHERE store_id = p_store AND id = p_id
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'ese producto ya no existe');
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', v_id);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 4 · Baja y alta de vuelta ───────────────────────────────
-- Cambia la firma (entra p_activo y p_quien).
DROP FUNCTION IF EXISTS public.accesorio_catalogo_baja(text,text,bigint);

CREATE OR REPLACE FUNCTION public.accesorio_catalogo_baja(
  p_store text, p_token text, p_id bigint,
  p_activo boolean DEFAULT false, p_quien text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE v_id bigint;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_quien),'') <> '' AND NOT public.puede_gestionar_(p_store, trim(p_quien)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'solo el gerente o el subgerente pueden tocar el catalogo');
  END IF;

  /* NUNCA se borra, se desactiva: las ventas guardan el nombre del producto
     como texto y borrar la fila dejaria el historico apuntando a algo que ya
     no existe. Ademas asi se puede volver a activar —el catalogo de Mr Fix va
     y viene con la temporada— sin volver a teclearlo. */
  UPDATE public.accesorios_catalogo SET activo = coalesce(p_activo, false)
   WHERE store_id = p_store AND id = p_id
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ese producto ya no existe');
  END IF;
  RETURN jsonb_build_object('ok', true);
EXCEPTION
  WHEN OTHERS THEN
    -- Reactivar puede chocar con el indice de articulo unico: si mientras
    -- estaba de baja se dio de alta otro con su mismo codigo.
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 5 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.accesorios_catalogo_admin(text,text,text) FROM public;
REVOKE ALL ON FUNCTION public.accesorio_catalogo_guardar(text,text,text,numeric,integer,bigint,text,text,text) FROM public;
REVOKE ALL ON FUNCTION public.accesorio_catalogo_baja(text,text,bigint,boolean,text) FROM public;

GRANT EXECUTE ON FUNCTION public.accesorios_catalogo_admin(text,text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accesorio_catalogo_guardar(text,text,text,numeric,integer,bigint,text,text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accesorio_catalogo_baja(text,text,bigint,boolean,text) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) Los 23 de siempre siguen ahi, y ahora se ven con sus usos:
--       select count(*) from public.accesorios_catalogo_admin(
--         '1217', (select gas_token from public.tiendas where store_id='1217'), '<empno-gerente>');
--     Tiene que dar 23 o mas (las de la lista vieja estan de baja y tambien salen).
--
--  2) Que el asesor NO puede. Con el numero de un asesor tiene que dar cero
--     filas, no la lista:
--       select count(*) from public.accesorios_catalogo_admin(
--         '1217', (select gas_token from public.tiendas where store_id='1217'), '<empno-asesor>');
--
--  3) LO QUE DE VERDAD HAY QUE COMPROBAR — que el alta sale COMPLETA.
--     Este es el fallo que traia la version anterior, y no daba error:
--       select public.accesorio_catalogo_guardar(
--         '1217', (select gas_token from public.tiendas where store_id='1217'),
--         'PRUEBA BORRAR', 111, 999, NULL, '43739-PRUEBA', '43739', '<empno-gerente>');
--     (los numeros de empleado de verdad estan en `_privado/datos_equipo.txt`)
--       select articulo, sku from public.accesorios_catalogo
--        where store_id='1217' and nombre='PRUEBA BORRAR';
--     `articulo` tiene que decir 43739-PRUEBA y `sku` 43739. Si `articulo`
--     sale vacio, el producto no se propondria nunca al leer un ticket.
--     Para deshacerlo:
--       delete from public.accesorios_catalogo
--        where store_id='1217' and nombre='PRUEBA BORRAR';
--
-- ============================================================
--  Odemas · Grupo Gigante — uso interno HES 1217
-- ============================================================

-- ============================================================
--  ACCESO DE TECNICOS EXTERNOS — solo accesorios, solo lectura
--  20-ago-2026
-- ============================================================
--
--  Dos tecnicos de Mr Fix necesitan cotejar su mes: que accesorios se vendieron,
--  en que ticket y a que precio. Nada mas del sistema.
--
--  ------------------------------------------------------------
--  POR QUE NO ENTRAN COMO EMPLEADOS
--  ------------------------------------------------------------
--  Son EXTERNOS. Meterlos en `empleados` les daria el `gas_token` de la tienda,
--  que es el permiso de ESCRITURA sobre todo: ventas, inventario, EOL, avisos,
--  apartados. Esconder pantallas en el cliente no impide llamar a una funcion.
--
--  Por eso llevan su propia clave, que NO sirve para escribir nada: las dos
--  funciones de abajo son las unicas que la aceptan, y las dos solo leen.
--
--  ------------------------------------------------------------
--  Y NO VEN NOMBRES
--  ------------------------------------------------------------
--  `accesorios_tecnico_lista` devuelve dia, ticket, producto, cantidad y
--  precio. NO devuelve `vendedor`: quien vendio es del equipo de la tienda y no
--  hace falta para cuadrar accesorios.
--
--  ⚠️ La FOTO del ticket si lo lleva, y mas: «Atendido por», los demas
--  articulos de esa compra, la forma de pago y parte del numero de tarjeta del
--  cliente. Se advirtio y Angel decidio mostrarla igual (20-ago-2026). Queda
--  escrito aqui porque quien lea esto dentro de seis meses tiene que saber que
--  fue una decision tomada, no un descuido.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · Quien puede mirar ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tecnicos_acceso (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  nombre     text        NOT NULL,
  -- Clave propia, larga y aleatoria. NO es el gas_token: con esta no se puede
  -- escribir nada en ningun sitio.
  clave      text        NOT NULL,
  activo     boolean     NOT NULL DEFAULT true,
  ultimo_acceso timestamptz,
  creado_en  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store_id, clave)
);

ALTER TABLE public.tecnicos_acceso ENABLE ROW LEVEL SECURITY;
-- Sin politicas: no se llega por REST. Solo la leen las funciones DEFINER.

COMMENT ON TABLE public.tecnicos_acceso IS
  'Tecnicos externos (Mr Fix) que consultan las ventas de accesorios. Su clave '
  'NO es el gas_token y no sirve para escribir: solo la aceptan '
  'accesorios_tecnico_lista y accesorios_tecnico_foto.';

/* NO SE SIEMBRA NINGUNA CLAVE AQUI, y es deliberado (24-ago-2026).

   Hasta hoy este archivo traia los dos tecnicos con su clave escrita. Este
   repo es PUBLICO —sirve la app por GitHub Pages— asi que esas dos claves
   estuvieron legibles para cualquiera que diera con el repositorio, y cada
   push las volvia a publicar. Con ellas se entra a ver las ventas de la
   tienda y las fotos de los tickets.

   Los tecnicos se dan de alta en Admin -> Equipo -> Tecnicos externos: el
   alta genera una clave aleatoria y el boton `clave` le pone la que el
   gerente elija. Ninguna de las dos pasa por aqui ni por el repo.

   Es el mismo motivo por el que se borro `comisiones_datos.js` el 1-ago. */

-- ── 2 · La clave vale, y se anota quien mira ────────────────
CREATE OR REPLACE FUNCTION public.tecnico_ok_(p_store text, p_clave text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE v_id bigint;
BEGIN
  SELECT id INTO v_id FROM public.tecnicos_acceso
   WHERE store_id = p_store AND clave = p_clave AND activo
   LIMIT 1;
  IF v_id IS NULL THEN RETURN false; END IF;
  -- Deja rastro de que se uso. Sin esto no habria forma de saber si una clave
  -- sigue en uso el dia que haya que retirarla.
  UPDATE public.tecnicos_acceso SET ultimo_acceso = now() WHERE id = v_id;
  RETURN true;
END $fn$;

REVOKE ALL ON FUNCTION public.tecnico_ok_(text,text) FROM public, anon, authenticated;


-- ── 3 · Las ventas del mes, SIN nombres ─────────────────────
CREATE OR REPLACE FUNCTION public.accesorios_tecnico_lista(
  p_store text, p_clave text,
  p_anio integer DEFAULT NULL, p_mes integer DEFAULT NULL
) RETURNS TABLE (dia date, ticket text, producto text,
                 cantidad integer, precio numeric, importe numeric,
                 captura_id text, tiene_foto boolean)
-- VOLATILE (por omision), y NO STABLE: `tecnico_ok_` sella `ultimo_acceso` con
-- un UPDATE. PostgREST corre las funciones STABLE en transaccion de SOLO
-- LECTURA, asi que marcarla STABLE la reventaba con 405 / 25006.
-- Y solo con la clave BUENA: con una mala se sale en el SELECT, antes del
-- UPDATE, y devuelve cero filas tan tranquila.
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.tecnico_ok_(p_store, p_clave) THEN
    RETURN;   -- clave mala: cero filas, sin decir por que
  END IF;
  RETURN QUERY
    SELECT v.dia, v.ticket, v.producto, v.cantidad, v.precio, v.importe,
           v.captura_id,
           EXISTS (SELECT 1 FROM public.venta_fotos f
                    WHERE f.store_id = v.store_id AND f.captura_id = v.captura_id)
    FROM public.accesorios_ventas v
    WHERE v.store_id = p_store
      AND extract(year  from v.dia)::int =
          coalesce(p_anio, extract(year  from (now() AT TIME ZONE 'America/Mexico_City'))::int)
      AND extract(month from v.dia)::int =
          coalesce(p_mes,  extract(month from (now() AT TIME ZONE 'America/Mexico_City'))::int)
    ORDER BY v.dia, v.vendida_en;
END $fn$;


-- ── 4 · La foto de ESE ticket → vive en supabase_reparaciones.sql ──
--
-- ⚠️ `accesorios_tecnico_foto` ESTABA AQUI y se quito el 24-ago-2026, porque
-- estaba definida DOS VECES: aqui en su version original —solo accesorios— y
-- en `supabase_reparaciones.sql` ampliada para servir tambien los tickets de
-- reparacion.
--
-- Dos definiciones de la misma funcion en dos archivos no dan error: gana LA
-- ULTIMA QUE SE PEGUE. Repegar este archivo por cualquier otro motivo —dar de
-- alta un tecnico, cambiar una clave— habria devuelto la version vieja y roto
-- las fotos de las reparaciones, sin tocar nada relacionado y sin avisar.
--
-- El candado que aplica sigue siendo el mismo y esta explicado alli: solo se
-- sirve la foto si el `captura_id` es de un accesorio O de una reparacion,
-- nunca de una venta con numero de serie.


-- ── 5 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.accesorios_tecnico_lista(text,text,integer,integer) FROM public;
GRANT EXECUTE ON FUNCTION public.accesorios_tecnico_lista(text,text,integer,integer) TO anon;
-- Los de `accesorios_tecnico_foto` viajan con la funcion, en
-- supabase_reparaciones.sql. Aqui darian error en una base donde ese archivo
-- no se haya pegado todavia: no se pueden dar permisos sobre lo que no existe,
-- y el pegado moriria a mitad por una linea que no hace falta.


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) Que tecnicos hay y con que clave (se dan de alta desde Admin):
--       select nombre, clave, activo from public.tecnicos_acceso where store_id='1217';
--
--  2) Con clave buena devuelve filas y SIN columna de vendedor:
--       select * from public.accesorios_tecnico_lista('1217','<la clave del tecnico>');
--
--  3) LO QUE HAY QUE COMPROBAR — con clave mala, CERO filas:
--       select count(*) from public.accesorios_tecnico_lista('1217','inventada');
--
--  4) Y que la clave no abre fotos que no son de accesorios. Coge un captura_id
--     de una venta de EQUIPO (tabla `ventas`) y pidelo:
--       select public.accesorios_tecnico_foto('1217','<la clave del tecnico>','<id de ventas>');
--     Tiene que responder «esa foto no es de un accesorio».
--
--  5) Retirar a un tecnico:
--       update public.tecnicos_acceso set activo=false where nombre='Tecnico Mr Fix 1';
--
-- ============================================================
--  Odemas · Grupo Gigante — uso interno HES 1217
-- ============================================================


-- ============================================================
--  ── 6 · Darlos de alta desde Admin (20-ago-2026) ──────────
-- ============================================================
--
--  Estas TRES si piden el gas_token: las usa el gerente desde Admin, no el
--  tecnico. La clave del tecnico no sirve aqui, y el token del gerente no
--  sirve para consultar las ventas — cada uno abre lo suyo.

-- La clave la genera la BASE, no el navegador. Escrita a mano acabaria siendo
-- «mrfix1» o el nombre de la tienda; aqui sale aleatoria y no se puede adivinar.
CREATE OR REPLACE FUNCTION public.tecnico_guardar(
  p_store text, p_token text, p_nombre text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $fn$
DECLARE v_clave text;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_nombre),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'falta el nombre');
  END IF;

  v_clave := 'mrfix-' || p_store || '-' ||
             substr(md5(random()::text || clock_timestamp()::text), 1, 12);

  INSERT INTO public.tecnicos_acceso (store_id, nombre, clave)
  VALUES (p_store, trim(p_nombre), v_clave);

  -- La clave se devuelve UNA vez, al crearla: es lo que hay que darle al
  -- tecnico. Despues se puede volver a ver en la lista, porque quien entra a
  -- Admin ya puede leerla de la tabla igual — esconderla seria teatro.
  RETURN jsonb_build_object('ok', true, 'clave', v_clave);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 120));
END $fn$;

CREATE OR REPLACE FUNCTION public.tecnicos_lista(p_store text, p_token text)
RETURNS TABLE (id bigint, nombre text, clave text, activo boolean,
               ultimo_acceso timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT t.id, t.nombre, t.clave, t.activo, t.ultimo_acceso
      FROM public.tecnicos_acceso t
     WHERE t.store_id = p_store
     ORDER BY t.activo DESC, t.nombre;
END $fn$;

-- ── 6-bis · El gerente le pone la clave (24-ago-2026) ───────
--
-- Hasta ahora la clave la inventaba `tecnico_guardar` y el gerente solo podia
-- copiarla. Una clave que nadie elige es una clave que se acaba apuntando en un
-- papel pegado al mostrador, y encima no se puede cambiar cuando un tecnico
-- deja de venir.
--
-- ⚠️ ESTA PANTALLA ES PUBLICA. `accesorios_tecnico.html` esta en internet y
-- cualquiera puede probar claves contra ella: no hay sesion, ni correo, ni
-- segundo factor. Por eso el minimo son 8 caracteres y no un PIN de 4 —10.000
-- combinaciones se prueban en un rato— y por eso se rechazan las obvias.
-- Quien entre con una clave adivinada ve las ventas de la tienda y las fotos de
-- los tickets.
CREATE OR REPLACE FUNCTION public.tecnico_clave_poner(
  p_store text, p_token text, p_id bigint, p_clave text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE v_clave text; v_nombre text;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;

  -- Se recortan los espacios de los extremos: el que dicta la clave por
  -- telefono y el que la teclea no ven los espacios, y una clave con uno
  -- delante no entra nunca sin decir por que.
  v_clave := trim(coalesce(p_clave, ''));

  IF length(v_clave) < 8 THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'La clave necesita al menos 8 caracteres. Esta pantalla esta abierta en '
      'internet y una corta se adivina probando.');
  END IF;
  IF v_clave ~ '\s' THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'Sin espacios: no se ven al dictarla ni al teclearla.');
  END IF;
  -- Todo digitos es un PIN por mucho que sean 8: son solo 100 millones de
  -- combinaciones y se prueban solas.
  IF v_clave ~ '^[0-9]+$' THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'Solo numeros no vale. Mezcla letras: un numero de 8 cifras se prueba entero.');
  END IF;
  -- Ni el numero de tienda ni la palabra de siempre.
  IF lower(v_clave) IN ('12345678','contrasena','password','mrfix1217','angelopolis')
     OR lower(v_clave) LIKE '%' || lower(p_store) || '%' AND length(v_clave) < 12 THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'Esa es de las primeras que probaria cualquiera. Pon otra.');
  END IF;

  -- Dos tecnicos con la misma clave harian imposible saber quien entro, que es
  -- justo para lo que sirve `ultimo_acceso`. Lo frena el UNIQUE, pero el error
  -- de Postgres no se le puede enseñar a nadie.
  IF EXISTS (SELECT 1 FROM public.tecnicos_acceso t
              WHERE t.store_id = p_store AND t.clave = v_clave AND t.id <> p_id) THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'Esa clave ya es la de otro tecnico. Cada uno la suya, o no se sabe quien entro.');
  END IF;

  UPDATE public.tecnicos_acceso
     SET clave = v_clave
   WHERE store_id = p_store AND id = p_id
   RETURNING nombre INTO v_nombre;

  IF v_nombre IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ese tecnico no existe en esta tienda');
  END IF;
  RETURN jsonb_build_object('ok', true, 'nombre', v_nombre);
END $fn$;


CREATE OR REPLACE FUNCTION public.tecnico_baja(
  p_store text, p_token text, p_id bigint, p_activo boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  /* Se da de baja, NO se borra: la fila guarda el ultimo acceso, y borrarla
     tira la unica pista de si esa clave llego a usarse y hasta cuando. */
  UPDATE public.tecnicos_acceso SET activo = coalesce(p_activo, false)
   WHERE store_id = p_store AND id = p_id;
  RETURN jsonb_build_object('ok', true);
END $fn$;

REVOKE ALL ON FUNCTION public.tecnico_guardar(text,text,text)              FROM public;
REVOKE ALL ON FUNCTION public.tecnicos_lista(text,text)                    FROM public;
REVOKE ALL ON FUNCTION public.tecnico_baja(text,text,bigint,boolean)       FROM public;
REVOKE ALL ON FUNCTION public.tecnico_clave_poner(text,text,bigint,text)   FROM public;
GRANT EXECUTE ON FUNCTION public.tecnico_clave_poner(text,text,bigint,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tecnico_guardar(text,text,text)            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tecnicos_lista(text,text)                  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tecnico_baja(text,text,bigint,boolean)     TO anon, authenticated;

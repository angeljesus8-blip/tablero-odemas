-- ============================================================
--  EL EQUIPO SE VE Y SE ADMINISTRA CON EL NUMERO DE EMPLEADO
--  ...y el responsable de las ventas deja de escribirse a mano
-- ============================================================
--
--  DOS COSAS QUE SALIERON DE LA MISMA PANTALLA (2-sep-2026)
--
--  1 · Admin -> Equipo se veia VACIA para quien entra con su numero, aunque
--      tuviera el permiso puesto. La lista se leia directo de `empleados`, y su
--      RLS pide `auth.uid()`: sin sesion de correo devuelve cero filas. No es
--      un caso raro —es el subgerente, que no tiene el correo de la tienda— y
--      lo que veia era «no hay nadie dado de alta» con tres personas dentro.
--
--  2 · La pestaña Config se quedo con UN campo: el nombre de quien puede abrir
--      «Ventas del dia», escrito a mano y comparado letra por letra contra la
--      lista del equipo. El mismo defecto que se acaba de quitar de los
--      vendedores, en pequeño: una tilde y esa persona no ve el boton, sin que
--      nada avise. Aqui pasa a ser una marca en su ficha.
--
--  Va DESPUES de supabase_hoja_auth.sql: recrea los dos logins.


-- ── 1 · La marca, en la ficha de la persona ─────────────────
ALTER TABLE public.empleados
  ADD COLUMN IF NOT EXISTS ventas_dia boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.empleados.ventas_dia IS
  'Puede abrir «Ventas del dia» en Captura de Series. Gerente y subgerente '
  'entran siempre por su puesto, sin necesidad de esta marca.';


/* De donde sale `hoja_auth` a partir de ahora.

   `tiendas.hoja_auth` se queda como PUENTE, igual que `tiendas.vendedores`: si
   nadie tiene la marca, se usa el texto de antes. Sin eso, la tienda que ya lo
   tenia configurado se queda sin ese boton el dia que se pegue esto. */
CREATE OR REPLACE FUNCTION public.hoja_auth_de_(p_store text)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT e.nombre FROM public.empleados e
      WHERE e.store_id = p_store AND e.activo = true AND e.ventas_dia = true
      ORDER BY e.nombre LIMIT 1),
    (SELECT t.hoja_auth FROM public.tiendas t WHERE t.store_id = p_store));
$$;

REVOKE ALL ON FUNCTION public.hoja_auth_de_(text) FROM public, anon, authenticated;


-- ── 2 · Los logins, con la marca en vez del texto ───────────
-- No cambia lo que devuelven —los mismos campos, en el mismo orden—, solo de
-- donde sale `hoja_auth`. Por eso basta CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION public.login_asesor(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               vendedores jsonb, gas_token text,
               hoja_auth text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad,
         public.vendedores_de_(t.store_id), t.gas_token,
         public.hoja_auth_de_(t.store_id)
  FROM public.tiendas t
  WHERE coalesce(t.activo, true) = true
    AND length(coalesce(p_pin,'')) >= 4
    AND p_pin = coalesce(nullif(t.asesor_pin, ''), t.store_id)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.login_empleado(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               vendedores jsonb,
               emp_no text, emp_nombre text, emp_puesto text, emp_admin boolean,
               gas_token text, hoja_auth text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad,
         public.vendedores_de_(t.store_id),
         e.empno, e.nombre, e.puesto, e.admin,
         t.gas_token, public.hoja_auth_de_(t.store_id)
  FROM public.empleados e
  JOIN public.tiendas  t ON t.store_id = e.store_id
  WHERE e.activo = true
    AND coalesce(t.activo, true) = true
    AND length(coalesce(p_pin,'')) >= 4
    AND e.empno = p_pin
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.login_asesor(text)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.login_empleado(text) TO anon, authenticated;


-- ── 3 · Ver el equipo con el numero ─────────────────────────
/* Dos llaves, no una: el token de la tienda (que solo entrega el login) Y que
   quien pregunta tenga el permiso de Admin. Con una sola bastaria adivinar un
   numero de empleado —son cortos y casi consecutivos— para leerse la lista
   entera con los numeros de todos, que son las llaves de entrada.

   NO devuelve `email` ni `user_id`: eso es de la administracion de cuentas, que
   sigue pidiendo sesion de gerente. Aqui se ve quien es quien y sus permisos. */
CREATE OR REPLACE FUNCTION public.equipo_lista(p_store text, p_token text, p_quien text)
RETURNS TABLE (id bigint, empno text, nombre text, puesto text,
               activo boolean, admin boolean, ventas_dia boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT e.id, e.empno, e.nombre, e.puesto, e.activo, e.admin, e.ventas_dia
    FROM public.empleados e
   WHERE e.store_id = p_store
     AND public.escritura_ok_(p_store, p_token)
     -- POR NOMBRE, no por posicion: la firma real es (p_store_id, p_empno) y
     -- llamarla al reves NO da error —devuelve false— o sea que el permiso se
     -- niega en silencio y la lista sale vacia como si no hubiera nadie. Paso
     -- el 2-sep-2026 y costo media hora de buscar en el sitio equivocado.
     AND public.puede_admin(p_store_id => p_store, p_empno => p_quien)
   ORDER BY e.activo DESC, e.nombre;
$$;

REVOKE ALL ON FUNCTION public.equipo_lista(text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.equipo_lista(text,text,text) TO anon, authenticated;


-- ── 4 · Marcar permisos con el numero ───────────────────────
/* Cambia UNA marca de UNA persona. Los tres campos que admite son los tres que
   se pueden repartir sin crear una llave nueva: `admin`, `ventas_dia` y
   `activo`. Dar de ALTA a alguien sigue pidiendo sesion de gerente, y es a
   proposito: un alta es un numero nuevo que abre la app, no un permiso sobre
   alguien que ya esta dentro.

   Las dos reglas que no pueden vivir solo en la pantalla, porque ahi se saltan
   con la consola abierta:
     · no quitarse el ultimo acceso a Admin —la tienda se quedaria sin quien
       reparta permisos, y arreglarlo necesitaria SQL—;
     · no darse a uno mismo, que es como un permiso se convierte en todos. */
CREATE OR REPLACE FUNCTION public.empleado_permiso(
  p_store text, p_token text, p_quien text,
  p_id bigint, p_campo text, p_valor boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE v_obj record; v_admins int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin permiso de escritura');
  END IF;
  -- Por nombre, por lo mismo que en `equipo_lista`: al reves niega en silencio.
  IF NOT public.puede_admin(p_store_id => p_store, p_empno => p_quien) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no administras esta tienda');
  END IF;
  IF p_campo NOT IN ('admin', 'ventas_dia', 'activo') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'campo no permitido: ' || coalesce(p_campo,'(vacío)'));
  END IF;

  SELECT * INTO v_obj FROM public.empleados
   WHERE id = p_id AND store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'esa persona no es de esta tienda');
  END IF;

  IF v_obj.empno = p_quien AND p_campo IN ('admin','activo') AND p_valor = false THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'no puedes quitarte a ti mismo ese acceso; que lo haga otra persona con Admin');
  END IF;

  IF p_campo IN ('admin','activo') AND p_valor = false THEN
    SELECT count(*) INTO v_admins FROM public.empleados
     WHERE store_id = p_store AND admin = true AND activo = true;
    IF v_admins <= 1 AND v_obj.admin AND v_obj.activo THEN
      RETURN jsonb_build_object('ok', false,
        'error', 'es el último acceso a Admin de la tienda: da Admin a alguien más antes de quitárselo');
    END IF;
  END IF;

  IF    p_campo = 'admin'      THEN UPDATE public.empleados SET admin      = p_valor WHERE id = p_id;
  ELSIF p_campo = 'ventas_dia' THEN UPDATE public.empleados SET ventas_dia = p_valor WHERE id = p_id;
  ELSE                              UPDATE public.empleados SET activo     = p_valor WHERE id = p_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'campo', p_campo, 'valor', p_valor,
                            'quien', v_obj.nombre);
END $fn$;

REVOKE ALL ON FUNCTION public.empleado_permiso(text,text,text,bigint,text,boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.empleado_permiso(text,text,text,bigint,text,boolean)
  TO anon, authenticated;


-- ── 5 · El que ya estaba escrito a mano, a su ficha ─────────
/* Una sola vez: quien figure en `tiendas.hoja_auth` y este en el equipo, se
   queda con la marca. Asi la tienda que ya lo tenia configurado no pierde el
   boton, y a partir de aqui se administra desde la ficha. Si el nombre no casa
   letra por letra —que es justo el problema que esto viene a quitar— no marca a
   nadie y el puente de `hoja_auth_de_` lo sigue cubriendo. */
UPDATE public.empleados e
   SET ventas_dia = true
  FROM public.tiendas t
 WHERE t.store_id = e.store_id
   AND coalesce(t.hoja_auth,'') <> ''
   AND e.nombre = t.hoja_auth
   AND e.activo = true
   AND e.ventas_dia = false;


-- ── 6 · Comprobar ───────────────────────────────────────────
-- Quien puede abrir «Ventas del día» en cada tienda, y de dónde sale el dato.
SELECT t.store_id,
       public.hoja_auth_de_(t.store_id) AS responsable,
       EXISTS (SELECT 1 FROM public.empleados e
                WHERE e.store_id = t.store_id AND e.activo AND e.ventas_dia)
         AS ya_sale_de_su_ficha
  FROM public.tiendas t ORDER BY t.store_id;

-- `ya_sale_de_su_ficha` en false significa que esa tienda sigue con el texto
-- viejo: nadie tiene la marca. Se arregla desde Admin → Equipo, no aquí.

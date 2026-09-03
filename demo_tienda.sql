-- ============================================================
--  UNA TIENDA FICTICIA, PARA VER LA APP FUNCIONANDO
-- ============================================================
--
--  Crea la tienda 9999 y tres personas inventadas. Sirve para abrir la app y
--  ver como se comporta con datos dentro, sin tocar ninguna tienda de verdad.
--
--  POR QUE VA POR SQL Y NO POR LA APP: el alta normal (menu -> Registrar
--  tienda) crea ademas una CUENTA de Supabase, con su correo y su confirmacion.
--  Para mirar la app eso sobra. El SQL Editor escribe saltandose la RLS, asi
--  que aqui la tienda puede nacer sin dueno.
--
--  LO QUE NO PODRA HACER esta tienda, justo por no tener dueno:
--    · abrir Admin con sesion de gerente (correo y contrasena);
--    · usar «✉️ Poner correo» del equipo.
--  Admin SI se abre con el numero de la persona que abajo lleva `admin=true`.
--
--  Todo lo demas —tablero, captura, comisiones, horarios— funciona igual que en
--  una tienda de verdad, porque la app no distingue: mira `store_id`.
--
--  ⚠️ Los datos de aqui son inventados. No pongas nombres ni numeros reales en
--  una tienda de prueba: acaban en la misma tabla que los de verdad.


-- ── 1 · La tienda ───────────────────────────────────────────
-- `gas_token` NO se escribe: lo genera la base sola (32 hex). El PIN de asesor
-- se deja en el numero de tienda, que es como entra el equipo el primer dia.
INSERT INTO public.tiendas (store_id, nombre, ciudad, vendedores, admin_pin, asesor_pin)
VALUES ('9999', 'Tienda Demo', 'Puebla',
        '["Ana Ramírez Solís","Luis Ortega Vidal","Elena Navarro Gálvez"]'::jsonb,
        '9999', '9999')
ON CONFLICT (store_id) DO UPDATE
  SET nombre     = excluded.nombre,
      ciudad     = excluded.ciudad,
      vendedores = excluded.vendedores;

-- Quien puede abrir «Ventas del dia» en Captura. Tiene que coincidir LETRA POR
-- LETRA con un nombre de la lista de arriba, o el boton no sale y nada avisa.
UPDATE public.tiendas SET hoja_auth = 'Ana Ramírez Solís' WHERE store_id = '9999';


-- ── 2 · Tres personas, con numeros que no existen ───────────
-- El puesto no es decorativo: de el sale el permiso de corregir ventas
-- (`puede_gestionar_`), que es lo que enseña el ✏️ en «Ventas del dia».
INSERT INTO public.empleados (store_id, empno, nombre, puesto, admin) VALUES
  ('9999', '100001', 'Elena Navarro Gálvez', 'Gerente de Tienda',    true),
  ('9999', '100002', 'Luis Ortega Vidal',    'Subgerente de Tienda', false),
  ('9999', '100003', 'Ana Ramírez Solís',    'Asesor de Tienda',     false)
ON CONFLICT (store_id, empno) DO UPDATE
  SET nombre = excluded.nombre,
      puesto = excluded.puesto,
      admin  = excluded.admin;


-- ── 3 · La clave de escritura, para poder llenarla ──────────
-- Sin este token no se puede cargar nada: las 15 funciones que escriben lo
-- exigen. Copiala de aqui.
SELECT store_id, nombre, asesor_pin AS pin_para_entrar, gas_token AS clave_de_escritura
  FROM public.tiendas WHERE store_id = '9999';


/* ============================================================
   PARA BORRARLA DESPUES
   ============================================================
   Se lleva TODO lo suyo —ventas, apartados, catalogo, promos— porque las diez
   tablas cuelgan de `tiendas.store_id` con ON DELETE CASCADE. Por eso basta una
   linea, y por eso conviene mirar dos veces el numero antes de correrla:

     DELETE FROM public.tiendas WHERE store_id = '9999';

   Los empleados se van con ella. Si algun dia la tienda 9999 fuera una tienda
   de verdad, cambia el numero de esta demo antes de crearla.
   ============================================================ */

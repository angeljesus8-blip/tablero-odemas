-- ============================================================
--  EXPORTAR AL EXCEL REGIONAL DE COMISIONES
--  18-ago-2026
-- ============================================================
--
--  El reporte es `Registro_Ventas_MrFix_Odemas_2026.xlsx` en SharePoint: 128
--  hojas (tienda x mes). La de la tienda este mes es «1217 AGOS 26» — agosto
--  va ABREVIADO, y ese detalle basta para pegar en la hoja equivocada.
--
--  ------------------------------------------------------------
--  LA HOJA ESTA PROTEGIDA Y SOLO 7 COLUMNAS SE PUEDEN ESCRIBIR
--  ------------------------------------------------------------
--  Leido del archivo, no supuesto:
--
--    B  DIA                     <- se escribe (numero del dia: 1, 2, 3...)
--    C  TIENDA                     formula  =IF($G6="","",1217)
--    D  # TICKET                <- se escribe
--    E  SKU                     <- se escribe
--    F  NOMBRE DEL PRODUCTO     <- se escribe
--    G  CANTIDAD                <- se escribe
--    H  PRECIO UNITARIO         <- se escribe
--    I  PRECIO SIN IVA             formula  =$H6/1.16
--    J  TOTAL                      formula  =$H6*$G6
--    K  TOTAL S/IVA                formula  =$I6*$G6
--    L  COMISION                   formula  =$K6*0.03
--    M  PUESTO                     formula  INDEX/MATCH sobre el equipo
--    N  NOMBRE DEL EMPLEADO     <- se escribe
--
--  Los datos empiezan en la FILA 6 (los titulos estan en la 5).
--
--  ------------------------------------------------------------
--  EL NOMBRE TIENE QUE COINCIDIR LETRA POR LETRA
--  ------------------------------------------------------------
--  La columna M no se escribe: la deduce una formula que BUSCA el nombre del
--  empleado en la lista del equipo (P:Q). Si no coincide exacto, el puesto sale
--  vacio y la comision no se suma a nadie — sin dar ningun error.
--
--  Y no coincide sola. En el Excel los nombres van APELLIDOS primero, en
--  mayusculas y sin acentos, y encima alguno esta escrito distinto:
--
--    en la app                     en el Excel
--    Ana Ramirez solis        ->   RAMIREZ SOLIS ANA        (solis/SOLIS)
--    Luis de Jesus Ortega V.  ->   ORTEGA VIDAL LUIS DE JESUS
--
--  Por eso el mapeo es EXPLICITO por numero de empleado. Convertirlo con una
--  regla («voltea apellidos y quita acentos») acertaria hoy y fallaria el dia
--  que entre alguien con dos nombres o un apellido compuesto, y ese fallo se
--  ve un mes despues, cuando la region revisa.
--
--  Se pega completo en el SQL Editor. Es idempotente.
--
--  ⚠️ Y DESPUES se pega `_privado/mapeo_nombres.sql`, que trae los nombres de
--  verdad. Sin el, la columna queda NULL y el reporte marca TODAS las ventas
--  con `sin_nombre` — que es correcto: sin mapeo, ninguna comision se sumaria.
-- ============================================================


-- ── 1 · El nombre tal como lo espera el reporte ─────────────
ALTER TABLE public.empleados ADD COLUMN IF NOT EXISTS nombre_reporte text;

COMMENT ON COLUMN public.empleados.nombre_reporte IS
  'El nombre EXACTO que lleva el Excel regional de comisiones (APELLIDOS '
  'NOMBRE, mayusculas, sin acentos). Si no coincide letra por letra, la '
  'formula del PUESTO no lo encuentra y la comision no se suma a nadie.';

/* Los cinco nombres NO estan aqui: este repo es publico y los llevo escritos
   desde el 18-ago hasta el 28-ago-2026. Viven en `_privado/mapeo_nombres.sql`,
   que el .gitignore deja fuera, y se pega justo despues de este archivo.

   La forma es esta, con los datos de verdad en lugar de los de ejemplo:

     UPDATE public.empleados SET nombre_reporte = v.n
       FROM (VALUES ('<empno>','APELLIDOS NOMBRE'),
                    ('<empno>','APELLIDOS NOMBRE')) AS v(e, n)
      WHERE empleados.store_id = '1217' AND empleados.empno = v.e;

   Se dejo fuera el mapeo y no la columna a proposito: la estructura no
   identifica a nadie, y quien lea este archivo tiene que poder entender como
   funciona el reporte sin abrir nada privado. */


/* Sin la extension `unaccent` instalada: quita los acentos a mano. Hace falta
   porque la app guarda «Angel de Jesus» con acentos y la tabla de empleados
   tambien, pero no siempre igual escritos. */
CREATE OR REPLACE FUNCTION public.unaccent_(t text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT translate(coalesce(t,''),
                   'áéíóúüñÁÉÍÓÚÜÑ',
                   'aeiouunAEIOUUN');
$$;


-- ── 2 · Las filas listas para pegar ─────────────────────────
--
-- Devuelve exactamente lo que va en cada columna escribible, en el orden del
-- Excel. Sin formulas y sin las columnas bloqueadas: pegarlas encima falla
-- porque la hoja esta protegida.
--
-- `sin_nombre` avisa de las ventas cuyo vendedor no tiene nombre de reporte.
-- Se devuelven IGUAL, con el nombre de la app, para que se vean y se puedan
-- arreglar — esconderlas seria entregar el reporte corto sin saberlo.
/* DROP antes del CREATE. `CREATE OR REPLACE` NO puede cambiar el tipo de
   retorno, y el 24-ago-2026 se le anadieron `captura_id` y `tiene_foto` al
   RETURNS TABLE: sin esto el pegado muere con
   `42P13: cannot change return type of existing function` y el archivo deja de
   ser idempotente justo el dia que hay que repegarlo.

   Los GRANT del final del archivo son los que lo hacen seguro: un DROP se lleva
   los permisos por delante, y una funcion sin GRANT existe pero no la puede
   llamar nadie — la pantalla diria «sin permiso» con todo bien puesto. */
DROP FUNCTION IF EXISTS public.accesorios_reporte(text,integer,integer);

CREATE OR REPLACE FUNCTION public.accesorios_reporte(
  p_store text,
  p_anio  integer DEFAULT NULL,
  p_mes   integer DEFAULT NULL
) RETURNS TABLE (
  dia integer, ticket text, sku text, producto text,
  cantidad integer, precio numeric, empleado text, sin_nombre boolean,
  -- Para abrir el ticket desde el reporte (24-ago-2026). Van AL FINAL y el
  -- generador del Excel mapea por nombre de campo, no por posicion, asi que no
  -- se mueve ninguna columna del pegado.
  captura_id text, tiene_foto boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH r AS (
    SELECT coalesce(p_anio, extract(year  from (now() AT TIME ZONE 'America/Mexico_City'))::int) AS a,
           coalesce(p_mes,  extract(month from (now() AT TIME ZONE 'America/Mexico_City'))::int) AS m
  )
  SELECT extract(day from v.dia)::int,
         v.ticket, v.sku, v.producto, v.cantidad, v.precio,
         coalesce(e.nombre_reporte, v.vendedor),
         (e.nombre_reporte IS NULL),
         v.captura_id,
         EXISTS (SELECT 1 FROM public.venta_fotos vf
                  WHERE vf.store_id = v.store_id AND vf.captura_id = v.captura_id)
  /* CROSS JOIN explicito y DESPUES del LEFT JOIN. Con `FROM v, r LEFT JOIN e`
     el join se asocia a `r`, no a `v`, y Postgres responde «invalid reference
     to FROM-clause entry for table v». */
  FROM public.accesorios_ventas v
  -- Por nombre y no por empno: `vendedor` guarda a quien ATENDIO, que puede no
  -- ser quien capturo. Es el mismo criterio que el ticket.
  LEFT JOIN public.empleados e
         ON e.store_id = v.store_id
        AND upper(unaccent_(e.nombre)) = upper(unaccent_(v.vendedor))
  CROSS JOIN r
  WHERE v.store_id = p_store
    AND extract(year  from v.dia)::int = r.a
    AND extract(month from v.dia)::int = r.m
  ORDER BY v.dia, v.vendida_en;
$$;

REVOKE ALL ON FUNCTION public.accesorios_reporte(text,integer,integer) FROM public;
GRANT EXECUTE ON FUNCTION public.accesorios_reporte(text,integer,integer) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) Que los cinco tengan nombre de reporte. Si alguno sale vacio, su
--     comision no se sumaria en el Excel:
--       select empno, nombre, nombre_reporte from public.empleados
--        where store_id='1217' order by activo desc, nombre;
--
--  2) El reporte del mes en curso:
--       select * from public.accesorios_reporte('1217');
--
--  3) LO QUE HAY QUE MIRAR: ninguna fila con sin_nombre = true.
--       select count(*) from public.accesorios_reporte('1217') where sin_nombre;
--     Si sale mayor que cero, esas ventas entrarian al Excel con un nombre que
--     la formula del PUESTO no reconoce, y su comision no se sumaria a nadie.
--
-- ============================================================
--  Odemas · Grupo Gigante — uso interno HES 1217
-- ============================================================

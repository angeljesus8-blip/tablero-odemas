-- ============================================================
-- HES Red — mover el tablero de Google Sheets a Supabase
-- Esquema base. NO correr completo de un jalón: ver el plan al final.
-- 1-ago-2026
-- ============================================================
--
-- Por qué
-- -------
-- Hoy cada tienda necesita su propia hoja de Google Y su propio proyecto de
-- Apps Script, con su URL pegada a mano en Admin (campo gas_url). Montar una
-- tienda son cuatro pasos manuales, y cada corrección de código obliga a
-- redesplegar en TODAS. Con diez tiendas eso no se sostiene.
--
-- Además, tres cosas que rompieron esta semana son del producto, no del código:
--   · Sheets convierte texto en fechas solo — dejó 117 promos invisibles.
--   · Apps Script descarta llamadas encimadas RESPONDIENDO 200: por eso el
--     tablero trae una cola con 1.5 s de separación. Con 30 asesores no aguanta.
--   · No hay constraints: nada impide apartar 37 piezas de un cupo de 36.
--
-- Regla de este diseño: TODA tabla lleva store_id. Cada gerente sube sus
-- documentos y sus datos quedan en su tienda; nadie ve ni pisa los de otra.
--
-- Lo que NO cambia: el flujo de trabajo del gerente. Sigue subiendo su Excel
-- de Sonar, su CEA y sus comisiones, desde las mismas pantallas.
-- ============================================================


-- ── Ayudas ──────────────────────────────────────────────────
-- admin_de(store_id) ya existe (dueño de la tienda o empleado con admin=true).
-- Se reutiliza tal cual para no inventar un modelo de permisos nuevo.

CREATE OR REPLACE FUNCTION public.toca_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;


-- ── 1 · CATÁLOGO (del Informe de Artículos Totales) ─────────
-- Reemplaza las hojas Catalogo y Catalogo_ref.

CREATE TABLE IF NOT EXISTS public.catalogo (
  store_id    text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku         text        NOT NULL,
  descripcion text        NOT NULL DEFAULT '',
  upc         text,
  precio      numeric(12,2),
  -- Catalogo_ref conserva SKUs que ya no vienen en el Excel: son los agotados
  -- que el cliente sigue pidiendo y se traen de otra tienda.
  vigente     boolean     NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, sku)
);

-- ── 2 · INVENTARIO (On Hand + exhibición) ───────────────────
CREATE TABLE IF NOT EXISTS public.inventario (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku        text        NOT NULL,
  onhand     integer     NOT NULL DEFAULT 0 CHECK (onhand >= 0),
  exhibicion integer     NOT NULL DEFAULT 0 CHECK (exhibicion >= 0),
  -- Corte propio de exhibición: NO se reinicia con el On Hand diario, para que
  -- una pieza vendida no reaparezca al día siguiente.
  exh_vendida integer    NOT NULL DEFAULT 0 CHECK (exh_vendida >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, sku)
);

-- ── 3 · PROMOCIONES (del CEA) ───────────────────────────────
-- d1/d2 son DATE de verdad: se acabó el "2026-08-01" contra "Sat Aug 01 2026".
CREATE TABLE IF NOT EXISTS public.promos (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku        text        NOT NULL,
  producto   text        NOT NULL DEFAULT '',
  precio_reg numeric(12,2),
  precio_pro numeric(12,2),
  estatus    text,
  msi        text,
  vigente_desde date,
  vigente_hasta date     NOT NULL,   -- obligatoria: sin fecha no hay promo
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, sku),
  CONSTRAINT promo_menor_que_regular CHECK (precio_pro IS NULL OR precio_reg IS NULL OR precio_pro < precio_reg),
  CONSTRAINT vigencia_coherente CHECK (vigente_desde IS NULL OR vigente_desde <= vigente_hasta)
);
CREATE INDEX IF NOT EXISTS promos_vigentes ON public.promos (store_id, vigente_hasta);

-- ── 4 · EOL, COMBOS Y AVISOS ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.eol (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku        text        NOT NULL,
  precio     numeric(12,2),
  pausado    boolean     NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, sku)
);

CREATE TABLE IF NOT EXISTS public.bundles (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  nombre     text        NOT NULL,
  skus       text[]      NOT NULL,          -- array de verdad, no "a,b,c"
  precio     numeric(12,2) NOT NULL,
  vigente_desde date,
  vigente_hasta date     NOT NULL,
  activo     boolean     NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.avisos (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  titulo     text        NOT NULL,
  detalle    text,
  prioridad  text        NOT NULL DEFAULT 'normal',
  vigente_hasta date,
  creado_en  timestamptz NOT NULL DEFAULT now()
);

-- ── 5 · VENTAS (lo que captura el asesor) ───────────────────
CREATE TABLE IF NOT EXISTS public.ventas (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  vendida_en timestamptz NOT NULL DEFAULT now(),
  serie      text        NOT NULL,
  sku        text        NOT NULL,
  descripcion text,
  precio     numeric(12,2),
  vendedor   text        NOT NULL,
  con_seguro boolean,                        -- NULL = ventas viejas sin dato
  foto_url   text,
  UNIQUE (store_id, serie)                   -- una serie no se vende dos veces
);
CREATE INDEX IF NOT EXISTS ventas_del_dia ON public.ventas (store_id, vendida_en DESC);

-- ── 6 · APARTADOS (preventa) ────────────────────────────────
-- El cupo se respeta en la base, no en el navegador: dos asesores apartando
-- a la vez ya no pueden pasarse del límite.
CREATE TABLE IF NOT EXISTS public.preventa_cupo (
  store_id  text    NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku       text    NOT NULL,
  cupo      integer NOT NULL CHECK (cupo >= 0),
  PRIMARY KEY (store_id, sku)
);

CREATE TABLE IF NOT EXISTS public.apartados (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku        text        NOT NULL,
  cliente    text        NOT NULL,
  telefono   text,
  piezas     integer     NOT NULL DEFAULT 1 CHECK (piezas > 0),
  con_seguro boolean     NOT NULL DEFAULT false,
  estatus    text        NOT NULL DEFAULT 'Apartado',
  vendedor   text,
  creado_en  timestamptz NOT NULL DEFAULT now(),

  /* 31-ago-2026 · Las ocho de abajo estaban en la base de la tienda de origen
     y NO aquí, igual que le pasó a `tiendas.vendedores`. Tres de ellas
     —color, precio, transaccion— no las creaba ningún archivo: se añadieron a
     mano en el panel y el `create table` nunca se actualizó, así que la tabla
     versionada llevaba meses sin describir la tabla de verdad.

     Las otras cinco sí se añaden más abajo (preventa_series, apartados_traspaso)
     pero DESPUÉS de que `inventario_vivo` las use, y una función `LANGUAGE sql`
     se valida al crearse: el pegado moría en «column a.venta_id does not
     exist», con la base a medio montar.

     Declararlas aquí no rompe nada donde ya existen —este CREATE es IF NOT
     EXISTS y los ALTER de más abajo son IF NOT EXISTS— y quita la dependencia
     de orden, que es la que no se ve venir. */
  color       text,         -- el producto entero, tal como se apartó
  precio      numeric(12,2),
  transaccion text,         -- ticket del POS: el enlace con la venta

  serie         text,       -- la pieza concreta, al asignarla del embarque
  asignado_en   timestamptz,
  entregado_en  timestamptz,
  entregado_por text,       -- quien la entregó, que no siempre es el vendedor
  venta_id      bigint      -- la venta que la entregó; sin ella se contaría dos veces
);

-- Y las mismas como ALTER, por la misma razón que en supabase_00_tiendas.sql:
-- donde `apartados` ya existe —la tienda de origen, o un pegado que se cortó a
-- la mitad— el CREATE de arriba no hace nada y las columnas seguirían faltando.
ALTER TABLE public.apartados
  ADD COLUMN IF NOT EXISTS color         text,
  ADD COLUMN IF NOT EXISTS precio        numeric(12,2),
  ADD COLUMN IF NOT EXISTS transaccion   text,
  ADD COLUMN IF NOT EXISTS serie         text,
  ADD COLUMN IF NOT EXISTS asignado_en   timestamptz,
  ADD COLUMN IF NOT EXISTS entregado_en  timestamptz,
  ADD COLUMN IF NOT EXISTS entregado_por text,
  ADD COLUMN IF NOT EXISTS venta_id      bigint;

CREATE OR REPLACE FUNCTION public.apartado_cabe()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE tope integer; usado integer;
BEGIN
  SELECT cupo INTO tope FROM public.preventa_cupo
   WHERE store_id = NEW.store_id AND sku = NEW.sku;
  IF tope IS NULL THEN RETURN NEW; END IF;   -- sin cupo definido, sin límite
  SELECT coalesce(sum(piezas),0) INTO usado FROM public.apartados
   WHERE store_id = NEW.store_id AND sku = NEW.sku
     AND estatus <> 'Cancelado' AND id <> coalesce(NEW.id, -1);
  IF usado + NEW.piezas > tope THEN
    RAISE EXCEPTION 'Cupo agotado: % de % piezas ya apartadas', usado, tope;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS apartado_cabe_trg ON public.apartados;
CREATE TRIGGER apartado_cabe_trg BEFORE INSERT OR UPDATE ON public.apartados
  FOR EACH ROW EXECUTE FUNCTION public.apartado_cabe();

-- ── 7 · COMISIONES ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.comisiones (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  empno      text        NOT NULL,
  nombre     text        NOT NULL,
  puesto     text,
  venta      numeric(14,2),
  ppto_pct   numeric(6,2),
  alcance    numeric(6,2),
  gar_pct    numeric(6,2),
  gar_pzas   integer,
  gar_elegible integer,
  gar_monto  numeric(12,2),
  periodo    text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, empno)
);
-- Ojo: alcance y gar_pct SÍ pueden pasar de 100 (ventana de 30 días para
-- comprar el seguro), así que aquí NO va un CHECK <= 100.


-- ── 8 · RLS — cada tienda ve solo lo suyo ───────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['catalogo','inventario','promos','eol','bundles',
                           'avisos','ventas','preventa_cupo','apartados','comisiones']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t||'_admin', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated
         USING (public.admin_de(store_id)) WITH CHECK (public.admin_de(store_id))',
      t||'_admin', t);
  END LOOP;
END $$;

-- El asesor entra por PIN, no con cuenta de Supabase, así que NO lee las tablas
-- directo: lo hace por funciones SECURITY DEFINER que validan su PIN, igual que
-- login_asesor. Se definen en el siguiente archivo para no alargar este.


-- ── 9 · updated_at automático ───────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['catalogo','inventario','promos','eol','bundles','comisiones']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_touch', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.toca_updated_at()',
                   t||'_touch', t);
  END LOOP;
END $$;


-- ============================================================
-- PLAN — por fases, sin apagar nada hasta que lo nuevo funcione
--
--  1. Correr este archivo. No toca nada de lo que hay: solo crea tablas
--     vacías. El tablero sigue leyendo del Apps Script.
--  2. Copiar los datos de hoy de las 10 hojas a estas tablas (838 filas en
--     total; un script lo hace en un rato).
--  3. Las funciones de lectura para el asesor (SECURITY DEFINER + PIN).
--  4. Las pantallas de carga escriben en LOS DOS lados un par de semanas.
--     Si algo sale mal, se apaga el nuevo y nadie se entera.
--  5. El tablero lee de Supabase, con el GAS como respaldo.
--  6. Se apaga el Apps Script. Y con él: la hoja por tienda, el despliegue
--     por tienda y el campo gas_url de Admin.
--
-- Montar una tienda nueva pasa de "crear hoja + crear script + desplegar +
-- pegar URL" a un INSERT en tiendas.
-- ============================================================

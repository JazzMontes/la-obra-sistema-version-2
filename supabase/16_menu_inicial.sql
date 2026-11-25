-- =====================================================================
-- La Obra v2 · 16 · Menú inicial de La Obra (datos para empezar)
-- Supabase → SQL Editor → New query → pegar → Run. Córrelo UNA vez (si lo vuelves a correr
-- no duplica nada: solo agrega lo que falte, buscando por nombre).
--
--  · 5 categorías y 15 productos con su precio y descripción del menú.
--  · 18 insumos con medidas caseras (cucharada, puño, lata…) para capturar recetas fácil.
--  · 2 preparaciones: "Carne de hamburguesa" y "Carne asada", cada una por 1 kg de carne.
--
-- Lo que queda pendiente de tu lado (desde la app, cuando quieras):
--  · Los costos salen de tus compras: registra una compra de cada insumo y la app calcula
--    cuánto te cuesta cada preparación y cada producto.
--  · En Productos → Componentes, di cuánta carne lleva cada producto (ej. el taco, la gringa).
--  · Las medidas caseras son aproximadas (ej. 1 cucharada de sal ≈ 18 g); ajústalas en Insumos.
-- =====================================================================

do $$
declare
  c record; p record; i record; u record; x record;
  v_cat int; v_input int; v_unit int; v_prep int;
begin
  -- ---------- Categorías ----------
  for c in select * from (values ('Hotdogs'), ('Boneless'), ('Garnachero'), ('Hamburguesas'), ('Papas fritas')) t(name) loop
    if not exists (select 1 from la_obra_v2.categories where lower(name) = lower(c.name)) then
      insert into la_obra_v2.categories(name) values (c.name);
    end if;
  end loop;

  -- ---------- Productos (precio del menú) ----------
  for p in select * from (values
    ('Hotdogs', 'Hotdog 3/8', 35, 'Salchicha de pavo, aderezos y tocino.'),
    ('Hotdogs', 'Hotdog 1/2', 60, 'Salchicha para asar con queso, aderezos y tocino.'),
    ('Hotdogs', 'Hotdog 3/4', 60, 'Salchicha de pavo, aderezos, boneless y salsa a elegir (BBQ, Búfalo o Mango habanero).'),
    ('Boneless', 'Boneless Carga 1', 130, '8 a 10 piezas con salsa a elegir (BBQ, Búfalo o Mango habanero), zanahoria, apio y aderezo ranch.'),
    ('Boneless', 'Boneless Carga 2', 190, '14 a 16 piezas con salsa a elegir (BBQ, Búfalo o Mango habanero), zanahoria, apio y aderezo ranch.'),
    ('Garnachero', 'Orden de tacos', 90, '5 tacos de asada, lechuga, limón, tomate y cebolla asada.'),
    ('Garnachero', 'Taco individual', 20, '1 taco de asada, lechuga, limón, tomate y cebolla asada.'),
    ('Garnachero', 'Gringa', 65, 'Asada, queso blanco, lechuga, limón, tomate y cebolla asada.'),
    ('Garnachero', 'Burro', 55, 'Asada, lechuga, limón, tomate y cebolla asada.'),
    ('Hamburguesas', 'Hamburguesa Chalán', 65, 'Carne de res al carbón, verduras, aderezos, jamón, queso amarillo y tocino.'),
    ('Hamburguesas', 'Hamburguesa Maistro', 75, 'Carne de res al carbón, verduras, aderezos, jamón, queso amarillo, tocino, salchicha y piña.'),
    ('Hamburguesas', 'Hamburguesa Inge', 80, 'Boneless, verduras, aderezos, queso blanco y salsa a elegir (BBQ, Búfalo o Mango habanero).'),
    ('Hamburguesas', 'Hamburguesa Patrón', 100, 'Carne de res al carbón, verduras, aderezos, jamón, tocino, salchicha para asar, piña y mezcla de quesos.'),
    ('Papas fritas', 'Papas Aligeradas', 55, 'Papas fritas clásicas con sal y aderezos.'),
    ('Papas fritas', 'Papas Macizas', 100, 'Papas fritas clásicas con sal, aderezos, boneless y salsa a elegir (BBQ, Búfalo o Mango habanero).')
  ) t(cat, name, price, descr) loop
    select id into v_cat from la_obra_v2.categories where lower(name) = lower(p.cat) order by id limit 1;
    if not exists (select 1 from la_obra_v2.products where lower(name) = lower(p.name)) then
      insert into la_obra_v2.products(name, description, category_id, type, price)
      values (p.name, p.descr, v_cat, 'prepared', p.price);
    end if;
  end loop;

  -- ---------- Insumos (unidad principal = la del inventario y del costo) ----------
  for i in select * from (values
    ('Carne molida de res 80/20', 'kg', 'kilo'),
    ('Carne para asar', 'kg', 'kilo'),
    ('Tomate', 'pieza', 'pieza'),
    ('Cebolla', 'pieza', 'pieza'),
    ('Cilantro', 'manojo', 'manojo'),
    ('Huevo', 'pieza', 'pieza'),
    ('Mostaza', 'g', 'frasco'),
    ('Sal', 'g', 'bolsa'),
    ('Pimienta', 'g', 'frasco'),
    ('Comino', 'g', 'frasco'),
    ('Ajo', 'diente', 'cabeza'),
    ('Knorr Suiza', 'cubo', 'caja'),
    ('Sazonador', 'g', 'frasco'),
    ('Harina', 'g', 'bolsa'),
    ('Pan molido', 'g', 'bolsa'),
    ('Cerveza', 'ml', 'lata'),
    ('Salsa Maggi o soya', 'ml', 'botella'),
    ('Limón', 'pieza', 'kilo')
  ) t(name, unit, ptype) loop
    if not exists (select 1 from la_obra_v2.inputs where lower(name) = lower(i.name)) then
      insert into la_obra_v2.inputs(name, unit, package_type, package_quantity) values (i.name, i.unit, i.ptype, 1);
    end if;
  end loop;

  -- Medidas caseras: "1 cucharada = 18 g" (aproximadas; se cambian en Insumos)
  for u in select * from (values
    ('Cilantro', 'puño', 0.25),
    ('Cilantro', 'tercio', 0.333),
    ('Mostaza', 'cucharada', 15),
    ('Sal', 'cucharada', 18),
    ('Pimienta', 'cucharada', 7),
    ('Comino', 'cucharada', 6),
    ('Sazonador', 'cucharada', 8),
    ('Harina', 'puño', 40),
    ('Pan molido', 'puño', 35),
    ('Cerveza', 'lata', 355),
    ('Salsa Maggi o soya', 'cucharada', 15),
    ('Ajo', 'cabeza', 10)
  ) t(input, name, base) loop
    select id into v_input from la_obra_v2.inputs where lower(name) = lower(u.input) order by id limit 1;
    if v_input is not null and not exists (select 1 from la_obra_v2.input_units where input_id = v_input and lower(name) = lower(u.name)) then
      insert into la_obra_v2.input_units(input_id, name, unit_amount, base_amount) values (v_input, u.name, 1, u.base);
    end if;
  end loop;

  -- ---------- Preparaciones (por cada kilo de carne) ----------
  -- yield: lo que rinde, aproximado (marcado como estimado)
  for x in select * from (values
    ('Carne de hamburguesa', 'Receta por 1 kg de carne 80/20.', 1250, 'g'),
    ('Carne asada', 'Receta por 1 kg de carne para asar.', 1000, 'g')
  ) t(name, descr, yield, unit) loop
    if not exists (select 1 from la_obra_v2.preparations where lower(name) = lower(x.name)) then
      insert into la_obra_v2.preparations(name, description, yield_quantity, yield_unit, yield_estimated)
      values (x.name, x.descr, x.yield, x.unit, true);
    end if;
  end loop;

  -- Ingredientes: (preparación, insumo, cantidad en la medida, medida casera o null = unidad principal, ¿aproximado?)
  for x in select * from (values
    ('Carne de hamburguesa', 'Carne molida de res 80/20', 1, null, false),
    ('Carne de hamburguesa', 'Tomate', 1, null, false),
    ('Carne de hamburguesa', 'Cebolla', 0.5, null, false),
    ('Carne de hamburguesa', 'Cilantro', 1, 'puño', true),
    ('Carne de hamburguesa', 'Huevo', 2, null, false),
    ('Carne de hamburguesa', 'Mostaza', 1, 'cucharada', true),
    ('Carne de hamburguesa', 'Sal', 1, 'cucharada', true),
    ('Carne de hamburguesa', 'Pimienta', 1, 'cucharada', true),
    ('Carne de hamburguesa', 'Comino', 1, 'cucharada', true),
    ('Carne de hamburguesa', 'Ajo', 1, null, false),
    ('Carne de hamburguesa', 'Knorr Suiza', 1, null, false),
    ('Carne de hamburguesa', 'Sazonador', 1, 'cucharada', true),
    ('Carne de hamburguesa', 'Harina', 1, 'puño', true),
    ('Carne de hamburguesa', 'Pan molido', 1, 'puño', true),
    ('Carne asada', 'Carne para asar', 1, null, false),
    ('Carne asada', 'Cilantro', 1, 'tercio', true),
    ('Carne asada', 'Cebolla', 0.5, null, false),
    ('Carne asada', 'Ajo', 1, null, false),
    ('Carne asada', 'Cerveza', 0.5, 'lata', true),
    ('Carne asada', 'Pimienta', 1, 'cucharada', true),
    ('Carne asada', 'Sal', 1, 'cucharada', true),
    ('Carne asada', 'Sazonador', 1, 'cucharada', true),
    ('Carne asada', 'Salsa Maggi o soya', 1, 'cucharada', true),
    ('Carne asada', 'Limón', 3, null, false)
  ) t(prep, input, qty, unit, est) loop
    select id into v_prep from la_obra_v2.preparations where lower(name) = lower(x.prep) order by id limit 1;
    select id into v_input from la_obra_v2.inputs where lower(name) = lower(x.input) order by id limit 1;
    v_unit := null;
    if x.unit is not null then
      select id into v_unit from la_obra_v2.input_units where input_id = v_input and lower(name) = lower(x.unit) limit 1;
    end if;
    if not exists (select 1 from la_obra_v2.preparation_inputs where preparation_id = v_prep and input_id = v_input) then
      insert into la_obra_v2.preparation_inputs(preparation_id, input_id, quantity, is_estimated, unit_id, unit_quantity)
      values (v_prep, v_input,
              x.qty * coalesce((select base_amount / unit_amount from la_obra_v2.input_units where id = v_unit), 1),
              x.est, v_unit, case when v_unit is not null then x.qty end);
    end if;
  end loop;
end $$;

select (select count(*) from la_obra_v2.products) as productos,
       (select count(*) from la_obra_v2.inputs) as insumos,
       (select count(*) from la_obra_v2.preparations) as preparaciones;

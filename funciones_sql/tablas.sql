DROP TABLE IF EXISTS 
    detalle_ventas,
    ventas,
    pedidos_insumos,
    pagos_insumos,
    pago_sueldos,
    pagos_servicios,
    movimientos,
    calculo_sueldo_neto,
    registro_mensual_empleados,
    registro_horas,
    registro_servicios,
    detalle_perdida,
    perdidas,
    motivo_perdida,
    stock_locales,
    lotes_stock,
    insumo_proveedor,
    ingredientes_platos,
    detalle_mesas_combinadas,
    mesas_combinadas,
    mesas,
    menu,
    subcategorias_menu,
    categorias_menu,
    insumos,
    vacaciones_empleado,
    bonificaciones_empleado,
    descuentos_empleado,
    documentos_empleado,
    empleados,
    turnos_trabajo,
    sueldo_por_pais,
    puestos_trabajo,
    areas_trabajo,
    niveles_accesibilidad,
    servicio_proveedor,
    servicios,
    proveedores,
    feriados_paises,
    parametros,
    clientes,
    historial_cuentas_propias,
    cuentas_propias,
    cuentas,
    entidades,
    locales,
    clase_movimiento,
    formas_pago,
    tipos_caja,
    monedas,
    paises
CASCADE;

CREATE TABLE parametros ( -- esta tabla contiene parámetros que serán útilies para el armado de funciones 
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parametro VARCHAR(50),
    valor_parámetro DECIMAL(10,2),
    monto_multiplicador DECIMAL(10,2),
    descripcion TEXT
);
INSERT INTO
  parametros (parametro,valor_parámetro ,monto_multiplicador, descripcion)
VALUES
  ('feriado',null, 2.0, 'multiplicador sobre las horas laborales de un dia si es feriado (se suma al sueldo neto)'),
  ('vacaciones_trabajadas',null, 1.0, 'multiplicador sobre las horas laborales de un dia si es feriado (se suma al sueldo neto)'),
  ('tardanzas mayor o igual a 15', 15 ,1.0, 'multiplicador sobre las horas laborales de un dia hubo una tardanza mayor o igual a 15min (se resta al sueldo neto)'),
  ('ausencia no justificada',null, 1.0, 'multiplicador sobre las horas laborales de un que hubo una ausencia sin justificacion (se resta al sueldo neto)');

CREATE TABLE monedas (
    id_moneda BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    moneda VARCHAR(50),
    conversion_USD DECIMAL(10,4),
    descripcion TEXT
);
INSERT INTO monedas (moneda,conversion_USD,descripcion) VALUES
    ('USD',1.0000,'dolar');

CREATE TABLE paises ( -- paises con los que tiene contacto el negocio 
    id_pais BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(50) UNIQUE NOT NULL,
    id_moneda INT NOT NULL,
    aporte_seguridad_social_empleado DECIMAL(10,4),
    aporte_seguridad_social_empleador DECIMAL(10,4),
    nro_horas_mensuales INT, 
--    dias_vacaciones_anuales INTEGER,
    decimo_tercero BOOLEAN,
    decimo_cuarto BOOLEAN,
    usa_fondos_reserva BOOLEAN,
    mes_pago_decimo_tercero INT,
    mes_pago_decimo_cuarto INT,
    FOREIGN KEY (id_moneda) REFERENCES monedas(id_moneda)
        ON DELETE CASCADE
        ON UPDATE CASCADE     
);

INSERT INTO paises (nombre, id_moneda, aporte_seguridad_social_empleado, aporte_seguridad_social_empleador, nro_horas_mensuales, decimo_tercero, decimo_cuarto, usa_fondos_reserva, mes_pago_decimo_tercero, mes_pago_decimo_cuarto) VALUES
('ecuador', 1 ,0.0945, 0.1115, 240, True, True, True, 12, 8);

CREATE TABLE feriados_paises (
    id_feriado BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_pais INT NOT NULL,
    fecha DATE NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    tipo VARCHAR(50), -- nacional, regional, observancia
    region VARCHAR(100), -- nullable, para regionales como Quito
    FOREIGN KEY (id_pais) REFERENCES paises(id_pais)
        ON DELETE CASCADE
        ON UPDATE CASCADE 
);
INSERT INTO feriados_paises (id_pais, fecha, nombre, tipo, region) VALUES
(1,'2000-01-01', 'Año Nuevo', 'nacional', NULL),
(1,'2000-03-03', 'Carnaval (Lunes)', 'nacional', NULL),
(1,'2000-03-04', 'Carnaval (Martes)', 'nacional', NULL),
(1,'2000-04-17', 'Jueves Santo', 'nacional', NULL),
(1,'2000-04-18', 'Viernes Santo', 'nacional', NULL),
(1,'2000-04-20', 'Domingo de Pascua', 'observancia', NULL),
(1,'2000-05-01', 'Día del Trabajo', 'nacional', NULL),
(1,'2000-05-02', 'Día libre por Día del Trabajo', 'nacional', NULL),
(1,'2000-05-23', 'Batalla de Pichincha (día compensatorio)', 'nacional', NULL),
(1,'2000-05-24', 'Batalla de Pichincha (original)', 'nacional', NULL),
(1,'2000-07-24', 'Natalicio de Simón Bolívar', 'observancia', NULL),
(1,'2000-08-10', 'Primer Grito de Independencia', 'nacional', NULL),
(1,'2000-08-11', 'Día libre por Independencia', 'nacional', NULL),
(1,'2000-10-09', 'Independencia de Guayaquil', 'nacional', NULL),
(1,'2000-10-10', 'Día libre por Independencia de Guayaquil', 'nacional', NULL),
(1,'2000-11-02', 'Día de los Difuntos', 'nacional', NULL),
(1,'2000-11-03', 'Independencia de Cuenca', 'nacional', NULL),
(1,'2000-11-04', 'Día libre por Día de los Difuntos', 'nacional', NULL),
(1,'2000-12-05', 'Fundación de Quito (compensatorio)', 'regional', 'Quito'),
(1,'2000-12-06', 'Fundación de Quito', 'regional', 'Quito'),
(1,'2000-12-25', 'Navidad', 'nacional', NULL),
(1,'2000-12-31', 'Despedida de Año', 'observancia', NULL);


CREATE TABLE proveedores ( -- Aquí van tanto los proveedores de insumos como los de servicios 
    id_proveedor BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- identificador del provedor
	nombre VARCHAR(50) NOT NULL,
    id_pais INT NOT NULL,
    ciudad VARCHAR(50),
    direccion VARCHAR(50),
    id_moneda_pago INT NOT NULL,
    nro_cuenta INT, -- CBU de la cuenta bancaria del proveedor 
    descripcion TEXT, 
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_pais) REFERENCES paises(id_pais)
        ON DELETE SET NULL
        ON UPDATE CASCADE, 
    FOREIGN KEY (id_moneda_pago) REFERENCES monedas(id_moneda)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

CREATE TABLE servicios ( -- en esta tabla se presentan los distintos servicios que contrata el negocio 
	id_servicio BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- identificador del servicio 
	servicio VARCHAR(50) NOT NULL -- nombre del servicio, por ejemplo, luz, gas, wifi, etc
);

CREATE TABLE servicio_proveedor ( -- Relaciona el proveedor con el servicio
    id_prov_serv BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- id único para el par (id_proveedor , id_servicio)
    id_servicio INT NOT NULL,
    id_proveedor INT NOT NULL,
    id_moneda INT NOT NULL,
    precio_unitario DECIMAL(10,2) NOT NULL, -- precio de la unidad de cada servicio 
    unidad_de_medida VARCHAR(50) NOT NULL, -- unidad de medida en la que se mide el consumo del servicio
    unidad DECIMAL(10,2) NOT NULL, --  cantidad de unidades para el precio unitario
    FOREIGN KEY (id_servicio) REFERENCES servicios(id_servicio)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE niveles_accesibilidad( -- en esta tabla están los distintos niveles de accesibilidad y una descripcion de cada uno 
    nivel_accesibilidad INT NOT NULL, -- nivel de accesibilidad a la página web 
    descripcion TEXT, 
    PRIMARY KEY (nivel_accesibilidad)
);

CREATE TABLE areas_trabajo ( -- en esta tabla se presentan las areas de trabajo dentro del negocio 
    id_area BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    area VARCHAR(50) NOT NULL -- nombre del area de trabajo 
);

CREATE TABLE puestos_trabajo ( -- en esta tabla se presentan los puestos de trabajo dentro de cada area 
    id_puesto BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_area INT,
    puesto VARCHAR(50) NOT NULL, -- puesto de trabajo 
    FOREIGN KEY (id_area) REFERENCES areas_trabajo(id_area)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE sueldo_por_pais(
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_pais INT NOT NULL,
    id_area INT NOT NULL,
    id_puesto INT NOT NULL,
    id_moneda INT NOT NULL,
    sueldo_bruto DECIMAL(10,2),
    precio_hora DECIMAL(10,2), -- precio de la hora para ese puesto
    FOREIGN KEY (id_puesto) REFERENCES puestos_trabajo(id_puesto)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (id_pais) REFERENCES paises(id_pais)
        ON DELETE CASCADE
        ON UPDATE CASCADE        
);

CREATE TABLE locales ( -- EN esta tabla se presentan los distintos locales o sucursales del negocio
    id_local BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_pais INT NOT NULL,
    provincia VARCHAR(50),
    ciudad VARCHAR(50),
    direccion VARCHAR(50),  -- calle y número
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_pais) REFERENCES paises(id_pais)
);
INSERT INTO locales (id_pais) VALUES (1);

CREATE TABLE turnos_trabajo (
    id_turno BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(50),  -- mañana, tarde, noche
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL,
    descripcion TEXT
);

CREATE TABLE empleados ( -- Tabla con los empleados del negocio 
	id_empleado BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    cedula VARCHAR(50) UNIQUE,
    telefono VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(50) NOT NULL,
    id_pais INT NOT NULL,
    ciudad VARCHAR(50),
--    direccion VARCHAR(50) NOT NULL,
--    piso INT, --piso en el caso de que viva en un departamento (no obligatorio)
--    departamento VARCHAR(50), -- departamento en el que vive 
    nro_cuenta INT NOT NULL UNIQUE, -- CBU de la cuanta bancaria
    tipo_contrato VARCHAR(50),
    empleado_informal BOOLEAN DEFAULT FALSE, 
    fecha_ingreso DATE NOT NULL,
    fecha_salida DATE,
    id_local INT, -- local en el que trabaja el empleado
    id_turno INT, -- turno en el que trabaja el empleado 
    id_area INT, -- area en la que trabaja 
    id_puesto INT, -- puesto de trabajo
    afiliado_seguridad_social BOOLEAN DEFAULT TRUE,
    numero_seguridad_social VARCHAR(30),
    mensualizacion_decimo_tercero BOOLEAN DEFAULT FALSE,
    mensualizacion_decimo_cuarto BOOLEAN DEFAULT FALSE,
    estado_laboral VARCHAR(50) DEFAULT 'activo', -- activo | vacaciones | suspendido | liquidado
    nivel_accesibilidad INT, -- nivel de accesibilidad que posee
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_pais) REFERENCES paises(id_pais), 
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (id_turno) REFERENCES turnos_trabajo(id_turno)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (nivel_accesibilidad) REFERENCES niveles_accesibilidad(nivel_accesibilidad)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (id_puesto) REFERENCES puestos_trabajo(id_puesto)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

CREATE TABLE documentos_empleado ( -- aquí figuran todos los documentos importantes del empleado
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_empleado INT NOT NULL,
    tipo_documento VARCHAR(50), -- cedula, certificado_medico, antecedentes_penales, contrato_firmado
    archivo_url TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
FOREIGN KEY (id_empleado) REFERENCES empleados(id_empleado)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE descuentos_empleado ( -- aquí se van agregando los descuentos correspondietes al mes para cada empleado
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE DEFAULT CURRENT_DATE,
    id_local INT,
    id_empleado INT NOT NULL,
    tipo VARCHAR(50), -- uniforme, préstamo, pérdida, otro
    motivo TEXT,
    id_moneda INT NOT NULL,
    monto NUMERIC(10,2),
FOREIGN KEY (id_empleado) REFERENCES empleados(id_empleado)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE bonificaciones_empleado ( -- aquí se van agregando las bonificaciones correspondietes al mes para cada empleado
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE DEFAULT CURRENT_DATE,
    id_local INT,
    id_empleado INT NOT NULL,
    tipo VARCHAR(50), -- horas extras, vacaciones trabajadas, feriado trabajado ,bono productividad, propina, otro
    motivo TEXT,
    id_moneda INT NOT NULL,
    monto NUMERIC(10,2),
FOREIGN KEY (id_empleado) REFERENCES empleados(id_empleado)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE vacaciones_empleado ( -- aquí figura el comienzo y el fin de las vacaciones de cada empleado 
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_empleado INT NOT NULL,
    fecha_inicio DATE,
    fecha_fin DATE,
FOREIGN KEY (id_empleado) REFERENCES empleados(id_empleado)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE insumos ( -- tabla con los insumos que utiliza el negocio
	id_insumo BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- identificador del insumo
	insumo VARCHAR(50) NOT NULL -- nombre del insumo
);

CREATE TABLE categorias_menu ( -- categorías de los productos del menú, por ejemplo, entradas, pizzas, bebidas 
    id_categoria BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    categoria VARCHAR(50) NOT NULL,
    descripcion TEXT
);

CREATE TABLE subcategorias_menu ( -- subcategorias de cada categoría de los productos del menú, por ejemplo, bebidas alcoholicas y bebidas sin alcohol 
    id_categoria INT,
    id_subcategoria BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subcategoria VARCHAR(50) NOT NULL,
    descripcion TEXT,
    FOREIGN KEY (id_categoria) REFERENCES categorias_menu(id_categoria)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE menu (
    id_local INT,
	id_producto BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- identificador del plato/bebida
    nombre_producto VARCHAR(50) NOT NULL,
    id_categoria INT, -- categoría del menú en que se encuentra el plato/bebida
    id_subcategoria INT,
    detalles_preparado TEXT,
    id_moneda INT NOT NULL,
    monto DECIMAL(10 , 2 ) NOT NULL, -- precio del plato/bebida
    disponible BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (id_subcategoria) REFERENCES subcategorias_menu(id_subcategoria)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

CREATE TABLE ingredientes_platos ( -- En esta tabla irían los ingredientes de cada plato 
    id_producto INT NOT NULL,
    id_insumo INT NOT NULL, -- ingredientes de cada producto
    unidad_medida VARCHAR(50) NOT NULL, -- unidad de medida del ingrediente 
    cantidad DECIMAL(10 , 2 ) NOT NULL, -- cantidad del ingrediente
    FOREIGN KEY (id_producto) REFERENCES menu(id_producto)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (id_insumo) REFERENCES insumos(id_insumo)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
CREATE INDEX id_producto ON ingredientes_platos(id_producto);

CREATE TABLE clientes ( -- tabla con los clientes registrados
	id_cliente BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- identificador del clientes
	nombre VARCHAR(50) NOT NULL, -- nombre del clientes
    nro_documento VARCHAR(50) NOT NULL UNIQUE, -- También puede ser el numero de pasaporte
    telefono VARCHAR(50) NOT NULL UNIQUE, -- número de teléfono
    correo VARCHAR(50) NOT NULL, -- correo electrónico
    id_pais_residencia INT NOT NULL,
    ciudad VARCHAR(50),
    direccion VARCHAR(50) NOT NULL, -- calle  y número,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_pais_residencia) REFERENCES paises(id_pais)
);

CREATE TABLE entidades ( -- tabla donde se encuentran las entidades para identificar a los propietarios de las cuentas bancarias 
    id_entidad BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- ID que identidica a la convinación de (tipo_indentidad , referencia_id)
    tipo_entidad VARCHAR(50) NOT NULL, -- empleado, proveedor, socio, otro
    referencia_id BIGINT NOT NULL -- ID real en su tabla específica
);

CREATE TABLE cuentas( -- cuentas bancarias propias, de empleados, de clientes, de proveedores, etc 
    nro_cuenta INT NOT NULL UNIQUE,
    tipo_cuenta VARCHAR(50) NOT NULL, --propia, cliente, empleado, proveedor, socio, otro
    id_entidad BIGINT NOT NULL,
    FOREIGN KEY (id_entidad) REFERENCES entidades(id_entidad)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    PRIMARY KEY (nro_cuenta)
);

CREATE TABLE cuentas_propias ( -- informacion de las cuentas propias  (DEBERIA AGREGARLE UN UPDATED AT)
    nro_cuenta INT NOT NULL PRIMARY KEY,
    propietario VARCHAR(50) NOT NULL, -- nombre del propietario de la cuenta 
    id_moneda INT NOT NULL,
    saldo DECIMAL(10 ,2) DEFAULT 0.0, -- este saldo debería irse modificando a medida que entra y sale plata 
    activa INT NOT NULL,   -- 1 (si) y 0 (no)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (nro_cuenta) REFERENCES cuentas(nro_cuenta)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);
CREATE INDEX nro_cuenta ON cuentas_propias(nro_cuenta);

CREATE TABLE registro_servicios ( -- tabla donde se registran los consumos periódicos de los servicios 
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- fecha y hora
	id_prov_serv INT NOT NULL, 
    id_local INT, -- local en el cual se hace el registro
    unidad_de_medida VARCHAR(50) NOT NULL, -- unidad de medida del servicio 
    consumo DECIMAL(10,2) NOT NULL, -- consunmo a registrar 
    costo DECIMAL(10,2) NOT NULL,
    id_moneda INT,
    PRIMARY KEY (id_prov_serv,fecha),
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (id_prov_serv) REFERENCES servicio_proveedor(id_prov_serv)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE registro_horas( -- en esta tabla figura un registro diario de cada empleado
    fecha DATE DEFAULT CURRENT_DATE,
    id_empleado INT NOT NULL,
    id_local INT, -- local en el que se hace el registro
    id_turno INT,
    hora_entrada TIME, -- debe rellenase con la hora con la que el empleado ingresó su entrada de forma automática, si no hubo entrada debe quedar como null
    hora_salida TIME, -- debe rellenase con la hora con la que el empleado ingresó su salida de forma automática, si no hubo salida debe quedar como null
    horas_extras TIME, -- horas extras de ese dia. Se calcula con la fórmula (hora_salida - fin_del_turno)
    mintos_tardanza TIME, -- minutos de tardanza de ese dia. Se calcula con la fórmula (hora_entrada - inicio_del_turno)
    dia_feriado BOOLEAN,
    ausencia BOOLEAN DEFAULT TRUE,
    justificacion_valida TEXT,
    dia_vacional BOOLEAN,
    id_moneda INT NOT NULL,
    sueldo_bruto_diario DECIMAL(10,2),
    descripcion TEXT,
    PRIMARY KEY (id_empleado,fecha),
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (id_empleado) REFERENCES empleados(id_empleado)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE registro_mensual_empleados ( -- registro mensual de cada empleado que recompila la informacion de los registros diarios  
    id_registro BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mes INT DEFAULT EXTRACT(MONTH FROM CURRENT_DATE), -- número del mes del año
    anio INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE), -- numero completo del año
    id_empleado INT NOT NULL, -- empleado al que se le hace la loquidación 
    id_local INT,
--    dias_laborales INT NOT NULL, -- número de horas que trabajó durante el mes de trabajo sin contar las horas extras
    horas_extras TIME, -- cantidad de horas extras que trabajó durante el período de liquidadión 
    dias_feriados INT NOT NULL, 
    dias_vacacionales INT NOT NULL,
    tardanzas_penalizadas INT NOT NULL, -- número de tadanzas durante el período de liquidación
    ausencias_justificadas INT NOT NULL DEFAULT 0, -- número deausencias durante el período de liquidación
    ausencias_no_justificadas INT NOT NULL DEFAULT 0, -- número deausencias durante el período de liquidación
    perdidas INT DEFAULT 0,
--    sueldo_bruto DECIMAL(10,2) NOT NULL DEFAULT 0.0,
--    moneda VARCHAR(50) NOT NULL,
    descripcion TEXT,
    FOREIGN KEY (id_empleado) REFERENCES empleados(id_empleado)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE calculo_sueldo_neto ( -- en esta tabla figura el cálculo del sueldo neto de cada empleado
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mes INT DEFAULT EXTRACT(MONTH FROM CURRENT_DATE), -- número del mes del año
    anio INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE), -- numero completo del año    
    id_empleado INT NOT NULL,
    id_local INT,
    id_moneda INT NOT NULL,
    sueldo_bruto DECIMAL(10,2),
    total_bonificaciones DECIMAL(10,2),
    total_descuentos DECIMAL(10,2),
    aporte_empleado DECIMAL(10,2),
    decimo_tercero DECIMAL(10,2), -- si en el empleado figura que lo tiene mensualizado le corresponde todos los meses, si no solo en la fecha correspondiente 
    decimo_cuarto DECIMAL(10,2), -- si en el empleado figura que lo tiene mensualizado le corresponde todos los meses, si no solo en la fecha correspondiente
    sueldo_neto DECIMAL(10,2),
    costo_total_para_empleador DECIMAL(10,2), -- sueldo_neto + sueldo_bruto*aporte_seguridad_social_empleador
    pendiente BOOLEAN DEFAULT TRUE,
        FOREIGN KEY (id_empleado) REFERENCES empleados(id_empleado)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE insumo_proveedor ( -- Relaciona el proveedor con el insumo
    cod_stock BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- id único para el par (id_proveedor , id_insumo)
    id_insumo INT NOT NULL,
    id_proveedor INT NOT NULL,
    unidades_por_pack DECIMAL(10,2) NOT NULL, -- cuantas unidades tiene el paquete vendido por el proveedor (ejemplo: 6 (copas), 12 (platos), 2 (litros), 1 (kg))
    unidad_de_medida VARCHAR(50) NOT NULL, -- unidad de medida de la unidad del insumo (ejemplo: copas, platos, litros, kg)
    id_moneda INT NOT NULL,
    precio_pack DECIMAL(10,2) NOT NULL, -- precio del paquete vendido por el proveedor
    precio_unitario DECIMAL(10,2) NOT NULL, -- precio_paquete/paquete
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_insumo) REFERENCES insumos(id_insumo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
        ON DELETE RESTRICT
        ON UPDATE CASCADE    
);

CREATE TABLE lotes_stock ( -- Stock de cada local
    cod_stock INT NOT NULL,
    id_local INT,
    lote VARCHAR(50),
    fecha_compra DATE NOT NULL, -- fecha de adquisición
    fecha_vencimiento DATE,
--    cantidad_minima INT NOT NULL,
    cantidad_unidades INT NOT NULL, -- esta cantidad debería ir modificándose
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (cod_stock,lote),
    FOREIGN KEY (cod_stock) REFERENCES insumo_proveedor(cod_stock)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE stock_locales (
    id_insumo INT NOT NULL,
    id_local INT NOT NULL,
    cantidad_minima INT,
    cantidad_unidades INT NOT NULL, -- esta cantidad debería ir modificándose y tener una cantidad mínima
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_insumo,id_local),
    FOREIGN KEY (id_insumo) REFERENCES insumos(id_insumo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE mesas (
    id_mesa BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_local INT NOT NULL,
    numero_mesa INT NOT NULL,  -- número visible al mozo
    capacidad INT NOT NULL,    -- personas sentadas
    nro_personas INT,
    ubicacion VARCHAR(100),    -- opcional: “terraza”, “salón”, “vip”
    activa BOOLEAN DEFAULT TRUE, -- si está disponible para asignar
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    UNIQUE (id_local, numero_mesa)
);

CREATE TABLE mesas_combinadas (
    id_mesa_combinada BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    id_local INT NOT NULL,
    creada_por INT, -- id_empleado que combinó las mesas (opcional)
    capacidad_total INT,
    activa BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE detalle_mesas_combinadas (
    id_mesa_combinada INT,
    id_mesa INT,
    PRIMARY KEY (id_mesa_combinada, id_mesa),
    FOREIGN KEY (id_mesa_combinada) REFERENCES mesas_combinadas(id_mesa_combinada)
        ON DELETE CASCADE,
    FOREIGN KEY (id_mesa) REFERENCES mesas(id_mesa)
        ON DELETE CASCADE
);

CREATE TABLE clase_movimiento (
    id_clase BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    clase VARCHAR(50) NOT NULL, -- pago de servicio, compra a proveedor, pago de sueldo, venta, transferencia interna,otros
    descripcion TEXT
);

INSERT INTO clase_movimiento(clase,descripcion) VALUES
    ('pago de servicio',NULL),
    ('compra a proveedor',NULL),
    ('pago de sueldo',NULL),
    ('venta',NULL),
    ('devolucion',NULL),
    ('transferencia interna',NULL),
    ('otros',NULL);

CREATE TABLE formas_pago (
    id_forma_pago BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    forma_pago VARCHAR(50) NOT NULL  -- efectivo, debito, credito, transferencia
);

INSERT INTO formas_pago(forma_pago) VALUES
    ('efectivo'),
    ('debito'),
    ('credito'),
    ('transferencia');

CREATE TABLE tipos_caja (
    id_tipo_caja BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_caja VARCHAR(50) NOT NULL -- caja chica, banco
);

INSERT INTO tipos_caja(tipo_caja) VALUES
    ('caja chica'),
    ('banco');


CREATE TABLE pagos_servicios (
    id_pago BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	id_prov_serv INT NOT NULL, -- identifica el par (proveedor, servicio)
    id_local INT,
    consumo DECIMAL(10,2) NOT NULL,
    unidad_de_medida VARCHAR(50) NOT NULL,
    id_moneda INT NOT NULL,
--    monto_deducido DECIMAL(10,2),
    monto DECIMAL(10,2) NOT NULL,
    nro_factura VARCHAR(50) NOT NULL,
    fecha_venc DATE NOT NULL, -- vencimiento de la factura 
    fecha_pago TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_prov_serv) REFERENCES servicio_proveedor(id_prov_serv)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
--    FOREIGN KEY (id_servicio) REFERENCES servicios(id_servicio)
);

CREATE TABLE pago_sueldos( -- La idea de esta tabla es que haga un recuento 
    id_pago BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_empleado INT NOT NULL,
    id_local INT,
    fecha_pago DATE NOT NULL,
    id_moneda INT NOT NULL,
    sueldo_neto DECIMAL(10,2) NOT NULL, -- sueldo neto mas aportes del empleador 
    costo_empleador DECIMAL(10,2) NOT NULL, --sueldo bruto del empleado + impuesto a empleador
    descripcion TEXT,
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_empleado) REFERENCES empleados(id_empleado)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);


CREATE TABLE pagos_insumos (
    id_pedido BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, --indentificador del pedido
    id_local INT NOT NULL,
    id_proveedor INT NOT NULL,
    id_forma_pago INT NOT NULL,
    id_moneda INT NOT NULL,
    monto_pedido DECIMAL(10,2), 
    monto_transporte DECIMAL(10,2) DEFAULT 0.0,
    monto_total DECIMAL(10,2) NOT NULL, -- monto_pedido + monto_transporte
    nro_factura VARCHAR(50) NOT NULL,
    fecha_entrada DATE, 
    fecha_pago TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_forma_pago) REFERENCES formas_pago(id_forma_pago)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE pedidos_insumos (
    id_pedido INT NOT NULL, --identificador del pedido
    id_insumo INT NOT NULL,
    fecha_vencimiento DATE, -- si es algo que no tiene vencimiento como un cubierto o aparato, será NULL
    cantidad_packs DECIMAL(10 , 2) NOT NULL, -- cantidad de packs comprados de ese cod_stock 
    unidades_por_pack DECIMAL(10 , 2) NOT NULL, -- cantidad de unidades del insumo en cada pack. Si se compra por unidad se pone un 1
    unidad_de_medida VARCHAR(50),
    id_moneda INT NOT NULL,
    monto DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (id_pedido) REFERENCES pagos_insumos(id_pedido)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_insumo) REFERENCES insumos(id_insumo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);


CREATE TABLE ventas (
  	id_venta BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- identificador de la venta
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
    id_local INT,
    id_turno INT,
    id_empleado INT, -- identificador del mozo
    id_cliente INT, -- identificador del cliente
    tipo_venta VARCHAR(50) NOT NULL, -- 'consumo en local', 'delivery', 'retira en local'
    id_mesa INT NOT NULL DEFAULT '0', -- mesa del pedido (0 significa que no fue un pedido en una mesa)
    id_mesa_combinada INT,
--    nro_personas INT NOT NULL, -- personas dentro del pedido
    servicio_mesa DECIMAL(10 , 2 ) NOT NULL, -- monto del servicio de mesa
    id_forma_pago INT,
    id_moneda INT NOT NULL,
    monto DECIMAL(10 ,2) NOT NULL,
    propina DECIMAL(10 ,2) DEFAULT 0.0, -- propina proporcionada por el cliente
    estado VARCHAR(50), -- en curso, cancelada, finalizada
    satisfaccion INT,
    comentario TEXT,
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_turno) REFERENCES turnos_trabajo(id_turno)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (id_forma_pago) REFERENCES formas_pago(id_forma_pago)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (id_empleado) REFERENCES empleados(id_empleado)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (id_moneda) REFERENCES monedas(id_moneda)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_mesa_combinada) REFERENCES mesas_combinadas(id_mesa_combinada)
        ON DELETE SET NULL
);

CREATE TABLE detalle_ventas (
    id_venta INT NOT NULL, 
    id_producto INT, 
    cantidad INT NOT NULL, 
    id_moneda INT NOT NULL,
    precio DECIMAL(10 , 2 ) NOT NULL, -- precio del producto
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_producto) REFERENCES menu(id_producto)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

CREATE TABLE motivo_perdida (
    id_motivo BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    motivo VARCHAR(50) NOT NULL,
    descripcion TEXT
);

INSERT INTO motivo_perdida(motivo, descripcion)
VALUES
    ('vencimiento', 'insumos que excedieron su fecha de caducidad'),
    ('rompimiento', 'rompimineto de algún elemento'),
    ('desecho', NULL),
    ('reemplazo',NULL);

CREATE TABLE perdidas (
	id_perdida BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE DEFAULT CURRENT_DATE,
    id_empleado_responable INT,
    id_local INT,
    id_motivo INT, -- vencimiento, rompimiento, desecho, reemplazo
    id_moneda INT NOT NULL,
    monto_total DECIMAL(10,2), 
    descripcion TEXT,
    FOREIGN KEY (id_motivo) REFERENCES motivo_perdida(id_motivo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (id_empleado_responable) REFERENCES empleados(id_empleado)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE detalle_perdida (
    id_perdida INT NOT NULL,
    id_insumo INT NOT NULL,
    cantidad_unidades DECIMAL(10,2) NOT NULL,
    unidad_medida VARCHAR(50),
    id_moneda INT NOT NULL,
    monto DECIMAL(10,2),
    FOREIGN KEY (id_perdida) REFERENCES perdidas(id_perdida)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_insumo) REFERENCES insumos(id_insumo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE movimientos (
	id_movimiento BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tabla INT NOT NULL,
    fecha DATE DEFAULT CURRENT_DATE,
    id_clase INT NOT NULL,
    id_local INT,
--    id_empleado_entrada INT, -- empleado que registró el movimiento
--    cuenta_salida INT, -- cuenta de la que sale la plata
--    cuenta_ingreso INT, -- cuenta en la que ingresa la plata
--    id_tipo_caja INT NOT NULL,
    id_forma_pago INT NOT NULL,
    id_moneda INT NOT NULL,
    monto DECIMAL(10 ,2),
    monto_dolares DECIMAL(10,2), 
    descripcion TEXT,
    FOREIGN KEY (id_clase) REFERENCES clase_movimiento(id_clase)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_local) REFERENCES locales(id_local)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_forma_pago) REFERENCES formas_pago(id_forma_pago)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (id_moneda) REFERENCES monedas(id_moneda)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE historial_cuentas_propias (
    id_historial BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nro_cuenta INT NOT NULL, -- cuenta propia 
    id_moneda INT NOT NULL,
    saldo DECIMAL(10, 2), -- saldo de la cuenta en la fecha
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- momento en el que se modificó el saldo de la cuenta 
    FOREIGN KEY (nro_cuenta) REFERENCES cuentas_propias(nro_cuenta)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

-- Áreas funcionales
INSERT INTO
  areas_trabajo (area)
VALUES
  ('Cocina'),
  ('Servicio'),
  ('Barra'),
  ('Gerencia'),
  ('Administración'),
  ('Limpieza'),
  ('Depósito'),
  ('Delivery');

-- Puestos de trabajo
INSERT INTO
  puestos_trabajo (id_area, puesto)
VALUES
  (1, 'Chef principal'),
  (1, 'Cocinero'),
  (1, 'Ayudante de cocina'),
  (2, 'Mozo'),
  (2, 'Jefe de salón'),
  (3, 'Bartender'),
  (3, 'Ayudante de barra'),
  (4, 'Gerente general'),
  (5, 'Contador'),
  (5, 'Recursos Humanos'),
  (6, 'Personal de limpieza'),
  (7, 'Encargado de stock'),
  (7, 'Repositor'),
  (8, 'Repartidor'),
  (8, 'Encargado de pedidos online');

CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE FUNCTION fn_normalizar_str(texto TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN trim(lower(unaccent(texto)));
END;
$$ LANGUAGE plpgsql;
-- migrate:up

-- =============================================================================
-- 1. EXTENSIONES NECESARIAS
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- 2. CATÁLOGOS MAESTROS DE IDENTIFICADORES
-- =============================================================================

CREATE TABLE cat_grado_academico (
    id INTEGER PRIMARY KEY,
    valor VARCHAR(20) UNIQUE NOT NULL
);
INSERT INTO cat_grado_academico (id, valor) VALUES
(1, 'Licenciatura'), (2, 'Maestría'), (3, 'Doctorado');

CREATE TABLE cat_estado_docente (
    id INTEGER PRIMARY KEY,
    codigo VARCHAR(10) UNIQUE NOT NULL,
    valor VARCHAR(30) UNIQUE NOT NULL,
    permite_asignacion BOOLEAN NOT NULL DEFAULT FALSE
);
INSERT INTO cat_estado_docente (id, codigo, valor, permite_asignacion) VALUES
(1, 'DISP', 'Disponible', TRUE),
(2, 'NODISP', 'No Disponible', FALSE),
(3, 'CONTR', 'En Contrato', FALSE),
(4, 'PEND', 'Pendiente', FALSE);

CREATE TABLE cat_disposicion_asignacion (
    id INTEGER PRIMARY KEY,
    codigo VARCHAR(15) UNIQUE NOT NULL,
    valor VARCHAR(40) UNIQUE NOT NULL
);
INSERT INTO cat_disposicion_asignacion (id, codigo, valor) VALUES
(10, 'VAC', 'Vacante'),
(11, 'ASIG', 'Asignado'),
(12, 'BLOQ_CONS', 'Bloqueado por Consecutividad'),
(13, 'BLOQ_EXC', 'Bloqueado con Excepción Pendiente'),
(14, 'CANC', 'Cancelado');

CREATE TABLE cat_estado_ejecucion (
    id INTEGER PRIMARY KEY,
    codigo VARCHAR(10) UNIQUE NOT NULL,
    valor VARCHAR(20) UNIQUE NOT NULL,
    impacto_nomina VARCHAR(30) NOT NULL
);
INSERT INTO cat_estado_ejecucion (id, codigo, valor, impacto_nomina) VALUES
(20, 'TERM', 'Terminada', 'Liquidación final'),
(21, 'CURS', 'Cursando', 'Dispersión periódica'),
(22, 'INIC', 'Por Iniciar', 'Solo anticipo si política lo permite'),
(23, 'SUSP', 'Suspendida', 'Bloquea pagos hasta resolución'),
(24, 'ANUL', 'Anulada', 'Revierte cualquier pago previo');

CREATE TABLE cat_resultado_validacion (
    id INTEGER PRIMARY KEY,
    codigo VARCHAR(15) UNIQUE NOT NULL,
    valor VARCHAR(30) UNIQUE NOT NULL,
    accion TEXT NOT NULL
);
INSERT INTO cat_resultado_validacion (id, codigo, valor, accion) VALUES
(30, 'APROB', 'Aprobado', 'Permite transición a PEND o CONTR'),
(31, 'BLQ_CONS', 'Bloqueado Consecutividad', 'Fuerza estado 2, rechaza asignación'),
(32, 'BLQ_EXC_APROB', 'Excepción Aprobada', 'Permite asignación con override'),
(33, 'BLQ_EXC_DENEG', 'Excepción Denegada', 'Mantiene bloqueo'),
(34, 'ERROR_DATOS', 'Error de Datos', 'Rechaza por inconsistencia');

CREATE TABLE cat_tipo_emergencia (
    id INTEGER PRIMARY KEY,
    codigo VARCHAR(15) UNIQUE NOT NULL,
    valor VARCHAR(30) UNIQUE NOT NULL,
    ejemplo TEXT
);
INSERT INTO cat_tipo_emergencia (id, codigo, valor, ejemplo) VALUES
(1, 'VAC_CRIT', 'Vacante Crítica', 'No hay otro docente disponible con la especialidad'),
(2, 'ESP_UNICA', 'Especialidad Única', 'Solo este docente domina el tema'),
(3, 'CONT_ADMIN', 'Continuidad Administrativa', 'Proceso académico en curso'),
(4, 'EMERG_INST', 'Emergencia Institucional', 'Situación excepcional aprobada por Rectoría');

CREATE TABLE cat_estado_asignacion_presupuesto (
    id INTEGER PRIMARY KEY,
    codigo VARCHAR(15) UNIQUE NOT NULL,
    valor VARCHAR(30) UNIQUE NOT NULL,
    equivalencia_disposicion INTEGER NOT NULL
);
INSERT INTO cat_estado_asignacion_presupuesto (id, codigo, valor, equivalencia_disposicion) VALUES
(40, 'VAC', 'Vacante', 10),
(41, 'CONT', 'Contratado', 11),
(42, 'PEND_APROB', 'Pendiente de Aprobación', 12),
(43, 'CANC', 'Cancelado', 14);

-- =============================================================================
-- USUARIOS DEL SISTEMA
-- Roles deben coincidir con los claims del JWT emitidos por Keycloak.
-- PostgREST asumirá este rol automáticamente al recibir el token.
-- =============================================================================
CREATE TABLE usuarios_sistema (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre_usuario VARCHAR(50) UNIQUE NOT NULL,
    rol VARCHAR(20) NOT NULL CHECK (rol IN ('ADMIN','GERENTE','RRHH','NOMINA','COORDINADOR','AUDITOR')),
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

-- =============================================================================
-- 3. TABLAS PRINCIPALES
-- =============================================================================

CREATE TABLE docentes_base (
    id_docente UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campus_centro VARCHAR(60) NOT NULL,
    programa_academico VARCHAR(100) NOT NULL,
    seccion_promocion VARCHAR(50),
    grado_catedratico_id INTEGER NOT NULL REFERENCES cat_grado_academico(id),
    nombre_completo VARCHAR(150) NOT NULL,
    dni VARCHAR(20) UNIQUE NOT NULL,
    cuenta_bancaria_encriptada VARCHAR(255),
    estado_id INTEGER NOT NULL DEFAULT 1 REFERENCES cat_estado_docente(id),
    ultimo_periodo_secuencia INTEGER,
    fecha_alta_sistema TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version_lock INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE asignaturas_periodos (
    id_asignacion UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    id_docente UUID REFERENCES docentes_base(id_docente),
    nombre_asignatura VARCHAR(120) NOT NULL,
    periodo_codigo VARCHAR(10) NOT NULL,
    periodo_secuencia INTEGER NOT NULL,
    disposicion_id INTEGER NOT NULL DEFAULT 10 REFERENCES cat_disposicion_asignacion(id),
    fecha_revision DATE,
    estado_clase_id INTEGER NOT NULL DEFAULT 22 REFERENCES cat_estado_ejecucion(id),
    observaciones_asignacion TEXT,
    observaciones_subsanacion TEXT
);

CREATE TABLE registro_excepciones_gerenciales (
    id_excepcion UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    id_docente UUID NOT NULL REFERENCES docentes_base(id_docente),
    id_asignacion UUID NOT NULL REFERENCES asignaturas_periodos(id_asignacion),
    periodo_secuencia_objetivo INTEGER NOT NULL,
    usuario_gerencial_id UUID NOT NULL REFERENCES usuarios_sistema(id),
    tipo_emergencia_id INTEGER NOT NULL REFERENCES cat_tipo_emergencia(id),
    justificacion_detallada TEXT NOT NULL CHECK (LENGTH(justificacion_detallada) >= 50),
    fecha_aprobacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_vencimiento TIMESTAMP,
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    hash_registro VARCHAR(64) NOT NULL
);

CREATE TABLE ejecucion_presupuestaria (
    id_ejecucion UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    id_asignacion UUID NOT NULL REFERENCES asignaturas_periodos(id_asignacion),
    ga VARCHAR(5) NOT NULL,
    ue VARCHAR(5) NOT NULL,
    prog VARCHAR(5) NOT NULL,
    sub_prog VARCHAR(5) NOT NULL,
    a_o VARCHAR(5) NOT NULL,
    fuente VARCHAR(5) NOT NULL,
    no_linea VARCHAR(10) NOT NULL,
    importe_mensual DECIMAL(10,2) NOT NULL CHECK (importe_mensual > 0),
    antiguedad_meses INTEGER NOT NULL DEFAULT 1 CHECK (antiguedad_meses >= 1),
    salario_mensual_bruto DECIMAL(10,2) GENERATED ALWAYS AS (importe_mensual * antiguedad_meses) STORED,
    total_salario_anual DECIMAL(12,2) GENERATED ALWAYS AS (importe_mensual * antiguedad_meses * 12) STORED,
    estado_actual_asignacion_id INTEGER NOT NULL REFERENCES cat_estado_asignacion_presupuesto(id),
    contrato_emitido DECIMAL(10,2) CHECK (contrato_emitido >= 0),
    diferencia DECIMAL(12,2) GENERATED ALWAYS AS (importe_mensual * antiguedad_meses * 12 - COALESCE(contrato_emitido, 0)) STORED,
    excedente_clase DECIMAL(12,2) GENERATED ALWAYS AS (importe_mensual * antiguedad_meses * 12 - COALESCE(contrato_emitido, 0)) STORED,
    pendiente_ejecutar DECIMAL(12,2) GENERATED ALWAYS AS (importe_mensual * antiguedad_meses * 12 - COALESCE(contrato_emitido, 0)) STORED,
    id_validacion_consecutividad INTEGER REFERENCES cat_resultado_validacion(id),
    excepcion_id UUID
);

ALTER TABLE ejecucion_presupuestaria
    ADD CONSTRAINT fk_ejecucion_excepcion
    FOREIGN KEY (excepcion_id) REFERENCES registro_excepciones_gerenciales(id_excepcion);

CREATE TABLE log_validacion_consecutividad (
    id_log UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    id_docente UUID NOT NULL REFERENCES docentes_base(id_docente),
    id_asignacion UUID NOT NULL REFERENCES asignaturas_periodos(id_asignacion),
    periodo_anterior_secuencia INTEGER NOT NULL,
    periodo_objetivo_secuencia INTEGER NOT NULL,
    resultado_validacion_id INTEGER NOT NULL REFERENCES cat_resultado_validacion(id),
    excepcion_aplicada BOOLEAN NOT NULL DEFAULT FALSE,
    justificacion_excepcion TEXT CHECK (LENGTH(justificacion_excepcion) > 50 OR excepcion_aplicada = FALSE),
    usuario_autorizador VARCHAR(50),
    timestamp_validacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_integridad VARCHAR(64) NOT NULL,
    ip_origen VARCHAR(45)
);

-- =============================================================================
-- 4. VISTAS
-- PostgREST expone estas vistas como endpoints REST.
-- =============================================================================

CREATE OR REPLACE VIEW vw_formato_base_docentes_completo AS
SELECT
    ROW_NUMBER() OVER (ORDER BY d.id_docente) AS "N°",
    d.campus_centro AS "Campus o Centro de Estudio",
    d.programa_academico AS "Programa Académico",
    d.seccion_promocion AS "Sección/ Promoción",
    cg.valor AS "Grado Académico del Catedrático",
    d.nombre_completo AS "Nombre del Catedrático",
    d.dni AS "N° de DNI",
    DECODE(d.cuenta_bancaria_encriptada, 'base64') AS "N° de Cta Bancaria",
    ap.nombre_asignatura AS "Nombre de la Asignatura",
    ep.contrato_emitido AS "Valor del contrato",
    ap.periodo_codigo AS "Periodo de la Asignatura",
    ap.fecha_revision AS "Fecha de Revisión",
    ap.observaciones_asignacion AS "Observaciones",
    ap.observaciones_subsanacion AS "Observaciones Subsanaciones",
    ced.valor AS "Estado Actual del Docente",
    cda.valor AS "Disposición de Asignación"
FROM docentes_base d
LEFT JOIN asignaturas_periodos ap ON d.id_docente = ap.id_docente
LEFT JOIN ejecucion_presupuestaria ep ON ap.id_asignacion = ep.id_asignacion
LEFT JOIN cat_grado_academico cg ON d.grado_catedratico_id = cg.id
LEFT JOIN cat_estado_docente ced ON d.estado_id = ced.id
LEFT JOIN cat_disposicion_asignacion cda ON ap.disposicion_id = cda.id;

CREATE OR REPLACE VIEW vw_control_ejecucion_presupuestaria_completo AS
SELECT
    ep.ga AS "GA",
    ep.ue AS "UE",
    ep.prog AS "Prog",
    ep.sub_prog AS "Sub Prog",
    ep.a_o AS "A/O",
    ep.fuente AS "Fuente",
    ep.no_linea AS "No.",
    ap.nombre_asignatura AS "Descripcion del Puesto- Asignatura",
    ceap.valor AS "Estado Actual",
    ep.importe_mensual AS "Importe Mensual",
    ep.antiguedad_meses AS "Antigüedad en meses",
    ep.salario_mensual_bruto AS "Salario Mensual Bruto",
    ep.total_salario_anual AS "Total Salario anual",
    ceap.valor AS "Estado Actual (contratado/pendiente)",
    d.nombre_completo AS "Docente",
    cee.valor AS "Estado de la Clase",
    ep.contrato_emitido AS "Contrato Emitido",
    ep.diferencia AS "Diferencia",
    ep.excedente_clase AS "Excedente por clase",
    ep.pendiente_ejecutar AS "Pendiente de Ejecutar",
    crv.valor AS "Validación Consecutividad",
    CASE WHEN ep.excepcion_id IS NOT NULL THEN 'SÍ' ELSE 'NO' END AS "Excepción Aplicada"
FROM ejecucion_presupuestaria ep
JOIN asignaturas_periodos ap ON ep.id_asignacion = ap.id_asignacion
JOIN cat_estado_asignacion_presupuesto ceap ON ep.estado_actual_asignacion_id = ceap.id
LEFT JOIN docentes_base d ON ap.id_docente = d.id_docente
LEFT JOIN cat_estado_ejecucion cee ON ap.estado_clase_id = cee.id
LEFT JOIN cat_resultado_validacion crv ON ep.id_validacion_consecutividad = crv.id;

-- =============================================================================
-- 5. ÍNDICES
-- =============================================================================

CREATE INDEX idx_docentes_estado_periodo ON docentes_base (estado_id, ultimo_periodo_secuencia);
CREATE INDEX idx_docentes_dni ON docentes_base (dni);
CREATE INDEX idx_asignaciones_docente_periodo ON asignaturas_periodos (id_docente, periodo_secuencia, disposicion_id);
CREATE INDEX idx_ejecucion_presupuesto ON ejecucion_presupuestaria (ga, ue, prog, sub_prog, a_o, fuente);
CREATE INDEX idx_ejecucion_calculos ON ejecucion_presupuestaria (id_asignacion, contrato_emitido);
CREATE INDEX idx_log_auditoria ON log_validacion_consecutividad (id_docente, timestamp_validacion, hash_integridad);
CREATE INDEX idx_excepciones_vigentes ON registro_excepciones_gerenciales (id_docente, periodo_secuencia_objetivo, activa);

-- =============================================================================
-- 6. FUNCIONES Y TRIGGERS
-- =============================================================================

-- Genera hash SHA-256 de una fila JSONB para auditoría inmutable
CREATE OR REPLACE FUNCTION generar_sha256(fila JSONB) RETURNS VARCHAR(64) AS $$
BEGIN
    RETURN encode(digest(fila::text::bytea, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql;

-- Valida la regla de descanso obligatorio por consecutividad y registra en log de auditoría.
-- Disparado en INSERT/UPDATE de asignaturas_periodos.
-- Si el docente ya fue contratado en el periodo inmediatamente anterior y no tiene
-- excepción gerencial vigente, bloquea la asignación y lanza EXCEPTION (HTTP 400 via PostgREST).
CREATE OR REPLACE FUNCTION validar_consecutividad_y_auditar() RETURNS TRIGGER AS $$
DECLARE
    ultimo_seq INTEGER;
    objetivo_seq INTEGER;
    excepcion_vigente UUID;
BEGIN
    IF TG_TABLE_NAME = 'asignaturas_periodos' AND NEW.id_docente IS NOT NULL THEN
        SELECT ultimo_periodo_secuencia INTO ultimo_seq
        FROM docentes_base WHERE id_docente = NEW.id_docente;
        objetivo_seq := NEW.periodo_secuencia;

        IF ultimo_seq IS NOT NULL AND objetivo_seq = ultimo_seq + 1 THEN
            -- Periodo consecutivo: verificar excepción gerencial vigente
            SELECT id_excepcion INTO excepcion_vigente
            FROM registro_excepciones_gerenciales
            WHERE id_docente = NEW.id_docente
              AND periodo_secuencia_objetivo = objetivo_seq
              AND activa = TRUE
            LIMIT 1;

            IF excepcion_vigente IS NOT NULL THEN
                NEW.disposicion_id := 11; -- ASIG
                UPDATE ejecucion_presupuestaria
                    SET id_validacion_consecutividad = 32, excepcion_id = excepcion_vigente
                    WHERE id_asignacion = NEW.id_asignacion;
                INSERT INTO log_validacion_consecutividad
                    (id_docente, id_asignacion, periodo_anterior_secuencia, periodo_objetivo_secuencia,
                     resultado_validacion_id, excepcion_aplicada, justificacion_excepcion,
                     usuario_autorizador, timestamp_validacion, hash_integridad)
                VALUES
                    (NEW.id_docente, NEW.id_asignacion, ultimo_seq, objetivo_seq,
                     32, TRUE, 'Excepción gerencial aplicada', 'SISTEMA', NOW(),
                     generar_sha256(row_to_json(NEW)::jsonb));
            ELSE
                NEW.disposicion_id := 12; -- BLOQ_CONS
                UPDATE docentes_base SET estado_id = 2 WHERE id_docente = NEW.id_docente;
                UPDATE ejecucion_presupuestaria
                    SET id_validacion_consecutividad = 31
                    WHERE id_asignacion = NEW.id_asignacion;
                INSERT INTO log_validacion_consecutividad
                    (id_docente, id_asignacion, periodo_anterior_secuencia, periodo_objetivo_secuencia,
                     resultado_validacion_id, excepcion_aplicada, timestamp_validacion, hash_integridad)
                VALUES
                    (NEW.id_docente, NEW.id_asignacion, ultimo_seq, objetivo_seq,
                     31, FALSE, NOW(), generar_sha256(row_to_json(NEW)::jsonb));
                RAISE EXCEPTION 'Bloqueado por descanso obligatorio. Docente ya contratado en periodo consecutivo.';
            END IF;
        ELSE
            -- Periodo no consecutivo o primer registro: aprobado
            NEW.disposicion_id := 11; -- ASIG
            UPDATE ejecucion_presupuestaria
                SET id_validacion_consecutividad = 30
                WHERE id_asignacion = NEW.id_asignacion;
            INSERT INTO log_validacion_consecutividad
                (id_docente, id_asignacion, periodo_anterior_secuencia, periodo_objetivo_secuencia,
                 resultado_validacion_id, excepcion_aplicada, timestamp_validacion, hash_integridad)
            VALUES
                (NEW.id_docente, NEW.id_asignacion, COALESCE(ultimo_seq, 0), objetivo_seq,
                 30, FALSE, NOW(), generar_sha256(row_to_json(NEW)::jsonb));
            UPDATE docentes_base
                SET ultimo_periodo_secuencia = objetivo_seq, estado_id = 3
                WHERE id_docente = NEW.id_docente;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_consecutividad
BEFORE INSERT OR UPDATE ON asignaturas_periodos
FOR EACH ROW EXECUTE FUNCTION validar_consecutividad_y_auditar();

-- Sincroniza el estado del docente al cierre de periodo (estado_id 3 = En Contrato)
CREATE OR REPLACE FUNCTION cierre_periodo_automatico() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.estado_id = 3 AND OLD.estado_id != 3 THEN
        UPDATE docentes_base
            SET estado_id = 2,
                ultimo_periodo_secuencia = (
                    SELECT periodo_secuencia FROM asignaturas_periodos
                    WHERE id_asignacion = TG_RELARGS[0]::uuid LIMIT 1
                )
            WHERE id_docente = NEW.id_docente;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Función RPC expuesta por PostgREST en /rpc/validar_pago_nomina.
-- Llamar via POST con body: {"docente_id": "<uuid>", "periodo_objetivo_seq": <int>}
CREATE OR REPLACE FUNCTION validar_pago_nomina(docente_id UUID, periodo_objetivo_seq INTEGER)
RETURNS TABLE(aprobado BOOLEAN, motivo TEXT) AS $$
DECLARE
    res_validacion INTEGER;
    exc_aplicada BOOLEAN;
    est_ejecucion INTEGER;
BEGIN
    SELECT id_validacion_consecutividad, excepcion_aplicada
        INTO res_validacion, exc_aplicada
        FROM log_validacion_consecutividad
        WHERE id_docente = docente_id
          AND periodo_objetivo_secuencia = periodo_objetivo_seq
        ORDER BY timestamp_validacion DESC LIMIT 1;

    SELECT ap.estado_clase_id INTO est_ejecucion
        FROM asignaturas_periodos ap
        JOIN docentes_base d ON ap.id_docente = d.id_docente
        WHERE d.id_docente = docente_id
          AND ap.periodo_secuencia = periodo_objetivo_seq
        LIMIT 1;

    IF res_validacion = 31 AND exc_aplicada = FALSE THEN
        RETURN QUERY SELECT FALSE, 'Bloqueado por regla de consecutividad sin excepción aprobada.'::TEXT;
    ELSIF est_ejecucion IN (22, 23, 24) THEN
        RETURN QUERY SELECT FALSE, 'Estado de ejecución no permite dispersión.'::TEXT;
    ELSE
        RETURN QUERY SELECT TRUE, 'Pago autorizado.'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- migrate:down

DROP FUNCTION IF EXISTS validar_pago_nomina(UUID, INTEGER);
DROP FUNCTION IF EXISTS cierre_periodo_automatico();
DROP TRIGGER IF EXISTS trg_validar_consecutividad ON asignaturas_periodos;
DROP FUNCTION IF EXISTS validar_consecutividad_y_auditar();
DROP FUNCTION IF EXISTS generar_sha256(JSONB);

DROP VIEW IF EXISTS vw_control_ejecucion_presupuestaria_completo;
DROP VIEW IF EXISTS vw_formato_base_docentes_completo;

DROP TABLE IF EXISTS log_validacion_consecutividad;
DROP TABLE IF EXISTS ejecucion_presupuestaria;
DROP TABLE IF EXISTS registro_excepciones_gerenciales;
DROP TABLE IF EXISTS asignaturas_periodos;
DROP TABLE IF EXISTS docentes_base;
DROP TABLE IF EXISTS usuarios_sistema;

DROP TABLE IF EXISTS cat_estado_asignacion_presupuesto;
DROP TABLE IF EXISTS cat_tipo_emergencia;
DROP TABLE IF EXISTS cat_resultado_validacion;
DROP TABLE IF EXISTS cat_estado_ejecucion;
DROP TABLE IF EXISTS cat_disposicion_asignacion;
DROP TABLE IF EXISTS cat_estado_docente;
DROP TABLE IF EXISTS cat_grado_academico;

DROP EXTENSION IF EXISTS "uuid-ossp";
DROP EXTENSION IF EXISTS "pgcrypto";

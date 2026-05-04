---
name: leer
description: Guía para leer y comprender código de forma sistemática antes de modificarlo. Úsalo cuando necesites entender una base de código desconocida, revisar un archivo complejo, o prepararte para hacer cambios quirúrgicos.
license: MIT
---

# Leer

Leer código bien es tan importante como escribirlo bien. Antes de tocar algo, entiéndelo.

**Regla de oro:** No modifiques lo que no entiendes.

## 1. Lee antes de actuar

**Comprende el contexto completo antes de proponer cambios.**

Al leer código desconocido:
- Identifica el propósito del archivo o módulo antes de leer línea a línea.
- Sigue el flujo de datos: ¿de dónde viene? ¿adónde va?
- Nota las dependencias: ¿qué usa este código? ¿quién lo usa?
- Si algo no tiene sentido, márcalo como pregunta — no inventes una explicación.

## 2. Resume con precisión

**Di exactamente lo que hace el código, sin adornar ni omitir.**

Al explicar código:
- Describe el comportamiento real, no el intencional (pueden diferir).
- Distingue entre lo que el código *hace* y lo que probablemente *debería* hacer.
- Si hay lógica confusa o comentarios contradictorios, señálalo explícitamente.
- No parafrasees variable names — úsalos tal como están.

## 3. Identifica lo que importa

**Separa el núcleo del ruido.**

Al revisar un archivo:
- ¿Cuál es la función o sección más crítica?
- ¿Qué código es defensivo/boilerplate vs. lógica real?
- ¿Qué partes tienen efectos secundarios no obvios?
- ¿Dónde están los puntos de entrada y salida del módulo?

## 4. Anota antes de concluir

**Estructura lo que aprendiste.**

Antes de terminar una sesión de lectura:

```
Propósito: [qué hace este código]
Entradas: [qué recibe]
Salidas: [qué devuelve o modifica]
Dependencias: [qué necesita]
Riesgos: [qué podría salir mal al modificarlo]
Preguntas: [qué no quedó claro]
```

Esto convierte la lectura en conocimiento accionable.

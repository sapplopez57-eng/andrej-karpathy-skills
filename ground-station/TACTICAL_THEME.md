# TACTICAL_THEME.md — Ares OS Tactical HUD Theme

Instrucciones para activar, desactivar y personalizar el modo táctico visual de Santa Bárbara.

## Activación / Desactivación

### Atajo de teclado (recomendado)

```
Ctrl + Shift + T
```

Alterna el modo táctico en cualquier momento mientras la aplicación está abierta.
El estado **no persiste** entre sesiones (por diseño — seguridad operacional).

### Activación programática (consola del navegador)

```javascript
// Activar
document.body.classList.add('ares-tactical');

// Desactivar
document.body.classList.remove('ares-tactical');

// Verificar estado
document.body.classList.contains('ares-tactical');
```

### Activación por URL (para launchers y scripts)

El script `start_santa_barbara.sh` puede inyectar la clase al arrancar el navegador:

```bash
# En start_santa_barbara.sh, abrir directamente en modo táctico:
chromium --app="http://localhost:3000" \
  --new-window \
  --js-flags="--allow-natives-syntax" &
# (La clase se aplica vía Ctrl+Shift+T una vez cargado)
```

---

## Paleta de Colores

| Elemento | Color | Hex |
|----------|-------|-----|
| Fondo principal | Negro profundo | `#050505` |
| Panel | Negro suave | `#0A0A0A` |
| Texto primario | Ámbar militar | `#FFB300` |
| Ámbar atenuado | Ámbar oscuro | `#7A5C00` |
| Alerta / Emergencia | Rojo vivo | `#FF1744` |
| Alerta atenuada | Rojo oscuro | `#7B0020` |
| Nominal / Seguro | Verde militar | `#33691E` |
| Datos de targeting | Cian | `#00E5FF` |
| Bordes de panel | Gris oscuro | `#2E2E2E` |

---

## Fuente

El tema usa **Share Tech Mono** (Google Fonts) — fuente monoespaciada de estilo táctico.

Fallback: `'Courier New', monospace`.

Si el sistema no tiene acceso a Google Fonts, instalar localmente:
```bash
yay -S ttf-share-tech-mono  # Ares OS / Arch
# o descargar desde: https://fonts.google.com/specimen/Share+Tech+Mono
```

---

## Efectos Visuales

| Efecto | Descripción |
|--------|-------------|
| Línea de horizonte artificial | Líneas cruzadas sobre el panel de tracking (CSS `::before`) |
| Scan lines CRT | Overlay de líneas horizontales animadas (CSS `::after`) |
| Barras de señal analógicas | Gradiente verde→ámbar→rojo en indicadores de señal |
| Pulso de alerta | Animación `alert-pulse` en elementos de emergencia SIGINT |
| Filtro waterfall | `saturate(0.6) brightness(0.9) sepia(0.2)` — aspecto táctico |

---

## Desactivar efectos específicos (personalización)

Para desactivar las scan lines manteniendo el resto del tema:

```css
body.ares-tactical::after {
    display: none !important;
}
```

Para desactivar la animación de pulso en alertas:

```css
body.ares-tactical .sb-intel-emergency {
    animation: none !important;
}
```

---

## Compatibilidad

- Navegadores: Chrome 90+, Firefox 88+, Edge 90+
- Resolución mínima recomendada: 1280×800
- Optimizado para uso nocturno / entornos de baja luminosidad

---

*Ares OS — Santa Bárbara Prototipo v5 — 2026*

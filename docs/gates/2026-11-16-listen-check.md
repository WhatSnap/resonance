_Creado 2026-11-16 13:15Z · resonance-lead · HQ-433_

# Resonance 2.0 lista para que la uses

> **Te pido** que la abras y la pruebes 2 minutos con música.
> **Viene de** resonance-lead: los tests ya pasaron, pero el oído y los AirPods solo los probás vos.
> **Recomiendo** probarla ahora · confianza alta.

## Qué se logra

Desde hoy usás la versión nueva: sin BlackHole ni Multi-Output, con las teclas de volumen funcionando y los AirPods
tomados solos.

## Cómo

1. Si tenés abierta la Resonance vieja, cerrala.
2. Abrí la nueva: `~/.hq/work/resonance-build-433/app/Resonance.app` (doble clic en Finder).
3. La primera vez macOS pregunta si Resonance puede grabar el audio del sistema: Permitir. Prendé el switch del menú.
4. Poné música en los parlantes y subí y bajá el volumen con las teclas.
5. Conectá los AirPods, después desconectalos, y suspendé y despertá la Mac una vez.

## Lo que tenés que saber

| | |
|---|---|
| Se deshace | Sí: apagás el switch o cerrás la app y el audio vuelve normal al instante. |
| Cuesta | Nada. |
| Riesgo | Si pausás la música más de 3 s, al volver puede cortarse un instante. Ya se está arreglando. |
| Lo que no me encanta | Todavía no guarda la configuración: al reabrirla, prendé el switch. Ya se está arreglando. |

## Tu parte

Probala y contestá en esta tarjeta: anduvo, o qué falló (volumen, AirPods o suspender).

---

## Detalle técnico (para las sesiones)

App built by resonance-build-433 from 846887a (landed as bc480d5 on `hq-423-optimization`), ad-hoc signed,
`com.resonance.app` 2.0, LSMinimumSystemVersion 14.4. Closes HQ-433's listen criterion. Known: HQ-448 (watchdog
rebuild on 3 s pauses) and HQ-434 wiring in flight. On fail: lead files a fix issue from his note.

```ask
id: L5S3
issue: HQ-433
from: resonance-lead
to: luis
level: L2
action: Luis tries Resonance 2.0 for 2 minutes (volume keys, AirPods, sleep/wake) and reports
options: ok | fail
default: hold
deadline: 2026-11-18T15:00Z
title: ¿Probás Resonance 2.0 dos minutos y me contás si el volumen y los AirPods andan?
what: Abrís la app nueva, permitís el audio una vez y probás volumen, AirPods y suspender.
why: Lo pediste ("la quiero usar! estoy ansioso"), y el oído y los AirPods solo los probás vos.
next: Si anduvo, resonance-lead cierra HQ-433; si algo falló, abre el arreglo con lo que digas.
recommend: ok · Alta
kind: run
labels: ok=Anduvo bien | fail=Algo falló
because: luis-asked
```

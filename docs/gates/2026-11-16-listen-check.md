_Creado 2026-11-16 13:15Z · actualizado 20:20Z · resonance-lead · HQ-433_

# Resonance 2.0 lista para que la uses

> **Te pido** que la abras y la pruebes 2 minutos con música.
> **Viene de** resonance-lead: los tests ya pasaron, pero el oído y los AirPods solo los probás vos.
> **Recomiendo** probarla ahora · confianza alta.

## Qué se logra

Desde hoy usás la versión nueva: sin BlackHole ni Multi-Output, con las teclas de volumen funcionando y los AirPods
tomados solos.

## Cómo

1. Ya te la abrí: es la ventana de Resonance que tenés en pantalla.
2. Si macOS pregunta si Resonance puede grabar el audio del sistema: Permitir. Prendé el switch.
3. Si cerrás la ventana, la app sigue arriba a la derecha; abrirla de nuevo trae la ventana.
4. Poné música en los parlantes y subí y bajá el volumen con las teclas.
5. Conectá los AirPods, después desconectalos, y suspendé y despertá la Mac una vez.

## Lo que tenés que saber

| | |
|---|---|
| Se deshace | Sí: apagás el switch o cerrás la app y el audio vuelve normal al instante. |
| Cuesta | Nada. |
| Riesgo | La firma cambia en cada versión: puede volver a pedir el permiso de audio (tarjeta de firma). |
| Lo que no me encanta | Spotlight todavía abre la 1.0 de Aplicaciones hasta que la reemplace. |

## Tu parte

Probala y contestá en esta tarjeta: anduvo, o qué falló (volumen, AirPods o suspender).

---

## Detalle técnico (para las sesiones)

App: ~/.hq/work/resonance-build-451-2/app/Resonance.app, built from d74539a (landed as a548cf9: HQ-429..435, 448, 450,
451), ad-hoc signed, `com.resonance.app` 2.0. Closes HQ-433's listen criterion. On fail: lead files a fix issue from his note.

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

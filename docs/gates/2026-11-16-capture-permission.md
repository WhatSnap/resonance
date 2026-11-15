_Creado 2026-11-16 01:30Z · resonance-lead · HQ-429_

# Probar en tu Mac la captura de audio nueva

> **Te pido** que estés en la Mac y toques "Permitir" cuando macOS avise que Warp quiere grabar el audio del sistema.
> **Viene de** resonance-lead: el permiso de grabar audio del sistema solo lo podés dar vos.
> **Recomiendo** correrla ahora · confianza alta.

## Qué se logra

Si pasa, el motor nuevo se construye sobre algo probado en tu Mac. Ese motor es el que te deja usar las teclas de
volumen y cambiar a los AirPods sin tocar nada.

## Cómo

1. La prueba reproduce un tono mudo: lo manda a BlackHole, que acá funciona solo como destino silencioso de la prueba.
   No suena en tus parlantes ni en los AirPods.
2. macOS muestra un aviso. Tocás Permitir.
3. La prueba captura el tono y termina. Tu salida de audio no se toca.

## Lo que tenés que saber

| | |
|---|---|
| Se deshace | Sí: Ajustes > Privacidad > Grabación de audio, y le sacás el permiso a Warp. |
| Cuesta | Nada. |
| Riesgo | Mientras tenga el permiso, Warp puede grabar el audio del sistema. |
| Lo que no me encanta | El permiso queda en Warp y no en Resonance, porque la prueba corre en la terminal. |

## Tu parte

Si la app Resonance está abierta, cerrala: la versión actual pasa BlackHole a los parlantes y el tono sonaría. Contestá
en esta tarjeta y tocá Permitir cuando aparezca el aviso.

---

## Detalle técnico (para las sesiones)

Worker `resonance-build-429`, commit eef84a9, test gated by `RESONANCE_TAP_SPIKE=1`. Child plays 997 Hz to BlackHole 2ch
only; aggregate clocked by BlackHole; the tap lists only the child (no global tap); the default output is never written.
The test refuses to run if Resonance.app is running. On go: lead sends `go run` to resonance-build-429.

```ask
id: C7T2
issue: HQ-429
from: resonance-lead
to: luis
level: L2
action: Run the HQ-429 tap capture test once (triggers the macOS System Audio Recording prompt for Warp)
options: go | hold
default: hold
deadline: 2026-11-17T15:00Z
title: ¿Corro la prueba de captura ahora, con vos en la Mac para tocar Permitir?
what: Una prueba silenciosa que hace aparecer un aviso de macOS; tocás Permitir y listo.
why: Da a Warp permiso de grabar el audio del sistema; ese acceso solo lo das vos.
next: resonance-lead le dice al worker que la corra y te confirma el resultado en una línea.
recommend: go · Alta
kind: run
labels: go=Sí, estoy en la Mac | hold=Más tarde
because: access
```

_Creado 2026-11-16 01:20Z · resonance-lead · HQ-423_

# Resonance sin BlackHole: los AirPods y el volumen andan solos

> **Te pido** que apruebes el plan para empezar a construir.
> **Viene de** resonance-lead, porque pediste armar el plan juntos antes de ejecutarlo.
> **Recomiendo** aprobarlo · confianza alta.

## Qué se logra

Hoy la salida es un Multi-Output con BlackHole, que no tiene volumen: por eso las teclas no hacen nada. La app
tampoco se entera cuando conectás los AirPods, y suenan dos señales juntas, la original y la afinada.

Con el cambio, la app captura el audio con una función de macOS 14.2, sin driver. Tus parlantes o AirPods siguen
siendo la salida real: el volumen anda normal y la app sigue sola al dispositivo que conectes.

## Cómo

1. Una prueba chica que confirma que la captura funciona.
2. Tests del afinado, del cambio de dispositivo y del buffer, en paralelo.
3. El motor nuevo.
4. Guardar la configuración y un "abrir al iniciar" opcional.
5. Sacar BlackHole del setup y del README.

## Lo que tenés que saber

| | |
|---|---|
| Se deshace | Sí: todo va en una rama local, sin push. |
| Cuesta | Nada. La firma de la app se decide al final, aparte. |
| Riesgo | La app pasa a pedir macOS 14.4 (vos tenés 26.4). |
| Lo que no me encanta | Hay que confirmar escuchando una vez que el volumen responde bien. |

## Tu parte

Aprobar acá. Después, dos momentos cortos: tocar "Permitir" una vez cuando macOS lo pida, y 2 minutos escuchando
música para probar el volumen y los AirPods. Te aviso antes de cada uno.

---

## Detalle técnico (para las sesiones)

Plan: `./docs/plans/2026-11-16-optimization-plan.md`. Dossier: `./docs/research/2026-11-16/resonance-audio-routing.md`.
On go: file steps 1–7 as HQ children of HQ-423, open workers for 1, 2, 3, 4 in parallel (tests first), branch
`hq-423-optimization`.

```ask
id: P4N1
issue: HQ-423
from: resonance-lead
to: luis
level: L2
action: Approve the Resonance optimization plan (process tap, no BlackHole)
options: go | hold
default: hold
deadline: 2026-11-18T15:00Z
title: ¿Apruebo el plan para que Resonance ande sin BlackHole?
what: La app captura el audio sin driver; volumen y AirPods quedan nativos. Se construye en una rama local, sin push.
why: Pediste armar el plan juntos antes de ejecutarlo ("armemos un plan de optimizacion y lo ejecutemos").
next: resonance-lead crea un issue por paso y abre los workers; te avisa antes del permiso y de la prueba de 2 minutos.
recommend: go · Alta
labels: go=Sí, arrancá | hold=Todavía no
because: luis-asked
```

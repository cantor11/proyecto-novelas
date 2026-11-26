# Proyecto de Curso — Planificación de los Ensayos en una Telenovela (COP)

Proyecto final de la asignatura **Programación por Restricciones**, Escuela de Ingeniería de Sistemas y Computación, **Universidad del Valle**.

## Integrantes

- Cristian David Cabrera Pantoja
- Junior Orlando Cantor Arevalo
- Juan Diego Cárdenas Mejía

**Profesor:** Robinson Duque

---

## Estructura del Repositorio

- `problemas/`: Implementaciones declarativas en MiniZinc de los Problemas de Optimización con Restricciones ($\text{COP}(\mathcal{FD})$).
  - `parte1/TelenovelaParte1.mzn`: Modelo COP de la Parte 1 construido estrictamente sobre los constructos de los fundamentos del curso para minimizar el costo salarial total de permanencia en el set, con canalización primal-dual `inverse(Orden, Pos)`, eliminación de simetrías ($S_1$–$S_3$), restricciones redundantes ($R_1$–$R_4$) y estrategia *Outside-In* ponderada por peso salarial ($E_1$).
  - `parte2/TelenovelaParte2.mzn`: Extensión COP de la Parte 2 con restricciones contractuales de `Disponibilidad`, cuantificación exacta de solape en estudio para pares conflictivos (`Evitar`) y función objetivo lexicográfica exacta ($Z_{\text{lex}} = W \cdot \text{Costo} + \text{TiempoCompartido}$).
- `datos/`: Batería de 13 archivos de entrada normalizados (`*.dzn`).
  - `parte1/`: `Trivial1.dzn`, `Instancia01_P1.dzn`..`Instancia04_P1.dzn`, `Desenfreno2.dzn` y `Desenfreno3.dzn` ($M \in \{6, 8, 10, 12, 15, 20\}$).
  - `parte2/`: `Trivial2.dzn`, `Instancia01_P2.dzn`..`Instancia04_P2.dzn` y `Desenfreno4.dzn` ($M \in \{6, 8, 10, 12, 15, 20\}$).
- `salidas/`: Archivos de salida normalizados de una línea (`*.txt`) generados para las 13 instancias de evaluación.
- `interfaz/`: Interfaz gráfica y de línea de comandos para entrada/salida y verificación visual.
  - `app_telenovela.py`: Aplicación en Python (`Tkinter`) que carga archivos `.dzn`, ejecuta `Chuffed` o `Gecode`, audita las restricciones, renderiza el diagrama de Gantt de actuación, espera y solapes `Evitar`, y exporta las salidas normalizadas `.txt`.
- `pruebas/`: Suite automatizada de verificación formal y experimental.
  - `test_telenovela.py`: Suite `unittest` con oráculo exacto independiente Held-Karp DP / Branch-and-Bound, equivalencia cruzada `Gecode`–`Chuffed`, ablación de simetrías/redundantes y validación de E/S.
- `Informe/`: Informe técnico modular en LaTeX (`main.tex` y `main.pdf`) libre de bloques de código fuente.
  - `secciones/`: Secciones modulares `01_modelo_parte1.tex` a `06_conclusiones.tex`.
  - `Imagenes/`: `logoUV.jpg` en la raíz y gráficas experimentales separadas en `parte1/` y `parte2/`.
- `readme.txt`: Descripción detallada de entregables e instrucciones de ejecución.
- `GUIA_LATEX.md`: Guía de configuración y compilación del informe en LaTeX.

---

## Ejecución Rápida

Desde la raíz del repositorio (`proyecto-novelas/`):

```bash
# Ejecutar Parte 1 (Desenfreno de Pasiones, M=20 -> Costo* = 871)
minizinc --solver chuffed --statistics problemas/parte1/TelenovelaParte1.mzn datos/parte1/Desenfreno2.dzn

# Ejecutar Parte 2 (Desenfreno de Pasiones con Disponibilidad y Evitar -> Costo* = 880, TC* = 37)
minizinc --solver chuffed --statistics problemas/parte2/TelenovelaParte2.mzn datos/parte2/Desenfreno4.dzn

# Lanzar la interfaz gráfica interactiva de entrada/salida (Tkinter)
python interfaz/app_telenovela.py

# Regenerar en lote todos los archivos de salida normalizados (.txt)
python interfaz/app_telenovela.py --lote

# Ejecutar la suite completa de pruebas automatizadas
python pruebas/test_telenovela.py
```

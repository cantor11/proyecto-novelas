# Proyecto de Curso: Planificación de los Ensayos en una Telenovela (COP)

Proyecto final de **Programación por Restricciones**, Escuela de Ingeniería de Sistemas y Computación, **Universidad del Valle**.

## Integrantes

- Cristian David Cabrera Pantoja
- Junior Orlando Cantor Arevalo
- Juan Diego Cárdenas Mejía

**Profesor:** Robinson Duque

## Estructura del Repositorio

- `problemas/`: Modelos COP en MiniZinc.
  - `parte1/TelenovelaParte1.mzn`: Minimización del costo salarial por permanencia en estudio con canalización `inverse(Orden, Pos)`, ruptura de simetrías (`S1`-`S3`), restricciones redundantes (`R1`-`R4`) y búsqueda *Outside-In* por peso salarial (`E1`).
  - `parte2/TelenovelaParte2.mzn`: Extensión con `Disponibilidad` máxima por actor, cálculo de solape para pares en `Evitar` y objetivo lexicográfico (`ObjetivoLex = W * Costo + TiempoCompartido`).
- `datos/`: 13 archivos de entrada normalizados (`*.dzn`).
  - `parte1/`: `Trivial1.dzn`, `Instancia01_P1.dzn`..`Instancia04_P1.dzn`, `Desenfreno2.dzn`, `Desenfreno3.dzn` ($M \in \{6, 8, 10, 12, 15, 20\}$).
  - `parte2/`: `Trivial2.dzn`, `Instancia01_P2.dzn`..`Instancia04_P2.dzn`, `Desenfreno4.dzn` ($M \in \{6, 8, 10, 12, 15, 20\}$).
- `salidas/`: Salidas normalizadas de una línea (`*.txt`) para las 13 instancias.
- `interfaz/app_telenovela.py`: Interfaz gráfica (`Tkinter`) y CLI para cargar `.dzn`, ejecutar `Chuffed` o `Gecode`, verificar restricciones, visualizar el diagrama de Gantt y exportar `.txt`.
- `pruebas/test_telenovela.py`: Suite `unittest` con oráculo exacto independiente (Held-Karp DP y Branch-and-Bound), equivalencia `Gecode`/`Chuffed`, ablación y pruebas de E/S.
- `Informe/`: Informe en LaTeX (`main.tex` y `main.pdf`), secciones en `secciones/` y figuras en `Imagenes/` (`parte1/`, `parte2/`).
- `readme.txt`: Contenido de la carpeta e instrucciones de ejecución.
- `GUIA_LATEX.md`: Instrucciones de compilación del informe.

## Ejecución

Desde la raíz del repositorio (`proyecto-novelas/`):

```bash
# Parte 1 (Desenfreno de Pasiones, M=20 -> Costo* = 871)
minizinc --solver chuffed --statistics problemas/parte1/TelenovelaParte1.mzn datos/parte1/Desenfreno2.dzn

# Parte 2 (Desenfreno de Pasiones -> Costo* = 880, TC* = 37)
minizinc --solver chuffed --statistics problemas/parte2/TelenovelaParte2.mzn datos/parte2/Desenfreno4.dzn

# Interfaz gráfica (Tkinter)
python interfaz/app_telenovela.py

# Regenerar todas las salidas normalizadas (.txt)
python interfaz/app_telenovela.py --lote

# Ejecutar pruebas automatizadas
python pruebas/test_telenovela.py
```

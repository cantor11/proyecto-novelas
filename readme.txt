===============================================================================
PROYECTO DE CURSO - PROGRAMACION POR RESTRICCIONES
Planificacion de los ensayos en una telenovela (Parte 1 y Parte 2)
Universidad del Valle - Escuela de Ingenieria de Sistemas y Computacion
===============================================================================

Integrantes:
  - Cristian David Cabrera Pantoja
  - Junior Orlando Cantor Arevalo
  - Juan Diego Cardenas Mejia

Profesor:
  - Robinson Duque

-------------------------------------------------------------------------------
1. ENUMERACION Y DESCRIPCION DEL CONTENIDO DE LA CARPETA
-------------------------------------------------------------------------------

  problemas/
    parte1/
      TelenovelaParte1.mzn      Modelo COP en MiniZinc para la Parte 1:
                                minimizacion del costo salarial total de los
                                actores segun su tiempo de permanencia en el
                                estudio, con canalizacion inverse(Orden, Pos),
                                eliminacion de simetrias (S1-S3), restricciones
                                redundantes (R1-R4) y 8 estrategias (E1-E8).
    parte2/
      TelenovelaParte2.mzn      Modelo COP extendido en MiniZinc para la Parte 2:
                                incorpora restricciones de Disponibilidad maxima
                                por actor, calculo de solape en estudio para los
                                pares de actores en Evitar y optimizacion
                                lexicografica estricta (prioridad Costo sobre
                                TiempoCompartido).

  datos/
    parte1/
      Trivial1.dzn              Instancia base oficial Parte 1 (N=3, M=6).
      Instancia01_P1.dzn        Instancia con escenas vacias y gemelas (N=5, M=8).
      Instancia02_P1.dzn        Instancia con estrella de alto costo (N=6, M=10).
      Instancia03_P1.dzn        Instancia de duraciones heterogeneas (N=7, M=12).
      Instancia04_P1.dzn        Instancia mediana-alta de escalabilidad (N=8, M=15).
      Desenfreno2.dzn           Caso completo Desenfreno de Pasiones (N=8, M=20).
      Desenfreno3.dzn           Copia de verificacion normalizada (N=8, M=20).
    parte2/
      Trivial2.dzn              Instancia base oficial Parte 2 (N=4, M=6).
      Instancia01_P2.dzn        Instancia de desempate lexicografico (N=5, M=8).
      Instancia02_P2.dzn        Instancia con disponibilidad cero-holgura (N=6, M=10).
      Instancia03_P2.dzn        Instancia con sobrecosto por disponibilidad (N=7, M=12).
      Instancia04_P2.dzn        Instancia mediana-alta con 5 conflictos (N=8, M=15).
      Desenfreno4.dzn           Caso completo Desenfreno de Pasiones Parte 2 (N=8, M=20).

  salidas/
    parte1/*.txt                Archivos de texto normalizados de una linea para
                                las 7 instancias de Parte 1 (orden de escenas +
                                costo total optimo).
    parte2/*.txt                Archivos de texto normalizados de una linea para
                                las 6 instancias de Parte 2 (orden de escenas +
                                costo total optimo + tiempo compartido Evitar).

  interfaz/
    app_telenovela.py           Interfaz grafica interactiva (Tkinter) y CLI de
                                entrada/salida que lee archivos *.dzn, ejecuta
                                MiniZinc, verifica todas las restricciones,
                                dibuja el diagrama de Gantt de actuacion/esperas
                                y solapes Evitar, y exporta la salida *.txt.

  pruebas/
    test_telenovela.py          Suite automatizada en Python (unittest) con
                                oraculo exacto Held-Karp DP / Branch-and-Bound,
                                equivalencia Gecode-Chuffed, pruebas de ablacion
                                de simetrias/redundantes y verificacion de E/S.

  Informe/
    main.pdf                    Informe tecnico compilado en formato PDF (sin
                                codigo fuente), con modelos, demostraciones,
                                tablas experimentales, graficas y conclusiones.
    main.tex                    Documento raiz LaTeX.
    secciones/                  Archivos modulares .tex (01 a 06).
    Imagenes/                   Logo institucional en la raiz y figuras en las
                                subcarpetas parte1/ y parte2/.

  ProyectoPPR.pdf               Enunciado oficial del proyecto de curso.
  ejercicios/CriteriosRubrica.jpg Rubrica oficial de evaluacion (100 puntos).
  readme.txt                    Este archivo descriptivo e instructivo de uso.
  README.md                     Documentacion general del repositorio en Markdown.
  GUIA_LATEX.md                 Guia de compilacion del informe LaTeX.

-------------------------------------------------------------------------------
2. INSTRUCCIONES PARA CORRER LOS MODELOS Y LA INTERFAZ
-------------------------------------------------------------------------------

A) Ejecucion directa en MiniZinc CLI (MiniZinc 2.9+):

   Ubicarse en la raiz del proyecto y ejecutar con Chuffed (recomendado para
   instancias grandes M=20) o Gecode:

   - Parte 1:
     minizinc --solver gecode  problemas/parte1/TelenovelaParte1.mzn datos/parte1/Trivial1.dzn
     minizinc --solver chuffed --statistics problemas/parte1/TelenovelaParte1.mzn datos/parte1/Desenfreno2.dzn

   - Parte 2:
     minizinc --solver gecode  problemas/parte2/TelenovelaParte2.mzn datos/parte2/Trivial2.dzn
     minizinc --solver chuffed --statistics problemas/parte2/TelenovelaParte2.mzn datos/parte2/Desenfreno4.dzn

   - Comparacion con y sin eliminacion de simetrias o restricciones redundantes:
     minizinc --solver gecode --statistics -D "opt_usar_simetrias=false;" problemas/parte1/TelenovelaParte1.mzn datos/parte1/Instancia01_P1.dzn
     minizinc --solver gecode --statistics -D "opt_usar_redundantes=false;" problemas/parte2/TelenovelaParte2.mzn datos/parte2/Instancia02_P2.dzn

   - Seleccion de cualquiera de las 8 estrategias de busqueda (1..8):
     minizinc --solver chuffed --statistics -D "opt_estrategia=1;" problemas/parte2/TelenovelaParte2.mzn datos/parte2/Desenfreno4.dzn

B) Ejecucion desde MiniZinc IDE:

   1. Abrir problemas/parte1/TelenovelaParte1.mzn (o TelenovelaParte2.mzn).
   2. Seleccionar un archivo .dzn correspondiente de datos/parte1/ (o datos/parte2/).
   3. Elegir el solver "Chuffed" o "Gecode" y presionar "Run" (Ctrl+R).

C) Interfaz grafica interactiva y generacion de archivos normalizados (.txt):

   - Abrir la interfaz grafica de escritorio (Tkinter):
     python interfaz/app_telenovela.py

   - Resolver un archivo .dzn y escribir su salida normalizada en texto:
     python interfaz/app_telenovela.py --entrada datos/parte1/Desenfreno2.dzn --salida salidas/parte1/Desenfreno2.txt
     python interfaz/app_telenovela.py --entrada datos/parte2/Desenfreno4.dzn --salida salidas/parte2/Desenfreno4.txt

   - Regenerar en lote todas las salidas normalizadas del repositorio:
     python interfaz/app_telenovela.py --lote

D) Ejecucion de la suite de pruebas automatizadas:

     python pruebas/test_telenovela.py

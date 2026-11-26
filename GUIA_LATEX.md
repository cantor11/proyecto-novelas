# Guía de Configuración y Compilación de LaTeX

Esta guía describe la estructura modular del informe técnico ubicado en `Informe/` y los comandos para compilar `Informe/main.pdf`.

---

## 1. Organización de `Informe/`

```text
proyecto-novelas/
├── .vscode/
│   └── settings.json                                 # Recetas automáticas para LaTeX Workshop
├── Informe/
│   ├── main.tex                                      # Documento raíz (portada, índice e imports)
│   ├── main.pdf                                      # Informe PDF compilado
│   ├── Imagenes/
│   │   ├── logoUV.jpg                                # Escudo institucional Universidad del Valle
│   │   ├── parte1/                                   # Figuras de Parte 1 (Gantt, ablación, estrategias)
│   │   └── parte2/                                   # Figuras de Parte 2 (Gantt Evitar, ablación, verificación)
│   └── secciones/
│       ├── 01_modelo_parte1.tex                      # Formulación matemática COP Parte 1
│       ├── 02_modelo_parte2.tex                      # Extensión COP Parte 2 y objetivo lexicográfico
│       ├── 03_implementacion_simetrias_redundantes.tex # Canalización, simetrías S1-S3 y redundantes R1-R4
│       ├── 04_estrategias_busqueda.tex               # Diseño y análisis teórico de estrategias E1-E8
│       ├── 05_pruebas_y_analisis.tex                 # Batería de 13 instancias, tablas y gráficas
│       └── 06_conclusiones.tex                       # Conclusiones técnicas sustentadas
```

---

## 2. Compilación

### 2.1. Con Tectonic desde terminal
```powershell
cd Informe
& "C:\Users\Jr Cantor\AppData\Local\Programs\Tectonic\tectonic.exe" -o . main.tex
```

### 2.2. Con LaTeX Workshop en Visual Studio Code
1. Abrir `Informe/main.tex` o cualquiera de los archivos en `Informe/secciones/`.
2. Guardar con `Ctrl + S` para compilar automáticamente o presionar `Ctrl + Alt + B`.
3. Visualizar el PDF compilado con `Ctrl + Alt + V`.

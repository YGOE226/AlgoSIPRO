# Compilateur ALgo → SIPRO

Projet de compilation (Flex/Bison) qui traduit des algorithmes ALgo (macros LaTeX) en assembleur SIPRO.

## Build

```bash
make
```

## Utilisation

```bash
./compil puissance.tex > out.asm
asipro out.asm puissance.sip
sipro puissance.sip
```

## Exemples validés

- `puissance.tex` → `8`
- `puissancerec.tex` → `8`
- `fibonacci.tex` → `55`
- `factorielle.tex` → `720`
- `somme.tex` → `55`

## Rapport

Voir [RAPPORT_CORRECTIONS.md](RAPPORT_CORRECTIONS.md) pour le détail des problèmes corrigés.

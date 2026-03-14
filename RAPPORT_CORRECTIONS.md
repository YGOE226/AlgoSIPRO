# Rapport de corrections — Compilateur ALgo → SIPRO

## Contexte

Le projet compile des fichiers source ALgo (macros LaTeX) en assembleur SIPRO, puis exécute le binaire obtenu avec `asipro` et `sipro`.

Pendant les tests, plusieurs anomalies sont apparues :
- `Bus error` à l'exécution de `puissance.sip`
- résultats numériques incorrects malgré une exécution sans crash
- erreurs syntaxiques sur certains fichiers source, notamment `puissancerec.tex`

Ce document résume les problèmes rencontrés, leurs causes et les corrections apportées.

---

## 1. Bus error dans SIPRO

### Symptôme

La commande suivante provoquait un `Bus error` :

```bash
sipro puissance.sip
```

### Cause

Le code généré utilisait l'instruction `storew` avec les opérandes dans un ordre incompatible avec la VM SIPRO installée.

Dans la génération des affectations, le compilateur produisait une écriture de la forme :

```asm
storew bx,cx
```

alors que l'interpréteur attendait l'ordre :

```asm
storew valeur,adresse
```

### Correction apportée

La génération des écritures mémoire a été corrigée dans `store_var()` pour produire :

```asm
storew cx,bx
```

### Impact

- suppression du `Bus error`
- affectations mémoire cohérentes pour les variables locales et paramètres

---

## 2. Sauts conditionnels faux à cause du flag écrasé

### Symptôme

Après correction du `Bus error`, certains programmes ne terminaient pas correctement ou produisaient des boucles incohérentes.

### Cause

Le flag de comparaison utilisé par `jmpc` était écrasé avant le saut conditionnel.

Le compilateur générait parfois une séquence de ce type :

```asm
cmp ax,cx
const dx,label
jmpc dx
```

ou :

```asm
sless ax,cx
const dx,label
jmpc dx
```

Or, sur cette VM SIPRO, l'instruction `const` modifie les flags. Le résultat du `cmp` ou du `sless` était donc perdu avant `jmpc`.

### Correction apportée

Le chargement de l'adresse de saut dans `dx` a été déplacé avant l'instruction qui calcule le flag :

```asm
const dx,label
cmp ax,cx
jmpc dx
```

ou :

```asm
const dx,label
sless ax,cx
jmpc dx
```

### Zones concernées

Cette correction a été appliquée dans :
- `IF`
- `DOWHILE`
- `DOFORI`
- la division par zéro
- toutes les comparaisons (`<`, `>`, `<=`, `>=`, `=`, `!=`)

### Impact

- conditions correctement évaluées
- boucles `for` et `while` redevenues cohérentes
- comparaisons booléennes fiables

---

## 3. Résultat final mal affiché avec `callprintfd`

### Symptôme

Après correction des problèmes précédents, `puissance(2,3)` s'exécutait sans planter, mais l'affichage final était faux.

### Cause

La VM SIPRO utilisée n'interprétait pas `callprintfd reg` comme “afficher la valeur contenue dans le registre”, mais comme “afficher la valeur située à l'adresse pointée par ce registre”.

Le compilateur faisait :

```asm
callprintfd ax
```

alors que `ax` contenait directement le résultat, et non une adresse mémoire.

### Correction apportée

Une case mémoire temporaire `print_tmp` a été ajoutée à la fin du programme généré.

Le compilateur produit maintenant :

```asm
const bx,print_tmp
storew ax,bx
callprintfd bx
```

### Impact

- le résultat final est maintenant correctement affiché
- `puissance(2,3)` renvoie bien `8`
- `puissancerec(2,3)` renvoie bien `8`

---

## 4. Erreur syntaxique sur `puissancerec.tex`

### Symptôme

La compilation de `puissancerec.tex` échouait avec une erreur du type :

```text
Erreur syntaxique ligne 5 : syntax error
```

### Cause

La règle Bison pour les appels de fonction dans une expression ne correspondait pas aux tokens produits par le lexer.

Le lexer renvoie directement le token `CALL` pour la séquence `\CALL{`, mais la grammaire attendait une structure avec un `'{'` supplémentaire.

Autrement dit, la règle d'expression ne correspondait pas à la syntaxe réelle de :

```tex
\SET{p}{\CALL{puissancerec}{a,b-1}}
```

### Correction apportée

La règle Bison des appels de fonction dans les expressions a été corrigée pour être cohérente avec le lexer.

### Impact

- `puissancerec.tex` est maintenant correctement parsé
- les appels récursifs dans les expressions fonctionnent

---

## Résultats validés

Après corrections :

### `puissance.tex`

Chaîne validée :

```bash
./compil puissance.tex > out.asm
asipro out.asm puissance.sip
sipro puissance.sip
```

Résultat :

```text
8
```

### `puissancerec.tex`

Chaîne validée :

```bash
./compil puissancerec.tex > out1.asm
asipro out1.asm puissancerec.sip
sipro puissancerec.sip
```

Résultat :

```text
8
```

---

## Synthèse

Les problèmes rencontrés ne venaient pas du langage source ALgo lui-même, mais de l'adaptation du générateur de code aux conventions réelles de la VM SIPRO.

Les corrections principales ont porté sur :
- l'ordre des opérandes de `storew`
- la préservation des flags avant `jmpc`
- la manière d'afficher un entier avec `callprintfd`
- la cohérence entre lexer et grammaire Bison pour `\CALL`

En conséquence, le compilateur gère maintenant correctement :
- les affectations
- les comparaisons
- les structures conditionnelles
- les boucles
- les appels de fonctions
- les appels récursifs
- l'affichage du résultat final

---

## Remarque

D'autres fichiers de test peuvent encore nécessiter des ajustements si leur syntaxe ALgo diverge des formes déjà couvertes, mais les problèmes critiques identifiés sur `puissance.tex` et `puissancerec.tex` ont été résolus.

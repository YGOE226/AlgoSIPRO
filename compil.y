%{
/*
 * compil.y  –– Compilateur ALgo → assembleur SIPRO
 *             Analyseur syntaxique (bison)
 *
 * Auteurs : YAMEOGO Ghislain & LOMPO Pascal — Licence 3 Informatique 2024-2025
 *
 * Convention d'appel SIPRO (pile croissante : push = sp += 2) :
 *   Appelant de f(a1,...,aN) :
 *     push a1 ; ... ; push aN
 *     const ax, f ; call ax
 *     const bx, 2*N ; sub sp, bx    (nettoyage cote appelant)
 *     resultat dans ax
 *
 *   Prologue de f(p1,...,pN) :
 *     push bp
 *     cp bp, sp                      → bp = sp (pointe sur [old_bp])
 *     const ax, FRAME_SIZE ; add sp, ax  (reserve les locaux)
 *
 *   Layout pile apres prologue :
 *     bp - 2*(N+1) = p1   (premier arg, le plus loin)
 *     bp - 4       = pN   (dernier arg)
 *     bp - 2       = adr_ret
 *     bp + 0       = old_bp  <- bp
 *     bp + 2       = local0
 *     bp + 4       = local1 ...
 *
 *   Epilogue (:ret_NOM) :
 *     cp sp, bp ; pop bp ; ret
 */

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Déclarations flex */
int  yylex(void);
extern int yylineno;
void yyerror(const char *s);

/* ─── Compteur de labels ─── */
static int lid = 0;
static int newlbl(void) { return lid++; }
static int if_id = 0;  /* label courant du \IF */

/* ─── Deux flux de sortie ───────────────────────────────────────────────────
 *   func_f  : code des fonctions  (fichier temporaire)
 *   main_f  : code du main        (fichier temporaire)
 *   cur_f   : flux actif
 */
static FILE *func_f = NULL;
static FILE *main_f = NULL;
static FILE *cur_f  = NULL;

#define E(...) fprintf(cur_f, __VA_ARGS__)

/* ─── Table des symboles ─────────────────────────────────────────────────── */
#define MAX_PARAMS   16
#define MAX_LOCALS   32
#define MAX_ALGOS    64
#define MAX_NAME    128
#define FRAME_SIZE  (2 * MAX_LOCALS)   /* 64 cellules = 32 variables locales */

typedef struct {
    char name   [MAX_NAME];
    int  nparams;
    char params [MAX_PARAMS][MAX_NAME];
    int  nlocals;
    char locals [MAX_LOCALS][MAX_NAME];
} AlgoDef;

static AlgoDef  algos[MAX_ALGOS];
static int      nalgo    = 0;
static AlgoDef *cur_algo = NULL;

/* ─── Recherche / ajout ─── */
static AlgoDef *find_algo(const char *n) {
    for (int i = 0; i < nalgo; i++)
        if (strcmp(algos[i].name, n) == 0) return &algos[i];
    return NULL;
}
static int find_param(const char *n) {
    if (!cur_algo) return -1;
    for (int i = 0; i < cur_algo->nparams; i++)
        if (strcmp(cur_algo->params[i], n) == 0) return i;
    return -1;
}
static int find_local(const char *n) {
    if (!cur_algo) return -1;
    for (int i = 0; i < cur_algo->nlocals; i++)
        if (strcmp(cur_algo->locals[i], n) == 0) return i;
    return -1;
}
static int ensure_local(const char *n) {
    int i = find_local(n);
    if (i >= 0) return i;
    if (cur_algo->nlocals >= MAX_LOCALS) {
        fprintf(stderr, "Trop de variables locales dans '%s'\n", cur_algo->name);
        exit(1);
    }
    strncpy(cur_algo->locals[cur_algo->nlocals], n, MAX_NAME-1);
    return cur_algo->nlocals++;
}

/* ─── Offsets bp ───────────────────────────────────────────────────────────
 *   param i (0-based) : bp + 2*(N-i) + 2
 *   local  j (0-based) : bp - 2*(j+1)
 */
static int param_off(int i) { return -(2*(cur_algo->nparams - i) + 2); }
static int local_off(int j) { return 2*(j+1); }

/* ─── Génération de code : accès aux variables ─── */
static void load_var(const char *n) {
    int i;
    if ((i = find_param(n)) >= 0) {
        int off = param_off(i);   /* toujours negatif : bp - |off| */
        E("\tcp bx,bp\n");
        E("\tconst ax,%d\n", -off);
        E("\tsub bx,ax\n");
        E("\tloadw ax,bx\n");
    } else if ((i = find_local(n)) >= 0) {
        int off = local_off(i);   /* toujours positif : bp + off */
        E("\tconst bx,%d\n", off);
        E("\tadd bx,bp\n");
        E("\tloadw ax,bx\n");
    } else {
        fprintf(stderr, "Ligne %d : variable inconnue '%s'\n", yylineno, n); exit(1);
    }
}
static void store_var(const char *n) {
    int i;
    if ((i = find_param(n)) >= 0) {
        int off = param_off(i);   /* toujours negatif : bp - |off| */
        E("\tcp cx,ax\n");         /* sauvegarder valeur a stocker */
        E("\tcp bx,bp\n");
        E("\tconst ax,%d\n", -off);
        E("\tsub bx,ax\n");
        E("\tstorew cx,bx\n");
    } else if ((i = find_local(n)) >= 0) {
        int off = local_off(i);   /* toujours positif : bp + off */
        E("\tcp cx,ax\n");         /* sauvegarder valeur a stocker */
        E("\tconst bx,%d\n", off);
        E("\tadd bx,bp\n");
        E("\tstorew cx,bx\n");
    } else {
        fprintf(stderr, "Ligne %d : variable inconnue '%s'\n", yylineno, n); exit(1);
    }
}

/* ─── Épilogue retour ─── */
static void emit_epilog(void) {
    E("\tcp sp,bp\n"); E("\tpop bp\n"); E("\tret\n");
}

/* ─── Appel de fonction ─── */
static void emit_call(const char *fname, int nargs) {
    AlgoDef *a = find_algo(fname);
    if (!a) { fprintf(stderr,"Ligne %d : algo inconnu '%s'\n",yylineno,fname); exit(1); }
    if (a->nparams != nargs) {
        fprintf(stderr,"Ligne %d : '%s' : %d args attendus, %d fournis\n",
                yylineno, fname, a->nparams, nargs); exit(1);
    }
    E("\tconst ax,%s\n", fname);
    E("\tcall ax\n");
    if (nargs > 0) { E("\tconst bx,%d\n", 2*nargs); E("\tsub sp,bx\n"); }
}


%}

/* ═══════════════════════════════════════════════════════════════════════════
   Déclarations Bison
   ═══════════════════════════════════════════════════════════════════════════ */

%union {
    int   integer;   /* INT_LIT, BOOL_LIT, et labels dans actions mid-rule */
    int   boolean;
    char *ident;     /* IDENT, param_list */
    int   nargs;     /* nombre d'arguments (arg_list) */
}

/* ── Tokens ── */
%token BEGIN_ALGO END_ALGO
%token SET IF ELSE FI DOWHILE DOFORI OD RETURN_KW CALL

%token <integer>  INT_LIT
%token <boolean>  BOOL_LIT
%token <ident>    IDENT

%token LE GE NEQ

/* ── Priorités (du moins prioritaire au plus prioritaire) ── */
%nonassoc NEQ '='
%nonassoc '<' '>' LE GE
%left  '+' '-'
%left  '*' '/'
%right UMINUS

/* ── Types des non-terminaux ── */
%type <ident>  param_list    /* chaîne CSV des paramètres formels */
%type <nargs>  arg_list      /* nombre d'args (déjà empilés sur la pile SIPRO) */
%type <nargs>  arg_list_ne   /* idem, version non-vide */

%%

/* ═══════════════════════════════════════════════════════════════════════════
   Règle de départ
   ═══════════════════════════════════════════════════════════════════════════ */

program
    : algo_list final_call
    ;

/* ─── Liste d'algorithmes ─── */
algo_list
    : /* vide */
    | algo_list algo_def
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   Définition d'un algorithme
   ═══════════════════════════════════════════════════════════════════════════ */

algo_def
    : BEGIN_ALGO IDENT '}' '{' param_list '}'
      {
          /* Enregistrer l'algo dans la table */
          if (nalgo >= MAX_ALGOS) { fprintf(stderr,"Trop d'algos\n"); exit(1); }
          AlgoDef *a = &algos[nalgo++];
          memset(a, 0, sizeof(*a));
          strncpy(a->name, $2, MAX_NAME-1);
          free($2);

          /* Analyser la liste de paramètres (format CSV) */
          if ($5 && strlen($5) > 0) {
              char *tmp = strdup($5);
              char *tok = strtok(tmp, ",");
              while (tok && a->nparams < MAX_PARAMS) {
                  while (*tok == ' ') tok++;
                  char *e = tok + strlen(tok) - 1;
                  while (e > tok && *e == ' ') *e-- = '\0';
                  strncpy(a->params[a->nparams++], tok, MAX_NAME-1);
                  tok = strtok(NULL, ",");
              }
              free(tmp);
          }
          free($5);
          cur_algo = a;

          /* ── Prologue ── */
                    E(":%s\n", a->name);
          E("\tpush bp\n");
          E("\tcp bp,sp\n");
          E("\tconst ax,%d\n", FRAME_SIZE);
          E("\tadd sp,ax\n");
      }
      body END_ALGO
      {
          /* ── Épilogue par défaut (retour implicite = 0) ── */
                    E("\tconst ax,0\n");
          E(":ret_%s\n", cur_algo->name);
          emit_epilog();
          cur_algo = NULL;
      }
    ;

/* ─── Paramètres formels → chaîne CSV ─── */
param_list
    : /* vide */               { $$ = strdup(""); }
    | IDENT                    { $$ = $1; }
    | param_list ',' IDENT
      {
          char *buf = malloc(strlen($1) + strlen($3) + 2);
          sprintf(buf, "%s,%s", $1, $3);
          free($1); free($3);
          $$ = buf;
      }
    ;

/* ─── Corps d'un algorithme ─── */
body
    : /* vide */
    | body instr
    ;

/* ─── Instructions ─── */
instr
    : set_instr
    | if_instr
    | dowhile_instr
    | dofori_instr
    | return_instr
    | call_stmt
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   \SET{var}{expr}
   ═══════════════════════════════════════════════════════════════════════════ */

set_instr
    : SET IDENT '}' '{' expr '}'
      {
          if (find_param($2) < 0) ensure_local($2);
          E("\tpop ax\n");
          store_var($2);
          free($2);
      }
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   \IF{cond} body [\ELSE body] \FI
   On utilise une action mid-rule pour émettre le saut conditionnel
   avant de parser le then-body, et une variable statique pour
   transmettre le label entre les différentes parties de la règle.
   ═══════════════════════════════════════════════════════════════════════════ */

if_instr
    : IF expr '}'
      {
          if_id = newlbl();
          E("\tpop ax\n");
          E("\tconst cx,0\n");
          E("\tconst dx,Lelse%d\n", if_id);
          E("\tcmp ax,cx\n");
          E("\tjmpc dx\n");
      }
      body else_opt
    ;

else_opt
    : FI
      {
          E(":Lelse%d\n", if_id);
          E(":Lfi%d\n",   if_id);
      }
    | ELSE
      {
          E("\tconst dx,Lfi%d\n", if_id);
          E("\tjmp dx\n");
          E(":Lelse%d\n", if_id);
      }
      body FI
      {
          E(":Lfi%d\n", if_id);
      }
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   \DOWHILE{cond} body \OD    (sémantique : while cond do body)
   ═══════════════════════════════════════════════════════════════════════════ */

dowhile_instr
    : DOWHILE
      {
          int id = newlbl();
          E(":Ldw%d\n", id);
          $<integer>$ = id;
      }
      expr '}'
      {
          int id = $<integer>2;
          E("\tpop ax\n");
          E("\tconst cx,0\n");
          E("\tconst dx,Ldwend%d\n", id);
          E("\tcmp ax,cx\n");
          E("\tjmpc dx\n");
          $<integer>$ = id;
      }
      body OD
      {
          int id = $<integer>5;
          E("\tconst dx,Ldw%d\n", id);
          E("\tjmp dx\n");
          E(":Ldwend%d\n", id);
      }
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   \DOFORI{k}{debut}{fin} body \OD    (for k := debut to fin do body)
   La borne 'fin' est stockée dans un local caché __finN__
   pour éviter toute corruption par des appels imbriqués dans le corps.
   ═══════════════════════════════════════════════════════════════════════════ */

dofori_instr
    : DOFORI IDENT '}' '{' expr '}' '{' expr '}'
      {
          /* pile : [..., val_debut, val_fin]  ← sp */
          char *kname = $2;
          if (find_param(kname) < 0) ensure_local(kname);

          int id = newlbl();
          char fin_var[MAX_NAME];
          snprintf(fin_var, MAX_NAME, "__fin%d__", id);
          ensure_local(fin_var);

                    E("\tpop ax\n");          /* ax = fin */
          store_var(fin_var);       /* __finN__ = fin */
          E("\tpop ax\n");          /* ax = debut */
          store_var(kname);         /* k = debut */

          E(":Lfor%d\n", id);
          /* Test : k <= fin  ↔  !(fin < k)  ↔  sless fin,k = faux */
          load_var(kname);          /* ax = k */
          E("\tpush ax\n");
          load_var(fin_var);        /* ax = fin */
          E("\tpop cx\n");          /* cx = k */
          E("\tconst dx,Lforend%d\n", id);
          E("\tsless ax,cx\n");     /* flag = (fin < k)  → fin < k → sortir */
          E("\tjmpc dx\n");

          $<integer>$ = id;
      }
      body OD
      {
          int    id    = $<integer>10;
          char  *kname = $2;

          load_var(kname);          /* ax = k */
          E("\tconst bx,1\n");
          E("\tadd ax,bx\n");
          store_var(kname);         /* k++ */

          E("\tconst dx,Lfor%d\n", id);
          E("\tjmp dx\n");
          E(":Lforend%d\n", id);

          free(kname);
      }
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   \RETURN{expr}
   ═══════════════════════════════════════════════════════════════════════════ */

return_instr
    : RETURN_KW expr '}'
      {
          E("\tpop ax\n");
          E("\tconst dx,ret_%s\n", cur_algo->name);
          E("\tjmp dx\n");
      }
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   \CALL{nom}{args}  comme instruction (résultat ignoré)
   ═══════════════════════════════════════════════════════════════════════════ */

call_stmt
    : CALL IDENT '}' '{' arg_list '}'
      {
          emit_call($2, $5);
          free($2);
      }
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   \CALL{nom}{args}  final  (hors algo) — résultat affiché sur stdout
   ═══════════════════════════════════════════════════════════════════════════ */

final_call
    : CALL IDENT '}' '{'
      {
          /* Basculer vers le flux main AVANT d'évaluer les arguments,
             pour que les push des args soient émis dans main et non dans func */
          cur_f = main_f;
      }
      arg_list '}'
      {
          emit_call($2, $6);
          E("\tconst bx,print_tmp\n");
          E("\tstorew ax,bx\n");
          E("\tconst ax,msg_result\n");
          E("\tcallprintfs ax\n");
          E("\tconst bx,print_tmp\n");
          E("\tcallprintfd bx\n");
          E("\tconst ax,msg_newline\n");
          E("\tcallprintfs ax\n");
          E("\tend\n");
          free($2);
      }
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   Liste d'arguments : empile chaque expr, renvoie le nombre d'args
   ═══════════════════════════════════════════════════════════════════════════ */

arg_list
    : /* vide */            { $$ = 0; }
    | arg_list_ne           { $$ = $1; }
    ;

arg_list_ne
    : expr                  { $$ = 1; }
    | arg_list_ne ',' expr  { $$ = $1 + 1; }
    ;

/* ═══════════════════════════════════════════════════════════════════════════
   Expressions  –  résultat au sommet de la pile SIPRO
   ═══════════════════════════════════════════════════════════════════════════ */

expr
    /* ── Littéraux ── */
    : INT_LIT
      { E("\tconst ax,%d\n", $1); E("\tpush ax\n"); }

    | BOOL_LIT
      { E("\tconst ax,%d\n", $1); E("\tpush ax\n"); }

    /* ── Variable ── */
    | IDENT
      { load_var($1); E("\tpush ax\n"); free($1); }

    /* ── Parenthèses ── */
    | '(' expr ')'

    /* ── Appel de fonction dans une expression ── */
        | CALL IDENT '}' '{' arg_list '}'
            { emit_call($2, $5); E("\tpush ax\n"); free($2); }

    /* ── Arithmétique ── */
    | expr '+' expr
      { E("\tpop bx\n"); E("\tpop ax\n"); E("\tadd ax,bx\n"); E("\tpush ax\n"); }

    | expr '-' expr
      {
          E("\tpop bx\n");    /* bx = droite */
          E("\tpop ax\n");    /* ax = gauche */
          E("\tsub ax,bx\n");
          E("\tpush ax\n");
      }

    | expr '*' expr
      { E("\tpop bx\n"); E("\tpop ax\n"); E("\tmul ax,bx\n"); E("\tpush ax\n"); }

    | expr '/' expr
      {
          E("\tpop bx\n");              /* bx = diviseur */
          E("\tconst cx,0\n");
                    E("\tconst dx,err_div0\n");
          E("\tcmp bx,cx\n");           /* flag = (bx==0) */
          E("\tjmpc dx\n");
          E("\tpop ax\n");              /* ax = dividende */
          E("\tdiv ax,bx\n");
          E("\tpush ax\n");
      }

    | '-' expr %prec UMINUS
      { E("\tpop ax\n"); E("\tconst bx,0\n"); E("\tsub bx,ax\n"); E("\tpush bx\n"); }

    /* ── Comparaisons : résultat booléen 0 ou 1 ── */
    | expr '<' expr
      {
          int id = newlbl();
          E("\tpop cx\n"); E("\tpop ax\n");
                    E("\tconst dx,Ltrue%d\n",  id);
          E("\tsless ax,cx\n");                    /* flag = (ax < cx) */
                    E("\tjmpc dx\n");
          E("\tconst ax,0\n");          E("\tpush ax\n");
          E("\tconst dx,Lend%d\n", id); E("\tjmp dx\n");
          E(":Ltrue%d\n", id);
          E("\tconst ax,1\n");          E("\tpush ax\n");
          E(":Lend%d\n",  id);
      }

    | expr '>' expr
      {
          int id = newlbl();
          E("\tpop cx\n"); E("\tpop ax\n");
                    E("\tconst dx,Ltrue%d\n",  id);
          E("\tsless cx,ax\n");                    /* flag = (cx < ax) ↔ ax > cx */
                    E("\tjmpc dx\n");
          E("\tconst ax,0\n");          E("\tpush ax\n");
          E("\tconst dx,Lend%d\n", id); E("\tjmp dx\n");
          E(":Ltrue%d\n", id);
          E("\tconst ax,1\n");          E("\tpush ax\n");
          E(":Lend%d\n",  id);
      }

    | expr LE expr                                 /* a <= b ↔ !(b < a) */
      {
          int id = newlbl();
          E("\tpop cx\n"); E("\tpop ax\n");         /* cx=b, ax=a */
                    E("\tconst dx,Lfalse%d\n",  id);
          E("\tsless cx,ax\n");                    /* flag = (b < a) → a > b */
                    E("\tjmpc dx\n");
          E("\tconst ax,1\n");           E("\tpush ax\n");
          E("\tconst dx,Lend%d\n",  id); E("\tjmp dx\n");
          E(":Lfalse%d\n", id);
          E("\tconst ax,0\n");           E("\tpush ax\n");
          E(":Lend%d\n",  id);
      }

    | expr GE expr                                 /* a >= b ↔ !(a < b) */
      {
          int id = newlbl();
          E("\tpop cx\n"); E("\tpop ax\n");         /* cx=b, ax=a */
                    E("\tconst dx,Lfalse%d\n",  id);
          E("\tsless ax,cx\n");                    /* flag = (a < b) */
                    E("\tjmpc dx\n");
          E("\tconst ax,1\n");           E("\tpush ax\n");
          E("\tconst dx,Lend%d\n",  id); E("\tjmp dx\n");
          E(":Lfalse%d\n", id);
          E("\tconst ax,0\n");           E("\tpush ax\n");
          E(":Lend%d\n",  id);
      }

    | expr '=' expr
      {
          int id = newlbl();
          E("\tpop cx\n"); E("\tpop ax\n");
                    E("\tconst dx,Ltrue%d\n",  id);
          E("\tcmp ax,cx\n");                      /* flag = (ax == cx) */
                    E("\tjmpc dx\n");
          E("\tconst ax,0\n");          E("\tpush ax\n");
          E("\tconst dx,Lend%d\n", id); E("\tjmp dx\n");
          E(":Ltrue%d\n", id);
          E("\tconst ax,1\n");          E("\tpush ax\n");
          E(":Lend%d\n",  id);
      }

    | expr NEQ expr                                /* a != b ↔ !(a == b) */
      {
          int id = newlbl();
          E("\tpop cx\n"); E("\tpop ax\n");
                    E("\tconst dx,Lfalse%d\n",  id);
          E("\tcmp ax,cx\n");
                    E("\tjmpc dx\n");
          E("\tconst ax,1\n");           E("\tpush ax\n");
          E("\tconst dx,Lend%d\n",  id); E("\tjmp dx\n");
          E(":Lfalse%d\n", id);
          E("\tconst ax,0\n");           E("\tpush ax\n");
          E(":Lend%d\n",  id);
      }
    ;

%%

/* ═══════════════════════════════════════════════════════════════════════════
   Fonctions C
   ═══════════════════════════════════════════════════════════════════════════ */

void yyerror(const char *s) {
    fprintf(stderr, "Erreur syntaxique ligne %d : %s\n", yylineno, s);
    exit(1);
}

static void output_file(FILE *f) {
    rewind(f); int c; while ((c = fgetc(f)) != EOF) putchar(c);
}

int main(int argc, char *argv[]) {
    extern FILE *yyin;

    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) { perror(argv[1]); return 1; }
    }

    /* Créer les fichiers temporaires */
    func_f = tmpfile();
    main_f = tmpfile();
    if (!func_f || !main_f) { perror("tmpfile"); return 1; }
    cur_f = func_f;          /* démarrer en mode "fonctions" */

    yyparse();               /* analyser et compiler */

    /* ── Assembler le programme complet ── */
            

    printf("\tconst ax,main\n");
    printf("\tjmp ax\n\n");

    printf(":msg_newline\n");
    printf("@string \"\\n\"\n\n");
    printf(":msg_result\n");
    printf("@string \"Resultat final : \"\n\n");
    printf(":msg_div0\n");
    printf("@string \"Erreur: division par zero\\n\"\n\n");

        output_file(func_f);
    fclose(func_f);

    printf("\n");
    printf(":main\n");
    printf("\tconst bp,stack\n");
    printf("\tconst sp,stack\n");

    output_file(main_f);
    fclose(main_f);

    printf("\n");
    printf(":err_div0\n");
    printf("\tconst ax,msg_div0\n");
    printf("\tcallprintfs ax\n");
    printf("\tend\n");

    printf("\n");
    printf(":stack\n");
    /* 64 niveaux d'imbrication × (FRAME_SIZE/2 mots locaux + 2 mots pour bp+adr_ret) */
    int stack_words = 1000;  /* 1000 mots = 2000 cellules, suffisant pour la recursivite */
    for (int i = 0; i < stack_words; i++)
        printf("@int 0\n");

    printf("\n");
    printf(":print_tmp\n");
    printf("@int 0\n");

    if (argc > 1) fclose(yyin);
    return 0;
}

%top{
/* _POSIX_C_SOURCE doit etre en tout premier, avant les headers de flex */
#define _POSIX_C_SOURCE 200809L
}

%{
/*
 * compil.l  -- Analyseur lexical ALgo (flex)
 */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "compil.tab.h"
%}

%option noinput
%option nounput
%option noyywrap
%option yylineno

DIGIT   [0-9]
ALPHA   [a-zA-Z_]
ALNUM   [a-zA-Z0-9_]
ID      {ALPHA}{ALNUM}*
INT     {DIGIT}+

%%

"\\begin{algo}{"    { return BEGIN_ALGO; }
"\\end{algo}"       { return END_ALGO;   }
"\\SET{"            { return SET;        }
"\\IF{"             { return IF;         }
"\\ELSE"            { return ELSE;       }
"\\FI"              { return FI;         }
"\\DOWHILE{"        { return DOWHILE;    }
"\\DOFORI{"         { return DOFORI;     }
"\\OD"              { return OD;         }
"\\RETURN{"         { return RETURN_KW;  }
"\\CALL{"           { return CALL;       }

"true"              { yylval.boolean = 1; return BOOL_LIT; }
"false"             { yylval.boolean = 0; return BOOL_LIT; }

{INT}               { yylval.integer = atoi(yytext); return INT_LIT; }

{ID}                { yylval.ident = strdup(yytext); return IDENT; }

"<="                { return LE;  }
">="                { return GE;  }
"!="                { return NEQ; }

"{"                 { return '{'; }
"}"                 { return '}'; }
"("                 { return '('; }
")"                 { return ')'; }
","                 { return ','; }
"+"                 { return '+'; }
"-"                 { return '-'; }
"*"                 { return '*'; }
"/"                 { return '/'; }
"<"                 { return '<'; }
">"                 { return '>'; }
"="                 { return '='; }

[ \t\r]+            { }
\n                  { }
"%"[^\n]*           { }
.                   { }

%%

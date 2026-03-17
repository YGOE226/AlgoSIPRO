# Makefile -- Compilateur ALgoSIPRO  (flex + bison)
CC    = gcc
FLEX  = flex
BISON = bison
# _POSIX_C_SOURCE pour strdup/fileno dans lex.yy.c genere par flex
CFLAGS = -Wall -Wextra -g -std=c11 -D_POSIX_C_SOURCE=200809L

TARGET = compil

.PHONY: all clean tests asm

all: $(TARGET)

# 1. Generer compil.tab.c + compil.tab.h depuis compil.y
compil.tab.c compil.tab.h: compil.y
	$(BISON) -d -v compil.y

# 2. Generer lex.yy.c depuis compil.l (requiert compil.tab.h pour les tokens)
lex.yy.c: compil.l compil.tab.h
	$(FLEX) compil.l

# 3. Compiler l'executable
$(TARGET): compil.tab.c lex.yy.c
	$(CC) $(CFLAGS) -o $@ compil.tab.c lex.yy.c

# -- Tests ------------------------------------------------------------------
tests: $(TARGET)
	@echo ""
	@echo "=============================================="
	@echo " Tests ALgoSIPRO (flex+bison)"
	@echo "=============================================="
	@for f in puissance.tex puissancerec.tex fibonacci.tex factorielle.tex somme.tex; do \
	    ./$(TARGET) "$$f" > /dev/null 2>&1 \
	        && printf "  OK  %s\n" "$$f" \
	        || printf "  KO  %s\n" "$$f"; \
	done
	@echo "=============================================="

# -- Generer les .asm -------------------------------------------------------
asm: $(TARGET)
	./$(TARGET) puissance.tex     > puissance.asm
	./$(TARGET) puissancerec.tex  > puissancerec.asm
	./$(TARGET) fibonacci.tex     > fibonacci.asm
	./$(TARGET) factorielle.tex   > factorielle.asm
	./$(TARGET) somme.tex         > somme.asm
	@echo "Fichiers ASM generes."

sip: 
	asipro puissance.asm puissance.sip
		asipro puissancerec.asm  puissancerec.sip
	asipro fibonacci.asm     fibonacci.sip
	asipro factorielle.asm   factorielle.sip
	asipro somme.asm         somme.sip	
		@echo "Fichiers SIP generes."
# -- Execution avec asipro + sipro ------------------------------------------
run_%: $(TARGET)
	./$(TARGET) $*.tex > /tmp/$*.asm
	asipro /tmp/$*.asm /tmp/$*.sip && sipro /tmp/$*.sip

clean:
	rm -f $(TARGET) compil.tab.c compil.tab.h lex.yy.c compil.output *.asm *.sip a.out

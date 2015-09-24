# makefile to split markdown files by h1-3 for mdp formatting
# mdp - markdown presentation tool (https://github.com/visit1985/mdp)

# by jeremy warner, jan 21 2014
BINDIR = mdp
PDFDIR = pdf
INPUT = $(wildcard *.md)
MDPOUT = $(INPUT:%.md=$(BINDIR)/%.mdp)
PDFOUT = $(INPUT:%.md=$(PDFDIR)/%.pdf)

all: $(MDPOUT)

$(BINDIR)/%.mdp: %.md | $(BINDIR)
	cat $< | perl -e 'while(<>){ if(/^(#.*)/){s/./***\n$&/} print }' > $@

$(BINDIR):
	mkdir -p mdp

clean:
	rm -f $(BINDIR)/*
	rmdir $(BINDIR)

thepdf: $(PDFOUT)

$(PDFDIR)/%.pdf: %.md | $(PDFDIR)
	pandoc $< -o $@

$(PDFDIR):
	mkdir -p pdf


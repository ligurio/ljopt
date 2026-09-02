# One source (main.tex), one PDF per venue mode.
#   make            -> all four PDFs
#   make tacas      -> ljopt-tacas.pdf  (LNCS, full tool paper, <= 16 pp + refs)
#   make vmcai      -> ljopt-vmcai.pdf  (LNCS, verification-slanted abstract)
#   make demo       -> ljopt-demo.pdf   (LNCS, short tool-demo cut, <= 6 pp)
#   make arxiv      -> ljopt-arxiv.pdf  (full content + appendices)

LATEXMK = latexmk -pdf -interaction=nonstopmode -halt-on-error

MODES = tacas vmcai demo arxiv

all: $(MODES)

$(MODES):
	$(LATEXMK) -jobname=ljopt-$@ -usepretex='\def\MODE{$@}' main.tex

clean:
	latexmk -C $(foreach m,$(MODES),-jobname=ljopt-$(m)) main.tex
	rm -f *.bbl *.run.xml

.PHONY: all clean $(MODES)

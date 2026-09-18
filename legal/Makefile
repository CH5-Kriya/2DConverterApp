# Rebuild the legal PDFs. Requires MacTeX (xelatex).
DOCS := PrivacyPolicy TermsAndConditions
PDFS := $(addsuffix .pdf,$(DOCS))

all: $(PDFS)

# Two passes: the second resolves the "Page N of M" reference.
%.pdf: %.tex tactura-legal.sty
	xelatex -interaction=nonstopmode $< > /dev/null
	xelatex -interaction=nonstopmode $< > /dev/null
	@echo "built $@"

clean:
	rm -f *.aux *.log *.out *.log.txt

distclean: clean
	rm -f $(PDFS)

.PHONY: all clean distclean

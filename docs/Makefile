# docs/Makefile
# Minimal Sphinx Makefile for local HTML generation
#
# Usage:
#   cd docs
#   make html          # build HTML output
#   make clean         # remove build directory
#   make livehtml      # auto-rebuild on file change (requires sphinx-autobuild)

SPHINXOPTS    ?=
SPHINXBUILD   ?= sphinx-build
SOURCEDIR     = source
BUILDDIR      = build

.PHONY: help html clean livehtml

help:
	@echo "Targets:"
	@echo "  html      Build HTML documentation"
	@echo "  clean     Remove build directory"
	@echo "  livehtml  Auto-rebuild on file change"

html:
	@pip install -q -r requirements.txt
	$(SPHINXBUILD) -M html "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS)
	@echo ""
	@echo "Build finished. Open build/html/index.html in your browser."

clean:
	@rm -rf $(BUILDDIR)

livehtml:
	@pip install -q sphinx-autobuild
	sphinx-autobuild "$(SOURCEDIR)" "$(BUILDDIR)/html" \
	  --port 8000 --open-browser $(SPHINXOPTS)

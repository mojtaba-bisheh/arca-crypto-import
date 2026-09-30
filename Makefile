# ARCA vendored-block Makefile
#
#   make import          # import every block from upstream caliptra-rtl
#   make import-ecc      # import a single block
#   make verify          # structural checks on the committed filesets
#   make roundtrip       # prove the rename is naming-only vs upstream
#   make updates         # show upstream changelog since the recorded commit

RENAME    := tools/scripts/rename
BLOCKS    := ecc hmac
UPSTREAM  ?=
PREFIX    ?= arca_
REF       ?=

UPSTREAM_ARG := $(if $(UPSTREAM),--upstream $(UPSTREAM),)
REF_ARG      := $(if $(REF),--ref $(REF),)

.PHONY: import verify roundtrip updates clean $(addprefix import-,$(BLOCKS))

import:
	$(RENAME)/import_block.sh all $(UPSTREAM_ARG) $(REF_ARG) --prefix $(PREFIX)

$(addprefix import-,$(BLOCKS)): import-%:
	$(RENAME)/import_block.sh $* $(UPSTREAM_ARG) $(REF_ARG) --prefix $(PREFIX)

verify:
	$(RENAME)/verify_import.sh

roundtrip:
	$(RENAME)/roundtrip_check.sh $(UPSTREAM_ARG)

updates:
	$(RENAME)/upstream_diff.sh $(UPSTREAM_ARG)

clean:
	rm -rf .upstream-cache

.PHONY: ctags default
default:
	echo "No default action"

test:
	prove -Ilib -rb t

BOOTSTRAP=$(wildcard ref/*.bootstrap)
REFPL=$(patsubst ref/%.bootstrap, ref/%.pl, $(BOOTSTRAP))
REFHEX=$(patsubst ref/%.bootstrap, ref/%.hex, $(BOOTSTRAP))
REFDUMP=$(patsubst ref/%.bootstrap, ref/%.dump, $(BOOTSTRAP))

ref: $(REFPL) $(REFHEX) $(REFDUMP)

%.pl: %.bootstrap
	perl tools/boxparser.pl $< | perltidy > $@

%.hex: %.bootstrap
	hexdump -C $< > $@

%.dump: %.bootstrap
	-./f4fpackager/linux/f4fpackager --input-file=$< --inspect-bootstrap > $@

ctags:
	-rm -f tags
	find ../osmf -name "*.as" -or -name "*.mxml" | ctags -L -

clean:
	-rm -f tags $(REFPL) $(REFHEX) $(REFDUMP)


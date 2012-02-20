.PHONY: ctags default
default:
	echo "No default action"

test:
	prove -Ilib -rb t

BOOTSTRAP=$(wildcard ref/*.bootstrap)
REFBSPL=$(patsubst ref/%.bootstrap, ref/%.bs.pl, $(BOOTSTRAP))
REFPLPL=$(patsubst ref/%.bootstrap, ref/%.pl.pl, $(BOOTSTRAP))
REFHEX=$(patsubst ref/%.bootstrap, ref/%.hex, $(BOOTSTRAP))
REFDUMP=$(patsubst ref/%.bootstrap, ref/%.dump, $(BOOTSTRAP))

ref: $(REFBSPL) $(REFPLPL) $(REFHEX) $(REFDUMP)

%.bs.pl: %.bootstrap
	perl tools/boot2pl $< | perltidy > $@

%.pl.pl: %.bootstrap
	perl tools/munge.pl $< | perltidy > $@

%.hex: %.bootstrap
	hexdump -C $< > $@

%.dump: %.bootstrap
	-../f4fpackager/linux/f4fpackager --input-file=$< --inspect-bootstrap > $@

ctags:
	-rm -f tags
	find ../osmf -name "*.as" -or -name "*.mxml" | ctags -L -

clean:
	-rm -f tags $(REFBSPL) $(REFPLPL) $(REFHEX) $(REFDUMP)


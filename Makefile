.PHONY: ctags default
default:
	echo "No default action"

test:
	prove -Ilib -rb t

bootstrap=$(wildcard ref/*.bootstrap)
refpl=$(patsubst ref/%.bootstrap, ref/%.pl, $(bootstrap))

ref: $(refpl)

ref/%.pl: ref/%.bootstrap
	perl tools/boxparser.pl $< | perltidy > $@

ctags:
	-rm -f tags
	find ../osmf -name "*.as" -or -name "*.mxml" | ctags -L -

clean:
	-rm -f tags $(refpl)

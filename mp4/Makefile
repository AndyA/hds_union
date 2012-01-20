.PHONY: ctags default
default:
	echo "No default action"

test:
	prove -Ilib -rb t

MP4=$(wildcard media/*.mp4)
MPL=$(patsubst media/%.mp4, media/%.pl, $(MP4))
HEX=$(patsubst media/%.mp4, media/%.hex, $(MP4))

%.pl: %.mp4
	perl tools/iso2pl.pl $< | perltidy > $@.tmp
	mv $@.tmp $@

%.hex: %.mp4
	hexdump -C $< > $@

ref: $(HEX) $(MPL)

clean:
	rm -f $(HEX) $(MPL)

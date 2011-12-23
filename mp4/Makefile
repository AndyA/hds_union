.PHONY: ctags default
default:
	echo "No default action"

test:
	prove -Ilib -rb t

MP4=$(wildcard *.mp4)
HEX=$(patsubst %.mp4, %.hex, $(MP4))

%.hex: %.mp4
	hexdump -C $< > $@

hex: $(HEX)

MMP4=$(wildcard media/*.mp4)
MPL=$(patsubst media/%.mp4, media/%.pl, $(MMP4))

%.pl: %.mp4
	perl tools/iso2pl.pl $< | perltidy > $@

pl: $(MPL)

clean:
	rm -f $(HEX) $(MPL)

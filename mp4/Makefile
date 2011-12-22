.PHONY: ctags default
default:
	echo "No default action"

test:
	prove -Ilib -rb t

MP4=$(wildcard *.mp4)
HEX=$(patsubst %.mp4, %.hex, $(MP4))

hex: $(HEX)

%.hex: %.mp4
	hexdump -C $< > $@

clean:
	rm -f $(HEX)

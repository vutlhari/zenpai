.PHONY: build run clean install

build:
	zig build -Doptimize=Debug

run:
	zig build run -Doptimize=Debug

install: build
	sudo cp zig-out/bin/zenpai /usr/local/bin/zenpai

clean:
	rm -rf \
		zig-out .zig-cache

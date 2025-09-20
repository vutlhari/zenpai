.PHONY: build run clean

build:
	zig build

run:
	zig build run

clean:
	rm -rf \
		zig-out .zig-cache

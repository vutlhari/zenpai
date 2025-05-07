run:
	zig build run

clean:
	rm -rf \
		zig-out zig-cache

.PHONY: clean

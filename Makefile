PASMO ?= pasmo
SRC := src/FDCLEAN.ASM
DIST := dist
COM := $(DIST)/FDCLEAN.COM
SYM := $(DIST)/FDCLEAN.SYM

.PHONY: all clean test

all: $(COM)

$(COM): $(SRC)
	mkdir -p $(DIST)
	$(PASMO) --bin --nocase $(SRC) $(COM) $(SYM)
	@test -s $(COM)
	@printf 'Built %s (%s bytes)\n' "$(COM)" "$$(wc -c < $(COM))"

test: $(COM)
	python3 tests/verify_build.py $(COM) $(SRC)

clean:
	rm -rf $(DIST)

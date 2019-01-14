default: convert generate

convert:
	./convert.sh

generate:
	./generate.sh

clean:
	rm -vfr build/ pics/

.PHONY: clean

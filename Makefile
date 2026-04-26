.PHONY: build run package clean

build:
	swift build

run:
	swift run AppMixer

package:
	./scripts/package-app.sh

clean:
	rm -rf .build dist

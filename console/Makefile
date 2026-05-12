FLUTTER ?= flutter

.PHONY: pub run-web run-web-profile run-web-wasm build-web build-web-wasm run-android run-linux run-linux-debug run-linux-release build-android build-linux

pub:
	$(FLUTTER) pub get

run-web: pub
	$(FLUTTER) run -d chrome

run-web-profile: pub
	$(FLUTTER) run -d chrome --profile

run-web-wasm: pub
	$(FLUTTER) run -d chrome --wasm

run-android: pub
	$(FLUTTER) run -d android

run-linux: pub
	$(FLUTTER) run -d linux --profile

run-linux-debug: pub
	$(FLUTTER) run -d linux

run-linux-release: pub
	$(FLUTTER) run -d linux --release

build-web: pub
	$(FLUTTER) build web --release -O4 --no-source-maps

build-web-wasm: pub
	$(FLUTTER) build web --wasm --release -O4 --no-source-maps

build-android: pub
	$(FLUTTER) build apk

build-linux: pub
	$(FLUTTER) build linux

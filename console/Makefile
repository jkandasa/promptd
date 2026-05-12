FLUTTER ?= flutter

.PHONY: pub run-web run-android run-linux run-linux-debug run-linux-release build-web build-android build-linux

pub:
	$(FLUTTER) pub get

run-web: pub
	$(FLUTTER) run -d chrome

run-android: pub
	$(FLUTTER) run -d android

run-linux: pub
	$(FLUTTER) run -d linux --profile

run-linux-debug: pub
	$(FLUTTER) run -d linux

run-linux-release: pub
	$(FLUTTER) run -d linux --release

build-web: pub
	$(FLUTTER) build web

build-android: pub
	$(FLUTTER) build apk

build-linux: pub
	$(FLUTTER) build linux

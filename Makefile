.PHONY: build check dmg install release publish run

build:
	./scripts/build-app.sh

check:
	xcodegen generate
	xcodebuild -quiet -project Barkeep.xcodeproj -scheme Barkeep -configuration Debug -derivedDataPath .xcode-build CODE_SIGNING_ALLOWED=NO test

dmg:
	./scripts/build-dmg.sh

install:
	./scripts/install-local.sh

release:
	./scripts/release.sh

publish:
	PUBLISH=1 ./scripts/release.sh

run: install

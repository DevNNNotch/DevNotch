.PHONY: build debug install test packaging-check

build:
	scripts/build-local --configuration Release

debug:
	scripts/build-local --configuration Debug

install:
	scripts/build-local --configuration Release --install

test:
	swift test
	python3 -m unittest discover -s Tests/Python -p 'test_*.py'

packaging-check:
	scripts/verify-packaging

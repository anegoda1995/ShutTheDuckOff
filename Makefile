APP     := ShutTheDuckOff
ID      := io.github.anegoda1995.shuttheduckoff
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
ARCHS   ?= arm64 x86_64
MIN_OS  := 14.2

BUILD   := build
BUNDLE  := $(BUILD)/$(APP).app
PLUGIN  := $(BUILD)/libnoduck_plugin.dylib
DIST    := $(BUILD)/$(APP)-$(VERSION).zip

.PHONY: all app plugin icon dist install uninstall status clean

all: app plugin

app:
	@for arch in $(ARCHS); do swift build -c release --triple $$arch-apple-macosx$(MIN_OS) || exit 1; done
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	lipo -create $(foreach arch,$(ARCHS),.build/$(arch)-apple-macosx/release/$(APP)) -output $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp -R Resources/AppIcon.icns Resources/Menu*Template*.png Resources/en.lproj Resources/uk.lproj $(BUNDLE)/Contents/Resources/
	codesign --force --sign - --identifier $(ID) $(BUNDLE)
	@echo "built $(BUNDLE) ($(VERSION), $(ARCHS))"

plugin:
	@mkdir -p $(BUILD)
	clang -O2 -Wall $(foreach arch,$(ARCHS),-arch $(arch)) -mmacosx-version-min=11.0 -bundle -fvisibility=hidden \
		-o $(PLUGIN) vlc-plugin/noduck.c -framework CoreAudio
	codesign --force --sign - $(PLUGIN)

# Needs rsvg-convert (brew install librsvg). The results are committed, so normal builds do not need it.
# 16 and 32 px are drawings of their own; the menu bar icons are template images (black with alpha).
icon:
	rm -rf $(BUILD)/AppIcon.iconset && mkdir -p $(BUILD)/AppIcon.iconset
	rsvg-convert -w 16 -h 16 assets/icon-16.svg -o $(BUILD)/AppIcon.iconset/icon_16x16.png
	rsvg-convert -w 32 -h 32 assets/icon-32.svg -o $(BUILD)/AppIcon.iconset/icon_16x16@2x.png
	rsvg-convert -w 32 -h 32 assets/icon-32.svg -o $(BUILD)/AppIcon.iconset/icon_32x32.png
	rsvg-convert -w 64 -h 64 assets/icon-32.svg -o $(BUILD)/AppIcon.iconset/icon_32x32@2x.png
	for size in 128 256 512; do \
		rsvg-convert -w $$size -h $$size assets/icon.svg -o $(BUILD)/AppIcon.iconset/icon_$${size}x$${size}.png; \
		rsvg-convert -w $$((size * 2)) -h $$((size * 2)) assets/icon.svg -o $(BUILD)/AppIcon.iconset/icon_$${size}x$${size}@2x.png; \
	done
	iconutil -c icns -o Resources/AppIcon.icns $(BUILD)/AppIcon.iconset
	for state in Waiting Active Off; do \
		svg=assets/menubar-$$(echo $$state | tr A-Z a-z).svg; \
		rsvg-convert -w 18 -h 18 $$svg -o Resources/Menu$${state}Template.png; \
		rsvg-convert -w 36 -h 36 $$svg -o Resources/Menu$${state}Template@2x.png; \
	done

dist: all
	rm -rf $(BUILD)/dist && mkdir -p $(BUILD)/dist/$(APP)
	cp -R $(BUNDLE) $(PLUGIN) scripts/install.sh scripts/uninstall.sh LICENSE $(BUILD)/dist/$(APP)/
	cd $(BUILD)/dist && ditto -c -k --keepParent $(APP) ../$(notdir $(DIST))
	@echo "packed $(DIST)"

install: all
	scripts/install.sh

uninstall:
	scripts/uninstall.sh

status:
	scripts/status.sh

clean:
	rm -rf $(BUILD) .build

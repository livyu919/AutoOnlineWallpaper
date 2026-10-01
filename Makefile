ARCHS = arm64 arm64e
TARGET = iphone:clang:17.0:17.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoOnlineWallpaper

AutoOnlineWallpaper_FILES = Tweak.xm
AutoOnlineWallpaper_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AutoOnlineWallpaper_FRAMEWORKS = UIKit SystemConfiguration CoreTelephony
AutoOnlineWallpaper_PRIVATE_FRAMEWORKS = PaperBoardUI

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "sbreload || killall -9 SpringBoard || true"

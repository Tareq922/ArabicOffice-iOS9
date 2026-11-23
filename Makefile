ARCHS = armv7
TARGET = iphone:clang:9.3:9.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ArabicOffice
ArabicOffice_FILES = main.m
ArabicOffice_FRAMEWORKS = UIKit Foundation CoreGraphics CoreText
ArabicOffice_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/application.mk

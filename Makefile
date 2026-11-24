TARGET := iphone:clang:latest:9.0
ARCHS := armv7
INSTALL_TARGET_PROCESSES := ArabicOffice

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ArabicOffice
ArabicOffice_FILES = main.m DocxHelper.m
 ArabicOffice_FRAMEWORKS = UIKit Foundation CoreGraphics CoreText ImageIO
ArabicOffice_LIBRARIES = z

include $(THEOS_MAKE_PATH)/application.mk

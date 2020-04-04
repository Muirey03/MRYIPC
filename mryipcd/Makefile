include $(THEOS)/makefiles/common.mk

TOOL_NAME = mryipcd
mryipcd_FILES = $(wildcard *.mm)
mryipcd_INSTALL_PATH = /usr/libexec
mryipcd_CODESIGN_FLAGS = -Sent.plist
mryipcd_CFLAGS = -fobjc-arc
mryipcd_PRIVATE_FRAMEWORKS = IOSurface
ADDITIONAL_CFLAGS += -DTHEOS_LEAN_AND_MEAN

include $(THEOS_MAKE_PATH)/tool.mk

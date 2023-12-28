INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ExampleServer
ExampleServer_FILES = Server.m
ExampleServer_CFLAGS = -fobjc-arc
ExampleServer_LIBRARIES = mryipc

include $(THEOS_MAKE_PATH)/tweak.mk

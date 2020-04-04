INSTALL_TARGET_PROCESSES = Apollo

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ExampleClient
ExampleClient_FILES = Tweak.x
ExampleClient_CFLAGS = -fobjc-arc
ExampleClient_LIBRARIES = mryipc

include $(THEOS_MAKE_PATH)/tweak.mk

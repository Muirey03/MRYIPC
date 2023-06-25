export ROOTLESS = 0

ifeq ($(ROOTLESS),1)
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = rootless
else
export ARCHS = armv7 arm64 arm64e
export TARGET = iphone:clang:latest:7.0
endif

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = libmryipc
libmryipc_FILES = MRYIPCCenter.m mrybootstrap.m
libmryipc_CFLAGS = -fobjc-arc -IInclude

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
libmryipc_LDFLAGS += -install_name @rpath/libmryipc.dylib
endif

include $(THEOS_MAKE_PATH)/library.mk

SUBPROJECTS += mrybootstrap

include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	cp MRYIPCCenter.h $(THEOS)/include
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	mkdir -p $(THEOS)/lib/iphone/rootless
	cp $(THEOS_STAGING_DIR)/usr/lib/libmryipc.dylib $(THEOS)/lib/iphone/rootless/
else
	cp $(THEOS_STAGING_DIR)/usr/lib/libmryipc.dylib $(THEOS)/lib
endif

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

include $(THEOS_MAKE_PATH)/library.mk

SUBPROJECTS += mrybootstrap

include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	@cp -a MRYIPCCenter.h $(THEOS_INCLUDE_PATH)
	@mkdir -p $(PWD)$(THEOS_PACKAGE_INSTALL_PREFIX)usr/lib/
	@cp -a $(THEOS_OBJ_DIR)/$(LIBRARY_NAME).dylib $(PWD)$(THEOS_PACKAGE_INSTALL_PREFIX)usr/lib/
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	@mkdir -p $(THEOS_LIBRARY_PATH)/$(THEOS_TARGET_NAME)/$(THEOS_PACKAGE_SCHEME)
	@cp -a $(THEOS_OBJ_DIR)/$(LIBRARY_NAME).dylib $(THEOS_LIBRARY_PATH)/$(THEOS_TARGET_NAME)/$(THEOS_PACKAGE_SCHEME)
else
	@cp -a $(THEOS_OBJ_DIR)/$(LIBRARY_NAME).dylib $(THEOS_LIBRARY_PATH)
endif

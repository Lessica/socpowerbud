PACKAGE_VERSION := 1.0
ARCHS := arm64
TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME := socpwrbud

socpwrbud_FILES += socpwrbud.m
socpwrbud_CFLAGS += -fobjc-arc
socpwrbud_CFLAGS += -DTHEOS
socpwrbud_LIBRARIES += IOReport
socpwrbud_FRAMEWORKS += IOKit
socpwrbud_CODESIGN_FLAGS += -Ssocpwrbud.plist
socpwrbud_INSTALL_PATH += /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
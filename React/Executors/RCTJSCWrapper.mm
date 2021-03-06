/**
 * Copyright (c) 2016-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTJSCWrapper.h"

#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

#import "RCTLog.h"

#include <dlfcn.h>

// Crash the app (with a descriptive stack trace) if a function that is not
//  supported by the system JSC is called.
#define UNIMPLEMENTED_SYSTEM_JSC_FUNCTION(FUNC_NAME) \
static void Unimplemented##FUNC_NAME(void* args...) { \
assert(false);\
}

UNIMPLEMENTED_SYSTEM_JSC_FUNCTION(JSEvaluateBytecodeBundle)

#undef UNIMPLEMENTED_SYSTEM_JSC_FUNCTION

// A no-op function, to replace void functions that do no exist in the system JSC
//  with a function that does nothing.
static void noOpSystemJSCFunc(void *args...){ }

void __attribute__((visibility("hidden"),weak)) RCTCustomJSCInit(__unused void *handle) {
  return;
}

static void *RCTCustomLibraryHandler(void)
{
  static dispatch_once_t token;
  static void *handler;
  dispatch_once(&token, ^{
    handler = dlopen("@loader_path/Frameworks/JSC.framework/JSC", RTLD_LAZY | RTLD_LOCAL);
    if (!handler) {
      const char *err = dlerror();

      // Ignore the dlopen failure if custom JSC wasn't included in our app
      // bundle. Unfortunately dlopen only provides string based errors.
      if (err != nullptr && strstr(err, "image not found") == nullptr) {
        RCTLogWarn(@"Can't load custom JSC library: %s", err);
      }
    }
  });

  return handler;
}

const int32_t JSNoBytecodeFileFormatVersion = -1;

static RCTJSCWrapper *RCTSetUpSystemLibraryPointers()
{
  return new RCTJSCWrapper {
    .JSStringCreateWithCFString = JSStringCreateWithCFString,
    .JSStringCreateWithUTF8CString = JSStringCreateWithUTF8CString,
    .JSStringRelease = JSStringRelease,
    .JSGlobalContextSetName = JSGlobalContextSetName,
    .JSObjectSetProperty = JSObjectSetProperty,
    .JSContextGetGlobalObject = JSContextGetGlobalObject,
    .JSObjectGetProperty = JSObjectGetProperty,
    .JSValueMakeFromJSONString = JSValueMakeFromJSONString,
    .JSObjectCallAsFunction = JSObjectCallAsFunction,
    .JSValueMakeNull = JSValueMakeNull,
    .JSValueCreateJSONString = JSValueCreateJSONString,
    .JSValueIsUndefined = JSValueIsUndefined,
    .JSValueIsNull = JSValueIsNull,
    .JSEvaluateScript = JSEvaluateScript,
    .JSEvaluateBytecodeBundle = (JSEvaluateBytecodeBundleFuncType)UnimplementedJSEvaluateBytecodeBundle,
    .configureJSCForIOS = (voidWithNoParamsFuncType)noOpSystemJSCFunc,
    .JSBytecodeFileFormatVersion = JSNoBytecodeFileFormatVersion,
    .JSContext = [JSContext class],
    .JSValue = [JSValue class],
  };
}

static RCTJSCWrapper *RCTSetUpCustomLibraryPointers()
{
  void *libraryHandle = RCTCustomLibraryHandler();
  if (!libraryHandle) {
    return RCTSetUpSystemLibraryPointers();
  }

  auto wrapper = new RCTJSCWrapper {
    .JSStringCreateWithCFString = (JSStringCreateWithCFStringFuncType)dlsym(libraryHandle, "JSStringCreateWithCFString"),
    .JSStringCreateWithUTF8CString = (JSStringCreateWithUTF8CStringFuncType)dlsym(libraryHandle, "JSStringCreateWithUTF8CString"),
    .JSStringRelease = (JSStringReleaseFuncType)dlsym(libraryHandle, "JSStringRelease"),
    .JSGlobalContextSetName = (JSGlobalContextSetNameFuncType)dlsym(libraryHandle, "JSGlobalContextSetName"),
    .JSObjectSetProperty = (JSObjectSetPropertyFuncType)dlsym(libraryHandle, "JSObjectSetProperty"),
    .JSContextGetGlobalObject = (JSContextGetGlobalObjectFuncType)dlsym(libraryHandle, "JSContextGetGlobalObject"),
    .JSObjectGetProperty = (JSObjectGetPropertyFuncType)dlsym(libraryHandle, "JSObjectGetProperty"),
    .JSValueMakeFromJSONString = (JSValueMakeFromJSONStringFuncType)dlsym(libraryHandle, "JSValueMakeFromJSONString"),
    .JSObjectCallAsFunction = (JSObjectCallAsFunctionFuncType)dlsym(libraryHandle, "JSObjectCallAsFunction"),
    .JSValueMakeNull = (JSValueMakeNullFuncType)dlsym(libraryHandle, "JSValueMakeNull"),
    .JSValueCreateJSONString = (JSValueCreateJSONStringFuncType)dlsym(libraryHandle, "JSValueCreateJSONString"),
    .JSValueIsUndefined = (JSValueIsUndefinedFuncType)dlsym(libraryHandle, "JSValueIsUndefined"),
    .JSValueIsNull = (JSValueIsNullFuncType)dlsym(libraryHandle, "JSValueIsNull"),
    .JSEvaluateScript = (JSEvaluateScriptFuncType)dlsym(libraryHandle, "JSEvaluateScript"),
    .JSEvaluateBytecodeBundle = (JSEvaluateBytecodeBundleFuncType)dlsym(libraryHandle, "JSEvaluateBytecodeBundle"),
    .configureJSCForIOS = (voidWithNoParamsFuncType)dlsym(libraryHandle, "configureJSCForIOS"),
    .JSBytecodeFileFormatVersion = *(const int32_t *)dlsym(libraryHandle, "JSBytecodeFileFormatVersion"),
    .JSContext = (__bridge Class)dlsym(libraryHandle, "OBJC_CLASS_$_JSContext"),
    .JSValue = (__bridge Class)dlsym(libraryHandle, "OBJC_CLASS_$_JSValue"),
  };

  static dispatch_once_t once;
  dispatch_once(&once, ^{
    RCTCustomJSCInit(libraryHandle);
  });

  return wrapper;
}

RCTJSCWrapper *RCTJSCWrapperCreate(BOOL useCustomJSC)
{
  return useCustomJSC
    ? RCTSetUpCustomLibraryPointers()
    : RCTSetUpSystemLibraryPointers();
}

void RCTJSCWrapperRelease(RCTJSCWrapper *wrapper)
{
  delete wrapper;
}

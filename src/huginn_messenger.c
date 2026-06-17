#include "huginn_messenger.h"

// This file is part of the Flutter FFI plugin that wraps the Go shared library.
//
// Build the Go library:
//   go build -buildmode=c-shared -o libhuginn_messenger.so
//
// The Go compiler auto-generates a matching header. This file provides
// the platform-specific Flutter plugin side. On most platforms, the
// exported Go functions are called directly via FFI from Dart, so this
// file serves as a reference and for any platform-specific glue.
//
// For Flutter integration, use dart:ffi to load libhuginn_messenger.so
// and bind to the functions declared in this header.

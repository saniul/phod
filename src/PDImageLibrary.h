/* -*- c-style: gnu -*-

   Copyright (c) 2013 John Harper <jsh@unfactored.org>

   Permission is hereby granted, free of charge, to any person
   obtaining a copy of this software and associated documentation files
   (the "Software"), to deal in the Software without restriction,
   including without limitation the rights to use, copy, modify, merge,
   publish, distribute, sublicense, and/or sell copies of the Software,
   and to permit persons to whom the Software is furnished to do so,
   subject to the following conditions:

   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. */

#import <Foundation/Foundation.h>

@class PDFileCatalog, PDImage;

extern NSString *const PDImageLibraryDirectoryDidChange;

@interface PDImageLibrary : NSObject
{
  NSString *_name;
  NSString *_path;
  NSString *_cachePath;
  uint32_t _libraryId;
  PDFileCatalog *_catalog;
  BOOL _transient;
  NSMutableArray *_activeImports;
}

+ (void)removeInvalidLibraries;

+ (NSArray *)allLibraries;

+ (PDImageLibrary *)libraryWithId:(uint32_t)lid;

/* Creates a new library if no existing library is found. */

+ (PDImageLibrary *)libraryWithPath:(NSString *)path;
+ (PDImageLibrary *)libraryWithPath:(NSString *)path onlyIfExists:(BOOL)flag;

+ (PDImageLibrary *)libraryWithPropertyList:(id)obj;

- (id)propertyList;

- (void)invalidate;

@property(nonatomic, copy) NSString *name;
@property(nonatomic, readonly) uint32_t libraryId;
@property(nonatomic, getter=isTransient) BOOL transient;

@property(nonatomic, readonly) NSString *path;
@property(nonatomic, readonly) NSString *cachePath;

/* 'rel_path' is relative to the root of the library. */

- (uint32_t)fileIdOfRelativePath:(NSString *)rel_path;

- (NSString *)cachePathForFileId:(uint32_t)file_id base:(NSString *)str;

/* Synchronize catalog to disk. */

- (void)synchronize;

/* Blow away all cached data. */

- (void)emptyCaches;

/* Wait for any async image imports to complete. */

- (void)waitForImportsToComplete;

/* Low-level file operations, all paths are relative to the root of the
   library. */

- (NSData *)contentsOfFile:(NSString *)rel_path;
- (BOOL)writeData:(NSData *)data toFile:(NSString *)rel_path;
- (NSArray *)contentsOfDirectory:(NSString *)rel_path;
- (BOOL)fileExistsAtPath:(NSString *)rel_path isDirectory:(BOOL *)dirp;
- (BOOL)removeItemAtPath:(NSString *)rel_path error:(NSError **)err;

/* Higher-level file primitives. */

- (void)foreachSubdirectoryOfDirectory:(NSString *)dir
    handler:(void (^)(NSString *dir_name))block;
- (void)loadImagesInSubdirectory:(NSString *)dir
    recursively:(BOOL)flag handler:(void (^)(PDImage *))block;

/* Notifications to the library that files under its path have been
   moved externally. */

- (void)didRenameDirectory:(NSString *)oldName to:(NSString *)newName;
- (void)didRenameFile:(NSString *)oldName to:(NSString *)newName;
- (void)didRemoveFileWithRelativePath:(NSString *)rel_path;

- (BOOL)copyImage:(PDImage *)image toDirectory:(NSString *)dir
    error:(NSError **)err;
- (BOOL)moveImage:(PDImage *)image toDirectory:(NSString *)dir
    error:(NSError **)err;
- (BOOL)renameDirectory:(NSString *)old_dir to:(NSString *)new_dir
    error:(NSError **)err;

- (void)importImages:(NSArray *)images toDirectory:(NSString *)dir
    fileTypes:(NSSet *)types preferredType:(NSString *)type
    filenameMap:(NSString *(^)(PDImage *src, NSString *name))f
    properties:(NSDictionary *)dict deleteSourceImages:(BOOL)flag;

@end

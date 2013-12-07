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

#import "PDImageLibrary.h"

#import "PDImage.h"

#import <stdlib.h>

#define CATALOG_FILE "catalog.json"
#define METADATA_EXTENSION "phod"
#define CACHE_BITS 6
#define CACHE_SEP '$'

@implementation PDImageLibrary

@synthesize path = _path;
@synthesize name = _name;
@synthesize libraryId = _libraryId;

static NSMutableArray *_allLibraries;

static void
add_library(PDImageLibrary *lib)
{
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    _allLibraries = [[NSMutableArray alloc] init];
  });

  [_allLibraries addObject:lib];
}

+ (NSArray *)allLibraries
{
  if (_allLibraries == nil)
    return [NSArray array];
  else
    return _allLibraries;
}

+ (PDImageLibrary *)libraryWithPath:(NSString *)path
{
  if (_allLibraries == nil)
    return nil;

  path = [path stringByStandardizingPath];

  for (PDImageLibrary *lib in _allLibraries)
    {
      if ([[lib path] isEqual:path])
	return lib;
    }

  return nil;
}

+ (PDImageLibrary *)libraryWithId:(uint32_t)lid
{
  if (_allLibraries == nil)
    return nil;

  for (PDImageLibrary *lib in _allLibraries)
    {
      if ([lib libraryId] == lid)
	return lib;
    }

  return nil;
}

- (void)dealloc
{
  [_name release];
  [_path release];
  [_cachePath release];
  [_catalog release];
  [super dealloc];
}

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [[path stringByStandardizingPath] copy];
  _name = [[path lastPathComponent] copy];

again:
  _libraryId = arc4random();
  for (PDImageLibrary *lib in _allLibraries)
    {
      if (_libraryId == [lib libraryId])
	goto again;
    }

  _catalog = [[NSMutableDictionary alloc] init];

  add_library(self);

  return self;
}

- (id)initWithPropertyList:(id)obj
{
  self = [super init];
  if (self == nil)
    return nil;

  if (![obj isKindOfClass:[NSDictionary class]])
    {
      [self release];
      return nil;
    }

  _path = [[[obj objectForKey:@"path"] stringByExpandingTildeInPath] copy];
  _name = [[obj objectForKey:@"name"] copy];
  _libraryId = [[obj objectForKey:@"libraryId"] unsignedIntValue];
  _lastFileId = [[obj objectForKey:@"lastFileId"] unsignedIntValue];

  if (_libraryId == 0)
    {
    again:
      _libraryId = arc4random();
      if (_libraryId == 0)
	goto again;
      for (PDImageLibrary *lib in _allLibraries)
	{
	  if (_libraryId == [lib libraryId])
	    goto again;
	}
    }
  else
    {
      for (PDImageLibrary *lib in _allLibraries)
	{
	  if (_libraryId == [lib libraryId])
	    {
	      [self release];
	      return [lib retain];
	    }
	}
    }

  if (_catalog == nil)
    {
      NSString *catalog_path
        = [[self cachePath] stringByAppendingPathComponent:@CATALOG_FILE];

      NSData *data = [[NSData alloc] initWithContentsOfFile:catalog_path];
      if (data != nil)
	{
	  id obj = [NSJSONSerialization
		    JSONObjectWithData:data options:0 error:nil];

	  if ([obj isKindOfClass:[NSDictionary class]])
	    _catalog = [obj mutableCopy];

	  [data release];
	}
    }

  if (_catalog == nil)
    _catalog = [[NSMutableDictionary alloc] init];

  [self validateCaches];

  add_library(self);

  return self;
}

- (id)propertyList
{
  return @{
    @"path": [_path stringByAbbreviatingWithTildeInPath],
    @"name": _name,
    @"libraryId": @(_libraryId),
    @"lastFileId": @(_lastFileId)
  };
}

- (void)synchronize
{
  NSString *path = [[self cachePath]
		    stringByAppendingPathComponent:@CATALOG_FILE];

  NSData *data = [NSJSONSerialization
		  dataWithJSONObject:_catalog options:0 error:nil];

  if (data == nil
      || ![data writeToFile:path atomically:YES])
    {    
      [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (void)remove
{
  [self emptyCaches];

  NSInteger idx = [_allLibraries indexOfObjectIdenticalTo:self];
  if (idx != NSNotFound)
    [_allLibraries removeObjectAtIndex:idx];
}

static unsigned int
convert_hexdigit(int c)
{
  if (c >= '0' && c <= '9')
    return c - '0';
  else if (c >= 'A' && c <= 'F')
    return 10 + c - 'A';
  else if (c >= 'a' && c <= 'f')
    return 10 + c - 'a';
  else
    return 0;
}

- (void)validateCaches
{
  /* This runs immediately after loading the catalog and before we pull
     anything out of the cache. It scans the cache directory hierarchy
     for any files that don't exist in the catalog and deletes them.

     This is to handle the case where the app crashed after finding new
     files (adding their results to the cache) but before writing out
     the updated catalog and library state. In this case we'll reuse
     image ids and musn't find data for those ids already in the cache.

     Note that this doesn't handle removing items from the cache that
     exist in the catalog but not in the library itself. That will be a
     separate scanning pass done once the app is up and running (not
     crucial, only to reclaim cache space). */

  @autoreleasepool
    {
      NSString *dir = [self cachePath];
      NSFileManager *fm = [NSFileManager defaultManager];

      NSMutableIndexSet *catalog = [NSMutableIndexSet indexSet];

      for (NSString *key in _catalog)
	[catalog addIndex:[[_catalog objectForKey:key] unsignedIntValue]];

      unsigned int i;
      for (i = 0; i < (1U << CACHE_BITS); i++)
	{
	  NSString *path = [dir stringByAppendingPathComponent:
			    [NSString stringWithFormat:@"%02x", i]];
	  if (![fm fileExistsAtPath:path])
	    continue;

	  for (NSString *file in [fm contentsOfDirectoryAtPath:path error:nil])
	    {
	      const char *str = [file UTF8String];
	      const char *end = strchr(str, CACHE_SEP);

	      BOOL delete = NO;
	      if (end != NULL)
		{
		  uint32_t fid = 0;
		  for (; str != end; str++)
		    fid = fid * 16 + convert_hexdigit(*str);
		  fid = (fid << CACHE_BITS) | i;
		  if (![catalog containsIndex:fid])
		    delete = YES;
		}
	      else
		delete = YES;

	      if (delete)
		{
		  NSLog(@"PDImageLibrary: orphan cache entry: %02x/%@",
			i, file);
		  [fm removeItemAtPath:
		   [path stringByAppendingPathComponent:file] error:nil];
		}
	    }
	}
    }
}

- (void)emptyCaches
{
  if (_cachePath != nil)
    {
      [[NSFileManager defaultManager] removeItemAtPath:_cachePath error:nil];
      [_cachePath release];
      _cachePath = nil;
    }
}

- (NSString *)cachePath
{
  if (_cachePath == nil)
    {
      NSArray *paths = (NSSearchPathForDirectoriesInDomains
			(NSCachesDirectory, NSUserDomainMask, YES));

      NSString *cache_root
        = [[[paths lastObject] stringByAppendingPathComponent:
	    [[NSBundle mainBundle] bundleIdentifier]]
	   stringByAppendingPathComponent:@"library"];

      _cachePath = [[cache_root stringByAppendingPathComponent:
		     [NSString stringWithFormat:@"%08x", _libraryId]] copy];

      NSFileManager *fm = [NSFileManager defaultManager];

      if (![fm fileExistsAtPath:_cachePath])
	{
	  [fm createDirectoryAtPath:_cachePath
	   withIntermediateDirectories:YES attributes:nil error:nil];
	}
    }

  return _cachePath;
}

- (NSString *)cachePathForFileId:(uint32_t)file_id base:(NSString *)str
{
  NSString *base = [NSString stringWithFormat:@"%02x/%x%c%@",
		    file_id & ((1U << CACHE_BITS) - 1),
		    file_id >> CACHE_BITS, CACHE_SEP, str];

  return [[self cachePath] stringByAppendingPathComponent:base];
}

- (uint32_t)fileIdOfPath:(NSString *)path
{
  if (![path hasPrefix:_path])
    return 0;

  NSInteger len = [_path length];
  if ([path characterAtIndex:len] == '/')
    len++;

  NSString *rel_path = [path substringFromIndex:len];

  NSNumber *obj = [_catalog objectForKey:rel_path];

  if (obj != nil)
    return [obj unsignedIntValue];

  uint32_t fid = ++_lastFileId;

  [_catalog setObject:[NSNumber numberWithUnsignedInt:fid] forKey:rel_path];

  return fid;
}

static NSSet *
raw_extensions(void)
{
  static NSSet *set;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    set = [[NSSet alloc] initWithObjects:
	   @"arw", @"cr2", @"crw", @"dng", @"fff", @"3fr", @"tif",
	   @"tiff", @"raw", @"nef", @"nrw", @"sr2", @"srf", @"srw",
	   @"erf", @"mrw", @"rw2", @"rwz", @"orf", nil];
  });

  return set;
}

/* 'ext' must be lowercase. */

static NSString *
filename_with_extension(NSString *path, NSSet *filenames,
			NSString *stem, NSString *ext)
{
  NSString *lower = [stem stringByAppendingPathExtension:ext];
  if ([filenames containsObject:lower])
    return [path stringByAppendingPathComponent:lower];

  NSString *upper = [stem stringByAppendingPathExtension:
		     [ext uppercaseString]];
  if ([filenames containsObject:upper])
    return [path stringByAppendingPathComponent:upper];

  return nil;
}

static NSString *
filename_with_extension_in_set(NSString *path, NSSet *filenames,
			       NSString *stem, NSSet *exts)
{
  for (NSString *ext in exts)
    {
      NSString *ret = filename_with_extension(path, filenames, stem, ext);
      if (ret != nil)
	return ret;
    }

  return nil;
}

- (void)loadImagesInSubdirectory:(NSString *)dir
    handler:(void (^)(PDImage *))block
{
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir_path = [_path stringByAppendingPathComponent:dir];

  NSSet *filenames = [[NSSet alloc] initWithArray:
		      [fm contentsOfDirectoryAtPath:dir_path error:nil]];

  NSMutableSet *stems = [[NSMutableSet alloc] init];

  for (NSString *file in filenames)
    {
      @autoreleasepool
        {
	  if ([file characterAtIndex:0] == '.')
	    continue;

	  NSString *path = [dir_path stringByAppendingPathComponent:file];
	  BOOL is_dir = NO;
	  if (![fm fileExistsAtPath:path isDirectory:&is_dir] || is_dir)
	    continue;

	  NSString *ext = [[file pathExtension] lowercaseString];

	  if (![ext isEqualToString:@METADATA_EXTENSION]
	      && ![ext isEqualToString:@"jpg"]
	      && ![ext isEqualToString:@"jpeg"]
	      && ![raw_extensions() containsObject:ext])
	    {
	      continue;
	    }

	  NSString *stem = [file stringByDeletingPathExtension];
	  if ([stems containsObject:stem])
	    continue;

	  [stems addObject:stem];

	  NSString *json_path
	    = filename_with_extension(dir_path, filenames,
				      stem, @METADATA_EXTENSION);
	  NSString *jpeg_path
	    = filename_with_extension(dir_path, filenames, stem, @"jpg");
	  if (jpeg_path == nil)
	    {
	      jpeg_path = filename_with_extension(dir_path, filenames,
						  stem, @"jpeg");
	    }
	  NSString *raw_path
	    = filename_with_extension_in_set(dir_path, filenames,
					     stem, raw_extensions());

	  PDImage *image = [[PDImage alloc] initWithLibrary:self
			    directory:dir name:stem JSONPath:json_path
			    JPEGPath:jpeg_path RAWPath:raw_path];
	  if (image != nil)
	    {
	      block(image);
	      [image release];
	    }
	}
    }

  [stems release];
  [filenames release];
}

@end
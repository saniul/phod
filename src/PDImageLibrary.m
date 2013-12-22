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

#import "PDAppDelegate.h"
#import "PDFileCatalog.h"
#import "PDImage.h"

#import <stdlib.h>
#import <utime.h>

#define CATALOG_FILE "catalog.json"
#define METADATA_EXTENSION "phod"
#define CACHE_BITS 6
#define CACHE_SEP '$'

#define ERROR_DOMAIN @"org.unfactored.PDImageLibrary"

NSString *const PDImageLibraryDirectoryDidChange = @"PDImageLibraryDirectoryDidChangeDidChange";

@interface PDImageLibrary ()
- (id)initWithDictionary:(NSDictionary *)dict;
- (void)validateCaches;
@end

@implementation PDImageLibrary

@synthesize name = _name;
@synthesize libraryId = _libraryId;
@synthesize transient = _transient;
@synthesize path = _path;

static NSMutableArray *_allLibraries;

static NSString *
cache_root(void)
{
  NSArray *paths = (NSSearchPathForDirectoriesInDomains
		    (NSCachesDirectory, NSUserDomainMask, YES));

  return [[[paths lastObject] stringByAppendingPathComponent:
	   [[NSBundle mainBundle] bundleIdentifier]]
	  stringByAppendingPathComponent:@"library"];
}

static NSString *
catalog_path(PDImageLibrary *self)
{
  return [[self cachePath] stringByAppendingPathComponent:@CATALOG_FILE];
}

+ (void)removeInvalidLibraries
{
  /* For now, simply remove any libraries that don't have catalogs. By
     definition they're useless to us. (E.g. transient libraries for
     SD cards that were left around after an app crash.) */

  assert(_allLibraries == nil);

  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir = cache_root();

  for (NSString *file in [fm contentsOfDirectoryAtPath:dir error:nil])
    {
      NSString *path = [dir stringByAppendingPathComponent:file];

      NSString *catalog_path
        = [path stringByAppendingPathComponent:@CATALOG_FILE];

      if (![fm fileExistsAtPath:catalog_path])
	{
	  NSLog(@"PDImageLibrary: orphan library: %@", file);
	  [fm removeItemAtPath:path error:nil];
	}
    }
}

+ (NSArray *)allLibraries
{
  if (_allLibraries == nil)
    return [NSArray array];
  else
    return _allLibraries;
}

+ (PDImageLibrary *)findLibraryWithPath:(NSString *)path
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

+ (PDImageLibrary *)libraryWithPath:(NSString *)path
{
  return [self libraryWithPath:path onlyIfExists:NO];
}

+ (PDImageLibrary *)libraryWithPath:(NSString *)path onlyIfExists:(BOOL)flag
{
  path = [path stringByStandardizingPath];

  if (_allLibraries != nil)
    {
      for (PDImageLibrary *lib in _allLibraries)
	{
	  if ([[lib path] isEqualToString:path])
	    return lib;
	}
    }

  if (flag)
    return nil;
  else
    return [[[self alloc] initWithDictionary:@{@"path": path}] autorelease];
}

+ (PDImageLibrary *)libraryWithPropertyList:(id)obj
{
  if (![obj isKindOfClass:[NSDictionary class]])
    return nil;

  NSString *path = [[obj objectForKey:@"path"] stringByExpandingTildeInPath];
  if (path == nil)
    return nil;

  path = [path stringByStandardizingPath];

  if (_allLibraries != nil)
    {
      for (PDImageLibrary *lib in _allLibraries)
	{
	  if ([[lib path] isEqualToString:path])
	    return lib;
	}
    }

  return [[[self alloc] initWithDictionary:obj] autorelease];
}

- (id)initWithDictionary:(NSDictionary *)dict
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [[[[dict objectForKey:@"path"] stringByExpandingTildeInPath]
	    stringByStandardizingPath] copy];

  _name = [[dict objectForKey:@"name"] copy];
  if (_name == nil)
    _name = [[_path lastPathComponent] copy];

  _libraryId = [[dict objectForKey:@"libraryId"] unsignedIntValue];

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

  _catalog = [[PDFileCatalog alloc] initWithContentsOfFile:catalog_path(self)];

  [self validateCaches];

  if (_allLibraries == nil)
    _allLibraries = [[NSMutableArray alloc] init];

  [_allLibraries addObject:self];

  return self;
}

- (id)propertyList
{
  return @{
    @"path": [_path stringByAbbreviatingWithTildeInPath],
    @"name": _name,
    @"libraryId": @(_libraryId),
  };
}

- (void)dealloc
{
  [_name release];
  [_path release];
  [_cachePath release];
  [_catalog release];
  [_activeImports release];
  [super dealloc];
}

- (void)synchronize
{
  [_catalog synchronizeWithContentsOfFile:catalog_path(self)];
}

- (void)remove
{
  [self waitForImportsToComplete];

  [self emptyCaches];

  [_catalog release];
  _catalog = nil;

  NSInteger idx = [_allLibraries indexOfObjectIdenticalTo:self];
  if (idx != NSNotFound)
    [_allLibraries removeObjectAtIndex:idx];
}

- (void)didRenameDirectory:(NSString *)oldName to:(NSString *)newName
{
  [_catalog renameDirectory:oldName to:newName];
}

- (void)didRenameFile:(NSString *)oldName to:(NSString *)newName
{
  [_catalog renameFile:oldName to:newName];
}

- (void)didRemoveFileWithRelativePath:(NSString *)rel_path
{
  [_catalog removeFileWithPath:rel_path];
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

     Note that this doesn't immediately remove items from the cache
     that exist in the catalog but not in the library itself. Due to
     how we double-buffer catalog dictionaries to remove unused file
     ids, any missing files will be removed when -validateCaches is
     called the next time the app is launched.

     (Or we could choose a point after all libraries have been scanned
     to release _catalog0 then call -validateCaches.) */

  @autoreleasepool
    {
      NSString *dir = [self cachePath];
      NSFileManager *fm = [NSFileManager defaultManager];

      NSIndexSet *catalogIds = [_catalog allFileIds];

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
		  if (![catalogIds containsIndex:fid])
		    delete = YES;
		}
	      else
		delete = YES;

	      if (delete)
		{
		  NSLog(@"PDImageLibrary: cache orphan: %02x/%@", i, file);
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

      [_catalog release];
      _catalog = [[PDFileCatalog alloc] init];
    }
}

- (NSString *)cachePath
{
  if (_cachePath == nil)
    {
      _cachePath = [[cache_root() stringByAppendingPathComponent:
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

- (uint32_t)fileIdOfRelativePath:(NSString *)rel_path
{
  return [_catalog fileIdForPath:rel_path];
}

static NSSet *
raw_extensions(void)
{
  static NSSet *set;
  static dispatch_once_t once;

  dispatch_once(&once, ^
    {
      set = [[NSSet alloc] initWithObjects:
	     @"arw", @"cr2", @"crw", @"dng", @"fff", @"3fr", @"tif",
	     @"tiff", @"raw", @"nef", @"nrw", @"sr2", @"srf", @"srw",
	     @"erf", @"mrw", @"rw2", @"rwz", @"orf", nil];
    });

  return set;
}

static NSSet *
jpeg_extensions(void)
{
  static NSSet *set;
  static dispatch_once_t once;

  dispatch_once(&once, ^
    {
      set = [[NSSet alloc] initWithObjects:@"jpg", @"jpeg", @"jpe", nil];
    });

  return set;
}

static NSSet *
jpeg_and_raw_extensions(void)
{
  static NSSet *set;
  static dispatch_once_t once;

  dispatch_once(&once, ^
    {
      set = [[raw_extensions()
	      setByAddingObjectsFromSet:jpeg_extensions()] copy];
    });

  return set;
}

/* 'ext' must be lowercase. */

static NSString *
filename_with_ext(NSSet *filenames, NSString *stem, NSString *ext)
{
  NSString *lower = [stem stringByAppendingPathExtension:ext];
  if ([filenames containsObject:lower])
    return lower;

  NSString *upper = [stem stringByAppendingPathExtension:
		     [ext uppercaseString]];
  if ([filenames containsObject:upper])
    return upper;

  return nil;
}

static NSString *
filename_with_ext_in_set(NSSet *filenames, NSString *stem, NSSet *exts)
{
  for (NSString *ext in exts)
    {
      NSString *ret = filename_with_ext(filenames, stem, ext);
      if (ret != nil)
	return ret;
    }

  return nil;
}

- (void)foreachSubdirectoryOfDirectory:(NSString *)dir
    handler:(void (^)(NSString *dir_name))block
{
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir_path = [_path stringByAppendingPathComponent:dir];

  for (NSString *file in [fm contentsOfDirectoryAtPath:dir_path error:nil])
    {
      if ([file characterAtIndex:0] == '.')
	continue;

      BOOL is_dir = NO;
      NSString *path = [dir_path stringByAppendingPathComponent:file];
      if (![fm fileExistsAtPath:path isDirectory:&is_dir] || !is_dir)
	continue;

      block(file);
    }
}

- (void)loadImagesInSubdirectory:(NSString *)dir
    recursively:(BOOL)flag handler:(void (^)(PDImage *))block
{
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir_path = [_path stringByAppendingPathComponent:dir];

  NSArray *files = [fm contentsOfDirectoryAtPath:dir_path error:nil];
  NSMutableSet *unused_files = [[NSMutableSet alloc] initWithArray:files];

  /* Two passes so we can read .phod files first. These may reference
     JPEG / RAW files, and if so we don't want to add those images
     separately. */

  for (int pass = 0; pass < 2; pass++)
    {
      for (NSString *file in files)
	{
	  @autoreleasepool
	    {
	      if ([file characterAtIndex:0] == '.')
		continue;
	      if (![unused_files containsObject:file])
		continue;

	      NSString *path = [dir_path stringByAppendingPathComponent:file];
	      BOOL is_dir = NO;
	      if (![fm fileExistsAtPath:path isDirectory:&is_dir])
		continue;
	      if (is_dir)
		{
		  if (flag && pass == 0)
		    {
		      [self loadImagesInSubdirectory:
		       [dir stringByAppendingPathComponent:file]
		       recursively:YES handler:block];
		    }
		  continue;
		}

	      NSString *ext = [[file pathExtension] lowercaseString];

	      if (pass == 0 && ![ext isEqualToString:@METADATA_EXTENSION])
		continue;
	      if (pass == 1 && ![jpeg_and_raw_extensions() containsObject:ext])
		continue;

	      NSString *stem = [file stringByDeletingPathExtension];

	      NSString *json_file = filename_with_ext(unused_files,
						stem, @METADATA_EXTENSION);
	      NSString *jpeg_file = filename_with_ext_in_set(unused_files,
						stem, jpeg_extensions());
	      NSString *raw_file = filename_with_ext_in_set(unused_files,
						stem, raw_extensions());

	      PDImage *image = [[PDImage alloc] initWithLibrary:self
				directory:dir JSONFile:json_file
				JPEGFile:jpeg_file RAWFile:raw_file];

	      if (image != nil)
		{
		  block(image);

		  NSString *json_file = [image JSONFile];
		  if (json_file != nil)
		    [unused_files removeObject:json_file];

		  NSString *jpeg_file = [image JPEGFile];
		  if (jpeg_file != nil)
		    [unused_files removeObject:jpeg_file];

		  NSString *raw_file = [image RAWFile];
		  if (raw_file != nil)
		    [unused_files removeObject:raw_file];

		  [image release];
		}
	    }
	}
    }

  [unused_files release];
}

static NSOperationQueue *_copyQueue;

+ (NSOperationQueue *)copyQueue
{
  static dispatch_once_t once;

  dispatch_once(&once, ^
    {
      _copyQueue = [[NSOperationQueue alloc] init];
      [_copyQueue setName:@"PDImageLibrary.copyQueue"];
      [_copyQueue setMaxConcurrentOperationCount:2];
      [_copyQueue addObserver:(id)self
       forKeyPath:@"operationCount" options:0 context:NULL];
    });

  return _copyQueue;
}

+ (void)observeValueForKeyPath:(NSString *)path ofObject:(id)obj
    change:(NSDictionary *)dict context:(void *)ctx
{
  if ([path isEqualToString:@"operationCount"])
    {
      dispatch_async(dispatch_get_main_queue(), ^
	{
	  NSInteger count = [_copyQueue operationCount];
	  PDAppDelegate *delegate = [NSApp delegate];
	  if (count != 0)
	    [delegate addBackgroundActivity:@"PDImageLibrary"];
	  else
	    [delegate removeBackgroundActivity:@"PDImageLibrary"];
	});
    }
}

- (void)reclaimImportBlocks
{
  NSInteger i = 0, count = [_activeImports count];

  while (i < count)
    {
      NSOperation *op = [_activeImports objectAtIndex:i];
      if ([op isFinished])
	{
	  [_activeImports removeObjectAtIndex:i];
	  count--;
	}
      else
	i++;
    }
}

- (void)waitForImportsToComplete
{
  for (NSOperation *op in _activeImports)
    {
      [op waitUntilFinished];
    }

  [_activeImports removeAllObjects];
}

- (BOOL)copyImage:(PDImage *)image toDirectory:(NSString *)dir
    error:(NSError **)err
{
  NSString *dir_path = [_path stringByAppendingPathComponent:dir];

  BOOL ret = [image copyToDirectoryPath:dir_path resetUUID:YES error:err];

  if (ret)
    {
      /* FIXME: pass UUIDs of changed image(s)? */

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageLibraryDirectoryDidChange
       object:self userInfo:@{@"libraryDirectory": dir}];
    }

  return ret;
}

- (BOOL)moveImage:(PDImage *)image toDirectory:(NSString *)dir
    error:(NSError **)err
{
  PDImageLibrary *src_lib = [image library];
  NSString *src_dir = [image libraryDirectory];
  BOOL ret = NO;

  if (src_lib == self)
    {
      if ([src_dir isEqualToString:dir])
	return YES;

      ret = [image moveToDirectory:dir error:err];

      if (ret && [image isDeleted])
	[image setDeleted:NO];
    }
  else
    {
      NSString *dir_path = [_path stringByAppendingPathComponent:dir];

      if ([image copyToDirectoryPath:dir_path resetUUID:NO error:err])
	{
	  [image remove];
	  ret = YES;
	}
    }

  if (ret)
    {
      /* FIXME: pass UUIDs of changed image(s)? */

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageLibraryDirectoryDidChange
       object:src_lib userInfo:@{@"libraryDirectory": src_dir}];

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageLibraryDirectoryDidChange
       object:self userInfo:@{@"libraryDirectory": dir}];
    }

  return ret;
}

static NSString *
find_unique_path(NSFileManager *fm, NSString *path)
{
  NSString *ext = [path pathExtension];
  NSString *rest = [path stringByDeletingPathExtension];

  for (int i = 0;; i++)
    {
      NSString *tem;
      if (i == 0)
	tem = path;
      else
	tem = [NSString stringWithFormat:@"%@-%d.%@", rest, i, ext];
      if (![fm fileExistsAtPath:tem])
	return tem;
    }

  /* not reached. */
}

static BOOL
copy_item_atomically(NSFileManager *fm, NSString *src_path,
		     NSString *dst_path, NSError **err)
{
  /* Put a "." in front of the file name to hide it until we move it
     into place. */

  NSString *tmp_path = [[dst_path stringByDeletingLastPathComponent]
			stringByAppendingPathComponent:
			  [@"." stringByAppendingString:
			   [dst_path lastPathComponent]]];

  if (![fm copyItemAtPath:src_path toPath:tmp_path error:err])
    return NO;

  /* Bump the mtime of the written files, -copyItemAtPath: doesn't, and
     we need to invalidate anything in the proxy cache that may have
     the same name. */

  time_t now = time(NULL);
  struct utimbuf times = {.actime = now, .modtime = now};
  utime([tmp_path fileSystemRepresentation], &times);

  if (![fm moveItemAtPath:tmp_path toPath:dst_path error:err])
    {
      [fm removeItemAtPath:tmp_path error:nil];
      return NO;
    }

  return YES;
}

- (BOOL)renameDirectory:(NSString *)old_dir to:(NSString *)new_dir
    error:(NSError **)err
{
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *old_path = [_path stringByAppendingPathComponent:old_dir];
  NSString *new_path = [_path stringByAppendingPathComponent:new_dir];

  BOOL is_dir = NO;
  if (![fm fileExistsAtPath:old_path isDirectory:&is_dir] || !is_dir)
    {
      if (err != NULL)
	{
	  NSString *str = [NSString stringWithFormat:
			   @"Can't rename directory %@ to %@, the source"
			   " directory doesn't exist.", old_dir, new_dir];
	  *err = [NSError errorWithDomain:ERROR_DOMAIN code:1
		  userInfo:@{NSLocalizedDescriptionKey: str}];
	}
      return NO;
    }

  if ([fm fileExistsAtPath:new_path])
    {
      if (err != NULL)
	{
	  NSString *str = [NSString stringWithFormat:
			   @"Can't rename directory %@ to %@, the destination"
			   " name is already in use.", old_dir, new_dir];
	  *err = [NSError errorWithDomain:ERROR_DOMAIN code:1
		  userInfo:@{NSLocalizedDescriptionKey: str}];
	}
      return NO;
    }

  if (![fm moveItemAtPath:old_path toPath:new_path error:err])
    return NO;

  [self didRenameDirectory:old_dir to:new_dir];

  return YES; 
}

- (void)importImages:(NSArray *)images toDirectory:(NSString *)dir
    fileTypes:(NSSet *)types preferredType:(NSString *)active_type
    filenameMap:(NSString *(^)(PDImage *src, NSString *name))f
    properties:(NSDictionary *)dict deleteSourceImages:(BOOL)delete_sources
{
  if ([images count] == 0)
    return;

  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir_path = [_path stringByAppendingPathComponent:dir];
  BOOL new_dir = NO;

  /* FIXME: check that dir_path is under _path? */

  BOOL is_dir = NO;
  if (![fm fileExistsAtPath:dir_path isDirectory:&is_dir])
    {
      new_dir = YES;
      if (![fm createDirectoryAtPath:dir_path withIntermediateDirectories:YES
	   attributes:nil error:nil])
	return;
    }
  else if (!is_dir)
    return;

  __block BOOL pending_notification = NO;

  NSDictionary *notification_info = @{@"libraryDirectory": dir};

  /* Called on main thread. */

  void (^post_notification)() = ^
    {
      if (!pending_notification)
	{
	  pending_notification = YES;

	  dispatch_time_t t
	    = dispatch_time(DISPATCH_TIME_NOW, 1LL * NSEC_PER_SEC);

	  dispatch_after(t, dispatch_get_main_queue(), ^
	    {
	      pending_notification = NO;

	      [[NSNotificationCenter defaultCenter]
	       postNotificationName:PDImageLibraryDirectoryDidChange
	       object:self userInfo:notification_info];
	    });
	}
    };

  __block NSError *error = nil;

  void (^set_error)(NSError *err) = ^(NSError *err)
    {
      dispatch_async(dispatch_get_main_queue(), ^
	{
	  [error release];
	  error = [err copy];
	});
    };

  NSMutableSet *all_libraries = [NSMutableSet set];
  [all_libraries addObject:self];
  for (PDImage *src_im in images)
    [all_libraries addObject:[src_im library]];

  NSMutableArray *dest_files = [NSMutableArray array];

  /* Final NSOperation that depends on all copy/write ops. It moves
     work synchronously back to the main thread and cleans up, presents
     any errors etc. */

  NSOperation *final_op = [NSBlockOperation blockOperationWithBlock:^
    {
      dispatch_sync(dispatch_get_main_queue(), ^
	{
	  if (error == nil)
	    {
	      if (delete_sources)
		{
		  for (PDImage *src_im in images)
		    [src_im remove];
		}
	    }
	  else
	    {
	      if (new_dir)
		[fm removeItemAtPath:dir_path error:nil];
	      else
		{
		  for (NSString *path in dest_files)
		    [fm removeItemAtPath:path error:nil];
		}

	      post_notification();

	      NSAlert *alert = [NSAlert alertWithError:error];
	      [alert runModal];
	    }

	  for (PDImageLibrary *lib in all_libraries)
	    [lib reclaimImportBlocks];
	});
    }];

  NSOperationQueue *queue = [PDImageLibrary copyQueue];

  for (PDImage *src_im in images)
    {
      NSString *name = [[src_im imageFile] stringByDeletingPathExtension];
      if (f != NULL)
	name = f(src_im, name);
      if (name == nil)
	continue;

      NSArray *src_types = [src_im imagePropertyForKey:PDImage_FileTypes];
      NSMutableArray *dst_types = [NSMutableArray array];
      NSMutableArray *dst_paths = [NSMutableArray array];

      NSString *JPEG_file = nil;
      NSString *RAW_file = nil;

      NSOperation *JPEG_op = nil;
      NSOperation *RAW_op = nil;

      for (NSString *type in src_types)
	{
	  NSString *src_path = nil;
	  NSString **dst_file_ptr = NULL;
	  NSOperation **op_ptr = NULL;

	  if (JPEG_file == nil
	      && [type isEqualToString:@"public.jpeg"]
	      && [types containsObject:type])
	    {
	      src_path = [src_im JPEGPath];
	      dst_file_ptr = &JPEG_file;
	      op_ptr = &JPEG_op;
	    }
	  else if (RAW_file == nil
		   && ![type isEqualToString:@"public.jpeg"]
		   && [types containsObject:@"public.camera-raw-image"])
	    {
	      src_path = [src_im RAWPath];
	      dst_file_ptr = &RAW_file;
	      op_ptr = &RAW_op;
	    }

	  if (src_path != nil)
	    {
	      NSString *dst_file = [name stringByAppendingPathExtension:
				    [src_path pathExtension]];
	      NSString *dst_path = [dir_path stringByAppendingPathComponent:
				    dst_file];
                             
	      /* FIXME: if file already exists at destination path,
		check if it's the same file and merge the two? */

	      if ([fm fileExistsAtPath:dst_path])
		{
		  dst_path = find_unique_path(fm, dst_path);
		  dst_file = [dst_path lastPathComponent];
		}

	      *dst_file_ptr = dst_file;
	      [dst_types addObject:type];
	      [dst_paths addObject:dst_path];

	      *op_ptr = [NSBlockOperation blockOperationWithBlock:^
		{
		  if (error != nil)
		    return;
		  NSError *err = nil;
		  if (copy_item_atomically(fm, src_path, dst_path, &err))
		    {
		      dispatch_async(dispatch_get_main_queue(), ^
			{
			  [dest_files addObject:dst_path];
			});
		    }
		  else if (err != nil)
		    set_error(err);
		}];
	    }
	}

      if ([dst_types count] != 0)
	{
	  NSMutableDictionary *dst_props = [NSMutableDictionary dictionary];

	  static NSSet *ignored_keys;
	  static dispatch_once_t once;

	  dispatch_once(&once, ^
	    {
	      ignored_keys = [[NSSet alloc] initWithObjects:PDImage_Name,
			      PDImage_FileTypes, PDImage_ActiveType, nil];
	    });

	  NSDictionary *src_props = [src_im explicitProperties];
	  for (NSString *key in src_props)
	    {
	      if (![ignored_keys containsObject:key])
		[dst_props setObject:[src_props objectForKey:key] forKey:key];
	    }

	  if (dict != nil)
	    [dst_props addEntriesFromDictionary:dict];

	  [dst_props setObject:dst_types forKey:PDImage_FileTypes];

	  NSString *dst_active = active_type;
	  if (![dst_types containsObject:dst_active])
	    dst_active = [dst_types firstObject];

	  [dst_props setObject:dst_active forKey:PDImage_ActiveType];

	  NSMutableDictionary *json_dict = [NSMutableDictionary dictionary];

	  [json_dict setObject:dst_props forKey:@"Properties"];

	  if (JPEG_file != nil)
	    [json_dict setObject:JPEG_file forKey:@"JPEGFile"];
	  if (RAW_file != nil)
	    [json_dict setObject:RAW_file forKey:@"RAWFile"];

	  NSString *json_path = [dir_path stringByAppendingPathComponent:
				 [name stringByAppendingPathExtension:
				  @METADATA_EXTENSION]];

	  if ([fm fileExistsAtPath:json_path])
	    json_path = find_unique_path(fm, json_path);

	  NSOperation *json_op = [NSBlockOperation blockOperationWithBlock:^
	    {
	      if (error != nil)
		return;
	      NSData *data = [NSJSONSerialization dataWithJSONObject:json_dict
			      options:NSJSONWritingPrettyPrinted error:nil];
	      NSError *err = nil;
	      if ([data writeToFile:json_path options:0 error:&err])
		{
		  dispatch_async(dispatch_get_main_queue(), ^
		    {
		      [dest_files addObject:json_path];
		      post_notification();
		    });
		}
	      else if (err != nil)
		set_error(err);
	    }];

	  NSOperation *main_op = nil, *secondary_op = nil;

	  if ([active_type isEqualToString:@"public.jpeg"])
	    main_op = JPEG_op, secondary_op = RAW_op;
	  else
	    main_op = RAW_op, secondary_op = JPEG_op;
	
	  if (main_op != nil)
	    {
	      [queue addOperation:main_op];
	      [final_op addDependency:main_op];
	    }

	  if (secondary_op != nil)
	    {
	      [secondary_op setQueuePriority:NSOperationQueuePriorityLow];
	      [queue addOperation:secondary_op];
	      [final_op addDependency:secondary_op];
	    }

	  [json_op setQueuePriority:NSOperationQueuePriorityHigh];
	  [json_op addDependency:main_op];
	  [queue addOperation:json_op];

	  [final_op addDependency:json_op];
	}
    }

  /* Add the sentinel operation to the list of active imports of all
     libraries either a source or destination for the set of files
     being copied. This will prevent them being destroyed or unmounted
     (by us) until the copies have completed asynchronously. */

  for (PDImageLibrary *lib in all_libraries)
    {
      if (lib->_activeImports == nil)
	lib->_activeImports = [[NSMutableArray alloc] init];

      [lib->_activeImports addObject:final_op];
    }

  [queue addOperation:final_op];

  if (new_dir)
    {
      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageLibraryDirectoryDidChange
       object:self userInfo:notification_info];
    }
}

@end

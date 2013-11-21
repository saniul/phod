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

#import "PDLibraryDirectory.h"

#import "PDAppKitExtensions.h"
#import "PDImage.h"

@implementation PDLibraryDirectory

@synthesize path = _path;
@synthesize titleImageName = _titleImageName;

+ (NSSet *)imagePathExtensions
{
  static NSSet *set;

  // FIXME: handle RAW files later

  if (set == nil)
    {
      set = [[NSSet alloc] initWithObjects:@"jpg", @"JPG", @"jpeg",
	     @"JPEG", nil];
    }

  return set;
}

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [path copy];
  _titleImageName = PDImage_GenericFolder;

  return self;
}

- (void)dealloc
{
  [_path release];
  [_subitems release];
  [_images release];
  [_subimages release];
  [super dealloc];
}

- (NSArray *)subitems
{
  NSFileManager *fm;
  NSMutableArray *array;
  NSString *path;
  BOOL dir;
  PDLibraryDirectory *subitem;

  if (_subitems == nil)
    {
      fm = [NSFileManager defaultManager];
      array = [[NSMutableArray alloc] init];

      for (NSString *file in [fm contentsOfDirectoryAtPath:_path error:nil])
	{
	  if ([file characterAtIndex:0] == '.')
	    continue;

	  path = [_path stringByAppendingPathComponent:file];
	  dir = NO;
	  if (![fm fileExistsAtPath:path isDirectory:&dir])
	    continue;

	  if (dir)
	    {
	      subitem = [[PDLibraryDirectory alloc] initWithPath:path];

	      if (subitem != nil)
		{
		  [array addObject:subitem];
		  [subitem release];
		}
	    }
	}

      _subitems = [array copy];
      [array release];
    }

  return _subitems;
}

- (NSArray *)subimages
{
  if (_subimages == nil)
    {
      NSFileManager *fm = [NSFileManager defaultManager];
      NSMutableArray *array = [[NSMutableArray alloc] init];

      for (NSString *file in [fm contentsOfDirectoryAtPath:_path error:nil])
	{
	  if ([file characterAtIndex:0] == '.')
	    continue;

	  NSString *path = [_path stringByAppendingPathComponent:file];
	  BOOL dir = NO;
	  if (![fm fileExistsAtPath:path isDirectory:&dir])
	    continue;

	  if (![[[self class] imagePathExtensions]
		containsObject:[file pathExtension]])
	    continue;

	  if (!dir)
	    {
	      PDImage *image = [[PDImage alloc] initWithPath:path];

	      if (image != nil)
		{
		  [array addObject:image];
		  [image release];
		}
	    }
	}

      _subimages = [array copy];
      [array release];
    }

  NSMutableArray *images = [NSMutableArray array];

  [images addObjectsFromArray:_subimages];

  for (PDLibraryDirectory *item in [self subitems])
    {
      if (![item isHidden])
	[images addObjectsFromArray:[item subimages]];
    }

  return images;
}

- (NSImage *)titleImage
{
  return PDImageWithName(_titleImageName);
}

- (NSString *)titleString
{
  return [[_path lastPathComponent]
	  stringByReplacingOccurrencesOfString:@":" withString:@"/"];
}

- (BOOL)isExpandable
{
  return [[self subitems] count] != 0;
}

- (BOOL)hasBadge
{
  return YES;
}

- (NSInteger)badgeValue
{
  return [self numberOfSubimages];
}

- (BOOL)needsUpdate
{
  // FIXME: do this correctly.

  return [super needsUpdate];
}

@end

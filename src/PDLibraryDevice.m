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

#import "PDLibraryDevice.h"

#import "PDAppKitExtensions.h"
#import "PDImage.h"
#import "PDImageLibrary.h"

@implementation PDLibraryDevice
{
  NSImage *_icon;
}

+ (BOOL)flattensSubdirectories
{
  return YES;
}

- (id)initWithLibrary:(PDImageLibrary *)lib
{
  return [super initWithLibrary:lib directory:@"DCIM"];
}

- (NSString *)titleString
{
  return self.library.name;
}

- (BOOL)hasTitleImage
{
  return YES;
}

- (NSImage *)titleImage
{
  if (_icon == nil)
    {
      _icon = self.library.iconImage;
      if (_icon == nil)
	_icon = PDImageWithName(PDImage_GenericRemovableDisk);
    }

  return _icon;
}

- (NSString *)identifier
{
  return nil;
}

- (void)unmount
{
  [self.library unmount];
}

@end

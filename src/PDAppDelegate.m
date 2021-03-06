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

#import "PDAppDelegate.h"

#import "PDWindowController.h"

NSString *const PDBackgroundActivityDidChange = @"PDBackgroundActivityDidChange";

@implementation PDAppDelegate
{
  NSMenu *_imageContextMenu;
  NSMutableSet *_backgroundActivity;
}

@synthesize windowController = _windowController;
@synthesize photosMenu = _photosMenu;
@synthesize viewMenu = _viewMenu;
@synthesize windowMenu = _windowMenu;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  NSString *path = [[NSBundle mainBundle]
		    pathForResource:@"defaults" ofType:@"plist"];
  if (path != nil)
    {
      NSData *data = [NSData dataWithContentsOfFile:path];

      if (data != nil)
	{
	  NSDictionary *dict = [NSPropertyListSerialization
				propertyListWithData:data options:
				NSPropertyListImmutable format:nil
				error:nil];
	  if (dict != nil)
	    [[NSUserDefaults standardUserDefaults] registerDefaults:dict];
	}
    }

  [self showWindow:self];
}

- (IBAction)showWindow:(id)sender
{
  [_windowController showWindow:sender];
}

- (BOOL)backgroundActivity
{
  return _backgroundActivity.count != 0;
}

- (void)addBackgroundActivity:(NSString *)name
{
  if (_backgroundActivity == nil)
    _backgroundActivity = [NSMutableSet set];

  NSInteger count = _backgroundActivity.count;

  [_backgroundActivity addObject:name];

  if (count == 0)
    {
      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDBackgroundActivityDidChange object:self];
    }
}

- (void)removeBackgroundActivity:(NSString *)name
{
  if (_backgroundActivity == nil)
    return;

  NSInteger count = _backgroundActivity.count;

  [_backgroundActivity removeObject:name];

  if (count != 0 && _backgroundActivity.count == 0)
    {
      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDBackgroundActivityDidChange object:self];
    }
}

- (void)popUpImageContextMenuWithEvent:(NSEvent *)e forView:(NSView *)view
{
  if (_imageContextMenu == nil)
    {
      _imageContextMenu = [_photosMenu copy];
      [_imageContextMenu setDelegate:self];
    }

  [NSMenu popUpContextMenu:_imageContextMenu withEvent:e forView:view
   withFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
}

// NSMenuDelegate methods

- (void)menuNeedsUpdate:(NSMenu *)menu
{
  if (menu == _photosMenu || menu == _imageContextMenu)
    {
      for (NSMenuItem *item in menu.itemArray)
	{
	  SEL sel = item.action;
	  if (sel == @selector(toggleFlaggedAction:))
	    item.state = _windowController.flaggedState;
	  else if (sel == @selector(toggleHiddenAction:))
	    item.state = _windowController.hiddenState;
	  else if (sel == @selector(toggleDeletedAction:))
	    item.state = _windowController.deletedState;
	  else if (sel == @selector(toggleRawAction:))
	    item.state = _windowController.rawState;
	}
    }
  else if (menu == _viewMenu)
    {
      NSInteger sidebarMode = _windowController.sidebarMode;
      NSInteger contentMode = _windowController.contentMode;

      for (NSMenuItem *item in menu.itemArray)
	{
	  SEL sel = item.action;
	  if (sel == @selector(setSidebarModeAction:))
	    item.state = sidebarMode == item.tag;
	  else if (sel == @selector(setContentModeAction:))
	    item.state = contentMode == item.tag;
	  else if (sel == @selector(toggleListMetadata:))
	    item.state = _windowController.displaysListMetadata;
	  else if (sel == @selector(toggleImageMetadata:))
	    item.state = _windowController.displaysImageMetadata;
	  else if (sel == @selector(toggleShowsHiddenImages:))
	    item.state = _windowController.showsHiddenImages;
	}
    }
  else if (menu == _windowMenu)
    {
      BOOL sidebarVisible = _windowController.sidebarVisible;

      for (NSMenuItem *item in menu.itemArray)
	{
	  SEL sel = item.action;
	  if (sel == @selector(toggleSidebarAction:))
	    item.hidden = item.tag != sidebarVisible;
	}
    }
}

@end

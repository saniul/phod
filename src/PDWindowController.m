// -*- c-style: gnu -*-

#import "PDWindowController.h"

#import "PDAdjustmentsViewController.h"
#import "PDAppDelegate.h"
#import "PDImageViewController.h"
#import "PDImageListViewController.h"
#import "PDInfoViewController.h"
#import "PDSplitView.h"
#import "PDLibraryViewController.h"

NSString *const PDImageListDidChange = @"PDImageListDidChange";
NSString *const PDSelectedImagesDidChange = @"PDSelectedImagesDidChange";

@implementation PDWindowController

- (NSString *)windowNibName
{
  return @"PDWindow";
}

- (PDViewController *)viewControllerWithClass:(Class)cls
{
  if (cls == nil)
    return nil;

  for (PDViewController *obj in _viewControllers)
    {
      obj = [obj viewControllerWithClass:cls];
      if (obj != nil)
	return obj;
    }

  return nil;
}

- (id)init
{
  self = [super initWithWindow:nil];
  if (self == nil)
    return nil;

  _viewControllers = [[NSMutableArray alloc] init];

  _sidebarMode = PDSidebarMode_Nil;
  _contentMode = PDContentMode_Nil;

  _imageList = [[NSArray alloc] init];
  _selectedImages = [[NSArray alloc] init];

  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSRunLoop cancelPreviousPerformRequestsWithTarget:self];

  [_viewControllers release];
  [_imageList release];
  [_selectedImages release];

  [super dealloc];
}

- (void)windowDidLoad
{
  NSWindow *window = [self window];

  [_splitView setIndexOfResizableSubview:1];

#if 0
  if (ActViewController *obj
      = [[ActViewerViewController alloc] initWithController:self])
    {
      [_viewControllers addObject:obj];
      [obj release];
    }

  if (ActViewController *obj
      = [[ActImporterViewController alloc] initWithController:self])
    {
      [_viewControllers addObject:obj];
      [obj release];
    }
#endif

  // make sure we're in viewer mode before trying to restore view state

  [self setSidebarMode:PDSidebarMode_Library];
  [self setContentMode:PDContentMode_List];

  [self applySavedWindowState];

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(windowWillClose:)
   name:NSWindowWillCloseNotification object:window];
}

- (void)windowWillClose:(NSNotification *)note
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [self saveWindowState];

  [NSApp terminate:self];
}

- (void)saveWindowState
{
  if (![self isWindowLoaded] || [self window] == nil)
    return;

  NSMutableDictionary *controllers = [NSMutableDictionary dictionary];

  for (PDViewController *controller in _viewControllers)
    {
      NSDictionary *sub = [controller savedViewState];
      if ([sub count] != 0)
	[controllers setObject:sub forKey:[controller identifier]];
    }

  NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
			controllers, @"PDViewControllers",
			[_splitView savedViewState], @"PDSplitViewState",
			nil];

  [[NSUserDefaults standardUserDefaults]
   setObject:dict forKey:@"PDSavedWindowState"];
}

- (void)applySavedWindowState
{
  NSDictionary *state, *dict, *sub;

  state = [[NSUserDefaults standardUserDefaults]
	   dictionaryForKey:@"PDSavedWindowState"];
  if (state == nil)
    return;

  dict = [state objectForKey:@"PDViewControllers"];

  if (dict != nil)
    {
      for (PDViewController *controller in _viewControllers)
	{
	  sub = [dict objectForKey:[controller identifier]];
	  if (sub != nil)
	    [controller applySavedViewState:sub];
	}
    }

  dict = [state objectForKey:@"PDSplitViewState"];
  if (dict != nil)
    [_splitView applySavedViewState:dict];
}

static Class
sidebarClassForMode(enum PDSidebarMode mode)
{
  switch (mode)
    {
    case PDSidebarMode_Nil:
      return nil;
    case PDSidebarMode_Library:
      return [PDLibraryViewController class];
    case PDSidebarMode_Info:
      return [PDInfoViewController class];
    case PDSidebarMode_Adjustments:
      return [PDAdjustmentsViewController class];
    }
}

static Class
contentClassForMode(enum PDContentMode mode)
{
  switch (mode)
    {
    case PDContentMode_Nil:
      return nil;
    case PDContentMode_List:
      return [PDImageListViewController class];
    case PDContentMode_Image:
      return [PDImageViewController class];
    }
}

- (NSInteger)sidebarMode
{
  return _sidebarMode;
}

- (void)setSidebarMode:(NSInteger)mode
{
  Class cls;
  PDViewController *controller;

  if (_sidebarMode != mode)
    {
      cls = sidebarClassForMode(_sidebarMode);
      controller = [self viewControllerWithClass:cls];
      [controller removeFromContainer];

      _sidebarMode = mode;

      cls = sidebarClassForMode(_sidebarMode);
      controller = [self viewControllerWithClass:cls];
      [controller addToContainerView:_contentView];
    }
}

- (NSInteger)contentMode
{
  return _contentMode;
}

- (void)setContentMode:(NSInteger)mode
{
  Class cls;
  PDViewController *controller;

  if (_contentMode != mode)
    {
      cls = contentClassForMode(_contentMode);
      controller = [self viewControllerWithClass:cls];
      [controller removeFromContainer];

      _contentMode = mode;

      cls = contentClassForMode(_contentMode);
      controller = [self viewControllerWithClass:cls];
      [controller addToContainerView:_contentView];
    }
}

- (NSArray *)imageList
{
  return _imageList;
}

- (void)setImageList:(NSArray *)array
{
  if (_imageList != array)
    {
      [_imageList release];
      _imageList = [array copy];

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageListDidChange object:self];
    }
}

- (NSArray *)selectedImages
{
  return _selectedImages;
}

- (void)setSelectedImages:(NSArray *)array
{
  if (_selectedImages != array)
    {
      [_selectedImages release];
      _selectedImages = [array copy];

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDSelectedImagesDidChange object:self];
    }
}

- (IBAction)setSidebarModeAction:(id)sender
{
  if (sender == _sidebarControl)
    [self setSidebarMode:[_sidebarControl selectedSegment]];
  else
    [self setSidebarMode:[sender tag]];
}

- (IBAction)setContentModeAction:(id)sender
{
  [self setContentMode:[sender tag]];
}

// NSSplitViewDelegate methods

- (BOOL)splitView:(NSSplitView *)view canCollapseSubview:(NSView *)subview
{
  return NO;
}

- (BOOL)splitView:(NSSplitView *)view shouldCollapseSubview:(NSView *)subview
    forDoubleClickOnDividerAtIndex:(NSInteger)idx
{
  return NO;
}

- (CGFloat)splitView:(NSSplitView *)view constrainMinCoordinate:(CGFloat)p
    ofSubviewAt:(NSInteger)idx
{
  NSView *subview = [[view subviews] objectAtIndex:idx];
  CGFloat min_size = [(PDSplitView *)view minimumSizeOfSubview:subview];

  return p + min_size;
}

- (CGFloat)splitView:(NSSplitView *)view constrainMaxCoordinate:(CGFloat)p
    ofSubviewAt:(NSInteger)idx
{
  NSView *subview = [[view subviews] objectAtIndex:idx];
  CGFloat min_size = [(PDSplitView *)view minimumSizeOfSubview:subview];

  return p - min_size;
}

- (BOOL)splitView:(NSSplitView *)view
    shouldAdjustSizeOfSubview:(NSView *)subview
{
  if ([view isKindOfClass:[PDSplitView class]])
    return [(PDSplitView *)view shouldAdjustSizeOfSubview:subview];
  else
    return YES;
}

@end

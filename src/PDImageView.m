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

#import "PDImageView.h"

#import "PDAppDelegate.h"
#import "PDAppKitExtensions.h"
#import "PDColor.h"
#import "PDImage.h"
#import "PDImageLayer.h"
#import "PDImageRatingLayer.h"
#import "PDImageViewController.h"
#import "PDWindowController.h"

#import <QuartzCore/QuartzCore.h>

#define FIT_MARGIN 10
#define MIN_RATING_HEIGHT 24

#define DRAG_MASK (NSLeftMouseDraggedMask | NSLeftMouseUpMask)

@implementation PDImageView
{
  CALayer *_clipLayer;
  PDImageLayer *_imageLayer;
  PDImageRatingLayer *_ratingLayer;
}

@synthesize controller = _controller;
@synthesize image = _image;
@synthesize imageScale = _imageScale;
@synthesize imageOrigin = _imageOrigin;
@synthesize displaysMetadata = _displaysMetadata;

- (id)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self != nil)
    {
      _imageScale = 1;
      _displaysMetadata = YES;
    }
  return self;
}

- (void)setImage:(PDImage *)image
{
  if (_image != image)
    {
      _image = image;
      self.needsDisplay = YES;
    }
}

- (void)setImageScale:(CGFloat)x
{
  if (_imageScale != x)
    {
      _imageScale = x;
      self.needsDisplay = YES;
    }
}

- (void)setImageOrigin:(CGPoint)p
{
  if (!CGPointEqualToPoint(_imageOrigin, p))
    {
      _imageOrigin = p;
      self.needsDisplay = YES;
    }
}

- (CGFloat)scaleToFitScale
{
  if (_image == nil)
    return 1;

  CGSize pixelSize = _image.orientedPixelSize;

  CGRect bounds = self.bounds;

  CGFloat sx = (bounds.size.width - (FIT_MARGIN)*2) / pixelSize.width;
  CGFloat sy = (bounds.size.height - (FIT_MARGIN)*2) / pixelSize.height;

  CGFloat scale = sx < sy ? sx : sy;

  return scale < 1 ? scale : 1;
}

- (CGFloat)scaleToFillScale
{
  if (_image == nil)
    return 1;

  CGSize pixelSize = _image.orientedPixelSize;

  CGRect bounds = self.bounds;

  CGFloat sx = bounds.size.width / pixelSize.width;
  CGFloat sy = bounds.size.height / pixelSize.height;

  CGFloat scale = sx > sy ? sx : sy;

  return scale < 1 ? scale : 1;
}

- (CGFloat)scaleToActualScale
{
  CGFloat scale = self.window.backingScaleFactor;
  return scale > 1 ? 1 / scale : 1;
}

- (void)setImageScale:(CGFloat)scale preserveOrigin:(BOOL)flag
{
  if (!flag)
    {
      self.imageScale = scale;
      return;
    }

  CGRect bounds = self.bounds;

  CGPoint p = [self convertPoint:
	       [self.window mouseLocationOutsideOfEventStream] fromView:nil];

  if (!CGRectContainsPoint(bounds, p))
    {
      p = CGPointMake(bounds.origin.x + bounds.size.width * (CGFloat).5,
		      bounds.origin.y + bounds.size.height * (CGFloat).5);
    }

  double factor = scale / _imageScale;

  CGFloat x = (_imageOrigin.x + p.x) * factor - p.x;
  CGFloat y = (_imageOrigin.y + p.y) * factor - p.y;

  self.imageScale = scale;

  _imageOrigin = CGPointMake(x, y);
}

- (void)setDisplaysMetadata:(BOOL)flag
{
  if (_displaysMetadata != flag)
    {
      _displaysMetadata = flag;
      self.needsDisplay = YES;
    }
}

- (BOOL)wantsUpdateLayer
{
  return YES;
}

- (CGSize)scaledImageSize
{
  if (_image != nil)
    {
      CGSize pixelSize = _image.orientedPixelSize;

      CGFloat width = ceil(pixelSize.width * _imageScale);
      CGFloat height = ceil(pixelSize.height * _imageScale);

      return CGSizeMake(width, height);
    }
  else
    return CGSizeZero;
}

- (void)updateLayer
{
  CALayer *layer = self.layer;

  layer.backgroundColor = [PDColor imageGridBackgroundColor].CGColor;

  if (_clipLayer == nil)
    {
      _clipLayer = [CALayer layer];
      _clipLayer.masksToBounds = YES;
      _clipLayer.delegate = _controller;
      [layer addSublayer:_clipLayer];

      _imageLayer = [PDImageLayer layer];
      _imageLayer.delegate = _controller;
      [_clipLayer addSublayer:_imageLayer];
    }

  if (_image != nil)
    {
      CGFloat fitScale = self.scaleToFitScale;

      if (_imageScale < fitScale)
	{
	  [self willChangeValueForKey:@"imageScale"];
	  _imageScale = fitScale;
	  [self didChangeValueForKey:@"imageScale"];
	}

      CGSize scaledSize = self.scaledImageSize;
      CGRect bounds = self.bounds;

      _clipLayer.frame = bounds;

      if (scaledSize.width < bounds.size.width)
	{
	  _imageOrigin.x = floor((scaledSize.width
				  - bounds.size.width) * (CGFloat).5);
	}
      else
	{
	  if (_imageOrigin.x < 0)
	    _imageOrigin.x = 0;
	  else if (_imageOrigin.x > scaledSize.width - bounds.size.width)
	    _imageOrigin.x = scaledSize.width - bounds.size.width;
	}

      if (scaledSize.height < bounds.size.height)
	{
	  _imageOrigin.y = floor((scaledSize.height
				  - bounds.size.height) * (CGFloat).5);
	}
      else
	{
	  if (_imageOrigin.y < 0)
	    _imageOrigin.y = 0;
	  else if (_imageOrigin.y > scaledSize.height - bounds.size.height)
	    _imageOrigin.y = scaledSize.height - bounds.size.height;
	  else
	    _imageOrigin.y = _imageOrigin.y;
	}

      _imageLayer.bounds =
        CGRectMake(0, 0, scaledSize.width, scaledSize.height);
      _imageLayer.position =
       CGPointMake(-_imageOrigin.x + scaledSize.width * (CGFloat).5,
		   -_imageOrigin.y + scaledSize.height * (CGFloat).5);
      _imageLayer.colorSpace = self.window.colorSpace.CGColorSpace;
      _imageLayer.contentsScale = self.window.backingScaleFactor;

      _imageLayer.image = _image;
      _clipLayer.hidden = NO;
    }
  else
    {
      _imageLayer.image = nil;
      _clipLayer.hidden = YES;
    }

  if (_image != nil && _displaysMetadata)
    {
      if (_ratingLayer == nil)
	{
	  _ratingLayer = [PDImageRatingLayer layer];
	  _ratingLayer.delegate = _controller;
	  [_clipLayer addSublayer:_ratingLayer];
	}

      _ratingLayer.rating = _image.rating;
      _ratingLayer.flagged =  _image.flagged;
      _ratingLayer.hiddenState = _image.hidden;
      _ratingLayer.contentsScale = self.window.backingScaleFactor;

      CGRect bounds = CGRectIntersection(_clipLayer.bounds, _imageLayer.frame);

      _ratingLayer.position =
        CGPointMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds));

      CGSize rating_size = [_ratingLayer preferredFrameSize];
      rating_size.width = fmin(rating_size.width, bounds.size.width);
      rating_size.height = fmax(rating_size.height, MIN_RATING_HEIGHT);

      _ratingLayer.bounds =
       CGRectMake(0, 0, rating_size.width, rating_size.height);
    }
  else
    {
      [_ratingLayer removeFromSuperlayer];
      _ratingLayer = nil;
    }

  self.preparedContentRect = self.visibleRect;
}

- (void)viewDidDisappear
{
  [_imageLayer removeContent];
}

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (void)keyDown:(NSEvent *)e
{
  NSString *chars = [e charactersIgnoringModifiers];

  if (chars.length == 1)
    {
      switch ([chars characterAtIndex:0])
	{
	case NSLeftArrowFunctionKey:
	  [_controller.controller movePrimarySelectionRight:-1
	   byExtendingSelection:(e.modifierFlags & NSShiftKeyMask) != 0];
	  return;

	case NSRightArrowFunctionKey:
	  [_controller.controller movePrimarySelectionRight:1
	   byExtendingSelection:(e.modifierFlags & NSShiftKeyMask) != 0];
	  return;
	}
    }

  [super keyDown:e];
}

- (void)mouseDown:(NSEvent *)e
{
  if (e.clickCount > 1)
    {
      _controller.controller.contentMode = PDContentMode_List;
      return;
    }

  if (([e modifierFlags] & NSControlKeyMask) != 0)
    {
      [(PDAppDelegate *)[NSApp delegate]
       popUpImageContextMenuWithEvent:e forView:self];
      return;
    }

  CGPoint p0 = [self convertPoint:e.locationInWindow fromView:nil];
  CGPoint o0 = _imageOrigin;

  while (1)
    {
      [CATransaction flush];

      @autoreleasepool
        {
	  e = [self.window nextEventMatchingMask:DRAG_MASK];

	  if (e.type != NSLeftMouseDragged)
	    break;

	  CGPoint p1 = [self convertPoint:e.locationInWindow fromView:nil];

	  _imageOrigin.x = o0.x + (p0.x - p1.x);
	  _imageOrigin.y = o0.y + (p0.y - p1.y);

	  self.needsDisplay = YES;
	  [self displayIfNeeded];
	}
    }
}

- (void)rightMouseDown:(NSEvent *)e
{
  [(PDAppDelegate *)[NSApp delegate]
   popUpImageContextMenuWithEvent:e forView:self];
}

- (void)scrollWheel:(NSEvent *)e
{
  _imageOrigin.x -= e.scrollingDeltaX;
  _imageOrigin.y -= e.scrollingDeltaY;

  self.needsDisplay = YES;
}

@end

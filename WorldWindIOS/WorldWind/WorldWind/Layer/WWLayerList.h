/*
 Copyright (C) 2013 United States Government as represented by the Administrator of the
 National Aeronautics and Space Administration. All Rights Reserved.
 
 @version $Id$
 */

#import <Foundation/Foundation.h>

@class WWLayer;

@interface WWLayerList : NSObject

- (NSUInteger) count;
- (WWLayer*) layerAtIndex:(NSUInteger)index;

@end

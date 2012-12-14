/*
 Copyright (C) 2013 United States Government as represented by the Administrator of the
 National Aeronautics and Space Administration. All Rights Reserved.
 
 @version $Id$
 */

#import <Foundation/Foundation.h>

@class WWTessellator;
@class WWTerrainTile;
@class WWTerrainTileList;
@class WWDrawContext;
@class WWVec4;
@class WWSector;

@interface WWGlobe : NSObject

@property(readonly, nonatomic) double equatorialRadius;
@property(readonly, nonatomic) double polarRadius;
@property(readonly, nonatomic) double es;
@property(readonly, nonatomic) double minElevation;
@property(readonly, nonatomic) WWTessellator* tessellator;

- (WWGlobe*) init;

- (WWTerrainTileList*) tessellate:(WWDrawContext*)dc;

- (void) computePointFromPosition:(double)latitude
                        longitude:(double)longitude
                         altitude:(double)altitude
                      outputPoint:(WWVec4*)result;

- (void) computePointFromPosition:(double)latitude
                        longitude:(double)longitude
                         altitude:(double)altitude
                           offset:(WWVec4*)offset
                      outputArray:(float [])result;

- (void) computePointsFromPositions:(WWSector*)sector
                             numLat:(int)numLat
                             numLon:(int)numLon
                    metersElevation:(double [])metersElevation
                  constantElevation:(double*)constantElevation
                             offset:(WWVec4*)offset
                        outputArray:(float [])result;

- (double) getElevation:(double)latitude longitude:(double)longitude;

- (void) getElevations:(WWSector*)sector
                numLat:(int)numLat
                numLon:(int)numLon
      targetResolution:(double)targetResolution
  verticalExaggeration:(double)verticalExaggeration
           outputArray:(double[])outputArray;


@end
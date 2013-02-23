/*
 Copyright (C) 2013 United States Government as represented by the Administrator of the
 National Aeronautics and Space Administration. All Rights Reserved.

@version $Id $
 */

#import "WorldWind/Terrain/WWEarthElevationModel.h"
#import "WorldWind/Geometry/WWLocation.h"
#import "WorldWind/Geometry/WWSector.h"
#import "WorldWind/Util/WWWmsUrlBuilder.h"

@implementation WWEarthElevationModel

- (WWEarthElevationModel*) init
{
    NSString* cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* cachePath = [cacheDir stringByAppendingPathComponent:@"EarthElevation"];

    self = [super initWithSector:[[WWSector alloc] initWithFullSphere]
                  levelZeroDelta:[[WWLocation alloc] initWithDegreesLatitude:45 longitude:45]
                       numLevels:12 // Approximately 10 meter resolution with 45x45 degree and 256x256 px tiles.
            retrievalImageFormat:@"application/bil16"
                       cachePath:cachePath];

    NSString* serviceLocation = @"http://data.worldwind.arc.nasa.gov/elev";
    WWWmsUrlBuilder* urlBuilder = [[WWWmsUrlBuilder alloc] initWithServiceLocation:serviceLocation
                                                                        layerNames:@"mergedAsterElevations"
                                                                        styleNames:@""
                                                                        wmsVersion:@"1.3.0"];
    [self setUrlBuilder:urlBuilder];

    return self;
}

@end
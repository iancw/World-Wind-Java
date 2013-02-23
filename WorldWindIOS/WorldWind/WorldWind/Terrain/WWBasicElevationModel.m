/*
 Copyright (C) 2013 United States Government as represented by the Administrator of the
 National Aeronautics and Space Administration. All Rights Reserved.

 @version $Id$
 */

#import "WorldWind/Terrain/WWBasicElevationModel.h"
#import "WorldWind/Terrain/WWElevationImage.h"
#import "WorldWind/Terrain/WWElevationTile.h"
#import "WorldWind/Geometry/WWLocation.h"
#import "WorldWind/Geometry/WWSector.h"
#import "WorldWind/Util/WWLevelSet.h"
#import "WorldWind/Util/WWLevel.h"
#import "WorldWind/Util/WWMemoryCache.h"
#import "WorldWind/Util/WWRetriever.h"
#import "WorldWind/Util/WWUrlBuilder.h"
#import "WorldWind/WorldWind.h"

@implementation WWBasicElevationModel
{
    WWLevelSet* levels;
    NSMutableSet* currentTiles;
    NSArray* tileSortDescriptors;

    WWMemoryCache* tileCache;
    WWMemoryCache* imageCache;

    NSMutableSet* currentRetrievals;
    NSMutableSet* currentLoads;
}

- (WWBasicElevationModel*) initWithSector:(WWSector*)sector
                           levelZeroDelta:(WWLocation*)levelZeroDelta
                                numLevels:(int)numLevels
                     retrievalImageFormat:(NSString*)retrievalImageFormat
                                cachePath:(NSString*)cachePath
{
    if (sector == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Sector is nil")
    }

    if (levelZeroDelta == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Level 0 delta is nil")
    }

    if (numLevels < 1)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Number of levels is less than 1")
    }

    if (retrievalImageFormat == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Image format is nil")
    }

    if (cachePath == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Cache path is nil")
    }

    self = [super init];

    if (self != nil)
    {
        _retrievalImageFormat = retrievalImageFormat;
        _cachePath = cachePath;

        self->levels = [[WWLevelSet alloc] initWithSector:sector
                                           levelZeroDelta:levelZeroDelta
                                                numLevels:numLevels];
        self->currentTiles = [[NSMutableSet alloc] init];
        self->tileSortDescriptors = [NSArray arrayWithObject:[[NSSortDescriptor alloc] initWithKey:@"level" ascending:YES]];

        self->tileCache = [[WWMemoryCache alloc] initWithCapacity:500000 lowWater:400000];
        self->imageCache = [[WWMemoryCache alloc] initWithCapacity:5000000 lowWater:4000000];

        self->currentRetrievals = [[NSMutableSet alloc] init];
        self->currentLoads = [[NSMutableSet alloc] init];

        // Set up to handle retrieval and image read monitoring.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleImageRetrievalNotification:)
                                                     name:WW_RETRIEVAL_STATUS // retrieval from net
                                                   object:self];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleImageReadNotification:)
                                                     name:WW_REQUEST_STATUS // opening image file on disk
                                                   object:self];
    }

    return self;
}

- (double) elevationForLatitude:(double)latitude longitude:(double)longitude
{
    return 0; // TODO
}

- (double) elevationsForSector:(WWSector*)sector
                       numLat:(int)numLat
                       numLon:(int)numLon
             targetResolution:(double)targetResolution
         verticalExaggeration:(double)verticalExaggeration
                       result:(double[])result
{
    if (sector == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Sector is nil")
    }

    if (result == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Output array is nil")
    }

    if (numLat <= 0 || numLon <= 0)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"A dimension is <= 0")
    }

    [self assembleTilesForSector:sector resolution:targetResolution];

    if ([self->currentTiles count] == 0)
    {
        return 0; // Sector is outside the elevation model's coverage area.
    }

    NSArray* sortedTiles = [self->currentTiles sortedArrayUsingDescriptors:self->tileSortDescriptors];

    double maxResolution = 0;
    double resolution;

    for (WWElevationTile* tile in sortedTiles)
    {
        WWElevationImage* image = [tile image];
        if (image != nil)
        {
            [image elevationsForSector:sector
                                numLat:numLat
                                numLon:numLon
                  verticalExaggeration:verticalExaggeration
                                result:result];

            resolution = [tile texelSize];

            if (maxResolution < resolution)
                maxResolution = resolution;
        }
        else
        {
            maxResolution = FLT_MAX;
        }
    }

    return maxResolution;
}

- (void) minAndMaxElevationsForSector:(WWSector*)sector result:(double[])result
{
    if (sector == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Sector is nil")
    }

    if (result == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Output array is nil")
    }

    result[0] = 0;
    result[1] = 0;
    // TODO
}

- (WWTile*) createTile:(WWSector*)sector level:(WWLevel*)level row:(int)row column:(int)column
{
    NSString* imagePath = [NSString stringWithFormat:@"%@/%d/%d/%d_%d.%@",
                                                     _cachePath, [level levelNumber], row, row, column, @"raw"];

    return [[WWElevationTile alloc] initWithSector:sector level:level row:row column:column imagePath:imagePath
                                             cache:self->imageCache];
}

- (void) assembleTilesForSector:(WWSector*)sector resolution:(double)targetResolution
{
    [self->currentTiles removeAllObjects];

    WWLevel* level = [self levelForResolution:targetResolution];

    // Intersect the requested sector with the elevation model's coverage area. This avoids attempting to assemble tiles
    // that are outside the coverage area.
    sector = [[WWSector alloc] initWithSector:sector];
    [sector intersection:[level sector]];

    if ([sector isEmpty])
    {
        return; // Sector is outside the elevation model's coverage area.
    }

    double deltaLat = [[level tileDelta] latitude];
    double deltaLon = [[level tileDelta] longitude];

    int firstRow = [WWTile computeRow:deltaLat latitude:[sector minLatitude]];
    int lastRow = [WWTile computeRow:deltaLat latitude:[sector maxLatitude]];
    int firstCol = [WWTile computeColumn:deltaLon longitude:[sector minLongitude]];
    int lastCol = [WWTile computeColumn:deltaLon longitude:[sector maxLongitude]];

    for (int row = firstRow; row <= lastRow; row++)
    {
        for (int col = firstCol; col <= lastCol; col++)
        {
            [self addTileOrAncestor:level row:row column:col];
        }
    }
}

- (void) addTileOrAncestor:(WWLevel*)level row:(int)row column:(int)column
{
    WWElevationTile* tile = [self tileForLevel:level row:row column:column];

    if ([self isTileImageLocal:tile])
    {
        [self->currentTiles addObject:tile];
    }
    else
    {
        [self retrieveTileImage:tile];

        if ([level isFirstLevel])
        {
            [self->currentTiles addObject:tile]; // No ancestor tile to add.
        }
        else
        {
            [self addAncestorFor:level row:row column:column];
        }
    }
}

- (void) addAncestorFor:(WWLevel*)level row:(int)row column:(int)column
{
    WWElevationTile* tile = nil;

    while (![level isFirstLevel])
    {
        level = [level previousLevel];
        row /= 2;
        column /= 2;

        tile = [self tileForLevel:level row:row column:column];

        if ([self isTileImageLocal:tile])
        {
            [self->currentTiles addObject:tile]; // Have an ancestor tile with an in-memory image.
            return;
        }
    }

    // No ancestor tiles have an in-memory image. Retrieve the ancestor tile corresponding for the first level, and
    // add it. We add the necessary tiles to provide coverage over the requested sector in order to accurately return
    // whether or not this elevation model has data for the entire sector.
    [self->currentTiles addObject:tile];
    [self retrieveTileImage:tile];
}

- (WWLevel*) levelForResolution:(double)targetResolution
{
    WWLevel* lastLevel = [self->levels lastLevel];

    if ([lastLevel texelSize] >= targetResolution)
    {
        return lastLevel; // Can't do any better than the last level.
    }

    for (int i = 0; i < [self->levels numLevels]; i++)
    {
        WWLevel* level = [self->levels level:i];

        if ([level texelSize] <= targetResolution)
        {
            return level;
        }
    }

    return lastLevel;
}

- (WWElevationTile*) tileForLevel:(WWLevel*)level row:(int)row column:(int)column
{
    NSString* key = [NSString stringWithFormat:@"%d/%d/%d", [level levelNumber], row, column];
    WWTile* tile = [self->tileCache getValueForKey:key];
    if (tile != nil)
    {
        return (WWElevationTile*) tile;
    }
    else
    {
        WWSector* sector = [WWTile computeSector:level row:row column:column];
        tile = [self createTile:sector level:level row:row column:column];
        [self->tileCache putValue:tile forKey:key];
        return (WWElevationTile*) tile;
    }
}

- (BOOL) isTileImageLocal:(WWElevationTile*)tile
{
    return [self->imageCache containsKey:[tile imagePath]];
}

- (void) retrieveTileImage:(WWElevationTile*)tile
{
    // See if it's already on disk.
    if ([[NSFileManager defaultManager] fileExistsAtPath:[tile imagePath]])
    {
        if ([self->currentLoads containsObject:[tile imagePath]])
            return;

        [self->currentLoads addObject:[tile imagePath]];

        WWElevationImage* image = [[WWElevationImage alloc] initWithImagePath:[tile imagePath]
                                                                       sector:[tile sector]
                                                                   imageWidth:[tile tileWidth]
                                                                  imageHeight:[tile tileHeight]
                                                                        cache:self->imageCache
                                                                       object:self];
        [[WorldWind retrievalQueue] addOperation:image];
        return;
    }

    // If the app is connected to the network, retrieve the image from there.

    if ([WorldWind isOfflineMode] || ![WorldWind isNetworkAvailable])
        return;

    if ([self->currentRetrievals containsObject:[tile imagePath]])
        return;

    [self->currentRetrievals addObject:[tile imagePath]];

    NSURL* url = [self resourceUrlForTile:tile imageFormat:_retrievalImageFormat];
    WWRetriever* retriever = [[WWRetriever alloc] initWithUrl:url filePath:[tile imagePath] object:self];
    [[WorldWind retrievalQueue] addOperation:retriever];
}

- (NSURL*) resourceUrlForTile:(WWTile*)tile imageFormat:(NSString*)imageFormat
{
    if (tile == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Tile is nil")
    }

    if (imageFormat == nil || [imageFormat length] == 0)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Image format is nil or empty")
    }

    if (_urlBuilder == nil)
    {
        WWLOG_AND_THROW(NSInternalInconsistencyException, @"URL builder is nil")
    }

    return [_urlBuilder urlForTile:tile imageFormat:imageFormat];
}

- (void) handleImageRetrievalNotification:(NSNotification*)notification
{
    NSDictionary* avList = [notification userInfo];
    NSString* imagePath = [avList valueForKey:WW_FILE_PATH];

    [self->currentRetrievals removeObject:imagePath];

    // TODO: notify elevation model changed if status is success
}

- (void) handleImageReadNotification:(NSNotification*)notification
{
    NSDictionary* avList = [notification userInfo];
    NSString* imagePath = [avList valueForKey:WW_FILE_PATH];

    [self->currentLoads removeObject:imagePath];

    // TODO: notify elevation model changed if status is success
}

@end
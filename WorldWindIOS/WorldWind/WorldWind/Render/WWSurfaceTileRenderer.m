/*
 Copyright (C) 2013 United States Government as represented by the Administrator of the
 National Aeronautics and Space Administration. All Rights Reserved.
 
 @version $Id$
 */

#import "WorldWind/Render/WWSurfaceTileRenderer.h"
#import "WorldWind/Render/WWGpuProgram.h"
#import "WorldWind/Render/WWDrawContext.h"
#import "WorldWind/Terrain/WWTerrainTile.h"
#import "WorldWind/Terrain/WWTerrainTileList.h"
#import "WorldWind/Geometry/WWMatrix.h"
#import "WorldWind/Render/WWSurfaceTile.h"
#import "WorldWind/Geometry/WWSector.h"
#import "WorldWind/WWLog.h"

// STRINGIFY is used in the shader files.
#define STRINGIFY(A) #A
#import "WorldWind/Shaders/SurfaceTileRenderer.vert"
#import "WorldWind/Shaders/SurfaceTileRenderer.frag"

@implementation WWSurfaceTileRenderer

- (WWSurfaceTileRenderer*) init
{
    self = [super init];

    self->tileCoordMatrix = [[WWMatrix alloc] initWithIdentity];
    self->texCoordMatrix = [[WWMatrix alloc] initWithIdentity];

    self->intersectingTiles = [[NSMutableArray alloc] init];
    self->intersectingGeometry = [[NSMutableArray alloc] init];

    return self;
}

- (void) renderTile:(WWDrawContext*)dc surfaceTile:(id <WWSurfaceTile>)surfaceTile
{
    if (dc == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Draw context is nil")
    }

    if (surfaceTile == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Surface tile is nil")
    }

    WWTerrainTileList* terrainTiles = [dc surfaceGeometry];
    if (terrainTiles == nil)
    {
        WWLog(@"No surface geometry");
        return;
    }

    WWGpuProgram* program = [self gpuProgram];
    [self beginRendering:dc program:program];
    [terrainTiles beginRendering:dc];
    @try
    {
        if ([surfaceTile bind:dc])
        {
            [self->intersectingGeometry removeAllObjects];
            [self assembleIntersectingGeometry:surfaceTile terrainTiles:terrainTiles];

            for (NSUInteger i = 0; i < [self->intersectingGeometry count]; i++)
            {
                WWTerrainTile* terrainTile = [self->intersectingGeometry objectAtIndex:i];

                [terrainTile beginRendering:dc];
                @try
                {
                    [self applyTileState:dc terrainTile:terrainTile surfaceTile:surfaceTile];
//                    [terrainTile render:dc];
                    [terrainTile renderWireframe:dc];
                }
                @finally
                {
                    [terrainTile endRendering:dc];
                }
            }
        }
    }
    @finally
    {
        [terrainTiles endRendering:dc];
        [self endRendering:dc];
    }

}

- (void) renderTiles:(WWDrawContext*)dc surfaceTiles:(NSArray*)surfaceTiles
{
    if (dc == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Draw context is nil")
    }

    if (surfaceTiles == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Surface tiles list is nil")
    }

    WWTerrainTileList* terrainTiles = [dc surfaceGeometry];
    if (terrainTiles == nil)
    {
        WWLog(@"No surface geometry");
        return;
    }

    WWGpuProgram* program = [self gpuProgram];
    [self beginRendering:dc program:program];
    [terrainTiles beginRendering:dc];

    @try
    {
        for (NSUInteger i = 0; i < [terrainTiles count]; i++)
        {
            WWTerrainTile* terrainTile = [terrainTiles objectAtIndex:i];

            [self->intersectingTiles removeAllObjects];
            [self assembleIntersectingTiles:terrainTile surfaceTiles:surfaceTiles];
            if ([self->intersectingTiles count] == 0)
            {
                continue;
            }

            [terrainTile beginRendering:dc];
            @try
            {
                for (NSUInteger j = 0; j < [self->intersectingTiles count]; j++)
                {
                    id <WWSurfaceTile> surfaceTile = [self->intersectingTiles objectAtIndex:j];
                    if ([surfaceTile bind:dc])
                    {
                        [self applyTileState:dc terrainTile:terrainTile surfaceTile:surfaceTile];
                        [terrainTile render:dc];
                    }
                }
            }
            @finally
            {
                [terrainTile endRendering:dc];
            }

        }
    }
    @finally
    {
        [terrainTiles endRendering:dc];
        [self endRendering:dc];
    }

}

- (void) beginRendering:(WWDrawContext*)dc program:(WWGpuProgram*)program
{
    [program bind];
    [dc setCurrentProgram:program];

    glActiveTexture(GL_TEXTURE0);

    [program loadUniformSampler:@"tileTexture" value:0];
}

- (void) endRendering:(WWDrawContext*)dc
{
    [dc setCurrentProgram:nil];

    glUseProgram(0);
    glActiveTexture(GL_TEXTURE0); // TODO: is this necessary? Was any other texture unit used?

    [self->intersectingGeometry removeAllObjects];
    [self->intersectingTiles removeAllObjects];
}

- (void) assembleIntersectingTiles:(WWTerrainTile*)terrainTile surfaceTiles:(NSArray*)surfaceTiles
{
    WWSector* terrainTileSector = [terrainTile sector];

    for (NSUInteger i = 0; i < [surfaceTiles count]; i++)
    {
        id <WWSurfaceTile> surfaceTile = [surfaceTiles objectAtIndex:i];

        if (surfaceTile != nil && [[surfaceTile sector] intersects:terrainTileSector])
        {
            [self->intersectingTiles addObject:surfaceTile];
        }
    }
}

- (void) assembleIntersectingGeometry:(id <WWSurfaceTile>)surfaceTile terrainTiles:(WWTerrainTileList*)terrainTiles
{
    WWSector* surfaceTileSector = [surfaceTile sector];

    for (NSUInteger i = 0; i < [terrainTiles count]; i++)
    {
        WWTerrainTile* terrainTile = [terrainTiles objectAtIndex:i];

        if (terrainTile != nil && [[terrainTile sector] intersects:surfaceTileSector])
        {
            [self->intersectingGeometry addObject:terrainTile];
        }
    }
}

- (void) applyTileState:(WWDrawContext*)dc terrainTile:(WWTerrainTile*)terrainTile surfaceTile:(id <WWSurfaceTile>)surfaceTile
{
    WWGpuProgram* prog = [dc currentProgram];

    [self computeTileCoordMatrix:terrainTile surfaceTile:surfaceTile result:self->tileCoordMatrix];
    [prog loadUniformMatrix:@"tileCoordMatrix" matrix:self->tileCoordMatrix];

    [self->texCoordMatrix setIdentity];
    [surfaceTile applyInternalTransform:dc matrix:self->texCoordMatrix];
    [self->texCoordMatrix multiply:self->tileCoordMatrix];
    [prog loadUniformMatrix:@"texCoordMatrix" matrix:self->texCoordMatrix];
}

- (void) computeTileCoordMatrix:(WWTerrainTile*)terrainTile surfaceTile:(id <WWSurfaceTile>)surfaceTile result:(WWMatrix*)result
{
    WWSector* terrainSector = [terrainTile sector];
    double terrainDeltaLon = [terrainSector deltaLon];
    double terrainDeltaLat = [terrainSector deltaLat];

    WWSector* surfaceSector = [surfaceTile sector];
    double surfaceDeltaLon = [surfaceSector deltaLon];
    double surfaceDeltaLat = [surfaceSector deltaLat];

    double sScale = surfaceDeltaLon > 0 ? terrainDeltaLon / surfaceDeltaLon : 1;
    double tScale = surfaceDeltaLat > 0 ? terrainDeltaLat / surfaceDeltaLat : 1;
    double sTrans = -([surfaceSector minLongitudeRadians] - [terrainSector minLongitudeRadians]) / terrainDeltaLon;
    double tTrans = -([surfaceSector minLatitudeRadians] - [terrainSector minLatitudeRadians]) / terrainDeltaLat;

    [result set:sScale m01:0 m02:0 m03:sScale * sTrans
            m10:0 m11:tScale m12:0 m13:tScale * tTrans
            m20:0 m21:0 m22:1 m23:0
            m30:0 m31:0 m32:0 m33:1];
}

- (WWGpuProgram*) gpuProgram
{
    if (self->rendererProgram != nil)
        return self->rendererProgram;

    @try
    {
        self->rendererProgram = [[WWGpuProgram alloc] initWithShaderSource:SurfaceTileRendererVertexShader
                                                            fragmentShader:SurfaceTileRendererFragmentShader];
    }
    @catch (NSException* exception)
    {
        WWLogE(@"making GPU program", exception);
    }

    return self->rendererProgram;
}

@end
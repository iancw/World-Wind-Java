/*
 Copyright (C) 2013 United States Government as represented by the Administrator of the
 National Aeronautics and Space Administration. All Rights Reserved.
 
 @version $Id$
 */

#import "PathFollower.h"
#import "WorldWind/Shapes/WWPath.h"
#import "WorldWind/WorldWindView.h"
#import "WorldWind/Shapes/WWSphere.h"
#import "WorldWind/Layer/WWLayer.h"
#import "WorldWind/Layer/WWRenderableLayer.h"
#import "WorldWind/Render/WWSceneController.h"
#import "WorldWind/Layer/WWLayerList.h"
#import "WorldWind/Geometry/WWPosition.h"
#import "WorldWind/Util/WWMath.h"
#import "WorldWind/Terrain/WWGlobe.h"
#import "WorldWind/Shapes/WWShapeAttributes.h"
#import "WorldWind/Util/WWColor.h"
#import "WorldWind/Navigate/WWNavigator.h"
#import "WorldWind/WorldWindConstants.h"

#define NAVIGATOR_MAX_DISTANCE 30000.0
#define TIMER_INTERVAL 0.2

@implementation PathFollower

- (PathFollower*) initWithPath:(WWPath*)path speed:(double)speed view:(WorldWindView*)view
{
    self = [super init];

    _path = path;
    _speed = speed;
    _wwv = view;

    WWPosition* firstPosition = [[_path positions] objectAtIndex:0];
    currentPosition = [[WWPosition alloc] initWithPosition:firstPosition];

    WWShapeAttributes* attributes = [[WWShapeAttributes alloc] init];
    [attributes setInteriorColor:[[WWColor alloc] initWithR:.24 g:.47 b:.99 a:1]];
    marker = [[WWSphere alloc] initWithPosition:currentPosition radiusInPixels:7];
    [marker setAttributes:attributes];

    layer = [[WWRenderableLayer alloc] init];
    [layer setDisplayName:@"Path Marker"];
    [layer addRenderable:marker];
    [[[_wwv sceneController] layers] addLayer:layer];

    return self;
}

- (void) dispose
{
    [self stopTimer];
    [self stopObservingNavigator];

    [layer removeRenderable:marker];
    [[[_wwv sceneController] layers] removeLayer:layer];
}

- (void) setEnabled:(BOOL)enabled
{
    if (_enabled == enabled)
    {
        return;
    }

    if (enabled)
    {
        [[_wwv navigator] gotoLocation:currentPosition fromDistance:NAVIGATOR_MAX_DISTANCE animate:YES];
        [self startObservingNavigator]; // Observe after the animation begins to ignore its begin notification.
    }
    else
    {
        [self stopTimer];
        [self stopObservingNavigator];
    }

    _enabled = enabled;
}

//--------------------------------------------------------------------------------------------------------------------//
//-- Timer Interface --//
//--------------------------------------------------------------------------------------------------------------------//

- (void) startTimer
{
    if (timer == nil)
    {
        beginTime = [NSDate timeIntervalSinceReferenceDate];
        offsetTime = currentTime; // Initially zero, then the last time associated with a timer firing thereafter.

        timer = [NSTimer scheduledTimerWithTimeInterval:TIMER_INTERVAL // update at 5 Hz
                                                 target:self
                                               selector:@selector(timerDidFire:)
                                               userInfo:nil repeats:YES];
    }
}

- (void) stopTimer
{
    if (timer != nil)
    {
        [timer invalidate];
        timer = nil;
    }
}

- (void) timerDidFire:(NSTimer*)notifyingTimer
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    currentTime = offsetTime + now - beginTime;

    if ([self positionForTimeInterval:currentTime outPosition:currentPosition])
    {
        [marker setPosition:currentPosition];
        [[_wwv navigator] gotoLocation:currentPosition animate:NO]; // Causes view to redraw.
    }
    else
    {
        [self setEnabled:NO];
    }
}

- (BOOL) positionForTimeInterval:(NSTimeInterval)timeInterval outPosition:(WWPosition*)result;
{
    double distanceTraveled = _speed * timeInterval;

    double remainingDistance = distanceTraveled;
    WWPosition* previousPathPosition = [[_path positions] objectAtIndex:0];

    for (NSUInteger i = 1; i < [[_path positions] count]; i++)
    {
        WWPosition* nextPathPosition = [[_path positions] objectAtIndex:i];

        double segmentDistance = [WWPosition rhumbDistance:previousPathPosition endLocation:nextPathPosition];
        segmentDistance = RADIANS(segmentDistance);
        segmentDistance *= [[[_wwv sceneController] globe] equatorialRadius];
        if (remainingDistance - segmentDistance > 0) // current position is beyond this segment
        {
            remainingDistance -= segmentDistance;
            previousPathPosition = nextPathPosition;
            continue;
        }

        if (remainingDistance - segmentDistance == 0)
        {
            [result setPosition:nextPathPosition];
            return YES;
        }

        // remainingDistance - segmentDistance < 0 ==> current position is within this segment
        double s = remainingDistance / segmentDistance;
        [WWPosition rhumbInterpolate:previousPathPosition
                         endPosition:nextPathPosition
                              amount:s
                      outputPosition:result];
        return YES;
    }

    WWPosition* lastPosition = [[_path positions] lastObject];
    [result setPosition:lastPosition];
    return NO;
}

//--------------------------------------------------------------------------------------------------------------------//
//-- Navigator Notification Interface --//
//--------------------------------------------------------------------------------------------------------------------//

- (void) startObservingNavigator
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleNavigatorNotification:)
                                                 name:nil
                                               object:[_wwv navigator]];
}

- (void) stopObservingNavigator
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) handleNavigatorNotification:(NSNotification*)notification
{
    if ([[notification name] isEqualToString:WW_NAVIGATOR_ANIMATION_ENDED])
    {
        [self startTimer];
    }
    else if ([[notification name] isEqualToString:WW_NAVIGATOR_ANIMATION_BEGAN]
            || [[notification name] isEqualToString:WW_NAVIGATOR_ANIMATION_CANCELLED]
            || [[notification name] isEqualToString:WW_NAVIGATOR_GESTURE_RECOGNIZED])
    {
        [self setEnabled:NO];
    }
}

@end
/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVSplashScreen.h"
#import <Cordova/CDVViewController.h>
#import <Cordova/CDVScreenOrientationDelegate.h>
#import "CDVViewController+SplashScreen.h"

#define kSplashScreenDurationDefault 0.25f


@implementation CDVSplashScreen

- (void)pluginInitialize
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pageDidLoad) name:CDVPageDidLoadNotification object:self.webView];
    
    [self setVisible:YES];
}

- (void)show:(CDVInvokedUrlCommand*)command
{
    [self setVisible:YES];
}

- (void)hide:(CDVInvokedUrlCommand*)command
{
    [self setVisible:NO];
}

- (void)pageDidLoad
{
    id autoHideSplashScreenValue = [self.commandDelegate.settings objectForKey:[@"AutoHideSplashScreen" lowercaseString]];
    
    // if value is missing, default to yes
    if ((autoHideSplashScreenValue == nil) || [autoHideSplashScreenValue boolValue]) {
        [self performSelector:@selector(ChangeImage:) withObject:[NSNumber numberWithBool:false] afterDelay:_temdata];
    }
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
    [self updateImage];
}

- (void)createViews
{
    /*
     * The Activity View is the top spinning throbber in the status/battery bar. We init it with the default Grey Style.
     *
     *     whiteLarge = UIActivityIndicatorViewStyleWhiteLarge
     *     white      = UIActivityIndicatorViewStyleWhite
     *     gray       = UIActivityIndicatorViewStyleGray
     *
     */
    
    // Determine whether rotation should be enabled for this device
    // Per iOS HIG, landscape is only supported on iPad and iPhone 6+
    CDV_iOSDevice device = [self getCurrentDevice];
    BOOL autorotateValue = (device.iPad || device.iPhone6Plus) ?
    [(CDVViewController *)self.viewController shouldAutorotateDefaultValue] :
    NO;
    
    [(CDVViewController *)self.viewController setEnabledAutorotation:autorotateValue];
    
    NSString* topActivityIndicator = [self.commandDelegate.settings objectForKey:[@"TopActivityIndicator" lowercaseString]];
    UIActivityIndicatorViewStyle topActivityIndicatorStyle = UIActivityIndicatorViewStyleGray;
    
    if ([topActivityIndicator isEqualToString:@"whiteLarge"]) {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleWhiteLarge;
    } else if ([topActivityIndicator isEqualToString:@"white"]) {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleWhite;
    } else if ([topActivityIndicator isEqualToString:@"gray"]) {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleGray;
    }
    
    UIView* parentView = self.viewController.view;
    parentView.userInteractionEnabled = NO;  // disable user interaction while splashscreen is shown
    _activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:topActivityIndicatorStyle];
    _activityView.center = CGPointMake(parentView.bounds.size.width / 2, parentView.bounds.size.height / 1.2);
    _activityView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin
    | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
    [_activityView startAnimating];
    
    // Set the frame & image later.
    _imageView = [[UIImageView alloc] init];
    _bgImgView=[[UIImageView alloc]initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
    _labelView = [[UILabel alloc]initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 30)];
    
    [parentView addSubview:_bgImgView];
    [parentView addSubview:_imageView];
    [parentView addSubview:_labelView];
    // Frame is required when launching in portrait mode.
    // Bounds for landscape since it captures the rotation.
    [parentView addObserver:self forKeyPath:@"frame" options:0 context:nil];
    [parentView addObserver:self forKeyPath:@"bounds" options:0 context:nil];
    
    [self updateImage];
}

- (void)destroyViews
{
    [(CDVViewController *)self.viewController setEnabledAutorotation:[(CDVViewController *)self.viewController shouldAutorotateDefaultValue]];
    
    [_imageView removeFromSuperview];
    [_bgImgView removeFromSuperview];
    [_activityView removeFromSuperview];
    [_labelView removeFromSuperview];
    
    _imageView = nil;
    _activityView = nil;
    _curImageName = nil;
    
    self.viewController.view.userInteractionEnabled = YES;  // re-enable user interaction upon completion
    //[self.viewController.view removeObserver:self forKeyPath:@"frame"];
    //[self.viewController.view removeObserver:self forKeyPath:@"bounds"];
}

- (CDV_iOSDevice) getCurrentDevice
{
    CDV_iOSDevice device;
    
    UIScreen* mainScreen = [UIScreen mainScreen];
    CGFloat mainScreenHeight = mainScreen.bounds.size.height;
    CGFloat mainScreenWidth = mainScreen.bounds.size.width;
    
    int limit = MAX(mainScreenHeight,mainScreenWidth);
    
    device.iPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    device.iPhone = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone);
    device.retina = ([mainScreen scale] == 2.0);
    device.iPhone5 = (device.iPhone && limit == 568.0);
    // note these below is not a true device detect, for example if you are on an
    // iPhone 6/6+ but the app is scaled it will prob set iPhone5 as true, but
    // this is appropriate for detecting the runtime screen environment
    device.iPhone6 = (device.iPhone && limit == 667.0);
    device.iPhone6Plus = (device.iPhone && limit == 736.0);
    
    return device;
}

- (NSString*)getImageName:(UIInterfaceOrientation)currentOrientation delegate:(id<CDVScreenOrientationDelegate>)orientationDelegate device:(CDV_iOSDevice)device
{
    // Use UILaunchImageFile if specified in plist.  Otherwise, use Default.
    NSString* imageName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UILaunchImageFile"];
    
    NSUInteger supportedOrientations = [orientationDelegate supportedInterfaceOrientations];
    
    // Checks to see if the developer has locked the orientation to use only one of Portrait or Landscape
    BOOL supportsLandscape = (supportedOrientations & UIInterfaceOrientationMaskLandscape);
    BOOL supportsPortrait = (supportedOrientations & UIInterfaceOrientationMaskPortrait || supportedOrientations & UIInterfaceOrientationMaskPortraitUpsideDown);
    // this means there are no mixed orientations in there
    BOOL isOrientationLocked = !(supportsPortrait && supportsLandscape);
    
    if (imageName) {
        imageName = [imageName stringByDeletingPathExtension];
    } else {
        imageName = @"Default";
    }
    
    if (device.iPhone5) { // does not support landscape
        imageName = [imageName stringByAppendingString:@"-568h"];
    } else if (device.iPhone6) { // does not support landscape
        imageName = [imageName stringByAppendingString:@"-667h"];
    } else if (device.iPhone6Plus) { // supports landscape
        if (isOrientationLocked) {
            imageName = [imageName stringByAppendingString:(supportsLandscape ? @"-Landscape" : @"")];
        } else {
            switch (currentOrientation) {
                case UIInterfaceOrientationLandscapeLeft:
                case UIInterfaceOrientationLandscapeRight:
                    imageName = [imageName stringByAppendingString:@"-Landscape"];
                    break;
                default:
                    break;
            }
        }
        imageName = [imageName stringByAppendingString:@"-736h"];
        
    } else if (device.iPad) { // supports landscape
        if (isOrientationLocked) {
            imageName = [imageName stringByAppendingString:(supportsLandscape ? @"-Landscape" : @"-Portrait")];
        } else {
            switch (currentOrientation) {
                case UIInterfaceOrientationLandscapeLeft:
                case UIInterfaceOrientationLandscapeRight:
                    imageName = [imageName stringByAppendingString:@"-Landscape"];
                    break;
                    
                case UIInterfaceOrientationPortrait:
                case UIInterfaceOrientationPortraitUpsideDown:
                default:
                    imageName = [imageName stringByAppendingString:@"-Portrait"];
                    break;
            }
        }
    }
    
    return imageName;
}

// Sets the view's frame and image.
- (void)updateImage
{
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    documentsDirectory = [documentsDirectory stringByAppendingPathComponent:@""];
    NSLog(@"do ==%@",documentsDirectory);
    
    NSString *URLImg = [documentsDirectory stringByAppendingPathComponent:@"organization_splash.png"];
    
    NSLog(@"==%@",URLImg);
    
    // Fallback to Default Splashscreen
    if (![URLImg isEqualToString:_curImageName]) {
        UIImage* img = [UIImage imageNamed:URLImg];
        _imageView.image = img;
        _curImageName = URLImg;
        fallbackToDefaultSplash = TRUE;
    } else {
        fallbackToDefaultSplash = FALSE;
    }
    
    id showSplashScreenSpinnerValue = [self.commandDelegate.settings objectForKey:[@"ShowSplashScreenSpinner" lowercaseString]];
    // backwards compatibility - if key is missing, default to true
    if ((showSplashScreenSpinnerValue == nil) || [showSplashScreenSpinnerValue boolValue]) {
        [self.viewController.view addSubview:_activityView];
    }
    
    // Check that splash screen's image exists before updating bounds
    if (_imageView.image) {
        [self updateBounds];
    } else {
        
        NSString* imageName = [self getImageName:[[UIApplication sharedApplication] statusBarOrientation] delegate:(id<CDVScreenOrientationDelegate>)self.viewController device:[self getCurrentDevice]];
        if (![imageName isEqualToString:_curImageName]) {
            UIImage* img = [UIImage imageNamed:imageName];
            _imageView.image = img;
            _curImageName = imageName;
        }
        
        if (_imageView.image) {
            [self updateBounds];
        }
        else
        {
            NSLog(@"WARNING: The splashscreen image named %@ was not found", imageName);
        }
    }
    
}

- (void)updateBounds
{
    UIImage* img = _imageView.image;
    CGRect imgBounds = (img) ? CGRectMake(0, 0, img.size.width, img.size.height) : CGRectZero;
    
    CGSize screenSize = [self.viewController.view convertRect:[UIScreen mainScreen].bounds fromView:nil].size;
    UIInterfaceOrientation orientation = self.viewController.interfaceOrientation;
    CGAffineTransform imgTransform = CGAffineTransformIdentity;
    
    /* If and only if an iPhone application is landscape-only as per
     * UISupportedInterfaceOrientations, the view controller's orientation is
     * landscape. In this case the image must be rotated in order to appear
     * correctly.
     */
    BOOL isIPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    if (UIInterfaceOrientationIsLandscape(orientation) && !isIPad) {
        imgTransform = CGAffineTransformMakeRotation(M_PI / 2);
        imgBounds.size = CGSizeMake(imgBounds.size.height, imgBounds.size.width);
    }
    
    // There's a special case when the image is the size of the screen.
    if (CGSizeEqualToSize(screenSize, imgBounds.size)) {
        CGRect statusFrame = [self.viewController.view convertRect:[UIApplication sharedApplication].statusBarFrame fromView:nil];
        if (!(IsAtLeastiOSVersion(@"7.0"))) {
            imgBounds.origin.y -= statusFrame.size.height;
        }
    } else if (imgBounds.size.width > 0) {
        CGRect viewBounds = self.viewController.view.bounds;
        CGFloat imgAspect = imgBounds.size.width / imgBounds.size.height;
        CGFloat viewAspect = viewBounds.size.width / viewBounds.size.height;
        // This matches the behaviour of the native splash screen.
        CGFloat ratio;
        if (viewAspect > imgAspect) {
            ratio = viewBounds.size.width / imgBounds.size.width;
        } else {
            ratio = viewBounds.size.height / imgBounds.size.height;
        }
        imgBounds.size.height *= ratio;
        imgBounds.size.width *= ratio;
    }
    
    _labelView.text = @"Updates powered by";
    _labelView.textAlignment = NSTextAlignmentCenter;
    _labelView.textColor = [UIColor colorWithRed:0.51f green:0.51f blue:0.51f alpha:0.75f];
    _labelView.font = [UIFont systemFontOfSize:17];
    
    if(fallbackToDefaultSplash == FALSE) {
        if(screenSize.width > screenSize.height) {
            _labelView.frame = CGRectMake(0, screenSize.height/2 - 40 - (screenSize.width/(6*(img.size.width/img.size.height))), screenSize.width, 30);
            _imageView.frame=CGRectMake(screenSize.width/6, 0, screenSize.width/3, screenSize.height);
        } else {
            if(screenSize.width >= 1024) {
                _labelView.frame = CGRectMake(0, screenSize.height/2 - 40 - (screenSize.width/(4*(img.size.width/img.size.height))), screenSize.width, 30);
                _imageView.frame=CGRectMake(screenSize.width/4, 0, screenSize.width/2, screenSize.height);
                
            } else {
                _labelView.frame = CGRectMake(0, screenSize.height/2 - 40 - (screenSize.width/(2.5*(img.size.width/img.size.height))), screenSize.width, 30);
                _imageView.frame=CGRectMake(screenSize.width/2.5, 0, screenSize.width/1.25, screenSize.height);
            }
        }
    } else {
        _labelView.frame = CGRectMake(0, 0, 0, 0);
        _imageView.frame=CGRectMake(0, 0, screenSize.width, screenSize.height);
    }
    _imageView.center=self.viewController.view.center;
    _imageView.transform = imgTransform;
    [_imageView setContentMode:UIViewContentModeScaleAspectFit
     ];
    NSLog(@"%@",NSStringFromCGRect(self.viewController.view.frame));
    [_bgImgView setBackgroundColor:[UIColor colorWithRed:223.0/255.0 green:231.0/255.0 blue:235.0/255.0 alpha:1.0]];
}

- (void)setVisible:(BOOL)visible
{
    if (visible == _visible) {
        return;
    }
    _visible = visible;
    
    id fadeSplashScreenValue = [self.commandDelegate.settings objectForKey:[@"FadeSplashScreen" lowercaseString]];
    id fadeSplashScreenDuration = [self.commandDelegate.settings objectForKey:[@"FadeSplashScreenDuration" lowercaseString]];
    
    float fadeDuration = fadeSplashScreenDuration == nil ? kSplashScreenDurationDefault : [fadeSplashScreenDuration floatValue];
    _temdata=fadeDuration;
    if ((fadeSplashScreenValue == nil) || ![fadeSplashScreenValue boolValue]) {
        fadeDuration = 0;
    }
    
    // Never animate the showing of the splash screen.
    if (visible) {
        if (_imageView == nil) {
            [self createViews];
        }
    } else if (fadeDuration == 0) {
        [self performSelector:@selector(ChangeImage:) withObject:[NSNumber numberWithBool:false] afterDelay:_temdata];
    } else {
        __weak __typeof(self) weakSelf = self;
        
        [UIView transitionWithView:self.viewController.view
                          duration:fadeDuration
                           options:UIViewAnimationOptionTransitionNone
                        animations:^(void) {
                            __typeof(self) strongSelf = weakSelf;
                            if (strongSelf != nil) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [strongSelf->_activityView setAlpha:0];
                                    [strongSelf->_imageView setAlpha:0];
                                });
                            }
                        }
                        completion:^(BOOL finished) {
                            if (finished) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [weakSelf destroyViews];
                                });
                            }
                        }
         ];
    }
}
-(void)ChangeImage:(id)sender{
    [self destroyViews];
}

@end

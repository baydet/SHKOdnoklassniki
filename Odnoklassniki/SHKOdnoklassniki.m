//
// Created by Alexandr Evsyuchenya on 3/3/15.
// Copyright (c) 2015 Orangesoft. All rights reserved.
//

#import "SHKOdnoklassniki.h"
#import "Odnoklassniki.h"
#import "SHKConfiguration.h"
#import "SHKSharer_protected.h"
#import "OKMediaTopicPostViewController.h"
#import "SHKFormController.h"


@interface SHKOdnoklassniki () <OKSessionDelegate, OKRequestDelegate>
@end

@implementation SHKOdnoklassniki

static SHKOdnoklassniki *__loginSharer = nil;

+ (Odnoklassniki *)instanceOK
{
    static Odnoklassniki *_instance = nil;

    @synchronized (self)
    {
        if (_instance == nil)
        {
            _instance = [[Odnoklassniki alloc] initWithAppId:SHKCONFIG(odnoklassnikiAppId) appSecret:SHKCONFIG(odnoklassnikiSecret) appKey:SHKCONFIG(odnoklassnikiAppKey) delegate:nil];
        }
    }

    return _instance;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        static dispatch_once_t token = 0;
        dispatch_once(&token, ^{
            [SHKOdnoklassniki logout];
        });
    }

    return self;
}

+ (BOOL)canShareOffline
{
    return NO;
}

+ (NSString *)sharerTitle
{
    return @"OK";
}

- (void)promptAuthorization
{
    Odnoklassniki *const odnoklassniki = [self.class instanceOK];
    __loginSharer = self;
    odnoklassniki.delegate = self;
    [odnoklassniki authorizeWithPermissions:SHKCONFIG(odnoklassnikiPermissions)];
}

+ (void)logout
{
    [[OKSession activeSession] close];
    [[self instanceOK] logout];
}

+ (NSString *)username
{
    return [super username];
}

+ (BOOL)canShareImage
{
    return YES;
}


+ (BOOL)isServiceAuthorized
{
    return [self instanceOK].isSessionValid;
}

- (BOOL)isAuthorized
{
    return [[self class] instanceOK].isSessionValid;
}

- (BOOL)send
{
    if (![self validateItem])
        return NO;

    switch (self.item.shareType)
    {
        case SHKShareTypeImage:
            [self sendImageAction];
            break;
        default:
            return NO;
    }

    return YES;
}

- (void)sendImageAction
{
    OKRequest *const requestURL = [Odnoklassniki requestWithMethodName:@"photosV2.getUploadUrl" params:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        [requestURL executeWithCompletionBlock:^(NSDictionary *responseDictionary) {
            NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
            NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:nil];

            id const photoId = [responseDictionary[@"photo_ids"] firstObject];
            NSMutableURLRequest *request = [self getPOSTPhotoRequestForURLString:responseDictionary[@"upload_url"] imageId:photoId];

            NSURLSessionDataTask *postDataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *httpurlResponse = (NSHTTPURLResponse *) response;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                     options:kNilOptions
                                                                       error:&error];

                if (httpurlResponse.statusCode == 200)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{

                        id const imageToken = json[@"photos"][photoId][@"token"];
                        OKRequest *commitRequest = [Odnoklassniki requestWithMethodName:@"photosV2.commit" params:@{
                                @"photo_id" : photoId,
                                @"token" : imageToken}];
                        [commitRequest executeWithCompletionBlock:^(id data1) {
                            NSDictionary *attachments = [self attachmentDictionaryWitImageId:data1[@"photos"][0][@"assigned_photo_id"]];

                            OKMediaTopicPostViewController *postViewController = [OKMediaTopicPostViewController postViewControllerWithAttachments:attachments];
                            __weak typeof (postViewController) wpostViewController = postViewController;
                            postViewController.resultBlock = ^(BOOL result, BOOL canceled, NSError *error) {
                                if (result)
                                    [self sendDidFinish];
                                else if (canceled)
                                    [self sendDidCancel];
                                else
                                    [self sendDidFailWithError:error];
                                [wpostViewController dismiss];
                            };
                            [postViewController presentInViewController:[UIApplication sharedApplication].keyWindow.rootViewController];

                        }                              errorBlock:^(NSError *error1) {
                            [self sendDidFailWithError:error1];
                        }];

                    });
                }
                else
                {
                    [self sendDidFailWithError:error];
                }
            }];
            [postDataTask resume];

        }                           errorBlock:^(NSError *error) {
            [self sendDidFailWithError:error];
        }];
    });
}

- (NSDictionary *)attachmentDictionaryWitImageId:(NSString *)imageId
{
    NSMutableArray *attachmentComponents = [NSMutableArray array];

    if (imageId && self.item.image)
    {
        [attachmentComponents addObject:[self attachmentPhotoDictionaryWithImageId:imageId]];
    }

    if (self.item.URL)
    {
        [attachmentComponents addObject:[self attachmentURLDictionary]];
    }

    if (self.item.title)
    {
        [attachmentComponents addObject:[self attachmentTextDictionary]];
    }

    return @{@"media" : attachmentComponents};
}

- (NSDictionary *)attachmentPhotoDictionaryWithImageId:(NSString *)imageId
{
    NSAssert(imageId, @"'imageId' cannot be nil");
    return @{@"type" : @"photo", @"list" : @[@{@"photoId" : imageId}]};
}

- (NSDictionary *)attachmentURLDictionary
{
    return @{@"type" : @"link", @"url" : [self.item.URL absoluteString]};
}

- (NSDictionary *)attachmentTextDictionary
{
    return @{@"type" : @"text", @"text" : self.item.title};
}


- (NSMutableURLRequest *)getPOSTPhotoRequestForURLString:(NSString *)URLString imageId:(NSString *)imageId
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URLString]];

    NSData *imageData = UIImageJPEGRepresentation(self.item.image, 1.0);

    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [request setHTTPShouldHandleCookies:NO];
    [request setTimeoutInterval:60];
    [request setHTTPMethod:@"POST"];

    NSString *boundary = [[NSUUID UUID] UUIDString];

    // set Content-Type in HTTP header
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];

    // post body
    NSMutableData *body = [NSMutableData data];

    // add params (all params are strings)
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=%@\r\n\r\n", imageId] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", @"Some Caption"] dataUsingEncoding:NSUTF8StringEncoding]];

    // add image data
    if (imageData)
    {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=%@; filename=%@.jpg\r\n", imageId, imageId] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Type: image/*\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:imageData];
        [body appendData:[[NSString stringWithFormat:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    }

    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    // setting the body of the post to the reqeust
    [request setHTTPBody:body];

    // set the content-length
    NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[body length]];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    return request;
}


#pragma mark - Private methods

- (void)okShouldPresentAuthorizeController:(UIViewController *)viewController
{
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:viewController animated:YES completion:nil];
}

- (void)okDidLogin
{
    id <SHKSharerDelegate> o = self.shareDelegate;
    if ([o respondsToSelector:@selector(sharerAuthDidFinish:success:)])
    {
        [o sharerAuthDidFinish:self success:YES];
    }
    [self authorizationFormSave](nil);
}

- (void)okDidNotLogin:(BOOL)canceled
{
    [self authorizationFormCancel](nil);
}

- (void)okDidNotLoginWithError:(NSError *)error
{
    [self authorizationFormCancel](nil);
}

- (void)okWillDismissAuthorizeControllerByCancel:(BOOL)canceled
{
    [self authorizationFormCancel](nil);
    id <SHKSharerDelegate> o = self.shareDelegate;
    if ([o respondsToSelector:@selector(sharerAuthDidFinish:success:)])
    {
        [o sharerAuthDidFinish:self success:NO];
    }
}


@end
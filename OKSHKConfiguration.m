//
// Created by Alexandr Evsyuchenya on 3/3/15.
// Copyright (c) 2015 Orangesoft. All rights reserved.
//

#import "DefaultSHKConfigurator.h"
#import "OKSHKConfiguration.h"


@implementation OKSHKConfiguration

- (NSString *)odnoklassnikiAppId
{
    return @"";
}

- (NSString *)odnoklassnikiSecret
{
    return @"";
}

- (NSString *)odnoklassnikiAppKey
{
    return @"";
}

- (NSArray *)odnoklassnikiPermissions
{
    return @[@"VALUABLE ACCESS", @"PHOTO CONTENT"];
}

@end
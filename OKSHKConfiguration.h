//
// Created by Alexandr Evsyuchenya on 3/3/15.
// Copyright (c) 2015 Orangesoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SHKConfiguration.h"


@interface OKSHKConfiguration : DefaultSHKConfigurator

- (NSString *)odnoklassnikiAppId;

- (NSString *)odnoklassnikiSecret;

- (NSString *)odnoklassnikiAppKey;

- (NSArray *)odnoklassnikiPermissions;

@end
// Copyright (c) Microsoft Corporation.
// All rights reserved.
//
// This code is licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <Foundation/Foundation.h>
#import "MSIDAccountType.h"
#import "MSIDAccountCacheItem.h"
#import "MSIDCredentialCacheItem.h"
#import "MSIDLogger.h"
#import "MSIDStorageManagerMac.h"
#import "MSIDCredentialType.h"
#import "MSIDJsonSerializer.h"

typedef NS_ENUM(NSInteger, MSIDKeychainAccountType)
{
    MSIDKeychainAccountTypeAADV1 = 1001,
    MSIDKeychainAccountTypeMSA,
    MSIDKeychainAccountTypeMSSTS,
    MSIDKeychainAccountTypeOther
};


@interface MSIDStorageManagerMac ()

@property (readwrite, nullable) MSIDJsonSerializer* jsonSerializer;

@end


@implementation MSIDStorageManagerMac

@synthesize accessGroup = _accessGroup;

#pragma mark - init

- (id)init {
    self = [super init];
    if (self) {
        _jsonSerializer = [MSIDJsonSerializer new];
        _accessGroup = @"";
    }
    return self;
}

#pragma mark - Credentials

/** Gets all credentials which match the parameters. */
- (nullable NSArray<MSIDCredentialCacheItem *> *)readCredentials:(nullable __unused NSString *)correlationId
                                                   homeAccountId:(nullable __unused NSString *)homeAccountId
                                                     environment:(nullable __unused NSString *)environment
                                                           realm:(nullable __unused NSString *)realm
                                                        clientId:(nullable __unused NSString *)clientId
                                                          target:(nullable __unused NSString *)target
                                                           types:(nullable __unused NSSet<NSNumber *> *)types
                                                           error:(__unused NSError *_Nullable *_Nullable)error {
    return nil;
}

/** Writes all credentials in the list to the storage. */
- (BOOL)writeCredentials:(nullable __unused NSString *)correlationId
             credentials:(nullable __unused NSArray<MSIDCredentialCacheItem *> *)credentials
                   error:(NSError __unused *_Nullable *_Nullable)error {
    return TRUE;
}

/** Deletes all matching credentials. Parameters mirror read_credentials. */
- (BOOL)deleteCredentials:(nullable __unused NSString *)correlationId
            homeAccountId:(nullable __unused NSString *)homeAccountId
              environment:(nullable __unused NSString *)environment
                    realm:(nullable __unused NSString *)realm
                 clientId:(nullable __unused NSString *)clientId
                   target:(nullable __unused NSString *)target
                    types:(nullable __unused NSSet<NSNumber *> *)types
                    error:(__unused NSError *_Nullable *_Nullable)error {
    return TRUE;
}

#pragma mark - Accounts

/** Reads all accounts present in the cache. */
- (nullable NSArray<MSIDAccountCacheItem *> *)readAllAccounts:(nullable __unused NSString *)correlationId
                                                        error:(__unused NSError *_Nullable *_Nullable)error {
    return nil;
}

/** Reads an account object, if present. */
- (nullable MSIDAccountCacheItem *)readAccount:(nullable __unused NSString *)correlationId
                                 homeAccountId:(nullable __unused NSString *)homeAccountId
                                   environment:(nullable __unused NSString *)environment
                                         realm:(nullable __unused NSString *)realm
                                         error:(__unused NSError *_Nullable *_Nullable)error {
    return nil;
}

/** Write an account object into cache. */
- (BOOL)writeAccount:(nullable __unused NSString *)correlationId
             account:(nullable MSIDAccountCacheItem *)account
               error:(NSError *_Nullable *_Nullable)error {

    NSData *itemData = [self.jsonSerializer toJsonData:account context:nil error:error];
    if (!itemData) {
        // TODO: handle error
        return FALSE;
    }

    NSDictionary *query = [self defaultAccountQuery:account];
    NSDictionary *update = @{ (id)kSecValueData:itemData };
    
    OSStatus status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
    if (status == errSecItemNotFound) {
        NSMutableDictionary* item = [query mutableCopy];
        [item addEntriesFromDictionary:update];
        status = SecItemAdd((CFDictionaryRef)item, NULL);
    }

    // TODO: Set the keychain item’s ACL to allow access by all apps.
    
    if (status != errSecSuccess) {
        // TODO: handle error
        return FALSE;
    } else {
        return TRUE;
    }
}

/** Deletes an account and all associated credentials. */
- (BOOL)deleteAccount:(nullable __unused NSString *)correlationId
        homeAccountId:(nullable __unused NSString *)homeAccountId
          environment:(nullable __unused NSString *)environment
                realm:(nullable __unused NSString *)realm
                error:(__unused NSError *_Nullable *_Nullable)error {
    return TRUE;
}

/** Deletes all information associated with a given homeAccountId and environment. */
- (BOOL)deleteAccounts:(nullable __unused NSString *)correlationId
         homeAccountId:(nullable __unused NSString *)homeAccountId
           environment:(nullable __unused NSString *)environment
                 error:(__unused NSError *_Nullable *_Nullable)error {
    return TRUE;
}

- (NSDictionary*)defaultAccountQuery:(MSIDAccountCacheItem*)account {
    return @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: account.realm,
        (id)kSecAttrAccount: [NSString stringWithFormat:@"%@-%@-%@",
                              self.accessGroup, account.homeAccountId, account.environment],
        (id)kSecAttrGeneric: account.localAccountId,
        (id)kSecAttrType: [self accountAttribute:account.accountType],
    };
}

- (NSNumber*)accountAttribute:(MSIDAccountType)accountType {
    switch (accountType) {
        case MSIDAccountTypeAADV1:
            return @(MSIDKeychainAccountTypeAADV1);
        case MSIDAccountTypeMSA:
            return @(MSIDKeychainAccountTypeMSA);
        case MSIDAccountTypeMSSTS:
            return @(MSIDKeychainAccountTypeMSSTS);
        case MSIDAccountTypeOther:
            return @(MSIDKeychainAccountTypeOther);
    }
}

- (MSIDAccountType)accountType:(NSNumber*)accountAttribute {
    switch ([accountAttribute integerValue]) {
        case MSIDKeychainAccountTypeAADV1:
            return MSIDAccountTypeAADV1;
        case MSIDKeychainAccountTypeMSA:
            return MSIDAccountTypeMSA;
        case MSIDKeychainAccountTypeMSSTS:
            return MSIDAccountTypeMSSTS;
        case MSIDKeychainAccountTypeOther:
            return MSIDAccountTypeOther;
        default:
            // TODO: report error/log?
            return MSIDAccountTypeOther;
    }
}

@end

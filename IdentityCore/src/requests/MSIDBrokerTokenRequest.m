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

#import "MSIDBrokerTokenRequest.h"
#import "MSIDInteractiveRequestParameters.h"
#import "MSIDVersion.h"
#import "MSIDIntuneEnrollmentIdsCache.h"
#import "MSIDIntuneMAMResourcesCache.h"
#import "MSIDAuthority.h"
#import "NSDictionary+MSIDExtensions.h"
#import "MSIDConstants.h"
#import "NSString+MSIDExtensions.h"

#if TARGET_OS_IPHONE
#import "MSIDKeychainTokenCache.h"
#endif

@interface MSIDBrokerTokenRequest()

@property (nonatomic, readwrite) MSIDInteractiveRequestParameters *requestParameters;
@property (nonatomic, readwrite) NSDictionary *resumeDictionary;
@property (nonatomic, readwrite) NSString *brokerKey;
@property (nonatomic, readwrite) NSURL *brokerRequestURL;

@end

@implementation MSIDBrokerTokenRequest

#pragma mark - Init

- (instancetype)initWithRequestParameters:(MSIDInteractiveRequestParameters *)parameters
                                brokerKey:(NSString *)brokerKey
                                    error:(NSError **)error
{
    self = [super init];

    if (self)
    {
        _requestParameters = parameters;

        if (![self initPayloadContentsWithError:error])
        {
            return nil;
        }

        [self initResumeDictionary];
    }

    return self;
}

- (BOOL)initPayloadContentsWithError:(NSError **)error
{
    NSMutableDictionary *contents = [NSMutableDictionary new];

    NSDictionary *defaultContents = [self defaultPayloadContents:error];

    if (!defaultContents)
    {
        return NO;
    }

    [contents addEntriesFromDictionary:defaultContents];

    NSDictionary *protocolContents = [self protocolPayloadContentsWithError:error];

    if (!protocolContents)
    {
        return NO;
    }

    [contents addEntriesFromDictionary:protocolContents];

    NSString* query = [NSString msidWWWFormURLEncodedStringFromDictionary:contents];

    NSURL *brokerRequestURL = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"%@://broker?%@", self.requestParameters.supportedBrokerProtocolScheme, query]];

    if (!brokerRequestURL)
    {
        if (error)
        {
            *error = MSIDCreateError(MSIDErrorDomain, MSIDErrorInternal, @"Unable to create broker request URL", nil, nil, nil, self.requestParameters.correlationId, nil);
        }

        MSID_LOG_ERROR(self.requestParameters, @"Unable to create broker request URL");
        MSID_LOG_ERROR(self.requestParameters, @"Unable to create broker request URL with contents %@", contents);
        return NO;
    }

    _brokerRequestURL = brokerRequestURL;
    return YES;
}

- (void)initResumeDictionary
{
    NSMutableDictionary *contents = [NSMutableDictionary new];
    [contents addEntriesFromDictionary:[self defaultResumeDictionaryContents]];
    [contents addEntriesFromDictionary:[self protocolResumeDictionaryContents]];

    _resumeDictionary = contents;
}

#pragma mark - Default contents

- (NSDictionary *)defaultPayloadContents:(NSError **)error
{
    if (![self checkParameter:self.requestParameters.authority parameterName:@"authority" error:error]) return nil;
    if (![self checkParameter:self.requestParameters.target parameterName:@"target" error:error]) return nil;
    if (![self checkParameter:self.requestParameters.correlationId parameterName:@"correlationId" error:error]) return nil;
    if (![self checkParameter:self.requestParameters.clientId parameterName:@"clientId" error:error]) return nil;
    if (![self checkParameter:self.brokerKey parameterName:@"brokerKey" error:error]) return nil;

    MSID_LOG_INFO(self.requestParameters, @"Invoking broker for authentication");

    NSString *enrollmentIds = [self intuneEnrollmentIdsParameterWithError:error];
    if (!enrollmentIds) return nil;

    NSString *mamResources = [self intuneMAMResourceParameterWithError:error];
    if (!mamResources) return nil;

    NSString *capabilities = [self.requestParameters.clientCapabilities componentsJoinedByString:@","];
    NSDictionary *clientMetadata = self.requestParameters.appRequestMetadata;
    NSString *claimsString = [self claimsParameter];
    NSString *clientAppName = clientMetadata[MSID_APP_NAME_KEY];
    NSString *clientAppVersion = clientMetadata[MSID_APP_VER_KEY];

    NSDictionary *queryDictionary =
    @{
      @"authority": self.requestParameters.authority.url.absoluteString,
      @"client_id": self.requestParameters.clientId,
      @"redirect_uri": self.requestParameters.redirectUri,
      @"correlation_id": self.requestParameters.correlationId.UUIDString,
#if TARGET_OS_IPHONE
      @"broker_key": self.brokerKey,
#endif
      @"client_version": [MSIDVersion sdkVersion],
      @"extra_qp": self.requestParameters.extraQueryParameters ?: @{},
      @"claims": claimsString ?: @"",
      @"intune_enrollment_ids": enrollmentIds ?: @"",
      @"intune_mam_resource": mamResources ?: @"",
      @"client_capabilities": capabilities ?: @"",
      @"client_app_name": clientAppName ?: @"",
      @"client_app_version": clientAppVersion ?: @""
    };

    return queryDictionary;
}

- (NSDictionary *)defaultResumeDictionaryContents
{
    NSDictionary *resumeDictionary =
    @{
      @"authority"        : self.requestParameters.authority.url.absoluteString,
      @"client_id"        : self.requestParameters.clientId,
      @"redirect_uri"     : self.requestParameters.redirectUri,
      @"correlation_id"   : self.requestParameters.correlationId.UUIDString,
#if TARGET_OS_IPHONE
      @"keychain_group"   : self.requestParameters.keychainAccessGroup ?: MSIDKeychainTokenCache.defaultKeychainGroup
#endif
      };
    return resumeDictionary;
}

- (BOOL)checkParameter:(id)parameter
         parameterName:(NSString *)parameterName
                 error:(NSError **)error
{
    if (!parameter)
    {
        NSString *errorDescription = [NSString stringWithFormat:@"%@ is nil, but is a required parameter", parameterName];
        MSID_LOG_ERROR(self.requestParameters, @"%@", errorDescription);

        if (error)
        {
            *error = MSIDCreateError(MSIDErrorDomain, MSIDErrorInvalidDeveloperParameter, errorDescription, nil, nil, nil, self.requestParameters.correlationId, nil);
        }

        return NO;
    }

    return YES;
}

#pragma mark - Helpers

- (NSString *)claimsParameter
{
    if (!self.requestParameters.claims)
    {
        return nil;
    }

    NSString *claimsString = [self.requestParameters.claims msidJSONSerializeWithContext:self.requestParameters];

    if (!claimsString)
    {
        MSID_LOG_WARN(self.requestParameters, @"Failed to serialize claims parameter");
        return nil;
    }

    return claimsString;
}

- (NSString *)intuneEnrollmentIdsParameterWithError:(NSError **)error
{
    NSError *cacheError = nil;

    NSDictionary *enrollmentIds = [[MSIDIntuneEnrollmentIdsCache sharedCache] enrollmentIdsJsonDictionaryWithContext:self.requestParameters
                                                                                                               error:&cacheError];

    if (cacheError)
    {
        MSID_LOG_ERROR(self.requestParameters, @"Failed to retrieve valid intune enrollment IDs with error %ld, %@", (long)cacheError.code, cacheError.domain);
        MSID_LOG_ERROR_PII(self.requestParameters, @"Failed to retrieve valid intune enrollment IDs with error %@", cacheError);
        if (error) *error = cacheError;
        return nil;
    }

    NSString *serializedEnrollmentIds = [enrollmentIds msidJSONSerializeWithContext:self.requestParameters];
    return serializedEnrollmentIds ?: @"";
}

- (NSString *)intuneMAMResourceParameterWithError:(NSError **)error
{
    NSError *cacheError = nil;

    NSDictionary *mamResources = [[MSIDIntuneMAMResourcesCache sharedCache] resourcesJsonDictionaryWithContext:self.requestParameters
                                                                                                         error:&cacheError];

    if (cacheError)
    {
        MSID_LOG_ERROR(self.requestParameters, @"Failed to retrieve valid intune MAM resource with error %ld, %@", (long)cacheError.code, cacheError.domain);
        MSID_LOG_ERROR_PII(self.requestParameters, @"Failed to retrieve valid intune MAM resource with error %@", cacheError);
        if (error) *error = cacheError;
        return nil;
    }

    NSString *serializedResources = [mamResources msidJSONSerializeWithContext:self.requestParameters];
    return serializedResources ?: @"";
}

#pragma mark - Abstract

// Thos parameters will be different depending on the broker protocol version
- (NSDictionary *)protocolPayloadContentsWithError:(NSError **)error
{
    NSAssert(NO, @"Abstract method. Should be implemented in its subclasses");
    return nil;
}

- (NSDictionary *)protocolResumeDictionaryContents
{
    NSAssert(NO, @"Abstract method. Should be implemented in its subclasses");
    return nil;
}

@end

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

#import "MSIDAdfsAuthorityResolver.h"
#import "MSIDAuthority.h"
#import "MSIDWebFingerRequest.h"
#import "MSIDDRSDiscoveryRequest.h"

static NSString *const s_kTrustedRelation = @"http://schemas.microsoft.com/rel/trusted-realm";

@implementation MSIDAdfsAuthorityResolver

- (void)discoverAuthority:(NSURL *)authority
        userPrincipalName:(NSString *)upn
                 validate:(BOOL)validate
                  context:(id<MSIDRequestContext>)context
          completionBlock:(MSIDAuthorityInfoBlock)completionBlock
{
    if (!validate)
    {
        __auto_type openIdConfigurationEndpoint = [self openIdConfigurationEndpointForAuthority:authority];
        if (completionBlock) completionBlock(authority, openIdConfigurationEndpoint, NO, nil);
        return;
    }
    
    // Check for upn suffix
    NSString *domain = [self getDomain:upn];
    if ([NSString msidIsStringNilOrBlank:domain])
    {
        __auto_type error = MSIDCreateError(MSIDErrorDomain, MSIDErrorInternal, @"'upn' is a required parameter and must not be nil or empty.", nil, nil, nil, context.correlationId, nil);
        
        completionBlock(nil, nil, NO, error);
        return;
    }
    
    [self sendDrsDiscoveryWithDomain:domain context:context completionBlock:^(NSURL *issuer, NSError *error)
     {
         __auto_type webFingerRequest = [[MSIDWebFingerRequest alloc] initWithIssuer:issuer
                                                                           authority:authority];
         [webFingerRequest sendWithBlock:^(id response, NSError *error)
          {
              if (error)
              {
                  if (completionBlock) completionBlock(nil, nil, NO, error);
                  return;
              }
              
              if ([self isRealmTrustedFromWebFingerPayload:response authority:authority])
              {
                  __auto_type openIdConfigurationEndpoint = [self openIdConfigurationEndpointForAuthority:authority];
                  completionBlock(authority, openIdConfigurationEndpoint, YES, nil);
              }
              else
              {
                  error = MSIDCreateError(MSIDErrorDomain, MSIDErrorDeveloperAuthorityValidation, @"WebFinger request was invalid or failed", nil, nil, nil, context.correlationId, nil);
                  completionBlock(nil, nil, NO, error);
              }
          }];
     }];
}

- (void)sendDrsDiscoveryWithDomain:(NSString *)domain
                           context:(id<MSIDRequestContext>)context
                   completionBlock:(MSIDHttpRequestDidCompleteBlock)completionBlock
{
    __auto_type drsPremRequest = [[MSIDDRSDiscoveryRequest alloc] initWithDomain:domain adfsType:MSIDADFSTypeOnPrems];
    drsPremRequest.context = context;
    [drsPremRequest sendWithBlock:^(id response, NSError *error)
     {
         if (response)
         {
             completionBlock(response, error);
             return;
         }
         
         __auto_type drsCloudRequest = [[MSIDDRSDiscoveryRequest alloc] initWithDomain:domain adfsType:MSIDADFSTypeCloud];
         drsCloudRequest.context = context;
         [drsCloudRequest sendWithBlock:^(id response, NSError *error)
          {
              if (response)
              {
                  completionBlock(response, error);
                  return;
              }
          }];
     }];
}

- (BOOL)isRealmTrustedFromWebFingerPayload:(id)json
                                 authority:(NSURL *)authority
{
    NSArray *links = [json objectForKey:@"links"];
    for (id link in links)
    {
        NSString *rel = [link objectForKey:@"rel"];
        NSString *target = [link objectForKey:@"href"];
        
        NSURL *targetURL = [NSURL URLWithString:target];
        
        if ([rel caseInsensitiveCompare:s_kTrustedRelation] == NSOrderedSame &&
            [targetURL msidIsEquivalentAuthority:authority])
        {
            return YES;
        }
    }
    return NO;
}

- (NSURL *)openIdConfigurationEndpointForAuthority:(NSURL *)authority
{
    if (!authority) return nil;
    
    return [authority URLByAppendingPathComponent:@".well-known/openid-configuration"];
}

- (NSString *)getDomain:(NSString *)upn
{
    if (!upn)
    {
        return nil;
    }
    
    NSArray *array = [upn componentsSeparatedByString:@"@"];
    if (array.count != 2)
    {
        return nil;
    }
    
    return array[1];
}

@end
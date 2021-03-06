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
#import "MSIDChallengeHandler.h"

static NSMutableDictionary *s_handlers = nil;

@implementation MSIDChallengeHandler

+ (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge
                webview:(WKWebView *)webview
                context:(id<MSIDRequestContext>)context
      completionHandler:(ChallengeCompletionHandler)completionHandler
{
    NSString *authMethod = [challenge.protectionSpace.authenticationMethod lowercaseString];
    
    BOOL handled = NO;
    Class<MSIDChallengeHandling> handler = nil;
    @synchronized (self)
    {
        handler = [s_handlers objectForKey:authMethod];
    }
    
    if (!handler)
    {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
    
    handled = [handler handleChallenge:challenge
                               webview:webview
                               context:context
                     completionHandler:completionHandler];

    if (!handled)
    {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
}

+ (void)registerHandler:(Class<MSIDChallengeHandling>)handler
             authMethod:(NSString *)authMethod
{
    if (!handler || !authMethod)
    {
        return;
    }
    
    authMethod = [authMethod lowercaseString];
    
    @synchronized(self)
    {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            s_handlers = [NSMutableDictionary new];
        });
        
        [s_handlers setValue:handler forKey:authMethod];
    }
}

+ (void)resetHandlers
{
    @synchronized(self)
    {
        for (NSString *key in s_handlers)
        {
            Class<MSIDChallengeHandling> handler = [s_handlers objectForKey:key];
            [handler resetHandler];
        }
    }
}

@end

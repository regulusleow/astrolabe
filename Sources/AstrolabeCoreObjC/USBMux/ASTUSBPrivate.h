//
//  ASTUSBPrivate.h
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/12.
//
//  Portions derived from PeerTalk and LookinServer.
//  See THIRD_PARTY_NOTICES for license and attribution details.
//

#pragma once

#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && (!defined(__IPHONE_6_0) || __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_6_0)) || \
    (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && (!defined(__MAC_10_8) || __MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_8))
#define AST_DISPATCH_RETAIN_RELEASE 1
#else
#define AST_DISPATCH_RETAIN_RELEASE 0
#endif

#if AST_DISPATCH_RETAIN_RELEASE
#define AST_PRECISE_LIFETIME
#define AST_PRECISE_LIFETIME_UNUSED
#else
#define AST_PRECISE_LIFETIME __attribute__((objc_precise_lifetime))
#define AST_PRECISE_LIFETIME_UNUSED __attribute__((objc_precise_lifetime, unused))
#endif

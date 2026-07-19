//
//  ASTUSBMuxTransport.h
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ASTUSBMuxTransportErrorDomain;

typedef NS_ERROR_ENUM(ASTUSBMuxTransportErrorDomain, ASTUSBMuxTransportErrorCode) {
    ASTUSBMuxTransportErrorCodeInvalidArgument = 1,
    ASTUSBMuxTransportErrorCodeListenerFailed = 2,
    ASTUSBMuxTransportErrorCodeConnectionFailed = 3,
    ASTUSBMuxTransportErrorCodeTimedOut = 4,
    ASTUSBMuxTransportErrorCodeConnectionClosed = 5,
};

/// Describes one physical device announced by the local usbmux daemon.
@interface ASTUSBMuxDevice : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Numeric identifier used by usbmux to open a device port.
@property(nonatomic, copy, readonly) NSString *deviceIdentifier;

/// Stable device serial number, normally equal to the iOS UDID.
@property(nonatomic, copy, readonly, nullable) NSString *serialNumber;

/// Creates an immutable usbmux device identity.
- (instancetype)initWithDeviceIdentifier:(NSString *)deviceIdentifier
                             serialNumber:(nullable NSString *)serialNumber NS_DESIGNATED_INITIALIZER;

@end

/// Discovers device identifiers published by the local usbmux daemon.
@interface ASTUSBMuxDeviceDiscovery : NSObject

/// Returns currently attached USB devices after discovery starts.
- (nullable NSArray<ASTUSBMuxDevice *> *)connectedDevicesWithTimeout:(NSTimeInterval)timeout
                                                                error:(NSError **)error;

@end

/// Provides a blocking byte-stream connection to one TCP port over usbmux.
@interface ASTUSBMuxConnection : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Creates a connection target without opening the underlying stream.
- (nullable instancetype)initWithDeviceIdentifier:(NSString *)deviceIdentifier
                                             port:(uint16_t)port NS_DESIGNATED_INITIALIZER;

/// Opens the usbmux stream.
- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/// Sends all bytes or returns an error.
- (BOOL)sendData:(NSData *)data
         timeout:(NSTimeInterval)timeout
           error:(NSError **)error;

/// Reads exactly `length` bytes or returns an error.
- (nullable NSData *)receiveDataOfLength:(NSUInteger)length
                                 timeout:(NSTimeInterval)timeout
                                   error:(NSError **)error;

/// Closes the stream and cancels pending I/O.
- (void)close;

@end

NS_ASSUME_NONNULL_END

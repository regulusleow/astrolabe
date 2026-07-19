//
//  ASTUSBMuxTransport.m
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/12.
//

#import <AstrolabeCoreObjC/ASTUSBMuxTransport.h>

#import "ASTUSBHub.h"

NSErrorDomain const ASTUSBMuxTransportErrorDomain = @"com.astrolabe.usbmux";

static NSError *ASTUSBMuxError(ASTUSBMuxTransportErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ASTUSBMuxTransportErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface ASTUSBMuxHubCoordinator : NSObject

@property(nonatomic, strong) ASTUSBHub *hub;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ASTUSBMuxDevice *> *devicesByIdentifier;
@property(nonatomic, strong, nullable) id attachObserver;
@property(nonatomic, strong, nullable) id detachObserver;
@property(nonatomic, assign) BOOL started;

+ (instancetype)sharedCoordinator;
- (BOOL)startWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;
- (NSArray<ASTUSBMuxDevice *> *)connectedDevices;

@end

@implementation ASTUSBMuxHubCoordinator

+ (instancetype)sharedCoordinator {
    static ASTUSBMuxHubCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [ASTUSBMuxHubCoordinator new];
    });
    return coordinator;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        NSLog(@"Failed: ASTUSBMuxHubCoordinator initialization failed");
        return nil;
    }
    _hub = [ASTUSBHub new];
    _queue = dispatch_queue_create("com.astrolabe.usbmux", DISPATCH_QUEUE_SERIAL);
    _devicesByIdentifier = [NSMutableDictionary dictionary];
    [self installObservers];
    return self;
}

- (void)dealloc {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    if (self.attachObserver) {
        [center removeObserver:self.attachObserver];
    }
    if (self.detachObserver) {
        [center removeObserver:self.detachObserver];
    }
}

- (BOOL)startWithTimeout:(NSTimeInterval)timeout error:(NSError **)error {
    if (timeout <= 0) {
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeInvalidArgument,
                @"USB device discovery timeout must be greater than zero"
            );
        }
        return NO;
    }
    @synchronized (self) {
        if (self.started) {
            return YES;
        }
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *startError;
    [self.hub listenOnQueue:self.queue timeout:timeout onStart:^(NSError *listenerError) {
        startError = listenerError;
        dispatch_semaphore_signal(semaphore);
    } onEnd:nil];

    long result = dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))
    );
    if (result != 0) {
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeTimedOut,
                @"Timed out while starting USB device discovery"
            );
        }
        return NO;
    }
    if (startError) {
        if (error) {
            ASTUSBMuxTransportErrorCode code =
                [startError.domain isEqualToString:ASTUSBHubErrorDomain] &&
                startError.code == ASTUSBHubErrorTimedOut
                    ? ASTUSBMuxTransportErrorCodeTimedOut
                    : ASTUSBMuxTransportErrorCodeListenerFailed;
            *error = ASTUSBMuxError(
                code,
                startError.localizedDescription
            );
        }
        return NO;
    }
    @synchronized (self) {
        self.started = YES;
    }
    return YES;
}

- (NSArray<ASTUSBMuxDevice *> *)connectedDevices {
    @synchronized (self.devicesByIdentifier) {
        return [self.devicesByIdentifier.allValues sortedArrayUsingComparator:^NSComparisonResult(
            ASTUSBMuxDevice *left,
            ASTUSBMuxDevice *right
        ) {
            return [left.deviceIdentifier compare:right.deviceIdentifier];
        }];
    }
}

- (void)installObservers {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    __weak typeof(self) weakSelf = self;
    self.attachObserver = [center addObserverForName:ASTUSBDeviceDidAttachNotification
                                              object:self.hub
                                               queue:nil
                                          usingBlock:^(NSNotification *notification) {
        NSNumber *deviceID = notification.userInfo[@"DeviceID"];
        if (!deviceID) {
            NSLog(@"Failed: USB device attachment notification is missing DeviceID");
            return;
        }
        ASTUSBMuxHubCoordinator *strongSelf = weakSelf;
        if (!strongSelf) {
            NSLog(@"Failed: ASTUSBMuxHubCoordinator has been released");
            return;
        }
        NSDictionary *properties = notification.userInfo[@"Properties"];
        NSString *serialNumber = properties[@"SerialNumber"];
        ASTUSBMuxDevice *device = [[ASTUSBMuxDevice alloc]
            initWithDeviceIdentifier:deviceID.stringValue
            serialNumber:serialNumber];
        @synchronized (strongSelf.devicesByIdentifier) {
            strongSelf.devicesByIdentifier[device.deviceIdentifier] = device;
        }
    }];
    self.detachObserver = [center addObserverForName:ASTUSBDeviceDidDetachNotification
                                              object:self.hub
                                               queue:nil
                                          usingBlock:^(NSNotification *notification) {
        NSNumber *deviceID = notification.userInfo[@"DeviceID"];
        if (!deviceID) {
            NSLog(@"Failed: USB device detachment notification is missing DeviceID");
            return;
        }
        ASTUSBMuxHubCoordinator *strongSelf = weakSelf;
        if (!strongSelf) {
            NSLog(@"Failed: ASTUSBMuxHubCoordinator has been released");
            return;
        }
        @synchronized (strongSelf.devicesByIdentifier) {
            [strongSelf.devicesByIdentifier removeObjectForKey:deviceID.stringValue];
        }
    }];
}

@end

@implementation ASTUSBMuxDevice

- (instancetype)initWithDeviceIdentifier:(NSString *)deviceIdentifier
                             serialNumber:(NSString *)serialNumber {
    if (deviceIdentifier.length == 0) {
        return nil;
    }
    self = [super init];
    if (!self) {
        NSLog(@"Failed: ASTUSBMuxDevice initialization failed");
        return nil;
    }
    _deviceIdentifier = [deviceIdentifier copy];
    _serialNumber = [serialNumber copy];
    return self;
}

@end

@implementation ASTUSBMuxDeviceDiscovery

- (NSArray<ASTUSBMuxDevice *> *)connectedDevicesWithTimeout:(NSTimeInterval)timeout
                                                       error:(NSError **)error {
    ASTUSBMuxHubCoordinator *coordinator = ASTUSBMuxHubCoordinator.sharedCoordinator;
    if (![coordinator startWithTimeout:timeout error:error]) {
        return nil;
    }
    usleep(250000);
    return coordinator.connectedDevices;
}

@end

@interface ASTUSBMuxConnection ()

@property(nonatomic, copy) NSString *deviceIdentifier;
@property(nonatomic, assign) uint16_t port;
@property(nonatomic, strong) dispatch_queue_t ioQueue;
@property(nonatomic, strong, nullable) dispatch_io_t channel;

@end

@implementation ASTUSBMuxConnection

- (instancetype)initWithDeviceIdentifier:(NSString *)deviceIdentifier
                                     port:(uint16_t)port {
    if (deviceIdentifier.length == 0 || port == 0) {
        return nil;
    }
    self = [super init];
    if (!self) {
        NSLog(@"Failed: ASTUSBMuxConnection initialization failed");
        return nil;
    }
    _deviceIdentifier = [deviceIdentifier copy];
    _port = port;
    _ioQueue = dispatch_queue_create("com.astrolabe.usbmux.io", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error {
    if (self.channel) {
        return YES;
    }
    if (timeout <= 0) {
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeInvalidArgument,
                @"USB connection timeout must be greater than zero"
            );
        }
        return NO;
    }
    ASTUSBMuxHubCoordinator *coordinator = ASTUSBMuxHubCoordinator.sharedCoordinator;
    if (![coordinator startWithTimeout:timeout error:error]) {
        return NO;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *connectionError;
    __block dispatch_io_t connectedChannel;
    NSNumber *deviceID = @([self.deviceIdentifier integerValue]);
    [coordinator.hub connectToDevice:deviceID
                               port:self.port
                            timeout:timeout
                            onStart:^(NSError *startError, dispatch_io_t channel) {
        connectionError = startError;
        connectedChannel = channel;
        dispatch_semaphore_signal(semaphore);
    } onEnd:nil];

    long result = dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))
    );
    if (result != 0) {
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeTimedOut,
                @"Timed out while connecting to the USB Runtime"
            );
        }
        return NO;
    }
    if (connectionError || !connectedChannel) {
        if (error) {
            ASTUSBMuxTransportErrorCode code =
                [connectionError.domain isEqualToString:ASTUSBHubErrorDomain] &&
                connectionError.code == ASTUSBHubErrorTimedOut
                    ? ASTUSBMuxTransportErrorCodeTimedOut
                    : ASTUSBMuxTransportErrorCodeConnectionFailed;
            *error = ASTUSBMuxError(
                code,
                connectionError.localizedDescription ?: @"Unable to connect to the USB Runtime"
            );
        }
        return NO;
    }
    self.channel = connectedChannel;
    return YES;
}

- (BOOL)sendData:(NSData *)data
         timeout:(NSTimeInterval)timeout
           error:(NSError **)error {
    if (timeout <= 0) {
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeInvalidArgument,
                @"USB write timeout must be greater than zero"
            );
        }
        return NO;
    }
    dispatch_io_t channel = self.channel;
    if (!channel) {
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeConnectionClosed,
                @"USB Runtime connection is closed"
            );
        }
        return NO;
    }
    if (data.length == 0) {
        return YES;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block int writeError = 0;
    dispatch_data_t dispatchData = dispatch_data_create(
        data.bytes,
        data.length,
        self.ioQueue,
        ^{ (void)data; }
    );
    dispatch_io_write(channel, 0, dispatchData, self.ioQueue, ^(bool done, dispatch_data_t remainingData, int ioError) {
        if (!done) {
            return;
        }
        writeError = ioError;
        dispatch_semaphore_signal(semaphore);
    });
    long result = dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))
    );
    if (result != 0) {
        [self close];
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeTimedOut,
                @"Timed out while writing to the USB Runtime"
            );
        }
        return NO;
    }
    if (writeError != 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:writeError userInfo:nil];
        }
        return NO;
    }
    return YES;
}

- (NSData *)receiveDataOfLength:(NSUInteger)length
                        timeout:(NSTimeInterval)timeout
                          error:(NSError **)error {
    if (timeout <= 0) {
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeInvalidArgument,
                @"USB read timeout must be greater than zero"
            );
        }
        return nil;
    }
    dispatch_io_t channel = self.channel;
    if (!channel) {
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeConnectionClosed,
                @"USB Runtime connection is closed"
            );
        }
        return nil;
    }
    if (length == 0) {
        return NSData.data;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSMutableData *receivedData = [NSMutableData dataWithCapacity:length];
    __block int readError = 0;
    dispatch_io_read(channel, 0, length, self.ioQueue, ^(bool done, dispatch_data_t data, int ioError) {
        if (data) {
            dispatch_data_apply(data, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                [receivedData appendBytes:buffer length:size];
                return true;
            });
        }
        if (!done) {
            return;
        }
        readError = ioError;
        dispatch_semaphore_signal(semaphore);
    });
    long result = dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))
    );
    if (result != 0) {
        [self close];
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeTimedOut,
                @"Timed out while reading from the USB Runtime"
            );
        }
        return nil;
    }
    if (readError != 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:readError userInfo:nil];
        }
        return nil;
    }
    if (receivedData.length != length) {
        if (error) {
            *error = ASTUSBMuxError(
                ASTUSBMuxTransportErrorCodeConnectionClosed,
                @"USB Runtime closed the connection before the complete response was read"
            );
        }
        return nil;
    }
    return receivedData.copy;
}

- (void)close {
    dispatch_io_t channel = self.channel;
    self.channel = nil;
    if (channel) {
        dispatch_io_close(channel, DISPATCH_IO_STOP);
    }
}

- (void)dealloc {
    [self close];
}

@end

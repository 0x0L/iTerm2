//
//  iTermLoggingHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/4/19.
//

#import "iTermLoggingHelper.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermNotificationController.h"

@interface iTermLoggingHelper()
@property (nullable, nonatomic, strong) NSFileHandle *fileHandle;
@end

@implementation iTermLoggingHelper {
    // File handle can only be accessed on this queue.
    dispatch_queue_t _queue;
}

- (instancetype)initWithRawLogger:(id<iTermLogging>)rawLogger
                      plainLogger:(id<iTermLogging>)plainLogger {
    self = [super init];
    if (self) {
        _path = nil;
        _enabled = NO;
        _plainText = NO;
        _rawLogger = rawLogger;
        _plainLogger = plainLogger;
        _appending = [iTermAdvancedSettingsModel autologAppends];
        _queue = dispatch_queue_create("com.iterm2.logging", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)setPath:(NSString *)path enabled:(BOOL)enabled plainText:(BOOL)plainText append:(NSNumber *)append {
    const BOOL wasLoggingRaw = self.isLoggingRaw;
    const BOOL wasLoggingPlainText = self.isLoggingPlainText;

    _path = [path copy];
    _enabled = path != nil && enabled;
    _plainText = plainText;
    _appending = append ? append.boolValue : [iTermAdvancedSettingsModel autologAppends];

    if (wasLoggingRaw && !self.isLoggingRaw) {
        [_rawLogger loggingHelperStop:self];
        [self close];
    }
    if (wasLoggingPlainText && !self.isLoggingPlainText) {
        [_plainLogger loggingHelperStop:self];
        [self close];
    }
    if (!wasLoggingRaw && self.isLoggingRaw) {
        [self start];
        [_rawLogger loggingHelperStart:self];
    }
    if (!wasLoggingPlainText && self.isLoggingPlainText) {
        [self start];
        [_plainLogger loggingHelperStart:self];
    }
}

- (void)stop {
    if (self.isLoggingRaw) {
        [_rawLogger loggingHelperStop:self];
    }
    if (self.isLoggingPlainText) {
        [_plainLogger loggingHelperStop:self];
    }
    [self close];
    _enabled = NO;
}

- (void)close {
    dispatch_async(_queue, ^{
        [self.fileHandle closeFile];
        self.fileHandle = nil;
    });
}

- (void)start {
    dispatch_async(_queue, ^{
        [self.fileHandle closeFile];
        self.fileHandle = nil;
        self.fileHandle = [self newFileHandle];
        if (!self.fileHandle) {
            self->_enabled = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[iTermNotificationController sharedInstance] notify:[NSString stringWithFormat:@"Couldn’t log to %@", self.path]];
            });
        }
    });
}

- (BOOL)isLoggingRaw {
    return _enabled && !_plainText;
}

- (BOOL)isLoggingPlainText {
    return _enabled && _plainText;
}

- (NSFileHandle *)newFileHandle {
    NSString *path = [_path stringByStandardizingPath];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager createFileAtPath:path contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (_appending) {
        [handle seekToEndOfFile];
    } else {
        [handle truncateFileAtOffset:0];
    }
    return handle;
}

- (void)logData:(NSData *)data {
    dispatch_async(_queue, ^{
        NSFileHandle *fileHandle = self.fileHandle;
        @try {
            [fileHandle writeData:data];
        } @catch (NSException *exception) {
            DLog(@"Exception while logging %@ bytes of data: %@", @(data.length), exception);
            [self.fileHandle closeFile];
            self.fileHandle = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_enabled = NO;
            });
        }
    });
}

@end

/**
 * Name: TechSupport
 * Type: iOS framework
 * Desc: iOS framework to assist in providing support for and receiving issue
 *       reports and feedback from users.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: LGPL v3 (See LICENSE file for details)
 */

#import "TSIncludeInstruction.h"

@interface TSInstruction (Private)
@property(nonatomic, copy) NSString *title;
@end

@implementation TSIncludeInstruction

@synthesize content = content_;
@synthesize filepath = filepath_;
@synthesize type = type_;

// NOTE: Format is:
//
//       include [as <title>] file <filename>
//       include [as <title>] command <command>
//       include [as <title>] plist <filename>
//
- (instancetype)initWithTokens:(NSArray *)tokens {
    self = [super initWithTokens:tokens];
    if (self != nil) {
        NSString *title = nil;

        enum {
            ModeAttribute,
            ModeFilepath,
            ModeTitle
        } mode = ModeAttribute;

        NSUInteger count = [tokens count];
        NSUInteger index;
        for (index = 0; index < count; ++index) {
            NSString *token = [tokens objectAtIndex:index];
            switch (mode) {
                case ModeAttribute:
                    if ([token isEqualToString:@"as"]) {
                        mode = ModeTitle;
                    } else if ([token isEqualToString:@"file"]) {
                        type_ = TSIncludeInstructionTypeFile;
                        mode = ModeFilepath;
                    } else if ([token isEqualToString:@"command"]) {
                        type_ = TSIncludeInstructionTypeCommand;
                        mode = ModeFilepath;
                    } else if ([token isEqualToString:@"plist"]) {
                        type_ = TSIncludeInstructionTypePlist;
                        mode = ModeFilepath;
                    }
                    break;
                case ModeTitle:
                    title = stripQuotes(token);
                    mode = ModeAttribute;
                    break;
                case ModeFilepath:
                    goto loop_exit;
                default:
                    break;
            }
        }

loop_exit:
        filepath_ = [stripQuotes([[tokens subarrayWithRange:NSMakeRange(index, (count - index))] componentsJoinedByString:@" "]) retain];
        [self setTitle:(title ?: filepath_)];
    }
    return self;
}

- (void)dealloc {
    [content_ release];
    [filepath_ release];
    [super dealloc];
}

- (UITableViewCell *)format:(UITableViewCell *)cell {
    cell = [super format:cell];
    cell.detailTextLabel.text = filepath_;
    return cell;
}

- (NSData *)content {
    if (content_ == nil) {
        NSString *filepath = [self filepath];
        if (type_ == TSIncludeInstructionTypeFile) {
            // Return contents of file.
            NSError *error = nil;
            content_ = [[NSData alloc] initWithContentsOfFile:filepath options:0 error:&error];
            if (content_ == nil) {
                fprintf(stderr, "ERROR: Unable to load contents of file \"%s\": \"%s\".\n",
                        [filepath UTF8String], [[error localizedDescription] UTF8String]);
            }
        } else if (type_ == TSIncludeInstructionTypePlist) {
            // Return contents of property list, converted to a legible format.
            NSError *error = nil;
            NSData *data = [[NSData alloc] initWithContentsOfFile:filepath options:0 error:&error];
            if (data != nil) {
                id plist = nil;
                if ([NSPropertyListSerialization respondsToSelector:@selector(propertyListWithData:options:format:error:)]) {
                    plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
                } else {
                    plist = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:0 format:NULL errorDescription:NULL];
                }
                content_ = [[[plist description] dataUsingEncoding:NSUTF8StringEncoding] retain];
            } else {
                fprintf(stderr, "ERROR: Unable to load data from \"%s\": \"%s\".\n",
                        [filepath UTF8String], [[error localizedDescription] UTF8String]);
            }
        } else {
            // Return the output of a command.
            fflush(stdout);
            FILE *f = popen([filepath UTF8String], "r");
            if (f == NULL) {
                return nil;
            }

            NSMutableString *string = [NSMutableString new];
            while (!feof(f)) {
                char buf[1024];
                size_t charsRead = fread(buf, 1, sizeof(buf), f);
                [string appendFormat:@"%.*s", (int)charsRead, buf];
            }
            pclose(f);

            // Treat output as a filename to be loaded and contents returned.
            // NOTE: We do not retrieve the error as failure is not unexpected.
            NSString *path = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSData *data = [[NSData alloc] initWithContentsOfFile:path options:0 error:nil];
            if (data != nil) {
                content_ = data;
            } else {
                // No such file or file could not be read; treat output itself as content.
                content_ = [[string dataUsingEncoding:NSUTF8StringEncoding] retain];
            }
            [string release];
        }
    }
    return content_;
}

@end

/* vim: set ft=objc ff=unix sw=4 ts=4 tw=80 expandtab: */

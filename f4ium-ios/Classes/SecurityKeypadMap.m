//
//  SecurityKeypadMap.m
//  f4ium-ios
//
//  Created by Mobile_KFTC on 2017. 9. 28..
//  Copyright © 2017년 모바일개발팀. All rights reserved.
//

#import "SecurityKeypadMap.h"

@implementation SecurityKeypadMap
@synthesize keyMap;

+ (id)sharedSecurityKeyMap {
    static SecurityKeypadMap *sharedKeyMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedKeyMap = [self new];
    });
    return sharedKeyMap;
}

- (id)init {
    if (self = [super init]) {
        keyMap = [[NSDictionary alloc] initWithObjectsAndKeys:
                  @"q   ,   비읍", @"q", @"w   ,   지읃", @"w", @"e   ,   디귿", @"e", @"r   ,   기역", @"r",
                  @"t   ,   시옫", @"t", @"y   ,   요", @"y", @"u   ,   여", @"u", @"i   ,   야", @"i",
                  @"o   ,   애", @"o", @"p   ,   에", @"p", @"a   ,   미음", @"a", @"s   ,   니은", @"s",
                  @"d   ,   이응", @"d", @"f   ,   리을", @"f", @"g   ,   히읃", @"g", @"h   ,   오", @"h",
                  @"j   ,   어", @"j", @"k   ,   아", @"k", @"l   ,   이", @"l", @"z   ,   키윽", @"z",
                  @"x   ,   티읃", @"x", @"c   ,   치읃", @"c", @"v   ,   피읍", @"v", @"b   ,   유", @"b",
                  @"n   ,   우", @"n", @"m   ,   으", @"m",
                  @"capital Q   ,   쌍비읍", @"Q", @"capital W   ,   쌍지읃", @"W", @"capital E   ,   쌍디귿", @"E", @"capital R   ,   쌍기역", @"R",
                  @"capital T   ,   쌍시옫", @"T", @"capital Y   ,   요", @"Y", @"capital U   ,   여", @"U", @"capital I   ,   야", @"I",
                  @"capital O   ,   애", @"O", @"capital P   ,   에", @"P", @"capital A   ,   미음", @"A", @"capital S   ,   니은", @"S",
                  @"capital D   ,   이응", @"D", @"capital F   ,   리을", @"F", @"capital G   ,   히읃", @"G", @"capital H   ,   오", @"H",
                  @"capital J   ,   어", @"J", @"capital K   ,   아", @"K", @"capital L   ,   이", @"L", @"capital Z   ,   키윽", @"Z",
                  @"capital X   ,   티읃", @"X", @"capital C   ,   치읃", @"C", @"capital V   ,   피읍", @"V", @"capital B   ,   유", @"B",
                  @"capital N   ,   우", @"N", @"capital M   ,   으", @"M",
                  @"1", @"1", @"2", @"2", @"3", @"3", @"4", @"4", @"5", @"5", @"6", @"6", @"7", @"7", @"8", @"8", @"9", @"9", @"0", @"0",
                  @"!", @"!", @"@", @"@", @"#", @"#", @"$", @"$", @"%", @"%", @"^", @"^", @"&", @"&", @"*", @"*", @"(", @"(", @")", @")",
                  @"`", @"`", @"-", @"-", @"=", @"=" @"\\", @"\\", @"[", @"[", @"]", @"]", @";", @";", @"'", @"'", @",", @",", @".", @".",
                  @"/", @"/", @"~", @"~", @"_", @"_", @"+", @"+", @"|", @"|", @"{", @"{", @"}", @"}", @":", @":", @"\"", @"\"", @"<", @"<",
                  @">", @">", @"?", @"?",
                  @"공백", @" ",
                  nil];
    }
    return self;
}

- (NSString *)retrieveID:(NSString *)key {
    return [keyMap objectForKey:key];
}

@end

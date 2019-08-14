//
//  ANSIEscapeHelper.m
//
//  Created by Ali Rantakari on 18.3.09.

/*
The MIT License

Copyright (c) 2008-2009,2013 Ali Rantakari

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

/*
 todo:

 - don't add useless "reset" escape codes to the string in
   -ansiEscapedStringWithAttributedString:

 */



#import "AMR_ANSIEscapeHelper.h"


// the CSI (Control Sequence Initiator) -- i.e. "escape sequence prefix".
// (add your own CSI:Miami joke here)
#define kANSIEscapeCSI          @"\033["

// the end byte of an SGR (Select Graphic Rendition)
// ANSI Escape Sequence
#define kANSIEscapeSGREnd       @"m"


// color definition helper macros
#define kBrightColorBrightness  1.0
#define kBrightColorSaturation  0.4
#define kBrightColorAlpha       1.0
#define kBrightColorWithHue(h)  [NSColor colorWithCalibratedHue:(h) saturation:kBrightColorSaturation brightness:kBrightColorBrightness alpha:kBrightColorAlpha]

// default colors
#define kDefaultANSIColorFgBlack    NSColor.blackColor
#define kDefaultANSIColorFgRed      NSColor.redColor
#define kDefaultANSIColorFgGreen    NSColor.greenColor
#define kDefaultANSIColorFgYellow   NSColor.yellowColor
#define kDefaultANSIColorFgBlue     NSColor.blueColor
#define kDefaultANSIColorFgMagenta  NSColor.magentaColor
#define kDefaultANSIColorFgCyan     NSColor.cyanColor
#define kDefaultANSIColorFgWhite    NSColor.whiteColor

#define kDefaultANSIColorFgBrightBlack      [NSColor colorWithCalibratedWhite:0.337 alpha:1.0]
#define kDefaultANSIColorFgBrightRed        kBrightColorWithHue(1.0)
#define kDefaultANSIColorFgBrightGreen      kBrightColorWithHue(1.0/3.0)
#define kDefaultANSIColorFgBrightYellow     kBrightColorWithHue(1.0/6.0)
#define kDefaultANSIColorFgBrightBlue       kBrightColorWithHue(2.0/3.0)
#define kDefaultANSIColorFgBrightMagenta    kBrightColorWithHue(5.0/6.0)
#define kDefaultANSIColorFgBrightCyan       kBrightColorWithHue(0.5)
#define kDefaultANSIColorFgBrightWhite      NSColor.whiteColor

#define kDefaultANSIColorBgBlack    NSColor.blackColor
#define kDefaultANSIColorBgRed      NSColor.redColor
#define kDefaultANSIColorBgGreen    NSColor.greenColor
#define kDefaultANSIColorBgYellow   NSColor.yellowColor
#define kDefaultANSIColorBgBlue     NSColor.blueColor
#define kDefaultANSIColorBgMagenta  NSColor.magentaColor
#define kDefaultANSIColorBgCyan     NSColor.cyanColor
#define kDefaultANSIColorBgWhite    NSColor.whiteColor

#define kDefaultANSIColorBgBrightBlack      kDefaultANSIColorFgBrightBlack
#define kDefaultANSIColorBgBrightRed        kDefaultANSIColorFgBrightRed
#define kDefaultANSIColorBgBrightGreen      kDefaultANSIColorFgBrightGreen
#define kDefaultANSIColorBgBrightYellow     kDefaultANSIColorFgBrightYellow
#define kDefaultANSIColorBgBrightBlue       kDefaultANSIColorFgBrightBlue
#define kDefaultANSIColorBgBrightMagenta    kDefaultANSIColorFgBrightMagenta
#define kDefaultANSIColorBgBrightCyan       kDefaultANSIColorFgBrightCyan
#define kDefaultANSIColorBgBrightWhite      kDefaultANSIColorFgBrightWhite

#define kDefaultFontSize [NSFont systemFontOfSize:NSFont.systemFontSize]
#define kDefaultForegroundColor NSColor.blackColor

// minimum weight for an NSFont for it to be considered bold
#define kBoldFontMinWeight          9


@implementation AMR_ANSIEscapeHelper

- (id) init
{
    if (!(self = [super init]))
        return nil;

    self.ansiColors = [NSMutableDictionary dictionary];

    return self;
}



- (NSAttributedString*) attributedStringWithANSIEscapedString:(NSString*)aString
{
    if (aString == nil)
        return nil;

    NSString *cleanString;
    NSArray *attributesAndRanges = [self attributesForString:aString cleanString:&cleanString];
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc]
                                                   initWithString:cleanString
                                                   attributes:@{
                                                   NSFontAttributeName: self.font ?: kDefaultFontSize,
                                                   NSForegroundColorAttributeName: self.defaultStringColor ?: kDefaultForegroundColor
                                                   }];

    for (NSDictionary *thisAttributeDict in attributesAndRanges)
    {
        [attributedString
         addAttribute:thisAttributeDict[kAMRAttrDictKey_attrName]
         value:thisAttributeDict[kAMRAttrDictKey_attrValue]
         range:[thisAttributeDict[kAMRAttrDictKey_range] rangeValue]
         ];
    }

    return attributedString;
}



- (NSString*) ansiEscapedStringWithAttributedString:(NSAttributedString*)aAttributedString
{
    NSMutableArray *codesAndLocations = [NSMutableArray array];

    NSArray *attrNames = @[
                          NSFontAttributeName, NSForegroundColorAttributeName,
                          NSBackgroundColorAttributeName, NSUnderlineStyleAttributeName,
                          ];

    for (NSString *thisAttrName in attrNames)
    {
        NSRange limitRange = NSMakeRange(0, aAttributedString.length);
        id attributeValue;
        NSRange effectiveRange;

        while (limitRange.length > 0)
        {
            attributeValue = [aAttributedString
                              attribute:thisAttrName
                              atIndex:limitRange.location
                              longestEffectiveRange:&effectiveRange
                              inRange:limitRange
                              ];

            AMR_SGRCode thisSGRCode = AMR_SGRCodeNoneOrInvalid;

            if ([thisAttrName isEqualToString:NSForegroundColorAttributeName])
            {
                if (attributeValue != nil)
                    thisSGRCode = [self closestSGRCodeForColor:attributeValue isForegroundColor:YES];
                else
                    thisSGRCode = AMR_SGRCodeFgReset;
            }
            else if ([thisAttrName isEqualToString:NSBackgroundColorAttributeName])
            {
                if (attributeValue != nil)
                    thisSGRCode = [self closestSGRCodeForColor:attributeValue isForegroundColor:NO];
                else
                    thisSGRCode = AMR_SGRCodeBgReset;
            }
            else if ([thisAttrName isEqualToString:NSFontAttributeName])
            {
                // we currently only use NSFontAttributeName for bolding so
                // here we assume that the formatting "type" in ANSI SGR
                // terms is indeed intensity
                if (attributeValue != nil)
                    thisSGRCode = ([NSFontManager.sharedFontManager weightOfFont:attributeValue] >= kBoldFontMinWeight)
                                    ? AMR_SGRCodeIntensityBold : AMR_SGRCodeIntensityNormal;
                else
                    thisSGRCode = AMR_SGRCodeIntensityNormal;
            }
            else if ([thisAttrName isEqualToString:NSUnderlineStyleAttributeName])
            {
                if (attributeValue != nil)
                {
                    if ([attributeValue intValue] == NSUnderlineStyleSingle)
                        thisSGRCode = AMR_SGRCodeUnderlineSingle;
                    else if ([attributeValue intValue] == NSUnderlineStyleDouble)
                        thisSGRCode = AMR_SGRCodeUnderlineDouble;
                    else
                        thisSGRCode = AMR_SGRCodeUnderlineNone;
                }
                else
                    thisSGRCode = AMR_SGRCodeUnderlineNone;
            }

            if (thisSGRCode != AMR_SGRCodeNoneOrInvalid)
            {
                [codesAndLocations addObject: @{
                           kAMRCodeDictKey_code: @(thisSGRCode),
                       kAMRCodeDictKey_location: @(effectiveRange.location),
                 }];
            }

            limitRange = NSMakeRange(NSMaxRange(effectiveRange),
                                     NSMaxRange(limitRange) - NSMaxRange(effectiveRange));
        }
    }

    return [self ansiEscapedStringWithCodesAndLocations:codesAndLocations cleanString:aAttributedString.string];
}


- (NSArray*) escapeCodesForString:(NSString*)aString cleanString:(NSString**)aCleanString
{
    if (aString == nil)
        return nil;
    if (aString.length <= kANSIEscapeCSI.length)
    {
        if (aCleanString)
            *aCleanString = aString.copy;
        return @[];
    }

    NSString *cleanString = @"";

    // find all escape sequence codes from aString and put them in this array
    // along with their start locations within the "clean" version of aString
    NSMutableArray *formatCodes = [NSMutableArray array];

    NSUInteger aStringLength = aString.length;
    NSUInteger coveredLength = 0;
    NSRange searchRange = NSMakeRange(0,aStringLength);
    NSRange thisEscapeSequenceRange;
    do
    {
        thisEscapeSequenceRange = [aString rangeOfString:kANSIEscapeCSI options:NSLiteralSearch range:searchRange];
        if (thisEscapeSequenceRange.location != NSNotFound)
        {
            // adjust range's length so that it encompasses the whole ANSI escape sequence
            // and not just the Control Sequence Initiator (the "prefix") by finding the
            // final byte of the control sequence (one that has an ASCII decimal value
            // between 64 and 126.) at the same time, read all formatting codes from inside
            // this escape sequence (there may be several, separated by semicolons.)
            NSMutableArray *codes = [NSMutableArray array];
            unsigned int code = 0;
            unsigned int lengthAddition = 1;
            NSUInteger thisIndex;
            for (;;)
            {
                thisIndex = (NSMaxRange(thisEscapeSequenceRange)+lengthAddition-1);
                if (thisIndex >= aStringLength)
                    break;

                unichar c = [aString characterAtIndex:thisIndex];

                if (('0' <= c) && (c <= '9'))
                {
                    int digit = c - '0';
                    code = (code == 0) ? digit : code*10+digit;
                }

                // ASCII decimal 109 is the SGR (Select Graphic Rendition) final byte
                // ("m"). this means that the code value we've just read specifies formatting
                // for the output; exactly what we're interested in.
                if (c == 'm')
                {
                    [codes addObject:@(code)];
                    break;
                }
                else if ((64 <= c) && (c <= 126)) // any other valid final byte
                {
                    [codes removeAllObjects];
                    break;
                }
                else if (c == ';') // separates codes within the same sequence
                {
                    [codes addObject:@(code)];
                    code = 0;
                }

                lengthAddition++;
            }
            thisEscapeSequenceRange.length += lengthAddition;

            NSUInteger locationInCleanString = coveredLength+thisEscapeSequenceRange.location-searchRange.location;

            for (NSNumber *codeToAdd in codes)
            {
                [formatCodes addObject: @{
                     kAMRCodeDictKey_code: codeToAdd,
                 kAMRCodeDictKey_location: @(locationInCleanString)
                 }];
            }

            NSUInteger thisCoveredLength = thisEscapeSequenceRange.location-searchRange.location;
            if (thisCoveredLength > 0)
                cleanString = [cleanString stringByAppendingString:[aString substringWithRange:NSMakeRange(searchRange.location, thisCoveredLength)]];

            coveredLength += thisCoveredLength;
            searchRange.location = NSMaxRange(thisEscapeSequenceRange);
            searchRange.length = aStringLength-searchRange.location;
        }
    }
    while(thisEscapeSequenceRange.location != NSNotFound);

    if (searchRange.length > 0)
        cleanString = [cleanString stringByAppendingString:[aString substringWithRange:searchRange]];

    if (aCleanString)
        *aCleanString = cleanString;
    return formatCodes;
}




- (NSString*) ansiEscapedStringWithCodesAndLocations:(NSArray*)aCodesArray cleanString:(NSString*)aCleanString
{
    NSMutableString* retStr = [NSMutableString stringWithCapacity:aCleanString.length];

    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:kAMRCodeDictKey_location ascending:YES];
    NSArray *codesArray = [aCodesArray sortedArrayUsingDescriptors:@[sortDescriptor]];

    NSUInteger aCleanStringIndex = 0;
    NSUInteger aCleanStringLength = aCleanString.length;
    for (NSDictionary *thisCodeDict in codesArray)
    {
        if (!(  thisCodeDict[kAMRCodeDictKey_code] &&
                thisCodeDict[kAMRCodeDictKey_location]
            ))
            continue;

        AMR_SGRCode thisCode = [thisCodeDict[kAMRCodeDictKey_code] unsignedIntValue];
        NSUInteger formattingRunStartLocation = [thisCodeDict[kAMRCodeDictKey_location] unsignedIntegerValue];

        if (formattingRunStartLocation > aCleanStringLength)
            continue;

        if (aCleanStringIndex < formattingRunStartLocation)
            [retStr appendString:[aCleanString substringWithRange:NSMakeRange(aCleanStringIndex, formattingRunStartLocation-aCleanStringIndex)]];
        [retStr appendFormat:@"%@%d%@", kANSIEscapeCSI, thisCode, kANSIEscapeSGREnd];

        aCleanStringIndex = formattingRunStartLocation;
    }

    if (aCleanStringIndex < aCleanStringLength)
        [retStr appendString:[aCleanString substringFromIndex:aCleanStringIndex]];

    [retStr appendFormat:@"%@%d%@", kANSIEscapeCSI, AMR_SGRCodeAllReset, kANSIEscapeSGREnd];

    return retStr;
}





- (NSArray*) attributesForString:(NSString*)aString cleanString:(NSString**)aCleanString
{
    if (aString == nil)
        return nil;
    if (aString.length <= kANSIEscapeCSI.length)
    {
        if (aCleanString)
            *aCleanString = aString.copy;
        return @[];
    }

    NSMutableArray *attrsAndRanges = [NSMutableArray array];

    NSString *cleanString;
    NSArray *formatCodes = [self escapeCodesForString:aString cleanString:&cleanString];

    // go through all the found escape sequence codes and for each one, create
    // the string formatting attribute name and value, find the next escape
    // sequence that specifies the end of the formatting run started by
    // the currently handled code, and generate a range from the difference
    // in those codes' locations within the clean aString.
    for (NSUInteger iCode = 0; iCode < formatCodes.count; iCode++)
    {
        NSDictionary *thisCodeDict = formatCodes[iCode];
        AMR_SGRCode thisCode = [thisCodeDict[kAMRCodeDictKey_code] unsignedIntValue];
        NSUInteger formattingRunStartLocation = [thisCodeDict[kAMRCodeDictKey_location] unsignedIntegerValue];

        // the attributed string attribute name for the formatting run introduced
        // by this code
        NSString *thisAttributeName = nil;

        // the attributed string attribute value for this formatting run introduced
        // by this code
        NSObject *thisAttributeValue = nil;

        // set attribute name
        switch(thisCode)
        {
            case AMR_SGRCodeFgBlack:
            case AMR_SGRCodeFgRed:
            case AMR_SGRCodeFgGreen:
            case AMR_SGRCodeFgYellow:
            case AMR_SGRCodeFgBlue:
            case AMR_SGRCodeFgMagenta:
            case AMR_SGRCodeFgCyan:
            case AMR_SGRCodeFgWhite:
            case AMR_SGRCodeFgBrightBlack:
            case AMR_SGRCodeFgBrightRed:
            case AMR_SGRCodeFgBrightGreen:
            case AMR_SGRCodeFgBrightYellow:
            case AMR_SGRCodeFgBrightBlue:
            case AMR_SGRCodeFgBrightMagenta:
            case AMR_SGRCodeFgBrightCyan:
            case AMR_SGRCodeFgBrightWhite:
                thisAttributeName = NSForegroundColorAttributeName;
                break;
            case AMR_SGRCodeBgBlack:
            case AMR_SGRCodeBgRed:
            case AMR_SGRCodeBgGreen:
            case AMR_SGRCodeBgYellow:
            case AMR_SGRCodeBgBlue:
            case AMR_SGRCodeBgMagenta:
            case AMR_SGRCodeBgCyan:
            case AMR_SGRCodeBgWhite:
            case AMR_SGRCodeBgBrightBlack:
            case AMR_SGRCodeBgBrightRed:
            case AMR_SGRCodeBgBrightGreen:
            case AMR_SGRCodeBgBrightYellow:
            case AMR_SGRCodeBgBrightBlue:
            case AMR_SGRCodeBgBrightMagenta:
            case AMR_SGRCodeBgBrightCyan:
            case AMR_SGRCodeBgBrightWhite:
                thisAttributeName = NSBackgroundColorAttributeName;
                break;
            case AMR_SGRCodeIntensityBold:
            case AMR_SGRCodeIntensityNormal:
            case AMR_SGRCodeIntensityFaint:
                thisAttributeName = NSFontAttributeName;
                break;
            case AMR_SGRCodeUnderlineSingle:
            case AMR_SGRCodeUnderlineDouble:
            case AMR_SGRCodeUnderlineNone:
                thisAttributeName = NSUnderlineStyleAttributeName;
                break;
            case AMR_SGRCodeAllReset:
            case AMR_SGRCodeFgReset:
            case AMR_SGRCodeBgReset:
            case AMR_SGRCodeNoneOrInvalid:
            case AMR_SGRCodeItalicOn:
                continue;
        }

        // set attribute value
        switch(thisCode)
        {
            case AMR_SGRCodeBgBlack:
            case AMR_SGRCodeFgBlack:
            case AMR_SGRCodeBgRed:
            case AMR_SGRCodeFgRed:
            case AMR_SGRCodeBgGreen:
            case AMR_SGRCodeFgGreen:
            case AMR_SGRCodeBgYellow:
            case AMR_SGRCodeFgYellow:
            case AMR_SGRCodeBgBlue:
            case AMR_SGRCodeFgBlue:
            case AMR_SGRCodeBgMagenta:
            case AMR_SGRCodeFgMagenta:
            case AMR_SGRCodeBgCyan:
            case AMR_SGRCodeFgCyan:
            case AMR_SGRCodeBgWhite:
            case AMR_SGRCodeFgWhite:
            case AMR_SGRCodeBgBrightBlack:
            case AMR_SGRCodeFgBrightBlack:
            case AMR_SGRCodeBgBrightRed:
            case AMR_SGRCodeFgBrightRed:
            case AMR_SGRCodeBgBrightGreen:
            case AMR_SGRCodeFgBrightGreen:
            case AMR_SGRCodeBgBrightYellow:
            case AMR_SGRCodeFgBrightYellow:
            case AMR_SGRCodeBgBrightBlue:
            case AMR_SGRCodeFgBrightBlue:
            case AMR_SGRCodeBgBrightMagenta:
            case AMR_SGRCodeFgBrightMagenta:
            case AMR_SGRCodeBgBrightCyan:
            case AMR_SGRCodeFgBrightCyan:
            case AMR_SGRCodeBgBrightWhite:
            case AMR_SGRCodeFgBrightWhite:
                thisAttributeValue = [self colorForSGRCode:thisCode];
                break;
            case AMR_SGRCodeIntensityBold:
                {
                NSFont *boldFont = [NSFontManager.sharedFontManager convertFont:self.font toHaveTrait:NSBoldFontMask];
                thisAttributeValue = boldFont;
                }
                break;
            case AMR_SGRCodeIntensityNormal:
            case AMR_SGRCodeIntensityFaint:
                {
                NSFont *unboldFont = [NSFontManager.sharedFontManager convertFont:self.font toHaveTrait:NSUnboldFontMask];
                thisAttributeValue = unboldFont;
                }
                break;
            case AMR_SGRCodeUnderlineSingle:
                thisAttributeValue = @(NSUnderlineStyleSingle);
                break;
            case AMR_SGRCodeUnderlineDouble:
                thisAttributeValue = @(NSUnderlineStyleDouble);
                break;
            case AMR_SGRCodeUnderlineNone:
                thisAttributeValue = @(NSUnderlineStyleNone);
                break;
            case AMR_SGRCodeAllReset:
            case AMR_SGRCodeFgReset:
            case AMR_SGRCodeBgReset:
            case AMR_SGRCodeNoneOrInvalid:
            case AMR_SGRCodeItalicOn:
                break;
        }


        // find the next sequence that specifies the end of this formatting run
        NSInteger formattingRunEndLocation = -1;
        if (iCode < (formatCodes.count - 1))
        {
            NSDictionary *thisEndCodeCandidateDict;
            unichar thisEndCodeCandidate;
            for (NSUInteger iEndCode = iCode+1; iEndCode < formatCodes.count; iEndCode++)
            {
                thisEndCodeCandidateDict = formatCodes[iEndCode];
                thisEndCodeCandidate = [thisEndCodeCandidateDict[kAMRCodeDictKey_code] unsignedIntValue];

                if ([self AMR_SGRCode:thisEndCodeCandidate endsFormattingIntroducedByCode:thisCode])
                {
                    formattingRunEndLocation = [thisEndCodeCandidateDict[kAMRCodeDictKey_location] unsignedIntegerValue];
                    break;
                }
            }
        }
        if (formattingRunEndLocation == -1)
            formattingRunEndLocation = cleanString.length;
        
        if (thisAttributeName && thisAttributeValue)
        {
            [attrsAndRanges addObject:@{
                kAMRAttrDictKey_range: [NSValue valueWithRange:NSMakeRange(formattingRunStartLocation, (formattingRunEndLocation-formattingRunStartLocation))],
             kAMRAttrDictKey_attrName: thisAttributeName,
            kAMRAttrDictKey_attrValue: thisAttributeValue,
             }];
        }
    }

    if (aCleanString)
        *aCleanString = cleanString;
    return attrsAndRanges;
}





- (BOOL) AMR_SGRCode:(AMR_SGRCode)endCode endsFormattingIntroducedByCode:(AMR_SGRCode)startCode
{
    switch(startCode)
    {
        case AMR_SGRCodeFgBlack:
        case AMR_SGRCodeFgRed:
        case AMR_SGRCodeFgGreen:
        case AMR_SGRCodeFgYellow:
        case AMR_SGRCodeFgBlue:
        case AMR_SGRCodeFgMagenta:
        case AMR_SGRCodeFgCyan:
        case AMR_SGRCodeFgWhite:
        case AMR_SGRCodeFgBrightBlack:
        case AMR_SGRCodeFgBrightRed:
        case AMR_SGRCodeFgBrightGreen:
        case AMR_SGRCodeFgBrightYellow:
        case AMR_SGRCodeFgBrightBlue:
        case AMR_SGRCodeFgBrightMagenta:
        case AMR_SGRCodeFgBrightCyan:
        case AMR_SGRCodeFgBrightWhite:
            return (endCode == AMR_SGRCodeAllReset || endCode == AMR_SGRCodeFgReset ||
                    endCode == AMR_SGRCodeFgBlack || endCode == AMR_SGRCodeFgRed ||
                    endCode == AMR_SGRCodeFgGreen || endCode == AMR_SGRCodeFgYellow ||
                    endCode == AMR_SGRCodeFgBlue || endCode == AMR_SGRCodeFgMagenta ||
                    endCode == AMR_SGRCodeFgCyan || endCode == AMR_SGRCodeFgWhite ||
                    endCode == AMR_SGRCodeFgBrightBlack || endCode == AMR_SGRCodeFgBrightRed ||
                    endCode == AMR_SGRCodeFgBrightGreen || endCode == AMR_SGRCodeFgBrightYellow ||
                    endCode == AMR_SGRCodeFgBrightBlue || endCode == AMR_SGRCodeFgBrightMagenta ||
                    endCode == AMR_SGRCodeFgBrightCyan || endCode == AMR_SGRCodeFgBrightWhite);
        case AMR_SGRCodeBgBlack:
        case AMR_SGRCodeBgRed:
        case AMR_SGRCodeBgGreen:
        case AMR_SGRCodeBgYellow:
        case AMR_SGRCodeBgBlue:
        case AMR_SGRCodeBgMagenta:
        case AMR_SGRCodeBgCyan:
        case AMR_SGRCodeBgWhite:
        case AMR_SGRCodeBgBrightBlack:
        case AMR_SGRCodeBgBrightRed:
        case AMR_SGRCodeBgBrightGreen:
        case AMR_SGRCodeBgBrightYellow:
        case AMR_SGRCodeBgBrightBlue:
        case AMR_SGRCodeBgBrightMagenta:
        case AMR_SGRCodeBgBrightCyan:
        case AMR_SGRCodeBgBrightWhite:
            return (endCode == AMR_SGRCodeAllReset || endCode == AMR_SGRCodeBgReset ||
                    endCode == AMR_SGRCodeBgBlack || endCode == AMR_SGRCodeBgRed ||
                    endCode == AMR_SGRCodeBgGreen || endCode == AMR_SGRCodeBgYellow ||
                    endCode == AMR_SGRCodeBgBlue || endCode == AMR_SGRCodeBgMagenta ||
                    endCode == AMR_SGRCodeBgCyan || endCode == AMR_SGRCodeBgWhite ||
                    endCode == AMR_SGRCodeBgBrightBlack || endCode == AMR_SGRCodeBgBrightRed ||
                    endCode == AMR_SGRCodeBgBrightGreen || endCode == AMR_SGRCodeBgBrightYellow ||
                    endCode == AMR_SGRCodeBgBrightBlue || endCode == AMR_SGRCodeBgBrightMagenta ||
                    endCode == AMR_SGRCodeBgBrightCyan || endCode == AMR_SGRCodeBgBrightWhite);
        case AMR_SGRCodeIntensityBold:
        case AMR_SGRCodeIntensityNormal:
            return (endCode == AMR_SGRCodeAllReset || endCode == AMR_SGRCodeIntensityNormal ||
                    endCode == AMR_SGRCodeIntensityBold || endCode == AMR_SGRCodeIntensityFaint);
        case AMR_SGRCodeUnderlineSingle:
        case AMR_SGRCodeUnderlineDouble:
            return (endCode == AMR_SGRCodeAllReset || endCode == AMR_SGRCodeUnderlineNone ||
                    endCode == AMR_SGRCodeUnderlineSingle || endCode == AMR_SGRCodeUnderlineDouble);
        case AMR_SGRCodeNoneOrInvalid:
        case AMR_SGRCodeItalicOn:
        case AMR_SGRCodeUnderlineNone:
        case AMR_SGRCodeIntensityFaint:
        case AMR_SGRCodeAllReset:
        case AMR_SGRCodeBgReset:
        case AMR_SGRCodeFgReset:
            return NO;
    }

    return NO;
}




- (NSColor*) colorForSGRCode:(AMR_SGRCode)code
{
    if (self.ansiColors)
    {
        NSColor *preferredColor = self.ansiColors[@(code)];
        if (preferredColor)
            return preferredColor;
    }

    switch(code)
    {
        case AMR_SGRCodeFgBlack:
            return kDefaultANSIColorFgBlack;
        case AMR_SGRCodeFgRed:
            return kDefaultANSIColorFgRed;
        case AMR_SGRCodeFgGreen:
            return kDefaultANSIColorFgGreen;
        case AMR_SGRCodeFgYellow:
            return kDefaultANSIColorFgYellow;
        case AMR_SGRCodeFgBlue:
            return kDefaultANSIColorFgBlue;
        case AMR_SGRCodeFgMagenta:
            return kDefaultANSIColorFgMagenta;
        case AMR_SGRCodeFgCyan:
            return kDefaultANSIColorFgCyan;
        case AMR_SGRCodeFgWhite:
            return kDefaultANSIColorFgWhite;
        case AMR_SGRCodeFgBrightBlack:
            return kDefaultANSIColorFgBrightBlack;
        case AMR_SGRCodeFgBrightRed:
            return kDefaultANSIColorFgBrightRed;
        case AMR_SGRCodeFgBrightGreen:
            return kDefaultANSIColorFgBrightGreen;
        case AMR_SGRCodeFgBrightYellow:
            return kDefaultANSIColorFgBrightYellow;
        case AMR_SGRCodeFgBrightBlue:
            return kDefaultANSIColorFgBrightBlue;
        case AMR_SGRCodeFgBrightMagenta:
            return kDefaultANSIColorFgBrightMagenta;
        case AMR_SGRCodeFgBrightCyan:
            return kDefaultANSIColorFgBrightCyan;
        case AMR_SGRCodeFgBrightWhite:
            return kDefaultANSIColorFgBrightWhite;
        case AMR_SGRCodeBgBlack:
            return kDefaultANSIColorBgBlack;
        case AMR_SGRCodeBgRed:
            return kDefaultANSIColorBgRed;
        case AMR_SGRCodeBgGreen:
            return kDefaultANSIColorBgGreen;
        case AMR_SGRCodeBgYellow:
            return kDefaultANSIColorBgYellow;
        case AMR_SGRCodeBgBlue:
            return kDefaultANSIColorBgBlue;
        case AMR_SGRCodeBgMagenta:
            return kDefaultANSIColorBgMagenta;
        case AMR_SGRCodeBgCyan:
            return kDefaultANSIColorBgCyan;
        case AMR_SGRCodeBgWhite:
            return kDefaultANSIColorBgWhite;
        case AMR_SGRCodeBgBrightBlack:
            return kDefaultANSIColorBgBrightBlack;
        case AMR_SGRCodeBgBrightRed:
            return kDefaultANSIColorBgBrightRed;
        case AMR_SGRCodeBgBrightGreen:
            return kDefaultANSIColorBgBrightGreen;
        case AMR_SGRCodeBgBrightYellow:
            return kDefaultANSIColorBgBrightYellow;
        case AMR_SGRCodeBgBrightBlue:
            return kDefaultANSIColorBgBrightBlue;
        case AMR_SGRCodeBgBrightMagenta:
            return kDefaultANSIColorBgBrightMagenta;
        case AMR_SGRCodeBgBrightCyan:
            return kDefaultANSIColorBgBrightCyan;
        case AMR_SGRCodeBgBrightWhite:
            return kDefaultANSIColorBgBrightWhite;
        case AMR_SGRCodeNoneOrInvalid:
        case AMR_SGRCodeItalicOn:
        case AMR_SGRCodeUnderlineNone:
        case AMR_SGRCodeIntensityFaint:
        case AMR_SGRCodeAllReset:
        case AMR_SGRCodeBgReset:
        case AMR_SGRCodeFgReset:
        case AMR_SGRCodeIntensityBold:
        case AMR_SGRCodeIntensityNormal:
        case AMR_SGRCodeUnderlineSingle:
        case AMR_SGRCodeUnderlineDouble:
            break;
    }

    return kDefaultANSIColorFgBlack;
}


- (AMR_SGRCode) AMR_SGRCodeForColor:(NSColor*)aColor isForegroundColor:(BOOL)aForeground
{
    if (self.ansiColors)
    {
        NSArray *codesForGivenColor = [self.ansiColors allKeysForObject:aColor];

        if (codesForGivenColor != nil && 0 < codesForGivenColor.count)
        {
            for (NSNumber *thisCode in codesForGivenColor)
            {
                BOOL thisIsForegroundColor = (thisCode.intValue < 40);
                if (aForeground == thisIsForegroundColor)
                    return thisCode.intValue;
            }
        }
    }

    if (aForeground)
    {
        if ([aColor isEqual:kDefaultANSIColorFgBlack])
            return AMR_SGRCodeFgBlack;
        else if ([aColor isEqual:kDefaultANSIColorFgRed])
            return AMR_SGRCodeFgRed;
        else if ([aColor isEqual:kDefaultANSIColorFgGreen])
            return AMR_SGRCodeFgGreen;
        else if ([aColor isEqual:kDefaultANSIColorFgYellow])
            return AMR_SGRCodeFgYellow;
        else if ([aColor isEqual:kDefaultANSIColorFgBlue])
            return AMR_SGRCodeFgBlue;
        else if ([aColor isEqual:kDefaultANSIColorFgMagenta])
            return AMR_SGRCodeFgMagenta;
        else if ([aColor isEqual:kDefaultANSIColorFgCyan])
            return AMR_SGRCodeFgCyan;
        else if ([aColor isEqual:kDefaultANSIColorFgWhite])
            return AMR_SGRCodeFgWhite;
        else if ([aColor isEqual:kDefaultANSIColorFgBrightBlack])
            return AMR_SGRCodeFgBrightBlack;
        else if ([aColor isEqual:kDefaultANSIColorFgBrightRed])
            return AMR_SGRCodeFgBrightRed;
        else if ([aColor isEqual:kDefaultANSIColorFgBrightGreen])
            return AMR_SGRCodeFgBrightGreen;
        else if ([aColor isEqual:kDefaultANSIColorFgBrightYellow])
            return AMR_SGRCodeFgBrightYellow;
        else if ([aColor isEqual:kDefaultANSIColorFgBrightBlue])
            return AMR_SGRCodeFgBrightBlue;
        else if ([aColor isEqual:kDefaultANSIColorFgBrightMagenta])
            return AMR_SGRCodeFgBrightMagenta;
        else if ([aColor isEqual:kDefaultANSIColorFgBrightCyan])
            return AMR_SGRCodeFgBrightCyan;
        else if ([aColor isEqual:kDefaultANSIColorFgBrightWhite])
            return AMR_SGRCodeFgBrightWhite;
    }
    else
    {
        if ([aColor isEqual:kDefaultANSIColorBgBlack])
            return AMR_SGRCodeBgBlack;
        else if ([aColor isEqual:kDefaultANSIColorBgRed])
            return AMR_SGRCodeBgRed;
        else if ([aColor isEqual:kDefaultANSIColorBgGreen])
            return AMR_SGRCodeBgGreen;
        else if ([aColor isEqual:kDefaultANSIColorBgYellow])
            return AMR_SGRCodeBgYellow;
        else if ([aColor isEqual:kDefaultANSIColorBgBlue])
            return AMR_SGRCodeBgBlue;
        else if ([aColor isEqual:kDefaultANSIColorBgMagenta])
            return AMR_SGRCodeBgMagenta;
        else if ([aColor isEqual:kDefaultANSIColorBgCyan])
            return AMR_SGRCodeBgCyan;
        else if ([aColor isEqual:kDefaultANSIColorBgWhite])
            return AMR_SGRCodeBgWhite;
        else if ([aColor isEqual:kDefaultANSIColorBgBrightBlack])
            return AMR_SGRCodeBgBrightBlack;
        else if ([aColor isEqual:kDefaultANSIColorBgBrightRed])
            return AMR_SGRCodeBgBrightRed;
        else if ([aColor isEqual:kDefaultANSIColorBgBrightGreen])
            return AMR_SGRCodeBgBrightGreen;
        else if ([aColor isEqual:kDefaultANSIColorBgBrightYellow])
            return AMR_SGRCodeBgBrightYellow;
        else if ([aColor isEqual:kDefaultANSIColorBgBrightBlue])
            return AMR_SGRCodeBgBrightBlue;
        else if ([aColor isEqual:kDefaultANSIColorBgBrightMagenta])
            return AMR_SGRCodeBgBrightMagenta;
        else if ([aColor isEqual:kDefaultANSIColorBgBrightCyan])
            return AMR_SGRCodeBgBrightCyan;
        else if ([aColor isEqual:kDefaultANSIColorBgBrightWhite])
            return AMR_SGRCodeBgBrightWhite;
    }

    return AMR_SGRCodeNoneOrInvalid;
}



// helper struct typedef and a few functions for
// -closestSGRCodeForColor:isForegroundColor:

typedef struct {
    CGFloat hue;
    CGFloat saturation;
    CGFloat brightness;
} AMR_HSB;

AMR_HSB makeHSB(CGFloat hue, CGFloat saturation, CGFloat brightness)
{
    AMR_HSB outHSB;
    outHSB.hue = hue;
    outHSB.saturation = saturation;
    outHSB.brightness = brightness;
    return outHSB;
}

AMR_HSB getHSBFromColor(NSColor *color)
{
    CGFloat hue = 0.0;
    CGFloat saturation = 0.0;
    CGFloat brightness = 0.0;
    [[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]
        getHue:&hue
        saturation:&saturation
        brightness:&brightness
        alpha:NULL
        ];
    return makeHSB(hue, saturation, brightness);
}

BOOL floatsEqual(CGFloat first, CGFloat second, CGFloat maxAbsError)
{
    return (fabs(first-second)) < maxAbsError;
}

#define MAX_HUE_FLOAT_EQUALITY_ABS_ERROR 0.000001

- (AMR_SGRCode) closestSGRCodeForColor:(NSColor *)color isForegroundColor:(BOOL)foreground
{
    if (color == nil)
        return AMR_SGRCodeNoneOrInvalid;

    AMR_SGRCode closestColorSGRCode = [self AMR_SGRCodeForColor:color isForegroundColor:foreground];
    if (closestColorSGRCode != AMR_SGRCodeNoneOrInvalid)
        return closestColorSGRCode;

    AMR_HSB givenColorHSB = getHSBFromColor(color);

    CGFloat closestColorHueDiff = FLT_MAX;
    CGFloat closestColorSaturationDiff = FLT_MAX;
    CGFloat closestColorBrightnessDiff = FLT_MAX;

    // (background SGR codes are +10 from foreground ones:)
    NSUInteger AMR_SGRCodeShift = (foreground)?0:10;
    NSArray *ansiFgColorCodes = @[
    @(AMR_SGRCodeFgBlack+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgRed+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgGreen+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgYellow+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgBlue+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgMagenta+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgCyan+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgWhite+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgBrightBlack+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgBrightRed+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgBrightGreen+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgBrightYellow+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgBrightBlue+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgBrightMagenta+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgBrightCyan+AMR_SGRCodeShift),
    @(AMR_SGRCodeFgBrightWhite+AMR_SGRCodeShift),
    ];
    for (NSNumber *thisSGRCodeNumber in ansiFgColorCodes)
    {
        AMR_SGRCode thisSGRCode = thisSGRCodeNumber.intValue;
        NSColor *thisColor = [self colorForSGRCode:thisSGRCode];

        AMR_HSB thisColorHSB = getHSBFromColor(thisColor);

        CGFloat hueDiff = fabs(givenColorHSB.hue - thisColorHSB.hue);
        CGFloat saturationDiff = fabs(givenColorHSB.saturation - thisColorHSB.saturation);
        CGFloat brightnessDiff = fabs(givenColorHSB.brightness - thisColorHSB.brightness);

        // comparison depends on hue, saturation and brightness
        // (strictly in that order):

        if (!floatsEqual(hueDiff, closestColorHueDiff, MAX_HUE_FLOAT_EQUALITY_ABS_ERROR))
        {
            if (hueDiff > closestColorHueDiff)
                continue;
            closestColorSGRCode = thisSGRCode;
            closestColorHueDiff = hueDiff;
            closestColorSaturationDiff = saturationDiff;
            closestColorBrightnessDiff = brightnessDiff;
            continue;
        }

        if (!floatsEqual(saturationDiff, closestColorSaturationDiff, MAX_HUE_FLOAT_EQUALITY_ABS_ERROR))
        {
            if (saturationDiff > closestColorSaturationDiff)
                continue;
            closestColorSGRCode = thisSGRCode;
            closestColorHueDiff = hueDiff;
            closestColorSaturationDiff = saturationDiff;
            closestColorBrightnessDiff = brightnessDiff;
            continue;
        }

        if (!floatsEqual(brightnessDiff, closestColorBrightnessDiff, MAX_HUE_FLOAT_EQUALITY_ABS_ERROR))
        {
            if (brightnessDiff > closestColorBrightnessDiff)
                continue;
            closestColorSGRCode = thisSGRCode;
            closestColorHueDiff = hueDiff;
            closestColorSaturationDiff = saturationDiff;
            closestColorBrightnessDiff = brightnessDiff;
            continue;
        }

        // If hue (especially hue!), saturation and brightness diffs all
        // are equal to some other color, we need to prefer one or the
        // other so we'll select the more 'distinctive' color of the
        // two (this is *very* subjective, obviously). I basically just
        // looked at the hue chart, went through all the points between
        // our main ANSI colors and decided which side the middle point
        // would lean on. (e.g. the purple color that is exactly between
        // the blue and magenta ANSI colors looks more magenta than
        // blue to me so I put magenta higher than blue in the list
        // below.)
        //
        // subjective ordering of colors from most to least 'distinctive':
        long colorDistinctivenessOrder[6] = {
            AMR_SGRCodeFgRed+AMR_SGRCodeShift,
            AMR_SGRCodeFgMagenta+AMR_SGRCodeShift,
            AMR_SGRCodeFgBlue+AMR_SGRCodeShift,
            AMR_SGRCodeFgGreen+AMR_SGRCodeShift,
            AMR_SGRCodeFgCyan+AMR_SGRCodeShift,
            AMR_SGRCodeFgYellow+AMR_SGRCodeShift
            };
        for (int i = 0; i < 6; i++)
        {
            if (colorDistinctivenessOrder[i] == closestColorSGRCode)
                break;
            else if (colorDistinctivenessOrder[i] == thisSGRCode)
            {
                closestColorSGRCode = thisSGRCode;
                closestColorHueDiff = hueDiff;
                closestColorSaturationDiff = saturationDiff;
                closestColorBrightnessDiff = brightnessDiff;
            }
        }
    }

    return closestColorSGRCode;
}



@end

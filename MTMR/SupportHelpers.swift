//
//  SupportHelpers.swift
//  MTMR
//
//  Created by Anton Palgunov on 13/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

extension String {
    func trim() -> String {
        return self.trimmingCharacters(in: NSCharacterSet.whitespaces)
    }

    func substring(from: Int, to: Int) -> String {
        let start = index(startIndex, offsetBy: from)
        let end = index(start, offsetBy: to - from)
        return String(self[start ..< end])
    }
    
    func substring(range: NSRange) -> String {
        return substring(from: range.lowerBound, to: range.upperBound)
    }
    
    func indexDistance(of character: Character) -> Int? {
        guard let index = index(of: character) else { return nil }
        return distance(from: startIndex, to: index)
    }
    
    func stripComments() -> String {
        let str = self
        let singleComment = 1;
        let multiComment = 2;
        var insideString = false
        var insideComment = 0
        var offset = 0
        var ret = ""
        
        for var i in 0..<str.count - 1 {
            let currentChar = Array(str)[i]
            let nextChar = Array(str)[i+1]
            
            if (insideComment == 0 && currentChar == "\"") {
                let escaped = Array(str)[i - 1] == "\\" && Array(str)[i - 2] != "\\"
                if (!escaped) {
                    insideString = !insideString
                }
            }
            
            if (insideString) {
                let jumpStr = String(str[str.index(startIndex, offsetBy: i)..<str.endIndex])
                i += (jumpStr.indexDistance(of: "\""))!
                continue
            }
            
            if (insideComment == 0 && String(currentChar) + String(nextChar) == "//") {
                ret += str.substring(from: offset, to: i)
                offset = i
                insideComment = singleComment
                i += 1
            } else if (insideComment == singleComment && String(currentChar) + String(nextChar) == "\r\n") {
                i += 1
                insideComment = 0
                offset = i
            } else if (insideComment == singleComment && currentChar == "\n") {
                insideComment = 0
                offset = i
            } else if (insideComment == 0 && String(currentChar) + String(nextChar) == "/*") {
                ret += str.substring(from: offset, to: i)
                offset = i
                insideComment = multiComment
                i += 1
            } else if (insideComment == multiComment && String(currentChar) + String(nextChar) == "*/") {
                i += 1
                insideComment = 0
                offset = i + 1
            }
        }
        
        return ret + str.substring(from: offset, to: str.count)
    }
}

extension NSImage {
    func resize(maxSize:NSSize) -> NSImage {
        var ratio:Float = 0.0
        let imageWidth = Float(self.size.width)
        let imageHeight = Float(self.size.height)
        let maxWidth = Float(maxSize.width)
        let maxHeight = Float(maxSize.height)
        
        // Get ratio (landscape or portrait)
        if (imageWidth > imageHeight) {
            // Landscape
            ratio = maxWidth / imageWidth;
        }
        else {
            // Portrait
            ratio = maxHeight / imageHeight;
        }
        
        // Calculate new size based on the ratio
        let newWidth = imageWidth * ratio
        let newHeight = imageHeight * ratio
        
        // Create a new NSSize object with the newly calculated size
        let newSize:NSSize = NSSize(width: Int(newWidth), height: Int(newHeight))
        
        // Cast the NSImage to a CGImage
        var imageRect:NSRect = NSMakeRect(0, 0, self.size.width, self.size.height)
        let imageRef = self.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
        
        // Create NSImage from the CGImage using the new size
        let imageWithNewSize = NSImage(cgImage: imageRef!, size: newSize)
        
        // Return the new image
        return imageWithNewSize
    }
    
    func rotateByDegreess(degrees:CGFloat) -> NSImage {
        
        var imageBounds = NSZeroRect ; imageBounds.size = self.size
        let pathBounds = NSBezierPath(rect: imageBounds)
        var transform = NSAffineTransform()
        transform.rotate(byDegrees: degrees)
        pathBounds.transform(using: transform as AffineTransform)
        let rotatedBounds:NSRect = NSMakeRect(NSZeroPoint.x, NSZeroPoint.y , self.size.width, self.size.height )
        let rotatedImage = NSImage(size: rotatedBounds.size)
        
        //Center the image within the rotated bounds
        imageBounds.origin.x = NSMidX(rotatedBounds) - (NSWidth(imageBounds) / 2)
        imageBounds.origin.y  = NSMidY(rotatedBounds) - (NSHeight(imageBounds) / 2)
        
        // Start a new transform
        transform = NSAffineTransform()
        // Move coordinate system to the center (since we want to rotate around the center)
        transform.translateX(by: +(NSWidth(rotatedBounds) / 2 ), yBy: +(NSHeight(rotatedBounds) / 2))
        transform.rotate(byDegrees: degrees)
        // Move the coordinate system bak to normal
        transform.translateX(by: -(NSWidth(rotatedBounds) / 2 ), yBy: -(NSHeight(rotatedBounds) / 2))
        // Draw the original image, rotated, into the new image
        rotatedImage.lockFocus()
        transform.concat()
        self.draw(in: imageBounds, from: NSZeroRect, operation: NSCompositingOperation.copy, fraction: 1.0)
        rotatedImage.unlockFocus()
        
        return rotatedImage
    }

}

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

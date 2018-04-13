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
}

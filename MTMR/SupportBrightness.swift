import Foundation

public let sharedBrightnessController: BrightnessController = {
    if #available(OSX 10.13, *) {
        return CoreDisplayBrightnessController()
    } else {
        return IOServiceBrightnessController()
    }
}()

public protocol BrightnessController: class {
    var brightness: Float { get set }
}

public extension BrightnessController {
    func increase() {
        brightness += 0.1
    }
    func decrease() {
        brightness -= 0.1
    }
}

@available(OSX 10.13, *)
private class CoreDisplayBrightnessController : BrightnessController {
    var brightness: Float {
        get {
            return Float(CoreDisplay_Display_GetUserBrightness(0))
        }
        set {
            CoreDisplay_Display_SetUserBrightness(0, Double(newValue));
        }
    }
}

private class IOServiceBrightnessController : BrightnessController {
    var brightness: Float {
        get {
            var level: Float32 = 0.5
            let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"))
            
            IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &level)
            return Float(level)
        }
        set {
            let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"))
            
            IODisplaySetFloatParameter(service, 1, kIODisplayBrightnessKey as CFString, newValue)
            IOObjectRelease(service)
        }
    }
}

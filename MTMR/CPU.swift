//
//  CPU.swift
//  Pods
//
//  Created by zixun on 2016/12/5.
//  https://github.com/zixun/SystemEye
//  MIT License
//
//

import Foundation

private let HOST_CPU_LOAD_INFO_COUNT      : mach_msg_type_number_t =
    UInt32(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

/// CPU Class
public class CPU: NSObject {
    
    //--------------------------------------------------------------------------
    // MARK: OPEN PROPERTY
    //--------------------------------------------------------------------------
    
//    /// Number of physical cores on this machine.
//    public static var physicalCores: Int {
//        get {
//            return Int(System.hostBasicInfo.physical_cpu)
//        }
//    }
//
//    /// Number of logical cores on this machine. Will be equal to physicalCores
//    /// unless it has hyper-threading, in which case it will be double.
//    public static var logicalCores: Int {
//        get {
//            return Int(System.hostBasicInfo.logical_cpu)
//        }
//    }
    
    //--------------------------------------------------------------------------
    // MARK: OPEN FUNCTIONS
    //--------------------------------------------------------------------------
    
    ///  Get CPU usage of hole system (system, user, idle, nice). Determined by the delta between
    ///  the current and last call.
    public static func systemUsage() -> (system: Double,
                                         user: Double,
                                         idle: Double,
                                         nice: Double) {
        let load = self.hostCPULoadInfo
        
        let userDiff = Double(load.cpu_ticks.0 - loadPrevious.cpu_ticks.0)
        let sysDiff  = Double(load.cpu_ticks.1 - loadPrevious.cpu_ticks.1)
        let idleDiff = Double(load.cpu_ticks.2 - loadPrevious.cpu_ticks.2)
        let niceDiff = Double(load.cpu_ticks.3 - loadPrevious.cpu_ticks.3)
        
        let totalTicks = sysDiff + userDiff + niceDiff + idleDiff
        
        let sys  = sysDiff  / totalTicks * 100.0
        let user = userDiff / totalTicks * 100.0
        let idle = idleDiff / totalTicks * 100.0
        let nice = niceDiff / totalTicks * 100.0
        
        loadPrevious = load
        
        return (sys, user, idle, nice)
    }
    
    
    /// Get CPU usage of application,get from all thread
    open class func applicationUsage() -> Double {
        let threads = self.threadBasicInfos()
        var result : Double = 0.0
        threads.forEach { (thread:thread_basic_info) in
            if self.flag(thread) {
                result += Double.init(thread.cpu_usage) / Double.init(TH_USAGE_SCALE);
            }
        }
        return result * 100
    }
    
    //--------------------------------------------------------------------------
    // MARK: PRIVATE PROPERTY
    //--------------------------------------------------------------------------
    
    /// previous load of cpu
    private static var loadPrevious = host_cpu_load_info()
    
    static var hostCPULoadInfo: host_cpu_load_info {
        get {
            var size     = HOST_CPU_LOAD_INFO_COUNT
            var hostInfo = host_cpu_load_info()
            let result = withUnsafeMutablePointer(to: &hostInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                    host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
                }
            }
            
            #if DEBUG
                if result != KERN_SUCCESS {
                    fatalError("ERROR - \(#file):\(#function) - kern_result_t = "
                        + "\(result)")
                }
            #endif
            
            return hostInfo
        }
    }
    
    //--------------------------------------------------------------------------
    // MARK: PRIVATE FUNCTION
    //--------------------------------------------------------------------------
    
    private class func flag(_ thread:thread_basic_info) -> Bool {
        let foo = thread.flags & TH_FLAGS_IDLE
        let number = NSNumber.init(value: foo)
        return !Bool.init(truncating: number)
    }
    
    private class func threadActPointers() -> [thread_act_t] {
        var threads_act = [thread_act_t]()
        
        var threads_array: thread_act_array_t? = nil
        var count = mach_msg_type_number_t()
        
        let result = task_threads(mach_task_self_, &(threads_array), &count)
        
        guard result == KERN_SUCCESS else {
            return threads_act
        }
        
        guard let array = threads_array  else {
            return threads_act
        }
        
        for i in 0..<count {
            threads_act.append(array[Int(i)])
        }
        
        let krsize = count * UInt32.init(MemoryLayout<thread_t>.size)
        _ = vm_deallocate(mach_task_self_, vm_address_t(array.pointee), vm_size_t(krsize));
        return threads_act
    }
    
    private class func threadBasicInfos() -> [thread_basic_info]  {
        var result = [thread_basic_info]()
        
        let thinfo : thread_info_t = thread_info_t.allocate(capacity: Int(THREAD_INFO_MAX))
        let thread_info_count = UnsafeMutablePointer<mach_msg_type_number_t>.allocate(capacity: 128)
        var basic_info_th: thread_basic_info_t? = nil
        
        for act_t in self.threadActPointers() {
            thread_info_count.pointee = UInt32(THREAD_INFO_MAX);
            let kr = thread_info(act_t ,thread_flavor_t(THREAD_BASIC_INFO),thinfo, thread_info_count);
            if (kr != KERN_SUCCESS) {
                return [thread_basic_info]();
            }
            basic_info_th = withUnsafePointer(to: &thinfo.pointee, { (ptr) -> thread_basic_info_t in
                let int8Ptr = unsafeBitCast(ptr, to: thread_basic_info_t.self)
                return int8Ptr
            })
            if basic_info_th != nil {
                result.append(basic_info_th!.pointee)
            }
        }
        
        return result
    }
    
    //TODO: this function is used for get cpu usage of all thread,and this is in developing
    private class func threadIdentifierInfos() -> [thread_identifier_info] {
        var result = [thread_identifier_info]()
        let thinfo : thread_info_t = thread_info_t.allocate(capacity: Int(THREAD_INFO_MAX))
        let thread_info_count = UnsafeMutablePointer<mach_msg_type_number_t>.allocate(capacity: 128)
        var identifier_info_th: thread_identifier_info_t? = nil
        
        for act_t in self.threadActPointers() {
            thread_info_count.pointee = UInt32(THREAD_INFO_MAX);
            let kr = thread_info(act_t ,thread_flavor_t(THREAD_IDENTIFIER_INFO),thinfo, thread_info_count);
            if (kr != KERN_SUCCESS) {
                return [thread_identifier_info]();
            }
            identifier_info_th = withUnsafePointer(to: &thinfo.pointee, { (ptr) -> thread_identifier_info_t in
                let int8Ptr = unsafeBitCast(ptr, to: thread_identifier_info_t.self)
                return int8Ptr
            })
            if identifier_info_th != nil {
                result.append(identifier_info_th!.pointee)
            }
        }
        return result
    }
}

import Foundation
import IOKit.hid

/// Watches AU05 HID interfaces with a given primary usage page.
/// Handles plug/unplug; delivers input reports with the report ID stripped.
public final class HIDDeviceWatcher {
    public let usagePage: Int
    public let seize: Bool
    public var onReport: ((_ reportID: UInt32, _ payload: Data) -> Void)?
    public var onConnectionChange: ((Bool) -> Void)?
    public var isConnected: Bool { !buffers.isEmpty }

    private var manager: IOHIDManager?
    private var buffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]
    private static let bufferSize = 256

    public init(usagePage: Int, seize: Bool = false) {
        self.usagePage = usagePage
        self.seize = seize
    }

    deinit { stop() }

    @discardableResult
    public func start() -> IOReturn {
        guard manager == nil else { return kIOReturnSuccess }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: AU05.vendorID,
            kIOHIDProductIDKey: AU05.productID,
            kIOHIDPrimaryUsagePageKey: usagePage,
        ]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDDeviceWatcher>.fromOpaque(ctx).takeUnretainedValue().attached(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDDeviceWatcher>.fromOpaque(ctx).takeUnretainedValue().removed(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let opts = seize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone
        let result = IOHIDManagerOpen(m, IOOptionBits(opts))
        manager = m
        return result
    }

    public func stop() {
        guard let m = manager else { return }
        for (device, buf) in buffers {
            IOHIDDeviceRegisterInputReportCallback(device, buf, Self.bufferSize, nil, nil)
            buf.deallocate()
        }
        buffers.removeAll()
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        onConnectionChange?(false)
    }

    /// Sends an output report to every matched device. `report[0]` is the report ID.
    @discardableResult
    public func sendOutputReport(_ report: [UInt8]) -> IOReturn {
        guard let id = report.first else { return kIOReturnBadArgument }
        var result = kIOReturnNotOpen
        for device in buffers.keys {
            result = report.withUnsafeBufferPointer { buf in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(id), buf.baseAddress!, buf.count)
            }
        }
        return result
    }

    private func attached(_ device: IOHIDDevice) {
        guard buffers[device] == nil else { return }
        let wasConnected = isConnected
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.bufferSize)
        buffers[device] = buf
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buf, Self.bufferSize, { ctx, _, _, _, reportID, report, length in
            guard let ctx else { return }
            Unmanaged<HIDDeviceWatcher>.fromOpaque(ctx).takeUnretainedValue()
                .received(reportID: reportID, bytes: report, length: length)
        }, ctx)
        if !wasConnected { onConnectionChange?(true) }
    }

    private func removed(_ device: IOHIDDevice) {
        guard let buf = buffers.removeValue(forKey: device) else { return }
        IOHIDDeviceRegisterInputReportCallback(device, buf, Self.bufferSize, nil, nil)
        buf.deallocate()
        if !isConnected { onConnectionChange?(false) }
    }

    private func received(reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length > 0 else { return }
        var data = Data(bytes: bytes, count: length)
        // IOKit includes the report ID as byte 0 for devices that use report IDs.
        if reportID != 0, data.first == UInt8(truncatingIfNeeded: reportID), length > 63 {
            data.removeFirst()
        }
        onReport?(reportID, data)
    }
}

public enum InputMonitoring {
    public static var granted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
    @discardableResult
    public static func request() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
}

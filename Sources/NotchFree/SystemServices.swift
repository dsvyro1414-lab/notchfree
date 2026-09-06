import AppKit
import CoreAudio
import IOKit.ps
import IOBluetooth
import ApplicationServices
import NotchFreeCore

final class BrightnessControl {
    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (UInt32, Float) -> Int32
    private var handle: UnsafeMutableRawPointer?
    private var get: Get?
    private var set: Set?
    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle, let read = dlsym(handle, "DisplayServicesGetBrightness"), let write = dlsym(handle, "DisplayServicesSetBrightness") {
            get = unsafeBitCast(read, to: Get.self); set = unsafeBitCast(write, to: Set.self)
        }
    }
    var display: UInt32? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 }?.displayID ?? NSScreen.screens.first { CGDisplayIsBuiltin($0.displayID) != 0 }?.displayID }
    func read() -> Float? {
        guard let get, let display else { return nil }; var value: Float = 0
        return get(display, &value) == 0 ? value : nil
    }
    func write(_ value: Float) -> Bool {
        guard let set, let display, value.isFinite else { return false }
        return set(display, min(1, max(0, value))) == 0
    }
    deinit { if let handle { dlclose(handle) } }
}

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}

@MainActor final class SystemHUDProvider: ObservableObject {
    @Published var volume: Float = 0
    @Published var muted = false
    @Published var volumeSupported = false
    @Published var brightness: Float?
    @Published var keyboardEnabled = false
    @Published var status = "System keys use the standard macOS indicators."
    var onActivity: ((Activity) -> Void)?
    private let brightnessControl = BrightnessControl()
    private var device = AudioDeviceID(0)
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var consumed = Set<Int>()
    init() { bindDevice() }
    private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    private func float(_ selector: AudioObjectPropertySelector, element: UInt32 = 0) -> Float? {
        var property = address(selector, element: element), result: Float = 0, size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &result) == noErr else { return nil }
        return result
    }
    private func muteValue() -> Bool {
        var property = address(kAudioDevicePropertyMute), value: UInt32 = 0, size: UInt32 = 4
        return AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr && value != 0
    }
    private func volumeElements() -> [UInt32] {
        if float(kAudioDevicePropertyVolumeScalar) != nil { return [0] }
        return [UInt32(1), 2].filter { float(kAudioDevicePropertyVolumeScalar, element: $0) != nil }
    }
    private func observe(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, _ action: @escaping () -> Void) {
        var property = property
        let block: AudioObjectPropertyListenerBlock = { _, _ in action() }
        if AudioObjectAddPropertyListenerBlock(object, &property, .main, block) == noErr { listeners.append((object, property, block)) }
    }
    private func unbind() {
        for (object, saved, block) in listeners { var property = saved; AudioObjectRemovePropertyListenerBlock(object, &property, .main, block) }
        listeners.removeAll()
    }
    private func bindDevice() {
        unbind()
        var property = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device)
        refresh()
        observe(AudioObjectID(kAudioObjectSystemObject), property) { [weak self] in self?.bindDevice() }
        for element in volumeElements() {
            observe(device, address(kAudioDevicePropertyVolumeScalar, element: element)) { [weak self] in self?.changedVolume() }
        }
        observe(device, address(kAudioDevicePropertyMute)) { [weak self] in self?.changedVolume() }
    }
    func refresh() {
        let values = volumeElements().compactMap { float(kAudioDevicePropertyVolumeScalar, element: $0) }
        volumeSupported = !values.isEmpty; volume = values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
        muted = muteValue(); brightness = brightnessControl.read()
    }
    private func changedVolume() {
        let previous = volume, wasMuted = muted
        refresh()
        if abs(previous - volume) > 0.002 || wasMuted != muted { showVolume() }
    }
    private func showVolume() { onActivity?(Activity(title: muted ? "Muted" : "Volume", symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", level: muted ? 0 : Double(volume), duration: 1.6)) }
    @discardableResult func setVolume(_ value: Float) -> Bool {
        guard value.isFinite else { return false }
        let elements = volumeElements(); guard !elements.isEmpty else { return false }
        var success = true, scalar = min(1, max(0, value))
        for element in elements {
            var property = address(kAudioDevicePropertyVolumeScalar, element: element)
            success = AudioObjectSetPropertyData(device, &property, 0, nil, 4, &scalar) == noErr && success
        }
        refresh(); showVolume(); return success
    }
    @discardableResult func setMute(_ enabled: Bool) -> Bool {
        var property = address(kAudioDevicePropertyMute), value: UInt32 = enabled ? 1 : 0
        let result = AudioObjectSetPropertyData(device, &property, 0, nil, 4, &value) == noErr
        refresh(); showVolume(); return result
    }
    @discardableResult func setBrightness(_ value: Float) -> Bool {
        guard brightnessControl.write(value) else { return false }
        brightness = brightnessControl.read()
        onActivity?(Activity(title: "Brightness", symbol: "sun.max.fill", level: Double(brightness ?? value), duration: 1.6))
        return true
    }
    func enableKeyboard(request: Bool) {
        disableKeyboard()
        let trusted = request ? AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) : AXIsProcessTrusted()
        guard trusted else { status = "Allow NotchFree in Accessibility, then click Enable again."; return }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<SystemHUDProvider>.fromOpaque(userInfo).takeUnretainedValue()
                return MainActor.assumeIsolated { controller.handle(type, event) }
            }, userInfo: pointer) else {
            status = "Could not intercept media keys. Standard macOS controls remain active."; return
        }
        tap = port; runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        keyboardEnabled = true; status = "Notch indicators replace supported volume and brightness keys."
        UserDefaults.standard.set(true, forKey: "replaceHUD")
    }
    func disableKeyboard() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil; runLoopSource = nil; keyboardEnabled = false; consumed.removeAll()
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return Unmanaged.passUnretained(event)
        }
        guard let key = NSEvent(cgEvent: event), key.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        let code = (key.data1 & 0xffff0000) >> 16, down = ((key.data1 & 0xff00) >> 8) == 0xa
        if !down { return consumed.remove(code) != nil ? nil : Unmanaged.passUnretained(event) }
        let step: Float = event.flags.contains([.maskAlternate, .maskShift]) ? 1 / 64 : 1 / 16
        var handled = false
        switch code {
        case 0, 1:
            if volumeSupported { if muted { _ = setMute(false) }; handled = setVolume(volume + (code == 0 ? step : -step)) }
        case 7: handled = volumeSupported && setMute(!muted)
        case 2, 3: if let current = brightnessControl.read() { handled = setBrightness(current + (code == 2 ? step : -step)) }
        default: break
        }
        if handled { consumed.insert(code); return nil }
        return Unmanaged.passUnretained(event)
    }
    func stop() { disableKeyboard(); unbind() }
}

@MainActor final class DeviceActivities: NSObject, ObservableObject {
    @Published var battery: Int?
    @Published var charging = false
    @Published var bluetoothEnabled = false
    @Published var bluetoothStatus = "Bluetooth alerts are off."
    var onActivity: ((Activity) -> Void)?
    private var powerSource: CFRunLoopSource?
    private var connection: IOBluetoothUserNotification?
    private var disconnections: [IOBluetoothUserNotification] = []
    private var initialized = false
    override init() {
        super.init(); updatePower()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let service = Unmanaged<DeviceActivities>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.updatePower() }
        }
        powerSource = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
    }
    func updatePower() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let data = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let capacity = data[kIOPSCurrentCapacityKey] as? Int, let maxCapacity = data[kIOPSMaxCapacityKey] as? Int, maxCapacity > 0 else { continue }
            let value = min(100, max(0, capacity * 100 / maxCapacity))
            let plugged = data[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            if initialized {
                if plugged != charging { onActivity?(Activity(title: plugged ? "Power connected" : "On battery", subtitle: "\(value)%", symbol: plugged ? "bolt.fill" : "battery.75percent")) }
                else if value <= 20 && (battery ?? 0) > 20 { onActivity?(Activity(title: "Battery is low", subtitle: "\(value)% remaining", symbol: "battery.25percent")) }
                else if value == 100 && battery != 100 { onActivity?(Activity(title: "Fully charged", symbol: "battery.100percent")) }
            }
            battery = value; charging = plugged; initialized = true; break
        }
    }
    func enableBluetooth() {
        guard !bluetoothEnabled else { return }
        connection = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(didConnect(_:device:)))
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in devices where device.isConnected() { registerDisconnect(device) }
        }
        bluetoothEnabled = connection != nil
        bluetoothStatus = bluetoothEnabled ? "Listening for device connections." : "Bluetooth access unavailable. Check System Settings."
    }
    @objc private func didConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onActivity?(Activity(title: device.name ?? "Bluetooth device", subtitle: "Connected", symbol: "headphones")); registerDisconnect(device)
    }
    private func registerDisconnect(_ device: IOBluetoothDevice) {
        if let item = device.register(forDisconnectNotification: self, selector: #selector(didDisconnect(_:device:))) { disconnections.append(item) }
    }
    @objc private func didDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onActivity?(Activity(title: device.name ?? "Bluetooth device", subtitle: "Disconnected", symbol: "headphones"))
        notification.unregister(); disconnections.removeAll { $0 === notification }
    }
    func disableBluetooth() { connection?.unregister(); connection = nil; disconnections.forEach { $0.unregister() }; disconnections.removeAll(); bluetoothEnabled = false }
    func stop() {
        disableBluetooth()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
    }
}

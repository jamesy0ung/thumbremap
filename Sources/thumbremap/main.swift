import Cocoa

guard AXIsProcessTrusted() else { print("Need Accessibility permission"); exit(1) }

enum ScrollState { case idle, active }
nonisolated(unsafe) var state: ScrollState = .idle
nonisolated(unsafe) var idleTimer: Timer?
let idleTimeout: TimeInterval = 0.08

let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

let tap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: { proxy, _, event, _ in
        
        let dx    = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        
        // Only touch legacy (phase=0) horizontal events
        guard dx != 0, phase == 0 else {
            return Unmanaged.passRetained(event)
        }
        
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -dx)  // invert the scroll, the default seems weird to me
        
        // Mutate in-place so the event keeps its original HID source trust
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        
        if state == .idle {
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1) // began
            state = .active
        } else {
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2) // changed
        }
        
        // Schedule synthetic end event. Control Center should handle missing end gracefully (slider just holds position)
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { _ in
            if let end = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
                                 units: .pixel, wheelCount: 2,
                                 wheel1: 0, wheel2: 0, wheel3: 0) {
                end.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4) // ended
                end.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                end.post(tap: .cghidEventTap)
            }
            state = .idle
        }
        
        return Unmanaged.passRetained(event) // return mutated original
    },
    userInfo: nil
)!

let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

RunLoop.main.run()

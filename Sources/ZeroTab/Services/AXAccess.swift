import AppKit
import ApplicationServices

enum AXAccess {
    static func values(_ element: AXUIElement, _ attributes: [String]) -> [String: CFTypeRef]? {
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &raw) == .success,
              let values = raw as? [CFTypeRef], values.count == attributes.count else { return nil }
        var result: [String: CFTypeRef] = [:]
        for (key, value) in zip(attributes, values) {
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { continue }
            result[key] = value
        }
        return result
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(element, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        frame(position: value(element, kAXPositionAttribute), size: value(element, kAXSizeAttribute))
    }

    static func frame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
        guard let position, CFGetTypeID(position) == AXValueGetTypeID(),
              let size, CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return element(app, kAXFocusedWindowAttribute)
    }
}

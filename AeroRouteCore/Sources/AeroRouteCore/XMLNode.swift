import Foundation

/// Minimal ordered XML tree used to reproduce ElementTree's deterministic SVG
/// serialization. It deliberately does not sort attributes.
final class OrderedXMLNode {
    let name: String
    private(set) var attributes: [(name: String, value: String)]
    var text: String?
    private(set) var children: [OrderedXMLNode] = []

    init(
        _ name: String,
        attributes: [(String, String)] = [],
        text: String? = nil
    ) {
        self.name = name
        self.attributes = attributes
        self.text = text
    }

    @discardableResult
    func add(
        _ name: String,
        attributes: [(String, String)] = [],
        text: String? = nil
    ) -> OrderedXMLNode {
        let child = OrderedXMLNode(name, attributes: attributes, text: text)
        children.append(child)
        return child
    }

    func setAttribute(_ name: String, _ value: String) {
        if let index = attributes.firstIndex(where: { $0.name == name }) {
            attributes[index].value = value
        } else {
            attributes.append((name, value))
        }
    }

    func serialized(indentation: String = "  ") -> String {
        var output = ""
        serialize(into: &output, depth: 0, indentation: indentation)
        return output
    }

    private func serialize(into output: inout String, depth: Int, indentation: String) {
        let prefix = String(repeating: indentation, count: depth)
        output += prefix
        output += "<"
        output += name
        for attribute in attributes {
            output += " "
            output += attribute.name
            output += "=\""
            output += Self.escapeAttribute(attribute.value)
            output += "\""
        }

        if children.isEmpty, text == nil {
            output += " />"
            return
        }

        output += ">"
        if let text {
            output += Self.escapeText(text)
        }
        if !children.isEmpty {
            for child in children {
                output += "\n"
                child.serialize(into: &output, depth: depth + 1, indentation: indentation)
            }
            output += "\n"
            output += prefix
        }
        output += "</"
        output += name
        output += ">"
    }

    private static func escapeText(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x26:
                escaped += "&amp;"
            case 0x3C:
                escaped += "&lt;"
            case 0x3E:
                escaped += "&gt;"
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }

    private static func escapeAttribute(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x09:
                escaped += "&#09;"
            case 0x0A:
                escaped += "&#10;"
            case 0x0D:
                escaped += "&#13;"
            case 0x22:
                escaped += "&quot;"
            case 0x26:
                escaped += "&amp;"
            case 0x3C:
                escaped += "&lt;"
            case 0x3E:
                escaped += "&gt;"
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }
}

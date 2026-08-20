import AppKit
import SwiftUI

struct SearchQueryField: NSViewRepresentable {
    @Binding var text: String
    let focusRequestID: UUID
    let palette: AppTheme.Palette
    let placeholder: String
    let onMoveSelection: (Int) -> Void
    let onSubmit: (_ searchesBackward: Bool) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if let searchCell = field.cell as? NSSearchFieldCell {
            searchCell.searchButtonCell = nil
            searchCell.cancelButtonCell = nil
        }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        field.textColor = palette.textNS
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: palette.secondaryTextNS]
        )
        if field.stringValue != text {
            field.stringValue = text
        }

        guard context.coordinator.lastFocusRequestID != focusRequestID else {
            return
        }
        context.coordinator.lastFocusRequestID = focusRequestID
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchQueryField
        var lastFocusRequestID: UUID?

        init(parent: SearchQueryField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else {
                return
            }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let command = NoteSearchFieldCommand.resolve(commandSelector) else {
                return false
            }

            switch command {
            case let .moveSelection(offset):
                parent.onMoveSelection(offset)
            case .submit:
                let searchesBackward = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                parent.onSubmit(searchesBackward)
            case .cancel:
                parent.onCancel()
            }
            return true
        }
    }
}

enum NoteSearchFieldCommand: Equatable {
    case moveSelection(offset: Int)
    case submit
    case cancel

    static func resolve(_ selector: Selector) -> NoteSearchFieldCommand? {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            return .moveSelection(offset: 1)
        case #selector(NSResponder.moveUp(_:)):
            return .moveSelection(offset: -1)
        case #selector(NSResponder.insertNewline(_:)):
            return .submit
        case #selector(NSResponder.cancelOperation(_:)):
            return .cancel
        default:
            return nil
        }
    }
}

import AppKit

/// Inserting, editing and interacting with embedded objects: charts,
/// equations, shapes, diagrams, drawings, spreadsheets, signature lines and
/// form controls.
extension EditorController {
    /// The object at the selection: a selected attachment, or the one just
    /// before the insertion point.
    var selectedObject: (object: DocumentObject, location: Int)? {
        let selection = textView.selectedRange()
        var candidates = [selection.location]
        if selection.length == 0 && selection.location > 0 { candidates.append(selection.location - 1) }
        for location in candidates where location < textStorage.length {
            if let object = DocumentObject.decode(textStorage.attribute(.wpObject, at: location, effectiveRange: nil)),
               !object.isTextual {
                if selection.length > 1 && location == selection.location { continue }
                return (object, location)
            }
        }
        return nil
    }

    func insertObject(_ object: DocumentObject, actionName: String) {
        let attributes = TextFormatter.baseAttributes(for: textView)
        let content = ObjectFactory.string(for: object, image: ObjectRenderer.image(for: object), attributes: attributes)
        TextFormatter.replaceSelection(in: textView, with: content, actionName: actionName)
    }

    /// Replaces the object character at `location` with `object`, keeping its formatting.
    func replaceObject(at location: Int, with object: DocumentObject, actionName: String) {
        guard location < textStorage.length else { return }
        var attributes = textStorage.attributes(at: location, effectiveRange: nil)
        attributes.removeValue(forKey: .attachment)
        attributes.removeValue(forKey: .wpObject)
        let image = object.isTextual || object.kind == .checkbox || object.kind == .dropdown || object.kind == .date ? nil : ObjectRenderer.image(for: object)
        let content = ObjectFactory.string(for: object, image: image, attributes: attributes)
        let range = NSRange(location: location, length: 1)
        let textView = self.textView(containingCharacterAt: location).textView
        // Form input is allowed in protected forms and isn't a tracked revision.
        let isForm = object.kind == .checkbox || object.kind == .dropdown || object.kind == .date
        if isForm { bypassProtection = true }
        defer { if isForm { bypassProtection = false } }
        guard textView.shouldChangeText(in: range, replacementString: content.string) else { return }
        textStorage.replaceCharacters(in: range, with: content)
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        layoutManager.invalidateLiveObjects()
    }

    // MARK: Form controls

    /// Handles a click on a form control. Returns true when handled.
    func handleFormControlClick(_ object: DocumentObject, at location: Int, in textView: NSTextView, cellFrame: NSRect) -> Bool {
        guard var form = object.form else { return false }
        var updated = object
        switch form.type {
        case .checkbox:
            form.checked.toggle()
            updated.form = form
            replaceObject(at: location, with: updated, actionName: "Check Box")
        case .dropdown:
            let menu = NSMenu()
            for (index, option) in form.options.enumerated() {
                let item = NSMenuItem(title: option, action: #selector(FormMenuTarget.choose(_:)), keyEquivalent: "")
                item.tag = index
                item.state = index == form.selected ? .on : .off
                menu.addItem(item)
            }
            let target = FormMenuTarget { [weak self] index in
                form.selected = index
                updated.form = form
                self?.replaceObject(at: location, with: updated, actionName: "Choose Item")
            }
            menu.items.forEach { $0.target = target }
            objc_setAssociatedObject(menu, &FormMenuTarget.key, target, .OBJC_ASSOCIATION_RETAIN)
            menu.popUp(positioning: menu.items.indices.contains(form.selected) ? menu.items[form.selected] : nil,
                       at: NSPoint(x: cellFrame.minX, y: cellFrame.maxY), in: textView)
        case .date:
            let controller = NSViewController()
            let picker = NSDatePicker()
            picker.datePickerStyle = .clockAndCalendar
            picker.datePickerElements = .yearMonthDay
            picker.dateValue = form.date ?? Date()
            picker.sizeToFit()
            controller.view = picker
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = controller
            let observer = DatePopoverObserver { [weak self] date in
                form.date = date
                updated.form = form
                self?.replaceObject(at: location, with: updated, actionName: "Choose Date")
            }
            picker.target = observer
            picker.action = #selector(DatePopoverObserver.changed(_:))
            objc_setAssociatedObject(popover, &DatePopoverObserver.key, observer, .OBJC_ASSOCIATION_RETAIN)
            popover.show(relativeTo: cellFrame, of: textView, preferredEdge: .maxY)
        }
        return true
    }

    func insertFormControl(_ type: FormControlType) {
        var object = DocumentObject(kind: type == .checkbox ? .checkbox : type == .dropdown ? .dropdown : .date)
        object.form = FormControlSpec(type: type)
        insertObject(object, actionName: "Insert Content Control")
    }

    /// Form controls in the document, in reading order, as name → value.
    var formValues: [(name: String, value: String)] {
        var values: [(String, String)] = []
        textStorage.enumerateAttribute(.wpObject, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            guard let object = DocumentObject.decode(value), let form = object.form else { return }
            let name = form.name.isEmpty ? "Field \(values.count + 1)" : form.name
            values.append((name, form.type == .checkbox ? (form.checked ? "Yes" : "No") : form.displayText))
        }
        return values
    }

    // MARK: Images

    /// The picture attachment at the selection (not an object).
    var selectedImage: (attachment: NSTextAttachment, image: NSImage, location: Int)? {
        let selection = textView.selectedRange()
        var candidates = [selection.location]
        if selection.length == 0 && selection.location > 0 { candidates.append(selection.location - 1) }
        for location in candidates where location < textStorage.length {
            guard textStorage.attribute(.wpObject, at: location, effectiveRange: nil) == nil,
                  let attachment = textStorage.attribute(.attachment, at: location, effectiveRange: nil) as? NSTextAttachment,
                  !HorizontalRule.isRule(attachment),
                  let data = attachment.fileWrapper?.regularFileContents, let image = NSImage(data: data) else { continue }
            return (attachment, image, location)
        }
        return nil
    }

    /// Replaces the selected picture with `image` (PNG, or JPEG when `jpegQuality` is set).
    func replaceSelectedImage(with image: NSImage, displaySize: CGSize? = nil, jpegQuality: CGFloat? = nil, actionName: String) {
        guard let (old, _, location) = selectedImage else { NSSound.beep(); return }
        let name = ((old.fileWrapper?.preferredFilename ?? "image") as NSString).deletingPathExtension
        let data: Data
        if let jpegQuality {
            data = ImageProcessing.jpegData(image, quality: jpegQuality)
        } else {
            data = ObjectFactory.pngData(image)
        }
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = name + (jpegQuality == nil ? ".png" : ".jpg")
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        if let displaySize {
            let scaled = image.copy() as! NSImage
            scaled.size = displaySize
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: scaled)
        }
        AttachmentNormalizer.normalize(attachment, maxSize: geometry.maxAttachmentSize)
        var attributes = textStorage.attributes(at: location, effectiveRange: nil)
        attributes[.attachment] = attachment
        let content = NSAttributedString(string: String(Character(UnicodeScalar(NSTextAttachment.character)!)), attributes: attributes)
        let range = NSRange(location: location, length: 1)
        guard textView.shouldChangeText(in: range, replacementString: content.string) else { return }
        textStorage.replaceCharacters(in: range, with: content)
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        textView.setSelectedRange(NSRange(location: location, length: 1))
    }

    func transformSelectedImage(_ actionName: String, _ transform: (NSImage) -> NSImage?) {
        guard let (_, image, _) = selectedImage, let result = transform(image) else { NSSound.beep(); return }
        replaceSelectedImage(with: result, actionName: actionName)
    }

    func setSelectedImageAltText(_ text: String) {
        guard let (_, _, location) = selectedImage ?? selectedObject.map({ (NSTextAttachment(), NSImage(), $0.location) }) else { return }
        let range = NSRange(location: location, length: 1)
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        if text.isEmpty {
            textStorage.removeAttribute(.wpAltText, range: range)
        } else {
            textStorage.addAttribute(.wpAltText, value: text, range: range)
        }
        textView.didChangeText()
        textView.undoManager?.setActionName("Alt Text")
    }

    var selectedAltText: String {
        guard let location = selectedImage?.location ?? selectedObject?.location else { return "" }
        return textStorage.attribute(.wpAltText, at: location, effectiveRange: nil) as? String ?? ""
    }
}

private final class FormMenuTarget: NSObject {
    static var key = 0
    let handler: (Int) -> Void
    init(_ handler: @escaping (Int) -> Void) { self.handler = handler }
    @objc func choose(_ sender: NSMenuItem) { handler(sender.tag) }
}

private final class DatePopoverObserver: NSObject {
    static var key = 0
    let handler: (Date) -> Void
    init(_ handler: @escaping (Date) -> Void) { self.handler = handler }
    @objc func changed(_ sender: NSDatePicker) { handler(sender.dateValue) }
}

import AppKit
import SwiftUI

/// Tables, pictures and embedded objects.
extension DocumentViewController {
    // MARK: Objects

    func presentObjectEditor(_ object: DocumentObject, location: Int?) {
        guard let window = view.window else { return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            ObjectEditorSheet(object: object, isNew: location == nil, onSave: { updated in
                dismiss()
                if let location {
                    editor.replaceObject(at: location, with: updated, actionName: "Edit Object")
                } else {
                    editor.insertObject(updated, actionName: "Insert Object")
                }
            }, onCancel: dismiss)
        }
    }

    private func newObject(_ kind: ObjectKind, _ configure: (inout DocumentObject) -> Void) {
        var object = DocumentObject(kind: kind)
        configure(&object)
        presentObjectEditor(object, location: nil)
    }

    @objc func insertChart(_ sender: Any?) {
        newObject(.chart) { object in
            var spec = ChartSpec()
            if let raw = (sender as? NSMenuItem)?.representedObject as? String, let type = ChartType(rawValue: raw) { spec.type = type }
            if spec.type == .pie { spec.series = [ChartSeries(name: "Share", values: [42, 28, 18, 12])] }
            object.chart = spec
        }
    }

    @objc func insertEquation(_ sender: Any?) { newObject(.equation) { $0.equation = EquationSpec() } }

    @objc func insertShape(_ sender: Any?) {
        newObject(.shape) { object in
            var spec = ShapeSpec()
            if let raw = (sender as? NSMenuItem)?.representedObject as? String, let kind = ShapeKind(rawValue: raw) { spec.kind = kind }
            if spec.kind == .line || spec.kind == .arrowLine { spec.height = 40; spec.fillHex = nil }
            object.shape = spec
        }
    }

    @objc func insertTextBox(_ sender: Any?) {
        newObject(.shape) { object in
            var spec = ShapeSpec()
            spec.kind = .textBox
            spec.width = 220
            spec.height = 90
            spec.fillHex = "#FFFFFF"
            spec.strokeHex = "#8A9499"
            spec.strokeWidth = 1
            spec.text = "Text box"
            object.shape = spec
        }
    }

    @objc func insertWordArt(_ sender: Any?) {
        newObject(.wordArt) { object in
            var spec = ShapeSpec()
            spec.kind = .wordArt
            spec.width = 360
            spec.height = 80
            spec.text = "Wired Paper"
            spec.fontSize = 48
            spec.fontFamily = "Avenir Next"
            spec.textColorHex = "#0B4F55"
            object.shape = spec
        }
    }

    @objc func insertIcon(_ sender: Any?) {
        newObject(.shape) { object in
            var spec = ShapeSpec()
            spec.kind = .icon
            spec.width = 48
            spec.height = 48
            spec.fillHex = "#13787F"
            object.shape = spec
        }
    }

    @objc func insertDiagram(_ sender: Any?) {
        newObject(.diagram) { object in
            var spec = DiagramSpec()
            if let raw = (sender as? NSMenuItem)?.representedObject as? String, let type = DiagramType(rawValue: raw) { spec.type = type }
            switch spec.type {
            case .hierarchy: spec.outline = "CEO\n\tDesign\n\t\tResearch\n\tEngineering\n\t\tPlatform\n\t\tApps\n\tSales"
            case .list: spec.outline = "Goals\n\tGrow reach\n\tDelight readers\nPlan\n\tShip monthly\nMeasure\n\tWeekly review"
            case .flowchart: spec.outline = "Start\nCollect input\nValid?\nProcess\nEnd"; spec.height = 320
            case .venn: spec.outline = "Useful\nBeautiful\nFast"
            case .timeline: spec.outline = "2023 Idea\n2024 Prototype\n2025 Launch\n2026 Growth"
            case .pyramid: spec.outline = "Vision\nStrategy\nTactics\nTasks"; spec.height = 240
            default: break
            }
            object.diagram = spec
        }
    }

    @objc func insertSpreadsheet(_ sender: Any?) { newObject(.spreadsheet) { $0.sheet = SpreadsheetSpec() } }
    @objc func insertDrawing(_ sender: Any?) { newObject(.drawing) { $0.drawing = DrawingSpec() } }
    @objc func insertSignatureLine(_ sender: Any?) {
        newObject(.signature) { object in
            var spec = SignatureSpec()
            spec.signer = AppSettings.shared.authorName
            object.signature = spec
        }
    }

    @objc func insertCheckboxControl(_ sender: Any?) { editor.insertFormControl(.checkbox) }
    @objc func insertDatePickerControl(_ sender: Any?) { editor.insertFormControl(.date) }
    @objc func insertDropdownControl(_ sender: Any?) {
        var object = DocumentObject(kind: .dropdown)
        var spec = FormControlSpec(type: .dropdown)
        spec.options = ["Choose an item", "Option A", "Option B", "Option C"]
        object.form = spec
        presentObjectEditor(object, location: nil)
    }

    @objc func editSelectedObject(_ sender: Any?) {
        if let (object, location) = editor.selectedObject {
            presentObjectEditor(object, location: location)
        } else if editor.selectedImage != nil {
            showPictureFormatSheet(sender)
        } else {
            NSSound.beep()
        }
    }

    // MARK: Pictures

    @objc func showPictureFormatSheet(_ sender: Any?) {
        guard let window = view.window, let (_, image, _) = editor.selectedImage else { NSSound.beep(); return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            PictureFormatSheet(original: image, altText: editor.selectedAltText, maxWidth: editor.geometry.maxAttachmentSize.width,
                               onApply: { result, altText, jpegQuality in
                dismiss()
                if let result { editor.replaceSelectedImage(with: result, jpegQuality: jpegQuality, actionName: "Format Picture") }
                editor.setSelectedImageAltText(altText)
            }, onCancel: dismiss)
        }
    }

    @objc func rotatePictureRight(_ sender: Any?) { editor.transformSelectedImage("Rotate") { ImageProcessing.rotate($0, clockwise: true) } }
    @objc func rotatePictureLeft(_ sender: Any?) { editor.transformSelectedImage("Rotate") { ImageProcessing.rotate($0, clockwise: false) } }
    @objc func flipPictureHorizontal(_ sender: Any?) { editor.transformSelectedImage("Flip") { ImageProcessing.flip($0, horizontal: true) } }
    @objc func flipPictureVertical(_ sender: Any?) { editor.transformSelectedImage("Flip") { ImageProcessing.flip($0, horizontal: false) } }
    @objc func removePictureBackground(_ sender: Any?) {
        editor.transformSelectedImage("Remove Background") { image in
            let result = ImageProcessing.removeBackground(image)
            if result == nil {
                let alert = NSAlert()
                alert.messageText = "No subject found"
                alert.informativeText = "Wired Paper couldn't separate a foreground subject from the background of this picture."
                if let window = self.view.window { alert.beginSheetModal(for: window) }
            }
            return result
        }
    }

    @objc func editAltText(_ sender: Any?) {
        guard let window = view.window, editor.selectedImage != nil || editor.selectedObject != nil else { NSSound.beep(); return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            TextPromptSheet(title: "Alt Text", label: "Description for screen readers", onApply: { text in
                dismiss()
                editor.setSelectedImageAltText(text)
            }, onCancel: dismiss, text: editor.selectedAltText)
        }
    }

    // MARK: Tables

    @objc func insertRowAbove(_ sender: Any?) { editor.insertTableRow(below: false) }
    @objc func insertRowBelow(_ sender: Any?) { editor.insertTableRow(below: true) }
    @objc func insertColumnLeft(_ sender: Any?) { editor.insertTableColumn(right: false) }
    @objc func insertColumnRight(_ sender: Any?) { editor.insertTableColumn(right: true) }
    @objc func deleteTableRow(_ sender: Any?) { editor.deleteTableRow() }
    @objc func deleteTableColumn(_ sender: Any?) { editor.deleteTableColumn() }
    @objc func deleteTable(_ sender: Any?) { editor.deleteTable() }
    @objc func selectTable(_ sender: Any?) { editor.selectTable() }
    @objc func mergeTableCells(_ sender: Any?) { editor.mergeTableCells() }
    @objc func splitTableCell(_ sender: Any?) { editor.splitTableCell() }
    @objc func sortTableAscending(_ sender: Any?) { editor.sortTable(ascending: true) }
    @objc func sortTableDescending(_ sender: Any?) { editor.sortTable(ascending: false) }
    @objc func distributeTableColumns(_ sender: Any?) { editor.distributeTableColumns() }
    @objc func convertTableToText(_ sender: Any?) { editor.convertTableToText() }
    @objc func convertTextToTable(_ sender: Any?) { editor.convertTextToTable() }
    @objc func updateTableFormulas(_ sender: Any?) { editor.updateFields() }

    @objc func applyTableStyleFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = TableStylePreset(rawValue: raw) else { return }
        editor.applyTableStyle(preset)
    }

    @objc func setCellShadingFromMenu(_ sender: NSMenuItem) {
        editor.setCellShading(sender.representedObject as? NSColor)
    }

    @objc func setCellAlignmentFromMenu(_ sender: NSMenuItem) {
        editor.setCellVerticalAlignment(NSTextBlock.VerticalAlignment(rawValue: sender.tag) ?? .topAlignment)
    }

    @objc func insertTableFormulaPrompt(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            TextPromptSheet(title: "Formula", label: "Formula (e.g. =SUM(ABOVE), =AVERAGE(LEFT), =B2*C2)", primaryTitle: "Insert", onApply: { text in
                dismiss()
                editor.insertTableFormula(text.hasPrefix("=") ? text : "=" + text)
            }, onCancel: dismiss, text: "=SUM(ABOVE)")
        }
    }

    func validateObjectMenuItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(setDocumentModeFromMenu(_:)):
            item.state = documentMode.rawValue == item.tag ? .on : .off
            return true
        case #selector(toggleFocusMode(_:)):
            item.state = isInFocusMode ? .on : .off
            return true
        case #selector(editRecipients(_:)):
            return true
        case #selector(finishMergeEditDocuments(_:)), #selector(finishMergePrint(_:)), #selector(finishMergePDF(_:)):
            return !editor.mailMerge.includedIndices.isEmpty
        case #selector(insertAddressBlock(_:)), #selector(insertGreetingLine(_:)), #selector(clearMailMerge(_:)):
            return !editor.mailMerge.isEmpty
        case #selector(toggleMergePreview(_:)):
            item.state = editor.mergePreviewIndex != nil ? .on : .off
            return !editor.mailMerge.records.isEmpty
        case #selector(toggleFormattingMarks(_:)):
            item.title = editor.showsFormattingMarks ? "Hide Formatting Marks" : "Show Formatting Marks"
            return true
        case #selector(toggleRibbonCollapsed(_:)):
            item.title = ribbon.isCollapsed ? "Expand Ribbon" : "Collapse Ribbon"
            return !formatBar.isHidden
        case #selector(showStylesPane(_:)):
            item.state = editor.sidebar.right == .styles ? .on : .off
            return true
        case #selector(showEditorPane(_:)):
            item.state = editor.sidebar.right == .editor ? .on : .off
            return true
        case #selector(insertRowAbove(_:)), #selector(insertRowBelow(_:)), #selector(insertColumnLeft(_:)), #selector(insertColumnRight(_:)),
             #selector(deleteTableRow(_:)), #selector(deleteTableColumn(_:)), #selector(deleteTable(_:)), #selector(selectTable(_:)),
             #selector(mergeTableCells(_:)), #selector(splitTableCell(_:)), #selector(sortTableAscending(_:)), #selector(sortTableDescending(_:)),
             #selector(distributeTableColumns(_:)), #selector(convertTableToText(_:)), #selector(applyTableStyleFromMenu(_:)),
             #selector(setCellShadingFromMenu(_:)), #selector(setCellAlignmentFromMenu(_:)):
            return editor.isInTable
        case #selector(convertTextToTable(_:)):
            return !editor.isInTable && editor.textView.selectedRange().length > 0
        case #selector(showPictureFormatSheet(_:)), #selector(rotatePictureLeft(_:)), #selector(rotatePictureRight(_:)),
             #selector(flipPictureHorizontal(_:)), #selector(flipPictureVertical(_:)), #selector(removePictureBackground(_:)):
            return editor.selectedImage != nil
        case #selector(editAltText(_:)):
            return editor.selectedImage != nil || editor.selectedObject != nil
        case #selector(editSelectedObject(_:)):
            return editor.selectedObject != nil || editor.selectedImage != nil
        default:
            return nil
        }
    }
}

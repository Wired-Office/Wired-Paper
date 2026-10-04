import AppKit

/// Builds the application's main menu in code (no nib required).
///
/// Nearly every item is nil-targeted so it travels the responder chain:
/// page text view → document view controller → window → window controller →
/// document → app delegate → document controller.
enum MainMenuBuilder {
    /// Keeps the Format ▸ Styles menu in sync with the active document's styles.
    static let stylesMenuController = StylesMenuController()

    static func build(recentDocumentsDelegate: NSMenuDelegate) -> NSMenu {
        let main = NSMenu(title: "Main Menu")
        main.addItem(submenuItem(appMenu()))
        main.addItem(submenuItem(fileMenu(recentDocumentsDelegate: recentDocumentsDelegate)))
        main.addItem(submenuItem(editMenu()))
        main.addItem(submenuItem(viewMenu()))
        main.addItem(submenuItem(insertMenu()))
        main.addItem(submenuItem(formatMenu()))
        main.addItem(submenuItem(layoutMenu()))
        main.addItem(submenuItem(referencesMenu()))
        main.addItem(submenuItem(mailingsMenu()))
        main.addItem(submenuItem(reviewMenu()))

        let window = windowMenu()
        main.addItem(submenuItem(window))
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        main.addItem(submenuItem(help))
        NSApp.helpMenu = help
        return main
    }

    // MARK: - Menus

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Wired Paper")
        menu.addItem(item("About Wired Paper", #selector(AppDelegate.showAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        NSApp.servicesMenu = services
        menu.addItem(submenuItem(services))
        menu.addItem(.separator())
        menu.addItem(item("Hide Wired Paper", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Wired Paper", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(recentDocumentsDelegate: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("New from Template…", #selector(AppDelegate.showTemplateChooser(_:)), "n", [.command, .shift]))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))

        let recent = NSMenu(title: "Open Recent")
        recent.delegate = recentDocumentsDelegate
        menu.addItem(submenuItem(recent))

        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:))))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Export…", #selector(DocumentViewController.exportDocument(_:)), "e", [.command, .shift]))
        menu.addItem(item("Export as PDF…", #selector(NSDocument.saveToPDF(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Properties…", #selector(DocumentViewController.showDocumentProperties(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Document Setup…", #selector(DocumentViewController.showDocumentSetup(_:))))
        menu.addItem(item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]))
        menu.addItem(item("Print…", #selector(NSDocument.printDocument(_:)), "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        find.addItem(findItem("Find…", .showFindInterface, "f"))
        find.addItem(findItem("Find and Replace…", .showReplaceInterface, "f", [.command, .option]))
        find.addItem(findItem("Find Next", .nextMatch, "g"))
        find.addItem(findItem("Find Previous", .previousMatch, "g", [.command, .shift]))
        find.addItem(findItem("Use Selection for Find", .setSearchString, "e"))
        find.addItem(findItem("Replace…", .showReplaceInterface, "h", [.control]))
        find.addItem(item("Advanced Find…", #selector(DocumentViewController.showSearchResults(_:)), "f", [.command, .shift]))
        find.addItem(item("Jump to Selection", #selector(NSTextView.centerSelectionInVisibleArea(_:)), "j"))
        menu.addItem(submenuItem(find))

        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"))
        spelling.addItem(item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"))
        spelling.addItem(.separator())
        spelling.addItem(item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))))
        spelling.addItem(item("Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:))))
        spelling.addItem(item("Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))))
        menu.addItem(submenuItem(spelling))

        let substitutions = NSMenu(title: "Substitutions")
        substitutions.addItem(item("Show Substitutions", #selector(NSTextView.orderFrontSubstitutionsPanel(_:))))
        substitutions.addItem(.separator())
        substitutions.addItem(item("Smart Copy/Paste", #selector(NSTextView.toggleSmartInsertDelete(_:))))
        substitutions.addItem(item("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))))
        substitutions.addItem(item("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:))))
        substitutions.addItem(item("Smart Links", #selector(NSTextView.toggleAutomaticLinkDetection(_:))))
        substitutions.addItem(item("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:))))
        menu.addItem(submenuItem(substitutions))

        let transformations = NSMenu(title: "Transformations")
        transformations.addItem(item("Make Upper Case", #selector(NSResponder.uppercaseWord(_:))))
        transformations.addItem(item("Make Lower Case", #selector(NSResponder.lowercaseWord(_:))))
        transformations.addItem(item("Capitalize", #selector(NSResponder.capitalizeWord(_:))))
        menu.addItem(submenuItem(transformations))

        let speech = NSMenu(title: "Speech")
        speech.addItem(item("Start Speaking", #selector(NSTextView.startSpeaking(_:))))
        speech.addItem(item("Stop Speaking", #selector(NSTextView.stopSpeaking(_:))))
        menu.addItem(submenuItem(speech))
        return menu
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")

        // Font
        let font = NSMenu(title: "Font")
        let showFonts = item("Show Fonts", #selector(NSFontManager.orderFrontFontPanel(_:)), "t")
        showFonts.target = NSFontManager.shared
        font.addItem(showFonts)
        font.addItem(item("Bold", #selector(DocumentViewController.formatBold(_:)), "b"))
        font.addItem(item("Italic", #selector(DocumentViewController.formatItalic(_:)), "i"))
        font.addItem(item("Underline", #selector(DocumentViewController.formatUnderline(_:)), "u"))
        font.addItem(item("Double Underline", #selector(DocumentViewController.toggleDoubleUnderline(_:)), "d", [.command, .shift]))
        font.addItem(item("Strikethrough", #selector(DocumentViewController.formatStrikethrough(_:)), "x", [.command, .shift]))
        font.addItem(.separator())
        font.addItem(item("Bigger", #selector(DocumentViewController.increaseFontSize(_:)), ">"))
        font.addItem(item("Smaller", #selector(DocumentViewController.decreaseFontSize(_:)), "<"))
        font.addItem(.separator())
        let baseline = NSMenu(title: "Baseline")
        baseline.addItem(item("Use Default", #selector(NSTextView.unscript(_:))))
        baseline.addItem(item("Superscript", #selector(NSTextView.superscript(_:)), "=", [.command, .shift]))
        baseline.addItem(item("Subscript", #selector(NSTextView.subscript(_:)), "=", [.command, .control]))
        baseline.addItem(item("Raise", #selector(NSTextView.raiseBaseline(_:))))
        baseline.addItem(item("Lower", #selector(NSTextView.lowerBaseline(_:))))
        font.addItem(submenuItem(baseline))

        let changeCase = NSMenu(title: "Change Case")
        for change in CharacterEffects.CaseChange.allCases {
            let caseItem = item(change.displayName, #selector(DocumentViewController.changeCaseFromMenu(_:)))
            caseItem.representedObject = change.rawValue
            changeCase.addItem(caseItem)
        }
        font.addItem(submenuItem(changeCase))
        font.addItem(item("Small Caps", #selector(DocumentViewController.toggleSmallCaps(_:)), "k", [.command, .shift]))
        font.addItem(item("All Caps", #selector(DocumentViewController.toggleAllCaps(_:)), "a", [.command, .shift]))
        font.addItem(item("Hidden", #selector(DocumentViewController.toggleHiddenText(_:)), "h", [.command, .shift]))
        font.addItem(.separator())

        let spacing = NSMenu(title: "Character Spacing")
        for (title, tenths) in [("Condensed by 1 pt", -10), ("Condensed by 0.5 pt", -5), ("Normal", 0), ("Expanded by 0.5 pt", 5), ("Expanded by 1 pt", 10), ("Expanded by 2 pt", 20)] {
            let spacingItem = item(title, #selector(DocumentViewController.setCharacterSpacingFromMenu(_:)))
            spacingItem.tag = tenths
            spacing.addItem(spacingItem)
        }
        font.addItem(submenuItem(spacing))
        let kerning = NSMenu(title: "Kerning")
        kerning.addItem(item("Use Default", #selector(NSTextView.useStandardKerning(_:))))
        kerning.addItem(item("Use None", #selector(NSTextView.turnOffKerning(_:))))
        kerning.addItem(item("Tighten", #selector(NSTextView.tightenKerning(_:))))
        kerning.addItem(item("Loosen", #selector(NSTextView.loosenKerning(_:))))
        font.addItem(submenuItem(kerning))
        let ligatures = NSMenu(title: "Ligatures")
        ligatures.addItem(item("Use Default", #selector(NSTextView.useStandardLigatures(_:))))
        ligatures.addItem(item("Use None", #selector(NSTextView.turnOffLigatures(_:))))
        ligatures.addItem(item("Use All", #selector(NSTextView.useAllLigatures(_:))))
        font.addItem(submenuItem(ligatures))
        let effects = NSMenu(title: "Text Effects")
        for effect in CharacterEffects.Effect.allCases {
            let effectItem = item(effect.displayName, #selector(DocumentViewController.setTextEffectFromMenu(_:)))
            effectItem.representedObject = effect.rawValue
            effects.addItem(effectItem)
        }
        font.addItem(submenuItem(effects))
        font.addItem(.separator())
        font.addItem(item("Show Colors", #selector(NSApplication.orderFrontColorPanel(_:)), "c", [.command, .shift]))
        font.addItem(.separator())
        font.addItem(item("Copy Style", #selector(NSTextView.copyFont(_:)), "c", [.command, .option]))
        font.addItem(item("Paste Style", #selector(NSTextView.pasteFont(_:)), "v", [.command, .option]))
        menu.addItem(submenuItem(font))
        menu.addItem(item("Format Painter", #selector(DocumentViewController.toggleFormatPainter(_:))))

        // Styles (rebuilt for the active document, including custom styles)
        let styles = NSMenu(title: "Styles")
        styles.delegate = stylesMenuController
        stylesMenuController.populate(styles, sheet: .standard)
        menu.addItem(submenuItem(styles))

        let themes = NSMenu(title: "Theme")
        for theme in DocumentTheme.presets {
            let themeItem = item("\(theme.name) (\(theme.headingFont) / \(theme.bodyFont))", #selector(DocumentViewController.applyThemeFromMenu(_:)))
            themeItem.representedObject = theme.id
            themes.addItem(themeItem)
        }
        menu.addItem(submenuItem(themes))
        menu.addItem(.separator())

        // Text color & highlight
        let textColor = NSMenu(title: "Text Color")
        textColor.addItem(item("Automatic", #selector(DocumentViewController.setTextColorFromMenu(_:))))
        textColor.addItem(.separator())
        for swatch in ColorPalettes.namedTextColors {
            let colorItem = item(swatch.name, #selector(DocumentViewController.setTextColorFromMenu(_:)))
            colorItem.representedObject = swatch.color
            colorItem.image = swatchImage(swatch.color)
            textColor.addItem(colorItem)
        }
        textColor.addItem(.separator())
        textColor.addItem(item("More Colors…", #selector(NSApplication.orderFrontColorPanel(_:))))
        menu.addItem(submenuItem(textColor))

        let highlight = NSMenu(title: "Highlight")
        highlight.addItem(item("No Highlight", #selector(DocumentViewController.setHighlightFromMenu(_:))))
        highlight.addItem(.separator())
        for swatch in ColorPalettes.namedHighlightColors {
            let colorItem = item(swatch.name, #selector(DocumentViewController.setHighlightFromMenu(_:)))
            colorItem.representedObject = swatch.color
            colorItem.image = swatchImage(swatch.color)
            highlight.addItem(colorItem)
        }
        menu.addItem(submenuItem(highlight))
        menu.addItem(.separator())

        // Alignment
        let alignment = NSMenu(title: "Alignment")
        alignment.addItem(item("Align Left", #selector(NSText.alignLeft(_:)), "{"))
        alignment.addItem(item("Center", #selector(NSText.alignCenter(_:)), "|"))
        alignment.addItem(item("Justify", #selector(NSTextView.alignJustified(_:))))
        alignment.addItem(item("Align Right", #selector(NSText.alignRight(_:)), "}"))
        menu.addItem(submenuItem(alignment))

        // Lists
        let lists = NSMenu(title: "Lists")
        lists.addItem(item("Bulleted List", #selector(DocumentViewController.toggleBulletList(_:)), "l", [.command, .shift]))
        lists.addItem(item("Numbered List", #selector(DocumentViewController.toggleNumberList(_:)), "l", [.command, .option]))
        let bulletStyles = NSMenu(title: "Bullet Style")
        for style in ListFormatter.bulletStyles {
            let styleItem = item(style.name, #selector(DocumentViewController.applyListStyleFromMenu(_:)))
            styleItem.representedObject = style.format
            bulletStyles.addItem(styleItem)
        }
        lists.addItem(submenuItem(bulletStyles))
        let numberStyles = NSMenu(title: "Numbering Style")
        for style in ListFormatter.numberStyles {
            let styleItem = item(style.name, #selector(DocumentViewController.applyListStyleFromMenu(_:)))
            styleItem.representedObject = style.format
            numberStyles.addItem(styleItem)
        }
        lists.addItem(submenuItem(numberStyles))
        lists.addItem(.separator())
        lists.addItem(item("Increase List Level", #selector(DocumentViewController.increaseListLevel(_:))))
        lists.addItem(item("Decrease List Level", #selector(DocumentViewController.decreaseListLevel(_:))))
        lists.addItem(.separator())
        lists.addItem(item("Restart Numbering", #selector(DocumentViewController.restartNumbering(_:))))
        lists.addItem(item("Continue Numbering", #selector(DocumentViewController.continueNumbering(_:))))
        lists.addItem(item("Set Numbering Value…", #selector(DocumentViewController.setNumberingValue(_:))))
        menu.addItem(submenuItem(lists))

        // Paragraph
        let paragraph = NSMenu(title: "Paragraph")
        paragraph.addItem(item("Paragraph Options…", #selector(DocumentViewController.showParagraphOptions(_:)), "m", [.command, .option]))
        paragraph.addItem(item("Tabs…", #selector(DocumentViewController.showTabsSheet(_:))))
        paragraph.addItem(item("Borders and Shading…", #selector(DocumentViewController.showBordersAndShading(_:))))
        paragraph.addItem(.separator())
        paragraph.addItem(item("Increase Indent", #selector(DocumentViewController.indentMore(_:)), "]"))
        paragraph.addItem(item("Decrease Indent", #selector(DocumentViewController.indentLess(_:)), "["))
        paragraph.addItem(.separator())
        for spacing in LineSpacingOption.all {
            let spacingItem = item("Line Spacing \(spacing.title)", #selector(DocumentViewController.setLineSpacingFromMenu(_:)))
            spacingItem.tag = spacing.tag
            paragraph.addItem(spacingItem)
        }
        paragraph.addItem(.separator())
        for (title, token) in [("Keep with Next", ParagraphFlags.keepWithNext), ("Keep Lines Together", ParagraphFlags.keepTogether), ("Page Break Before", ParagraphFlags.pageBreakBefore)] {
            let flagItem = item(title, #selector(DocumentViewController.toggleParagraphFlagFromMenu(_:)))
            flagItem.representedObject = token
            paragraph.addItem(flagItem)
        }
        menu.addItem(submenuItem(paragraph))
        menu.addItem(.separator())

        // Table
        menu.addItem(submenuItem(tableMenu()))
        menu.addItem(submenuItem(pictureMenu()))
        menu.addItem(item("Edit Object…", #selector(DocumentViewController.editSelectedObject(_:)), "e", [.command, .option]))
        return menu
    }

    private static func tableMenu() -> NSMenu {
        let table = NSMenu(title: "Table")
        table.addItem(item("Insert Table…", #selector(DocumentViewController.showInsertTableSheet(_:))))
        table.addItem(item("Convert Text to Table", #selector(DocumentViewController.convertTextToTable(_:))))
        table.addItem(item("Convert Table to Text", #selector(DocumentViewController.convertTableToText(_:))))
        table.addItem(.separator())
        table.addItem(item("Insert Row Above", #selector(DocumentViewController.insertRowAbove(_:))))
        table.addItem(item("Insert Row Below", #selector(DocumentViewController.insertRowBelow(_:))))
        table.addItem(item("Insert Column Left", #selector(DocumentViewController.insertColumnLeft(_:))))
        table.addItem(item("Insert Column Right", #selector(DocumentViewController.insertColumnRight(_:))))
        table.addItem(.separator())
        table.addItem(item("Delete Row", #selector(DocumentViewController.deleteTableRow(_:))))
        table.addItem(item("Delete Column", #selector(DocumentViewController.deleteTableColumn(_:))))
        table.addItem(item("Delete Table", #selector(DocumentViewController.deleteTable(_:))))
        table.addItem(.separator())
        table.addItem(item("Select Table", #selector(DocumentViewController.selectTable(_:))))
        table.addItem(item("Merge Cells", #selector(DocumentViewController.mergeTableCells(_:))))
        table.addItem(item("Split Cell", #selector(DocumentViewController.splitTableCell(_:))))
        table.addItem(item("Distribute Columns Evenly", #selector(DocumentViewController.distributeTableColumns(_:))))
        table.addItem(.separator())
        table.addItem(item("Sort Ascending", #selector(DocumentViewController.sortTableAscending(_:))))
        table.addItem(item("Sort Descending", #selector(DocumentViewController.sortTableDescending(_:))))
        table.addItem(.separator())
        let styles = NSMenu(title: "Table Style")
        for preset in TableStylePreset.allCases {
            let styleItem = item(preset.displayName, #selector(DocumentViewController.applyTableStyleFromMenu(_:)))
            styleItem.representedObject = preset.rawValue
            styles.addItem(styleItem)
        }
        table.addItem(submenuItem(styles))
        let shading = NSMenu(title: "Cell Shading")
        let none = item("No Shading", #selector(DocumentViewController.setCellShadingFromMenu(_:)))
        shading.addItem(none)
        for (name, hex) in [("Teal", "#D7ECEF"), ("Gray", "#EEEEEE"), ("Yellow", "#FFF4C2"), ("Green", "#DDF2DA"), ("Blue", "#DCE8FA"), ("Rose", "#F8DDE1")] {
            let color = NSColor(hex: hex)!
            let shadeItem = item(name, #selector(DocumentViewController.setCellShadingFromMenu(_:)))
            shadeItem.representedObject = color
            shadeItem.image = swatchImage(color)
            shading.addItem(shadeItem)
        }
        table.addItem(submenuItem(shading))
        let alignment = NSMenu(title: "Cell Alignment")
        for (title, value) in [("Top", NSTextBlock.VerticalAlignment.topAlignment), ("Middle", .middleAlignment), ("Bottom", .bottomAlignment)] {
            let alignItem = item(title, #selector(DocumentViewController.setCellAlignmentFromMenu(_:)))
            alignItem.tag = Int(value.rawValue)
            alignment.addItem(alignItem)
        }
        table.addItem(submenuItem(alignment))
        table.addItem(.separator())
        table.addItem(item("Formula…", #selector(DocumentViewController.insertTableFormulaPrompt(_:))))
        table.addItem(item("Table Properties…", #selector(NSTextView.orderFrontTablePanel(_:))))
        return table
    }

    private static func pictureMenu() -> NSMenu {
        let picture = NSMenu(title: "Picture")
        picture.addItem(item("Format Picture…", #selector(DocumentViewController.showPictureFormatSheet(_:))))
        picture.addItem(item("Alt Text…", #selector(DocumentViewController.editAltText(_:))))
        picture.addItem(.separator())
        picture.addItem(item("Rotate Right 90°", #selector(DocumentViewController.rotatePictureRight(_:))))
        picture.addItem(item("Rotate Left 90°", #selector(DocumentViewController.rotatePictureLeft(_:))))
        picture.addItem(item("Flip Horizontal", #selector(DocumentViewController.flipPictureHorizontal(_:))))
        picture.addItem(item("Flip Vertical", #selector(DocumentViewController.flipPictureVertical(_:))))
        picture.addItem(.separator())
        picture.addItem(item("Remove Background", #selector(DocumentViewController.removePictureBackground(_:))))
        return picture
    }

    private static func referencesMenu() -> NSMenu {
        let menu = NSMenu(title: "References")
        menu.addItem(item("Table of Contents", #selector(DocumentViewController.insertTableOfContents(_:))))
        menu.addItem(item("Update Tables", #selector(DocumentViewController.updateTableOfContents(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Insert Footnote", #selector(DocumentViewController.insertFootnote(_:)), "f", [.command, .option, .shift]))
        menu.addItem(item("Insert Endnote", #selector(DocumentViewController.insertEndnote(_:)), "e", [.command, .option, .shift]))
        menu.addItem(item("Show Notes", #selector(DocumentViewController.showNotesPane(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Citations & Sources…", #selector(DocumentViewController.showCitationsPane(_:))))
        let style = NSMenu(title: "Citation Style")
        for citationStyle in CitationStyle.allCases {
            let styleItem = item(citationStyle.displayName, #selector(DocumentViewController.setCitationStyleFromMenu(_:)))
            styleItem.representedObject = citationStyle.rawValue
            style.addItem(styleItem)
        }
        menu.addItem(submenuItem(style))
        menu.addItem(item("Bibliography", #selector(DocumentViewController.insertBibliography(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Insert Caption…", #selector(DocumentViewController.showCaptionSheet(_:))))
        let figures = NSMenu(title: "Table of Figures")
        for label in EditorController.captionLabels {
            let figureItem = item("List of \(label)s", #selector(DocumentViewController.insertTableOfFiguresFromMenu(_:)))
            figureItem.representedObject = label
            figures.addItem(figureItem)
        }
        menu.addItem(submenuItem(figures))
        menu.addItem(item("Cross-reference…", #selector(DocumentViewController.showCrossReferenceSheet(_:))))
        menu.addItem(item("Bookmarks…", #selector(DocumentViewController.showBookmarkSheet(_:)), "b", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Mark Index Entry…", #selector(DocumentViewController.showMarkIndexEntry(_:)), "x", [.command, .option, .shift]))
        menu.addItem(item("Insert Index", #selector(DocumentViewController.insertIndex(_:))))
        return menu
    }

    private static func mailingsMenu() -> NSMenu {
        let menu = NSMenu(title: "Mailings")
        menu.addItem(item("Envelopes…", #selector(DocumentViewController.showEnvelopes(_:))))
        menu.addItem(item("Labels…", #selector(DocumentViewController.showLabels(_:))))
        menu.addItem(.separator())
        let recipients = NSMenu(title: "Select Recipients")
        recipients.addItem(item("Use an Existing List…", #selector(DocumentViewController.selectRecipientsFromFile(_:))))
        recipients.addItem(item("Type a New List…", #selector(DocumentViewController.editRecipients(_:))))
        menu.addItem(submenuItem(recipients))
        menu.addItem(item("Edit Recipient List…", #selector(DocumentViewController.editRecipients(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Address Block", #selector(DocumentViewController.insertAddressBlock(_:))))
        menu.addItem(item("Greeting Line", #selector(DocumentViewController.insertGreetingLine(_:))))
        menu.addItem(item("Preview Results", #selector(DocumentViewController.toggleMergePreview(_:))))
        menu.addItem(.separator())
        let finish = NSMenu(title: "Finish & Merge")
        finish.addItem(item("Edit Individual Documents…", #selector(DocumentViewController.finishMergeEditDocuments(_:))))
        finish.addItem(item("Print Documents…", #selector(DocumentViewController.finishMergePrint(_:))))
        finish.addItem(item("Save as PDF…", #selector(DocumentViewController.finishMergePDF(_:))))
        menu.addItem(submenuItem(finish))
        menu.addItem(item("Remove Recipients (Normal Document)", #selector(DocumentViewController.clearMailMerge(_:))))
        return menu
    }

    private static func reviewMenu() -> NSMenu {
        let menu = NSMenu(title: "Review")
        menu.addItem(item("Editor", #selector(DocumentViewController.showEditorPane(_:))))
        menu.addItem(item("Spelling & Grammar", #selector(NSText.showGuessPanel(_:))))
        menu.addItem(item("Word Count…", #selector(DocumentViewController.showWordCount(_:)), "g", [.command, .shift]))
        menu.addItem(item("Look Up", #selector(DocumentViewController.lookUpSelection(_:)), "d", [.command, .control]))
        menu.addItem(item("Check Accessibility…", #selector(DocumentViewController.checkAccessibility(_:))))
        menu.addItem(.separator())
        menu.addItem(item("New Comment", #selector(DocumentViewController.newComment(_:)), "a", [.command, .option]))
        menu.addItem(item("Delete Comment", #selector(DocumentViewController.deleteCurrentComment(_:))))
        menu.addItem(item("Previous Comment", #selector(DocumentViewController.previousComment(_:))))
        menu.addItem(item("Next Comment", #selector(DocumentViewController.nextComment(_:))))
        menu.addItem(item("Show Comments", #selector(DocumentViewController.showCommentsPane(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Track Changes", #selector(DocumentViewController.toggleTrackChanges(_:)), "e", [.command, .shift]))
        let markup = NSMenu(title: "Markup")
        for mode in MarkupMode.allCases {
            let modeItem = item(mode.displayName, #selector(DocumentViewController.setMarkupModeFromMenu(_:)))
            modeItem.representedObject = mode.rawValue
            markup.addItem(modeItem)
        }
        menu.addItem(submenuItem(markup))
        menu.addItem(item("Accept Change", #selector(DocumentViewController.acceptChange(_:))))
        menu.addItem(item("Reject Change", #selector(DocumentViewController.rejectChange(_:))))
        menu.addItem(item("Accept All Changes", #selector(DocumentViewController.acceptAllChanges(_:))))
        menu.addItem(item("Reject All Changes", #selector(DocumentViewController.rejectAllChanges(_:))))
        menu.addItem(item("Previous Change", #selector(DocumentViewController.previousChange(_:))))
        menu.addItem(item("Next Change", #selector(DocumentViewController.nextChange(_:))))
        menu.addItem(item("Reviewing Pane", #selector(DocumentViewController.showReviewPane(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Restrict Editing…", #selector(DocumentViewController.showRestrictEditing(_:))))
        menu.addItem(item("Stop Protection…", #selector(DocumentViewController.stopProtection(_:))))
        menu.addItem(item("Mark as Final", #selector(DocumentViewController.markAsFinal(_:))))
        return menu
    }

    private static func layoutMenu() -> NSMenu {
        let menu = NSMenu(title: "Layout")

        let margins = NSMenu(title: "Margins")
        for (title, tag) in [("Normal (1\")", 0), ("Narrow (0.5\")", 1), ("Moderate", 2), ("Wide", 3)] {
            let marginItem = item(title, #selector(DocumentViewController.setMarginsFromMenu(_:)))
            marginItem.tag = tag
            margins.addItem(marginItem)
        }
        margins.addItem(.separator())
        margins.addItem(item("Custom Margins…", #selector(DocumentViewController.showDocumentSetup(_:))))
        menu.addItem(submenuItem(margins))

        let orientation = NSMenu(title: "Orientation")
        let portrait = item("Portrait", #selector(DocumentViewController.setOrientationFromMenu(_:)))
        portrait.tag = 0
        let landscape = item("Landscape", #selector(DocumentViewController.setOrientationFromMenu(_:)))
        landscape.tag = 1
        orientation.addItem(portrait)
        orientation.addItem(landscape)
        menu.addItem(submenuItem(orientation))

        let size = NSMenu(title: "Size")
        for preset in PaperPreset.allCases {
            let sizeItem = item("\(preset.displayName) (\(preset.dimensionsDescription))", #selector(DocumentViewController.setPaperFromMenu(_:)))
            sizeItem.representedObject = preset.rawValue
            size.addItem(sizeItem)
        }
        size.addItem(.separator())
        size.addItem(item("Custom Size…", #selector(DocumentViewController.showDocumentSetup(_:))))
        menu.addItem(submenuItem(size))

        let columns = NSMenu(title: "Columns")
        for (title, count) in [("One", 1), ("Two", 2), ("Three", 3), ("Four", 4)] {
            let columnItem = item(title, #selector(DocumentViewController.setColumnsFromMenu(_:)))
            columnItem.tag = count
            columns.addItem(columnItem)
        }
        columns.addItem(.separator())
        columns.addItem(item("More Columns…", #selector(DocumentViewController.showColumnsSheet(_:))))
        menu.addItem(submenuItem(columns))

        let breaks = NSMenu(title: "Breaks")
        breaks.addItem(item("Page Break", #selector(DocumentViewController.insertPageBreakAction(_:))))
        breaks.addItem(item("Column Break", #selector(DocumentViewController.insertColumnBreak(_:)), "\r", [.command, .shift]))
        menu.addItem(submenuItem(breaks))
        menu.addItem(.separator())

        let lineNumbers = NSMenu(title: "Line Numbers")
        for (title, tag) in [("None", 0), ("Continuous", 1), ("Restart Each Page", 2)] {
            let numberItem = item(title, #selector(DocumentViewController.setLineNumbersFromMenu(_:)))
            numberItem.tag = tag
            lineNumbers.addItem(numberItem)
        }
        menu.addItem(submenuItem(lineNumbers))
        menu.addItem(item("Automatic Hyphenation", #selector(DocumentViewController.toggleHyphenation(_:))))
        menu.addItem(item("Widow/Orphan Control", #selector(DocumentViewController.toggleWidowControl(_:))))
        let vertical = NSMenu(title: "Vertical Alignment")
        for alignment in VerticalPageAlignment.allCases where alignment != .justified {
            let alignmentItem = item(alignment.displayName, #selector(DocumentViewController.setVerticalAlignmentFromMenu(_:)))
            alignmentItem.representedObject = alignment.rawValue
            vertical.addItem(alignmentItem)
        }
        menu.addItem(submenuItem(vertical))
        menu.addItem(.separator())

        let pageColor = NSMenu(title: "Page Color")
        pageColor.addItem(item("No Color", #selector(DocumentViewController.setPageColorFromMenu(_:))))
        pageColor.addItem(.separator())
        for (name, hex) in [("Ivory", 0xFFFBEF), ("Cream", 0xFBF3DD), ("Mist", 0xEEF4F6), ("Mint", 0xEEF7EF), ("Blush", 0xFBEEF0), ("Lavender", 0xF1EEFA), ("Slate", 0x2B2F36)] {
            let colorItem = item(name, #selector(DocumentViewController.setPageColorFromMenu(_:)))
            let color = ColorPalettes.hex(UInt32(hex))
            colorItem.representedObject = color
            colorItem.image = swatchImage(color)
            pageColor.addItem(colorItem)
        }
        menu.addItem(submenuItem(pageColor))
        menu.addItem(item("Watermark…", #selector(DocumentViewController.showWatermarkSheet(_:))))
        menu.addItem(item("Page Borders…", #selector(DocumentViewController.showPageBorderSheet(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Header & Footer…", #selector(DocumentViewController.showHeaderFooterSheet(_:))))
        let pageNumbers = NSMenu(title: "Page Numbers")
        let bottom = item("Bottom of Page", #selector(DocumentViewController.insertPageNumbers(_:)))
        bottom.representedObject = "footer"
        let pageOf = item("Bottom: Page X of Y", #selector(DocumentViewController.insertPageNumbers(_:)))
        pageOf.representedObject = "footer"
        pageOf.tag = 1
        let top = item("Top of Page", #selector(DocumentViewController.insertPageNumbers(_:)))
        top.representedObject = "header"
        pageNumbers.addItem(bottom)
        pageNumbers.addItem(pageOf)
        pageNumbers.addItem(top)
        menu.addItem(submenuItem(pageNumbers))
        menu.addItem(.separator())
        menu.addItem(item("Document Setup…", #selector(DocumentViewController.showDocumentSetup(_:))))
        return menu
    }

    private static func insertMenu() -> NSMenu {
        let menu = NSMenu(title: "Insert")
        menu.addItem(item("Image…", #selector(DocumentViewController.insertImageFromFile(_:)), "i", [.command, .option]))
        menu.addItem(item("Table…", #selector(DocumentViewController.showInsertTableSheet(_:))))
        let charts = NSMenu(title: "Chart")
        for type in ChartType.allCases {
            let chartItem = item(type.displayName, #selector(DocumentViewController.insertChart(_:)))
            chartItem.representedObject = type.rawValue
            chartItem.image = NSImage(systemSymbolName: type.symbol, accessibilityDescription: nil)
            charts.addItem(chartItem)
        }
        menu.addItem(submenuItem(charts))
        let diagrams = NSMenu(title: "Diagram")
        for type in DiagramType.allCases {
            let diagramItem = item(type.displayName, #selector(DocumentViewController.insertDiagram(_:)))
            diagramItem.representedObject = type.rawValue
            diagrams.addItem(diagramItem)
        }
        menu.addItem(submenuItem(diagrams))
        menu.addItem(item("Equation…", #selector(DocumentViewController.insertEquation(_:)), "=", [.control, .option]))
        menu.addItem(.separator())
        let shapes = NSMenu(title: "Shape")
        for kind in ShapeKind.allCases where kind != .textBox && kind != .wordArt && kind != .icon {
            let shapeItem = item(kind.displayName, #selector(DocumentViewController.insertShape(_:)))
            shapeItem.representedObject = kind.rawValue
            shapeItem.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
            shapes.addItem(shapeItem)
        }
        menu.addItem(submenuItem(shapes))
        menu.addItem(item("Text Box", #selector(DocumentViewController.insertTextBox(_:))))
        menu.addItem(item("Decorative Text…", #selector(DocumentViewController.insertWordArt(_:))))
        menu.addItem(item("Icon…", #selector(DocumentViewController.insertIcon(_:))))
        menu.addItem(item("Drawing…", #selector(DocumentViewController.insertDrawing(_:))))
        menu.addItem(item("Spreadsheet…", #selector(DocumentViewController.insertSpreadsheet(_:))))
        menu.addItem(item("Signature Line…", #selector(DocumentViewController.insertSignatureLine(_:))))
        let controls = NSMenu(title: "Form Control")
        controls.addItem(item("Check Box", #selector(DocumentViewController.insertCheckboxControl(_:))))
        controls.addItem(item("Drop-Down List…", #selector(DocumentViewController.insertDropdownControl(_:))))
        controls.addItem(item("Date Picker", #selector(DocumentViewController.insertDatePickerControl(_:))))
        menu.addItem(submenuItem(controls))
        menu.addItem(.separator())
        menu.addItem(item("Page Break", #selector(DocumentViewController.insertPageBreakAction(_:)), "\r"))
        menu.addItem(item("Horizontal Line", #selector(DocumentViewController.insertHorizontalRule(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Link…", #selector(DocumentViewController.showLinkSheet(_:)), "k"))
        menu.addItem(item("Date and Time", #selector(DocumentViewController.insertCurrentDate(_:))))
        menu.addItem(.separator())
        let fields = NSMenu(title: "Field")
        for kind in [FieldKind.page, .numPages, .date, .time, .title, .author, .subject, .filename] {
            let fieldItem = item(kind.displayName, #selector(DocumentViewController.insertFieldFromMenu(_:)))
            fieldItem.representedObject = kind.rawValue
            fields.addItem(fieldItem)
        }
        fields.addItem(.separator())
        fields.addItem(item("Field…", #selector(DocumentViewController.showInsertFieldSheet(_:))))
        menu.addItem(submenuItem(fields))
        menu.addItem(item("Update Fields", #selector(DocumentViewController.updateFields(_:)), String(UnicodeScalar(NSF9FunctionKey)!), []))
        menu.addItem(item("Header & Footer…", #selector(DocumentViewController.showHeaderFooterSheet(_:))))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Zoom In", #selector(DocumentViewController.zoomInDocument(_:)), "="))
        menu.addItem(item("Zoom Out", #selector(DocumentViewController.zoomOutDocument(_:)), "-"))
        menu.addItem(item("Actual Size", #selector(DocumentViewController.zoomDocumentToActualSize(_:)), "0"))
        menu.addItem(item("Fit Page Width", #selector(DocumentViewController.zoomDocumentToPageWidth(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option]))
        menu.addItem(item("Customize Toolbar…", #selector(NSWindow.runToolbarCustomizationPalette(_:))))
        menu.addItem(item("Hide Ribbon", #selector(DocumentViewController.toggleFormatBar(_:)), "r", [.command, .option, .shift]))
        menu.addItem(item("Collapse Ribbon", #selector(DocumentViewController.toggleRibbonCollapsed(_:)), String(UnicodeScalar(NSF1FunctionKey)!), [.command]))
        menu.addItem(item("Show Ruler", #selector(DocumentViewController.toggleRulerVisibility(_:)), "r"))
        menu.addItem(item("Hide Status Bar", #selector(DocumentViewController.toggleStatusBar(_:))))
        menu.addItem(item("Show Hidden Text", #selector(DocumentViewController.toggleShowHiddenText(_:))))
        menu.addItem(item("Show Formatting Marks", #selector(DocumentViewController.toggleFormattingMarks(_:)), "8"))
        menu.addItem(item("Focus", #selector(DocumentViewController.toggleFocusMode(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Navigation Pane", #selector(DocumentViewController.toggleNavigationPane(_:)), "n", [.command, .option]))
        menu.addItem(item("Comments", #selector(DocumentViewController.showCommentsPane(_:)), "c", [.command, .option, .shift]))
        menu.addItem(item("Reviewing Pane", #selector(DocumentViewController.showReviewPane(_:)), "r", [.command, .option]))
        menu.addItem(item("Notes", #selector(DocumentViewController.showNotesPane(_:))))
        menu.addItem(item("Citations", #selector(DocumentViewController.showCitationsPane(_:))))
        menu.addItem(item("Styles Pane", #selector(DocumentViewController.showStylesPane(_:)), "t", [.command, .option, .shift]))
        menu.addItem(item("Editor", #selector(DocumentViewController.showEditorPane(_:)), "7", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    // MARK: - Helpers

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        return item
    }

    private static func findItem(
        _ title: String,
        _ action: NSTextFinder.Action,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = item(title, #selector(NSResponder.performTextFinderAction(_:)), key, modifiers)
        item.tag = action.rawValue
        return item
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func swatchImage(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
}

/// Rebuilds Format ▸ Styles for the active document (built-in and custom styles).
final class StylesMenuController: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let document = (NSApp.mainWindow?.windowController as? DocumentWindowController)?.document as? WiredPaperDocument
        populate(menu, sheet: document?.styleSheet ?? .standard)
    }

    func populate(_ menu: NSMenu, sheet: StyleSheet) {
        menu.removeAllItems()
        for style in sheet.allStyles {
            let styleItem = NSMenuItem(title: style.name, action: #selector(DocumentViewController.applyStyleFromMenu(_:)), keyEquivalent: "")
            styleItem.representedObject = style.id
            if let kind = ParagraphStyleKind(rawValue: style.id), let key = kind.keyEquivalent {
                styleItem.keyEquivalent = key
                styleItem.keyEquivalentModifierMask = [.command, .option]
            }
            if style.id == sheet.customStyles.first?.id {
                menu.addItem(.separator())
            }
            menu.addItem(styleItem)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Manage Styles…", action: #selector(DocumentViewController.showStylesManager(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear Formatting", action: #selector(DocumentViewController.clearAllFormatting(_:)), keyEquivalent: ""))
    }
}

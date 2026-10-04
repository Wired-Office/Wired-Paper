import AppKit

/// Owns the pages of a document's layout: one text container per column per
/// page, grown and trimmed as text flows. Used both on screen (with views, laid
/// out lazily) and for printing (paginated synchronously).
///
/// After layout settles it applies pagination rules — keep with next, keep lines
/// together, widow/orphan control — by pushing paragraphs to the next container,
/// collapses remaining columns after a page break, reserves space for footnotes
/// and computes vertical page alignment.
final class PaginationEngine: NSObject, NSLayoutManagerDelegate {
    let layoutManager: WPLayoutManager
    let policy = LayoutPolicy()
    private(set) var geometry: PageGeometry
    var verticalAlignment: VerticalPageAlignment = .top
    var widowControl = true
    /// On screen, pages are added from layout callbacks; printing paginates explicitly.
    var autoPaginate = true
    /// Height to keep free at the bottom of a page (footnotes), by page index.
    var reserveProvider: ((Int) -> CGFloat)?

    private(set) var pageCount = 0
    private(set) var verticalOffsets: [Int: CGFloat] = [:]
    private(set) var layoutGeneration = 0
    private var reserves: [Int: CGFloat] = [:]
    private var collapsedFrom: [Int: Int] = [:]

    var onPageAdded: ((Int) -> Void)?
    var onPageRemoved: ((Int) -> Void)?
    var onGeometryChanged: (() -> Void)?
    var onLayoutSettled: (() -> Void)?

    private var isChangingPages = false
    private var checkScheduled = false
    private var settleScheduled = false
    private var settlePasses = 0
    private var allowReserveShrink = true

    init(layoutManager: WPLayoutManager, geometry: PageGeometry) {
        self.layoutManager = layoutManager
        self.geometry = geometry
        super.init()
        layoutManager.delegate = self
        layoutManager.columnsPerPage = geometry.columns
        layoutManager.pageCountProvider = { [weak self] in max(self?.pageCount ?? 1, 1) }
    }

    var columns: Int { max(geometry.columns, 1) }

    // MARK: Queries

    func containers(onPage page: Int) -> [NSTextContainer] {
        let all = layoutManager.textContainers
        let start = page * columns
        guard start < all.count else { return [] }
        return Array(all[start..<min(start + columns, all.count)])
    }

    func page(of container: NSTextContainer) -> Int? {
        layoutManager.pageIndex(of: container)
    }

    func container(forCharacterAt index: Int) -> NSTextContainer? {
        guard let storage = layoutManager.textStorage else { return nil }
        if index >= storage.length {
            if let extra = layoutManager.extraLineFragmentTextContainer { return extra }
            guard storage.length > 0 else { return layoutManager.textContainers.first }
            return container(forCharacterAt: storage.length - 1)
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil)
    }

    func page(forCharacterAt index: Int) -> Int {
        container(forCharacterAt: index).flatMap(page(of:)) ?? 0
    }

    func characterRange(onPage page: Int) -> NSRange {
        var result: NSRange?
        for container in containers(onPage: page) {
            let glyphs = layoutManager.glyphRange(for: container)
            guard glyphs.length > 0 else { continue }
            let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            result = result.map { NSUnionRange($0, characters) } ?? characters
        }
        return result ?? NSRange(location: 0, length: 0)
    }

    func containerSize(page: Int, column: Int) -> CGSize {
        let rect = geometry.columnRects()[min(column, columns - 1)]
        var height = rect.height - (reserves[page] ?? 0)
        if let first = collapsedFrom[page], column >= first { height = 0 }
        return CGSize(width: rect.width, height: max(height, 0))
    }

    // MARK: Pages

    func setGeometry(_ newGeometry: PageGeometry) {
        guard newGeometry != geometry else { return }
        let columnsChanged = newGeometry.columns != geometry.columns
        geometry = newGeometry
        layoutManager.columnsPerPage = columns
        resetPaginationRules()
        if columnsChanged {
            collapsedFrom = [:]
            rebuild()
        } else {
            applyContainerSizes()
        }
        onGeometryChanged?()
    }

    func addPage() {
        guard !isChangingPages else {
            scheduleOverflowCheck()
            return
        }
        isChangingPages = true
        defer { isChangingPages = false }

        let page = pageCount
        for column in 0..<columns {
            let container = NSTextContainer(size: containerSize(page: page, column: column))
            container.widthTracksTextView = false
            container.heightTracksTextView = false
            layoutManager.addTextContainer(container)
        }
        pageCount += 1
        onPageAdded?(page)
    }

    func removeLastPage() {
        guard !isChangingPages else {
            scheduleOverflowCheck()
            return
        }
        guard pageCount > 1 else { return }
        isChangingPages = true
        defer { isChangingPages = false }

        let page = pageCount - 1
        onPageRemoved?(page)
        for _ in 0..<columns where !layoutManager.textContainers.isEmpty {
            layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
        }
        pageCount -= 1
        reserves[page] = nil
        collapsedFrom[page] = nil
        verticalOffsets[page] = nil
    }

    /// Removes every page and starts over (column count changed).
    func rebuild() {
        isChangingPages = true
        while pageCount > 0 {
            onPageRemoved?(pageCount - 1)
            pageCount -= 1
        }
        while !layoutManager.textContainers.isEmpty {
            layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
        }
        reserves = [:]
        verticalOffsets = [:]
        isChangingPages = false
        addPage()
    }

    private func applyContainerSizes() {
        for page in 0..<pageCount {
            for (column, container) in containers(onPage: page).enumerated() {
                let size = containerSize(page: page, column: column)
                if container.size != size { container.size = size }
            }
        }
    }

    // MARK: Text changes

    /// Called before the text changes so pagination decisions after the edit are recomputed.
    func noteTextChanged(at location: Int) {
        let stale = policy.dynamicBreaks.filter { $0 >= location - 1 }
        if !stale.isEmpty {
            policy.dynamicBreaks.subtract(stale)
            invalidateBreaks(stale)
        }
        settlePasses = 0
        allowReserveShrink = true
    }

    /// Pagination decisions depend on geometry; start over after it changes.
    func resetPaginationRules() {
        let stale = policy.dynamicBreaks
        policy.dynamicBreaks = []
        invalidateBreaks(stale)
        settlePasses = 0
        allowReserveShrink = true
    }

    func invalidateAllGlyphs() {
        guard let storage = layoutManager.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        layoutManager.invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
    }

    private func invalidateBreaks(_ starts: Set<Int>) {
        guard let storage = layoutManager.textStorage else { return }
        for start in starts where start > 0 && start <= storage.length {
            let range = NSRange(location: start - 1, length: 1)
            layoutManager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: NSRange(location: start - 1, length: storage.length - start + 1), actualCharacterRange: nil)
        }
    }

    // MARK: NSLayoutManagerDelegate

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        guard autoPaginate else { return }
        let all = layoutManager.textContainers
        if !layoutFinishedFlag || textContainer == nil {
            guard let last = all.last else { return }
            if textContainer === last || textContainer == nil {
                if layoutManager.glyphRange(for: last).length > 0 || textContainer == nil || collapsedFrom[pageCount - 1] != nil {
                    addPage()
                }
            }
        } else if let textContainer, let lastUsed = all.firstIndex(where: { $0 === textContainer }) {
            let lastUsedPage = lastUsed / columns
            while pageCount - 1 > lastUsedPage {
                removeLastPage()
                if isChangingPages { break }
            }
            scheduleSettle()
        }
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        policy.generateGlyphs(layoutManager, glyphs: glyphs, properties: props, characterIndexes: charIndexes, font: aFont, glyphRange: glyphRange)
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        policy.controlCharacterAction(layoutManager, proposed: action, at: charIndex)
    }

    // MARK: Settling

    private func scheduleOverflowCheck() {
        guard !checkScheduled else { return }
        checkScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.checkScheduled = false
            self.reconcilePageCount()
        }
    }

    private func reconcilePageCount() {
        guard let last = layoutManager.textContainers.last else { return }
        layoutManager.ensureLayout(for: last)
        if hasOverflow() {
            addPage()
            return
        }
        trimEmptyTrailingPages()
    }

    private func hasOverflow() -> Bool {
        guard let last = layoutManager.textContainers.last else { return false }
        let placed = NSMaxRange(layoutManager.glyphRange(for: last))
        return placed < layoutManager.numberOfGlyphs
    }

    private func trimEmptyTrailingPages() {
        while pageCount > 1 {
            let trailing = containers(onPage: pageCount - 1)
            let empty = trailing.allSatisfy { layoutManager.glyphRange(for: $0).length == 0 && layoutManager.extraLineFragmentTextContainer !== $0 }
            guard empty else { break }
            removeLastPage()
        }
    }

    private func scheduleSettle() {
        guard !settleScheduled else { return }
        settleScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settleScheduled = false
            self.settle()
        }
    }

    /// Applies rules after layout; if anything changed, layout runs again and we come back here.
    private func settle() {
        if settlePasses < 6, applyRules() {
            settlePasses += 1
            if let last = layoutManager.textContainers.last { layoutManager.ensureLayout(for: last) }
            return
        }
        settlePasses = 0
        allowReserveShrink = false
        finishSettling()
    }

    private func finishSettling() {
        updateVerticalOffsets()
        layoutGeneration += 1
        onLayoutSettled?()
    }

    /// Returns true when a rule changed the layout.
    private func applyRules() -> Bool {
        var changed = false
        if evaluatePaginationRules() { changed = true }
        if updateCollapsedColumns() { changed = true }
        if updateReserves() { changed = true }
        return changed
    }

    /// Synchronous pagination for printing and export.
    func paginateAll(maxPages: Int = 5000) {
        if pageCount == 0 { addPage() }
        var passes = 0
        while true {
            while pageCount < maxPages {
                guard let last = layoutManager.textContainers.last else { break }
                layoutManager.ensureLayout(for: last)
                guard hasOverflow() else { break }
                let lastPageEmpty = containers(onPage: pageCount - 1).allSatisfy { layoutManager.glyphRange(for: $0).length == 0 }
                if lastPageEmpty && pageCount > 1 && collapsedFrom[pageCount - 1] == nil { break }
                addPage()
            }
            trimEmptyTrailingPages()
            passes += 1
            guard passes < 8, applyRules() else { break }
        }
        updateVerticalOffsets()
        layoutGeneration += 1
    }

    // MARK: Rules

    private func evaluatePaginationRules() -> Bool {
        guard let storage = layoutManager.textStorage, storage.length > 0 else { return false }
        let string = storage.string as NSString
        var added = Set<Int>()

        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { [self] _, content, enclosing, _ in
            let start = enclosing.location
            guard content.length > 0, start > 0, !policy.dynamicBreaks.contains(start) else { return }
            let attributes = storage.attributes(at: content.location, effectiveRange: nil)
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle, !style.textBlocks.isEmpty { return }
            if let previous = storage.attribute(.paragraphStyle, at: start - 1, effectiveRange: nil) as? NSParagraphStyle, !previous.textBlocks.isEmpty { return }
            let flags = FlagTokens.set(attributes[.wpParaFlags])

            let firstGlyph = layoutManager.glyphIndexForCharacter(at: content.location)
            let lastGlyph = layoutManager.glyphIndexForCharacter(at: NSMaxRange(content) - 1)
            guard firstGlyph < layoutManager.numberOfGlyphs, lastGlyph < layoutManager.numberOfGlyphs,
                  let firstContainer = layoutManager.textContainer(forGlyphAt: firstGlyph, effectiveRange: nil),
                  let lastContainer = layoutManager.textContainer(forGlyphAt: lastGlyph, effectiveRange: nil)
            else { return }

            // Already at the top of a column or page: moving wouldn't help.
            let firstLine = layoutManager.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
            if firstLine.minY < 1 { return }

            var needsBreak = false
            if flags.contains(ParagraphFlags.keepWithNext), NSMaxRange(enclosing) < string.length {
                let nextGlyph = layoutManager.glyphIndexForCharacter(at: NSMaxRange(enclosing))
                if nextGlyph < layoutManager.numberOfGlyphs,
                   let nextContainer = layoutManager.textContainer(forGlyphAt: nextGlyph, effectiveRange: nil),
                   nextContainer !== lastContainer {
                    needsBreak = true
                }
            }
            if firstContainer !== lastContainer {
                if flags.contains(ParagraphFlags.keepTogether) {
                    needsBreak = true
                } else if widowControl && !flags.contains(ParagraphFlags.noWidowControl) {
                    let (inFirst, inLast, total) = lineCounts(firstGlyph: firstGlyph, lastGlyph: lastGlyph, first: firstContainer, last: lastContainer)
                    if total >= 2 && (inFirst == 1 || inLast == 1) { needsBreak = true }
                }
            }
            guard needsBreak else { return }
            // Only move paragraphs that fit in an empty container.
            let height = layoutManager.boundingRect(forGlyphRange: NSRange(location: firstGlyph, length: lastGlyph - firstGlyph + 1), in: firstContainer).height
            if height < firstContainer.size.height * 0.8 {
                added.insert(start)
            }
        }

        guard !added.isEmpty else { return false }
        policy.dynamicBreaks.formUnion(added)
        invalidateBreaks(added)
        return true
    }

    private func lineCounts(firstGlyph: Int, lastGlyph: Int, first: NSTextContainer, last: NSTextContainer) -> (Int, Int, Int) {
        var glyph = firstGlyph
        var inFirst = 0, inLast = 0, total = 0
        while glyph <= lastGlyph {
            var lineRange = NSRange()
            _ = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
            let container = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil)
            total += 1
            if container === first { inFirst += 1 }
            if container === last { inLast += 1 }
            glyph = max(NSMaxRange(lineRange), glyph + 1)
        }
        return (inFirst, inLast, total)
    }

    /// With several columns, a page break skips the remaining columns of its page.
    private func updateCollapsedColumns() -> Bool {
        guard columns > 1, let storage = layoutManager.textStorage else {
            if collapsedFrom.isEmpty { return false }
            collapsedFrom = [:]
            applyContainerSizes()
            return true
        }
        var collapsed: [Int: Int] = [:]
        for page in 0..<pageCount {
            let pageContainers = containers(onPage: page)
            for (column, container) in pageContainers.enumerated() where column < columns - 1 {
                let glyphs = layoutManager.glyphRange(for: container)
                guard glyphs.length > 0 else { continue }
                let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                if containsPageBreak(characters, in: storage) {
                    collapsed[page] = column + 1
                    break
                }
            }
            if let existing = collapsedFrom[page], collapsed[page] == nil {
                // Keep a collapse whose break still sits just before the collapsed column.
                let before = pageContainers.indices.contains(existing - 1) ? pageContainers[existing - 1] : nil
                if let before, containsPageBreak(layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(for: before), actualGlyphRange: nil), in: storage) {
                    collapsed[page] = existing
                }
            }
        }
        guard collapsed != collapsedFrom else { return false }
        collapsedFrom = collapsed
        applyContainerSizes()
        return true
    }

    private func containsPageBreak(_ range: NSRange, in storage: NSAttributedString) -> Bool {
        let string = storage.string as NSString
        var index = range.location
        while index < NSMaxRange(range) {
            let character = string.character(at: index)
            if (character == 0x0C || character == 0x0A || character == 0x2029), policy.isPageBreak(at: index, in: storage) {
                return true
            }
            index += 1
        }
        return false
    }

    private func updateReserves() -> Bool {
        guard let reserveProvider else {
            if reserves.isEmpty { return false }
            reserves = [:]
            applyContainerSizes()
            return true
        }
        var changed = false
        for page in 0..<pageCount {
            let wanted = reserveProvider(page).rounded(.up)
            let current = reserves[page] ?? 0
            if wanted > current + 0.5 || (allowReserveShrink && wanted < current - 0.5) {
                reserves[page] = wanted
                changed = true
            }
        }
        if changed { applyContainerSizes() }
        return changed
    }

    private func updateVerticalOffsets() {
        verticalOffsets = [:]
        guard verticalAlignment != .top, columns == 1 else { return }
        for page in 0..<pageCount {
            guard let container = containers(onPage: page).first else { continue }
            let used = layoutManager.usedRect(for: container).height
            let free = max(container.size.height - used, 0)
            switch verticalAlignment {
            case .center: verticalOffsets[page] = floor(free / 2)
            case .bottom: verticalOffsets[page] = floor(free)
            default: break
            }
        }
    }
}

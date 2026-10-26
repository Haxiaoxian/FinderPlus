import FinderPlusCore
import Foundation

/// One row of Finder's sidebar Favorites, as read from `LSSharedFileList`.
public struct SidebarRow: Hashable, Identifiable, Sendable {
    /// `LSSharedFileListItemGetID`: stable across processes and in-place updates.
    public var id: UInt32
    public var name: String
    /// Resolved path, or the path the row's bookmark was recorded with when it cannot resolve
    /// (a cloud domain still starting, an unmounted volume).
    public var path: String?
    /// The row's icon override code (`com.apple.LSSharedFileList.OverrideIcon.OSType`), if any.
    public var iconCode: String?
    /// Built-in entries (Recents, AirDrop, Applications…) carry a special identifier and never
    /// draw an override, so they are listed but not offered for icons.
    public var isSpecial: Bool

    public var url: URL? { path.map { URL(fileURLWithPath: $0, isDirectory: true) } }
}

public enum SidebarBackendError: LocalizedError {
    case unavailable
    case operationFailed(String)
    case rowNotFound
    case folderMissing

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The Finder sidebar list API is not available on this version of macOS."
        case .operationFailed(let detail):
            return detail
        case .rowNotFound:
            return "That folder is no longer in Finder's sidebar."
        case .folderMissing:
            return LocalizedText(en: "The folder no longer exists (deleted, renamed or moved).",
                                 zhHans: "文件夹已不存在（可能已被删除、重命名或移动）。",
                                 ko: "폴더가 더 이상 없습니다(삭제, 이름 변경 또는 이동됨).").localized
        }
    }
}

/// Access to Finder's Favorites through `LSSharedFileList`, resolved at run time with `dlsym`.
///
/// The approach (icon override property + Launch Services type declarations) follows
/// SidebarFavorites by Ilya Gusinski (MIT, github.com/ivg-design/SidebarFavorites), including
/// these measured rules:
///   * item references are only valid while their snapshot array is alive;
///   * `kLSSharedFileListItemLast`/`BeforeFirst` are bogus pointers (0x2/0x1) that current macOS
///     dereferences, so anchors are always real rows (or NULL = before the first row);
///   * `LSSharedFileListItemSetProperty` crashes on a NULL value: clearing goes through an
///     in-place re-insert with `propertiesToClear`;
///   * re-inserting a URL the list already holds updates that row in place when anchored after
///     its own predecessor, and an empty display name resets the label, so the current name is
///     always passed back in.
/// FinderPlus never moves rows; it only adds, removes and sets icons.
final class SidebarBackend {
    static let overrideIconKey = "com.apple.LSSharedFileList.OverrideIcon.OSType" as CFString
    static let specialItemKey = "com.apple.LSSharedFileList.SpecialItemIdentifier" as CFString

    private typealias CreateFn = @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    private typealias SnapshotFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt32>?) -> OpaquePointer?
    private typealias CopyFn = @convention(c) (OpaquePointer?) -> OpaquePointer?
    private typealias CopyURLFn = @convention(c) (OpaquePointer?, UInt32, UnsafeMutablePointer<OpaquePointer?>?) -> OpaquePointer?
    private typealias InsertFn = @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?, OpaquePointer?, OpaquePointer?,
                                                 OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    private typealias RemoveFn = @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    private typealias GetIDFn = @convention(c) (OpaquePointer?) -> UInt32
    private typealias CopyPropertyFn = @convention(c) (OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    private typealias SetPropertyFn = @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?) -> Int32

    private let fnCreate: CreateFn
    private let fnSnapshot: SnapshotFn
    private let fnCopyName: CopyFn
    private let fnCopyURL: CopyURLFn
    private let fnInsert: InsertFn
    private let fnRemove: RemoveFn
    private let fnGetID: GetIDFn
    private let fnCopyProperty: CopyPropertyFn
    private let fnSetProperty: SetPropertyFn
    private let fnCopyBookmark: CopyFn?
    private let favoritesListType: OpaquePointer

    /// `nil` when the running macOS no longer exports the API.
    init?() {
        let handle = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let create = symbol("LSSharedFileListCreate", as: CreateFn.self),
              let snapshot = symbol("LSSharedFileListCopySnapshot", as: SnapshotFn.self),
              let copyName = symbol("LSSharedFileListItemCopyDisplayName", as: CopyFn.self),
              let copyURL = symbol("LSSharedFileListItemCopyResolvedURL", as: CopyURLFn.self),
              let insert = symbol("LSSharedFileListInsertItemURL", as: InsertFn.self),
              let remove = symbol("LSSharedFileListItemRemove", as: RemoveFn.self),
              let getID = symbol("LSSharedFileListItemGetID", as: GetIDFn.self),
              let copyProperty = symbol("LSSharedFileListItemCopyProperty", as: CopyPropertyFn.self),
              let setProperty = symbol("LSSharedFileListItemSetProperty", as: SetPropertyFn.self),
              let favoritesPointer = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), "kLSSharedFileListFavoriteItems"),
              let favorites = favoritesPointer.assumingMemoryBound(to: OpaquePointer?.self).pointee
        else { return nil }
        fnCreate = create
        fnSnapshot = snapshot
        fnCopyName = copyName
        fnCopyURL = copyURL
        fnInsert = insert
        fnRemove = remove
        fnGetID = getID
        fnCopyProperty = copyProperty
        fnSetProperty = setProperty
        fnCopyBookmark = symbol("LSSharedFileListItemCopyBookmarkData", as: CopyFn.self)
        favoritesListType = favorites
    }

    // MARK: Reading

    func rows() throws -> [SidebarRow] {
        try withSnapshot { _, items in items.map(row(for:)) }
    }

    // MARK: Writing

    /// Sets the icon code on an existing row (identified by path). Name and position are unchanged.
    func setIconCode(_ code: String, forPath path: String) throws {
        try withSnapshot { _, items in
            guard let item = items.first(where: { Self.samePath(self.path(of: $0), path) }) else {
                throw SidebarBackendError.rowNotFound
            }
            let value = code as CFString
            let status = withExtendedLifetime(value) {
                fnSetProperty(item, opaque(Self.overrideIconKey), opaque(value))
            }
            if status != 0 { throw SidebarBackendError.operationFailed("LSSharedFileListItemSetProperty: \(status)") }
        }
    }

    /// Removes the icon code from the row for `path`, keeping its name and position.
    func clearIconCode(forPath path: String) throws {
        try withSnapshot { list, items in
            guard let index = items.firstIndex(where: { Self.samePath(self.path(of: $0), path) }) else { return }
            let item = items[index]
            let name = displayName(item)
            let anchor: OpaquePointer? = index > 0 ? items[index - 1] : nil
            let label = name as CFString
            let url = URL(fileURLWithPath: self.path(of: item) ?? path, isDirectory: true) as CFURL
            let clear = [Self.overrideIconKey] as CFArray
            let inserted = withExtendedLifetime((label, url, clear)) {
                fnInsert(list, anchor, opaque(label), nil, opaque(url), nil, opaque(clear))
            }
            guard let inserted else {
                throw SidebarBackendError.operationFailed("Couldn't update the sidebar row.")
            }
            release(inserted)
        }
    }

    /// Appends a row for `url` with an icon code. Returns false if the folder was already there
    /// (then its icon is set in place and the row stays where it is).
    @discardableResult
    func insert(_ url: URL, name: String, iconCode: String) throws -> Bool {
        let path = url.standardizedFileURL.path
        return try withSnapshot { list, items in
            if let existing = items.first(where: { Self.samePath(self.path(of: $0), path) }) {
                let value = iconCode as CFString
                let status = withExtendedLifetime(value) {
                    fnSetProperty(existing, opaque(Self.overrideIconKey), opaque(value))
                }
                if status != 0 { throw SidebarBackendError.operationFailed("LSSharedFileListItemSetProperty: \(status)") }
                return false
            }
            let anchor = items.last
            let properties = [Self.overrideIconKey: iconCode as CFString] as CFDictionary
            let label = (name.isEmpty ? url.lastPathComponent : name) as CFString
            let target = url as CFURL
            let inserted = withExtendedLifetime((properties, label, target)) {
                fnInsert(list, anchor, opaque(label), nil, opaque(target), opaque(properties), nil)
            }
            guard let inserted else {
                throw SidebarBackendError.operationFailed("Couldn't add \(url.lastPathComponent) to Finder's sidebar.")
            }
            release(inserted)
            return true
        }
    }

    /// Swaps the row for `path` for a fresh one with `iconCode`, at the same position and with the
    /// same name. Finder redraws an inserted row immediately, whereas a changed code on a row
    /// already on screen only shows after Finder restarts. Only used for rows FinderPlus added.
    func replaceRow(path: String, iconCode: String) throws {
        try withSnapshot { list, items in
            guard let index = items.firstIndex(where: { Self.samePath(self.path(of: $0), path) }) else {
                throw SidebarBackendError.rowNotFound
            }
            let item = items[index]
            let label = displayName(item) as CFString
            let url = URL(fileURLWithPath: self.path(of: item) ?? path, isDirectory: true) as CFURL
            // The predecessor stays valid: the snapshot array keeps every item alive.
            let anchor: OpaquePointer? = index > 0 ? items[index - 1] : nil
            let status = fnRemove(list, item)
            if status != 0 { throw SidebarBackendError.operationFailed("LSSharedFileListItemRemove: \(status)") }
            let properties = [Self.overrideIconKey: iconCode as CFString] as CFDictionary
            let inserted = withExtendedLifetime((properties, label, url)) {
                fnInsert(list, anchor, opaque(label), nil, opaque(url), opaque(properties), nil)
            }
            guard let inserted else {
                throw SidebarBackendError.operationFailed("Couldn't put the sidebar row back.")
            }
            release(inserted)
        }
    }

    func remove(path: String) throws {
        try withSnapshot { list, items in
            for item in items where Self.samePath(self.path(of: item), path) {
                let status = fnRemove(list, item)
                if status != 0 { throw SidebarBackendError.operationFailed("LSSharedFileListItemRemove: \(status)") }
            }
        }
    }

    // MARK: Helpers

    /// Calls `body` with the list and its items. Item references are owned by the snapshot array,
    /// so they are only valid inside `body` — never let them escape.
    private func withSnapshot<T>(_ body: (OpaquePointer, [OpaquePointer]) throws -> T) throws -> T {
        guard let list = fnCreate(nil, favoritesListType, nil) else { throw SidebarBackendError.unavailable }
        defer { release(list) }
        guard let arrayPointer = fnSnapshot(list, nil) else { throw SidebarBackendError.unavailable }
        let array = Unmanaged<CFArray>.fromOpaque(UnsafeRawPointer(arrayPointer)).takeRetainedValue()
        return try withExtendedLifetime(array) {
            let items = (0..<CFArrayGetCount(array)).compactMap { index in
                CFArrayGetValueAtIndex(array, index).map { OpaquePointer($0) }
            }
            return try body(list, items)
        }
    }

    private func row(for item: OpaquePointer) -> SidebarRow {
        SidebarRow(id: fnGetID(item), name: displayName(item), path: path(of: item), iconCode: iconCode(of: item),
                   isSpecial: hasProperty(item, Self.specialItemKey))
    }

    private func displayName(_ item: OpaquePointer) -> String {
        guard let pointer = fnCopyName(item) else { return "" }
        return Unmanaged<CFString>.fromOpaque(UnsafeRawPointer(pointer)).takeRetainedValue() as String
    }

    private func path(of item: OpaquePointer) -> String? {
        // kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes
        if let pointer = fnCopyURL(item, 0b11, nil) {
            return (Unmanaged<CFURL>.fromOpaque(UnsafeRawPointer(pointer)).takeRetainedValue() as URL).path
        }
        guard let fnCopyBookmark, let pointer = fnCopyBookmark(item) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(UnsafeRawPointer(pointer)).takeRetainedValue() as Data
        let values = URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: data)
        return values?.path
    }

    private func iconCode(of item: OpaquePointer) -> String? {
        guard let pointer = fnCopyProperty(item, opaque(Self.overrideIconKey)) else { return nil }
        // Only string values are meaningful; anything else is treated as "no override".
        let value = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(pointer)).takeRetainedValue()
        return value as? String
    }

    private func hasProperty(_ item: OpaquePointer, _ key: CFString) -> Bool {
        guard let pointer = fnCopyProperty(item, opaque(key)) else { return false }
        release(pointer)
        return true
    }

    static func samePath(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        if lhs == rhs { return true }
        let left = URL(fileURLWithPath: lhs).standardizedFileURL.resolvingSymlinksInPath().path
        let right = URL(fileURLWithPath: rhs).standardizedFileURL.resolvingSymlinksInPath().path
        return left == right
    }

    private func opaque(_ object: AnyObject) -> OpaquePointer {
        OpaquePointer(Unmanaged.passUnretained(object).toOpaque())
    }

    private func release(_ pointer: OpaquePointer) {
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(pointer)).release()
    }
}

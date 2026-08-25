import SwiftUI
import ResvgMobile
import ResvgMobileUI

@main
struct ResvgGalleryApp: App {
    var body: some Scene {
        WindowGroup {
            GalleryView()
        }
    }
}

private enum GalleryFonts {
    static let config: FontConfig = {
        let bundled = Resvg.bundledFontConfig()
        if !bundled.data.isEmpty {
            return bundled
        }
        return FontConfig(
            dirs: Resvg.systemFontDirs,
            data: [],
            aliases: Resvg.defaultFontAliases,
            defaultFamily: "Noto Sans"
        )
    }()
}

private enum SuiteDomain {
    static let order = [
        "filters",
        "masking",
        "paint-servers",
        "painting",
        "shapes",
        "structure",
        "text",
    ]
}

private enum GroupMode: String, CaseIterable, Identifiable {
    case domainAndSubgroup = "Domain + subgroup"
    case domain = "Domain only"
    case subgroup = "Subgroup"
    case flat = "Flat list"

    var id: String { rawValue }
}

private struct SvgAsset: Identifiable, Hashable {
    let id: String
    let category: String
    let relativePath: String
    let url: URL

    var displayPath: String { relativePath }
    var selectionKey: String { id }

    var isCustom: Bool { category == "Custom" }

    var suiteDomain: String? {
        guard !isCustom else { return nil }
        let parts = relativePath.split(separator: "/").map(String.init)
        return parts.first
    }

    var suiteSubgroup: String? {
        guard !isCustom else { return nil }
        let parts = relativePath.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts[1]
    }

    func matchesQuery(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return relativePath.lowercased().contains(q) ||
            category.lowercased().contains(q) ||
            suiteDomain?.lowercased().contains(q) == true ||
            suiteSubgroup?.lowercased().contains(q) == true
    }
}

private struct SvgSubgroup: Identifiable {
    let key: String
    let name: String
    let assets: [SvgAsset]

    var id: String { key }
}

private struct SvgDomainGroup: Identifiable {
    let key: String
    let title: String
    let subgroups: [SvgSubgroup]

    var id: String { key }

    var assets: [SvgAsset] {
        subgroups.flatMap(\.assets)
    }

    var assetCount: Int {
        assets.count
    }
}

private func domainSectionKey(_ domainKey: String) -> String {
    "d:\(domainKey)"
}

private func subgroupSectionKey(domainKey: String, subgroupKey: String) -> String {
    "s:\(domainKey):\(subgroupKey)"
}

private func collectSectionKeys(_ groups: [SvgDomainGroup]) -> Set<String> {
    var keys = Set<String>()
    for domain in groups {
        keys.insert(domainSectionKey(domain.key))
        for subgroup in domain.subgroups where subgroup.name != "(all)" {
            keys.insert(subgroupSectionKey(domainKey: domain.key, subgroupKey: subgroup.key))
        }
    }
    return keys
}

private func isSectionExpanded(
    expandedSections: Set<String>,
    sectionKey: String,
    forceExpand: Bool
) -> Bool {
    if forceExpand { return true }
    return expandedSections.contains(sectionKey)
}

private func toggleSectionExpansion(_ current: Set<String>, sectionKey: String) -> Set<String> {
    var updated = current
    if updated.contains(sectionKey) {
        updated.remove(sectionKey)
    } else {
        updated.insert(sectionKey)
    }
    return updated
}

struct GalleryView: View {
    @State private var query = ""
    @State private var groupMode: GroupMode = .domainAndSubgroup
    @State private var selectedKeys: Set<String> = []
    @State private var expandedSections: Set<String> = [domainSectionKey("custom")]

    private let assets: [SvgAsset] = Self.loadAssets()

    private var filtered: [SvgAsset] {
        assets.filter { $0.matchesQuery(query) }
    }

    private var groups: [SvgDomainGroup] {
        Self.buildGroups(filtered, mode: groupMode)
    }

    private var visibleKeys: Set<String> {
        Set(groups.flatMap(\.assets).map(\.selectionKey))
    }

    private var selectedVisibleCount: Int {
        selectedKeys.intersection(visibleKeys).count
    }

    private var filterActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var allSectionKeys: Set<String> {
        collectSectionKeys(groups)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 156), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GallerySearchHeader(
                    totalCount: assets.count,
                    matchCount: filtered.count,
                    selectedCount: selectedVisibleCount,
                    query: $query,
                    groupMode: $groupMode,
                    onClearSelection: { selectedKeys.removeAll() },
                    onSelectVisible: { selectedKeys.formUnion(visibleKeys) },
                    onExpandAll: { expandedSections = allSectionKeys },
                    onCollapseAll: { expandedSections = [] }
                )
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { domain in
                            let domainSection = domainSectionKey(domain.key)
                            let domainExpanded = isSectionExpanded(
                                expandedSections: expandedSections,
                                sectionKey: domainSection,
                                forceExpand: filterActive
                            )
                            Section {
                                if domainExpanded {
                                    ForEach(domain.subgroups) { subgroup in
                                        let showSubgroup = shouldShowSubgroup(subgroup, in: domain)
                                        let subgroupSection = subgroupSectionKey(
                                            domainKey: domain.key,
                                            subgroupKey: subgroup.key
                                        )
                                        let subgroupExpanded = showSubgroup && subgroup.name != "(all)"
                                            ? isSectionExpanded(
                                                expandedSections: expandedSections,
                                                sectionKey: subgroupSection,
                                                forceExpand: filterActive
                                            )
                                            : true

                                        if showSubgroup && subgroup.name != "(all)" {
                                            CollapsibleGroupHeader(
                                                title: subgroup.name,
                                                count: subgroup.assets.count,
                                                selectedCount: selectedCount(for: subgroup.assets),
                                                expanded: subgroupExpanded,
                                                emphasized: false,
                                                onToggleExpanded: {
                                                    expandedSections = toggleSectionExpansion(
                                                        expandedSections,
                                                        sectionKey: subgroupSection
                                                    )
                                                },
                                                onToggleSelection: { toggleSelection(for: subgroup.assets) }
                                            )
                                        }

                                        if subgroupExpanded {
                                            LazyVGrid(columns: columns, spacing: 12) {
                                                ForEach(subgroup.assets) { asset in
                                                    SvgTile(
                                                        asset: asset,
                                                        selected: selectedKeys.contains(asset.selectionKey),
                                                        onToggleSelect: { toggleSelection(for: asset) }
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            } header: {
                                CollapsibleGroupHeader(
                                    title: domain.title,
                                    count: domain.assetCount,
                                    selectedCount: selectedCount(for: domain.assets),
                                    expanded: domainExpanded,
                                    emphasized: groupMode != .flat,
                                    onToggleExpanded: {
                                        expandedSections = toggleSectionExpansion(
                                            expandedSections,
                                            sectionKey: domainSection
                                        )
                                    },
                                    onToggleSelection: { toggleSelection(for: domain.assets) }
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).ignoresSafeArea())
            .navigationTitle("resvg-mobile gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func shouldShowSubgroup(_ subgroup: SvgSubgroup, in domain: SvgDomainGroup) -> Bool {
        if subgroup.name == "(all)" { return false }
        if groupMode == .domainAndSubgroup { return true }
        if groupMode == .subgroup, domain.subgroups.count == 1 { return false }
        return false
    }

    private func selectedCount(for assets: [SvgAsset]) -> Int {
        assets.filter { selectedKeys.contains($0.selectionKey) }.count
    }

    private func toggleSelection(for asset: SvgAsset) {
        if selectedKeys.contains(asset.selectionKey) {
            selectedKeys.remove(asset.selectionKey)
        } else {
            selectedKeys.insert(asset.selectionKey)
        }
    }

    private func toggleSelection(for assets: [SvgAsset]) {
        let keys = Set(assets.map(\.selectionKey))
        guard !keys.isEmpty else { return }
        if keys.isSubset(of: selectedKeys) {
            selectedKeys.subtract(keys)
        } else {
            selectedKeys.formUnion(keys)
        }
    }

    private static func loadAssets() -> [SvgAsset] {
        var out: [SvgAsset] = []
        out += loadDirectory(name: "svg-set", category: "Custom")
        out += loadDirectory(name: "resvg-suite", category: "resvg-test-suite")
        return out.sorted { lhs, rhs in
            let lhsDomain = lhs.isCustom ? -1 : SuiteDomain.order.firstIndex(of: lhs.suiteDomain ?? "") ?? Int.max
            let rhsDomain = rhs.isCustom ? -1 : SuiteDomain.order.firstIndex(of: rhs.suiteDomain ?? "") ?? Int.max
            if lhsDomain != rhsDomain { return lhsDomain < rhsDomain }
            if lhs.suiteSubgroup != rhs.suiteSubgroup {
                return (lhs.suiteSubgroup ?? "") < (rhs.suiteSubgroup ?? "")
            }
            return lhs.relativePath < rhs.relativePath
        }
    }

    private static func loadDirectory(name: String, category: String) -> [SvgAsset] {
        guard let base = Bundle.main.resourceURL?.appendingPathComponent(name, isDirectory: true) else {
            return []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var assets: [SvgAsset] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "svg" else { continue }
            let rel = url.path.replacingOccurrences(of: base.path + "/", with: "")
            assets.append(
                SvgAsset(
                    id: "\(category)/\(rel)",
                    category: category,
                    relativePath: rel,
                    url: url
                )
            )
        }
        return assets
    }

    private static func buildGroups(_ assets: [SvgAsset], mode: GroupMode) -> [SvgDomainGroup] {
        guard !assets.isEmpty else { return [] }
        switch mode {
        case .domainAndSubgroup:
            return buildDomainAndSubgroupGroups(assets)
        case .domain:
            return buildDomainOnlyGroups(assets)
        case .subgroup:
            return buildSubgroupGroups(assets)
        case .flat:
            return [
                SvgDomainGroup(
                    key: "all",
                    title: "All",
                    subgroups: [
                        SvgSubgroup(
                            key: "all",
                            name: "(all)",
                            assets: assets.sorted { $0.relativePath < $1.relativePath }
                        ),
                    ]
                ),
            ]
        }
    }

    private static func buildDomainAndSubgroupGroups(_ assets: [SvgAsset]) -> [SvgDomainGroup] {
        var out: [SvgDomainGroup] = []
        let custom = assets.filter(\.isCustom)
        let suite = assets.filter { !$0.isCustom }

        if !custom.isEmpty {
            out.append(
                SvgDomainGroup(
                    key: "custom",
                    title: "Custom",
                    subgroups: [
                        SvgSubgroup(
                            key: "svg-set",
                            name: "svg-set",
                            assets: custom.sorted { $0.relativePath < $1.relativePath }
                        ),
                    ]
                )
            )
        }

        let byDomain = Dictionary(grouping: suite, by: { $0.suiteDomain ?? "other" })
        for domain in SuiteDomain.order {
            guard let domainAssets = byDomain[domain], !domainAssets.isEmpty else { continue }
            let grouped = Dictionary(grouping: domainAssets, by: { $0.suiteSubgroup ?? "(root)" })
            let subgroups = grouped.keys.sorted().map { name in
                SvgSubgroup(
                    key: name,
                    name: name,
                    assets: grouped[name, default: []].sorted { $0.relativePath < $1.relativePath }
                )
            }
            out.append(SvgDomainGroup(key: domain, title: domain, subgroups: subgroups))
        }

        appendOtherDomains(to: &out, byDomain: byDomain)
        return out
    }

    private static func buildDomainOnlyGroups(_ assets: [SvgAsset]) -> [SvgDomainGroup] {
        var out: [SvgDomainGroup] = []
        let custom = assets.filter(\.isCustom)
        let suite = assets.filter { !$0.isCustom }

        if !custom.isEmpty {
            out.append(
                SvgDomainGroup(
                    key: "custom",
                    title: "Custom",
                    subgroups: [
                        SvgSubgroup(
                            key: "all",
                            name: "(all)",
                            assets: custom.sorted { $0.relativePath < $1.relativePath }
                        ),
                    ]
                )
            )
        }

        let byDomain = Dictionary(grouping: suite, by: { $0.suiteDomain ?? "other" })
        for domain in SuiteDomain.order {
            guard let domainAssets = byDomain[domain], !domainAssets.isEmpty else { continue }
            out.append(
                SvgDomainGroup(
                    key: domain,
                    title: domain,
                    subgroups: [
                        SvgSubgroup(
                            key: "all",
                            name: "(all)",
                            assets: domainAssets.sorted { $0.relativePath < $1.relativePath }
                        ),
                    ]
                )
            )
        }

        appendOtherDomains(to: &out, byDomain: byDomain, flattenSubgroups: true)
        return out
    }

    private static func buildSubgroupGroups(_ assets: [SvgAsset]) -> [SvgDomainGroup] {
        var out: [SvgDomainGroup] = []
        let custom = assets.filter(\.isCustom)
        let suite = assets.filter { !$0.isCustom }

        if !custom.isEmpty {
            out.append(
                SvgDomainGroup(
                    key: "custom",
                    title: "Custom",
                    subgroups: [
                        SvgSubgroup(
                            key: "svg-set",
                            name: "svg-set",
                            assets: custom.sorted { $0.relativePath < $1.relativePath }
                        ),
                    ]
                )
            )
        }

        let bySubgroup = Dictionary(grouping: suite, by: { $0.suiteSubgroup ?? "(root)" })
        for name in bySubgroup.keys.sorted() {
            guard let subgroupAssets = bySubgroup[name], !subgroupAssets.isEmpty else { continue }
            out.append(
                SvgDomainGroup(
                    key: name,
                    title: name,
                    subgroups: [
                        SvgSubgroup(
                            key: name,
                            name: name,
                            assets: subgroupAssets.sorted { $0.relativePath < $1.relativePath }
                        ),
                    ]
                )
            )
        }

        return out
    }

    private static func appendOtherDomains(
        to out: inout [SvgDomainGroup],
        byDomain: [String?: [SvgAsset]],
        flattenSubgroups: Bool = false
    ) {
        let otherDomains = byDomain.keys
            .compactMap { $0 }
            .filter { !SuiteDomain.order.contains($0) }
            .sorted()
        for domain in otherDomains {
            guard let domainAssets = byDomain[domain], !domainAssets.isEmpty else { continue }
            let subgroups: [SvgSubgroup]
            if flattenSubgroups {
                subgroups = [
                    SvgSubgroup(
                        key: "all",
                        name: "(all)",
                        assets: domainAssets.sorted { $0.relativePath < $1.relativePath }
                    ),
                ]
            } else {
                let grouped = Dictionary(grouping: domainAssets, by: { $0.suiteSubgroup ?? "(root)" })
                subgroups = grouped.keys.sorted().map { name in
                    SvgSubgroup(
                        key: name,
                        name: name,
                        assets: grouped[name, default: []].sorted { $0.relativePath < $1.relativePath }
                    )
                }
            }
            out.append(SvgDomainGroup(key: domain, title: domain, subgroups: subgroups))
        }
    }
}

private struct GallerySearchHeader: View {
    let totalCount: Int
    let matchCount: Int
    let selectedCount: Int
    @Binding var query: String
    @Binding var groupMode: GroupMode
    let onClearSelection: () -> Void
    let onSelectVisible: () -> Void
    let onExpandAll: () -> Void
    let onCollapseAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(totalCount) SVGs · expand groups to browse, tap tiles to select")
                .font(.subheadline)
                .foregroundStyle(Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255))
            TextField("Filter", text: $query, prompt: Text("e.g. text, filters, writing-mode"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255))
                Spacer()
                if selectedCount > 0 {
                    Button("Clear", action: onClearSelection)
                        .font(.caption)
                } else if matchCount > 0 {
                    Button("Select visible", action: onSelectVisible)
                        .font(.caption)
                }
            }
            HStack {
                Spacer()
                Button("Expand all", action: onExpandAll)
                    .font(.caption)
                Button("Collapse all", action: onCollapseAll)
                    .font(.caption)
            }
            Picker("Group by", selection: $groupMode) {
                ForEach(GroupMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255))
    }

    private var statusText: String {
        if selectedCount > 0 {
            return "\(selectedCount) selected · \(matchCount) visible"
        }
        if !query.isEmpty {
            return "\(matchCount) matches"
        }
        return "Group by:"
    }
}

private struct CollapsibleGroupHeader: View {
    let title: String
    let count: Int
    let selectedCount: Int
    let expanded: Bool
    let emphasized: Bool
    let onToggleExpanded: () -> Void
    let onToggleSelection: () -> Void

    private var allSelected: Bool {
        count > 0 && selectedCount == count
    }

    private var partiallySelected: Bool {
        selectedCount > 0 && selectedCount < count
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleExpanded) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)

            Button(action: onToggleSelection) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : (partiallySelected ? "minus.circle.fill" : "circle"))
                    .foregroundStyle(allSelected || partiallySelected ? Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255) : Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255))
            }
            .buttonStyle(.plain)

            Button(action: onToggleExpanded) {
                Text(headerText)
                    .font(emphasized ? .title3.weight(.semibold) : .headline)
                    .foregroundStyle(emphasized ? .white : Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, emphasized ? 8 : 4)
        .padding(.leading, emphasized ? 0 : 8)
        .background(Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255))
    }

    private var headerText: String {
        if partiallySelected {
            return "\(title) (\(count)) · \(selectedCount) selected"
        }
        return "\(title) (\(count))"
    }
}

private struct SvgTile: View {
    let asset: SvgAsset
    let selected: Bool
    let onToggleSelect: () -> Void

    var body: some View {
        Button(action: onToggleSelect) {
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    Text(asset.displayPath)
                        .font(.caption2)
                        .foregroundStyle(Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255) : Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255))
                }
                Group {
                    if let data = try? Data(contentsOf: asset.url) {
                        ResvgImage(data: data, fonts: GalleryFonts.config)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(12)
            .background(Color(red: 30 / 255, green: 41 / 255, blue: 59 / 255))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selected ? Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255) : .clear,
                        lineWidth: 2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

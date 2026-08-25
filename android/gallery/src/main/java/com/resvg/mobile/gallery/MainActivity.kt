package com.resvg.mobile.gallery

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.resvg.mobile.FontConfig
import com.resvg.mobile.Resvg
import com.resvg.mobile.ui.ResvgImage

private val SuiteDomainOrder = listOf(
    "filters",
    "masking",
    "paint-servers",
    "painting",
    "shapes",
    "structure",
    "text",
)

private enum class GroupMode(val label: String) {
    DomainAndSubgroup("Domain + subgroup"),
    Domain("Domain only"),
    Subgroup("Subgroup"),
    Flat("Flat list"),
}

data class SvgAsset(
    val category: String,
    val assetPath: String,
    val relativePath: String,
) {
    val selectionKey: String get() = "$category/$relativePath"

    val isCustom: Boolean get() = category == "Custom"

    val suiteDomain: String?
        get() {
            if (isCustom) return null
            return relativePath.substringBefore('/', missingDelimiterValue = relativePath)
        }

    val suiteSubgroup: String?
        get() {
            if (isCustom) return null
            val parts = relativePath.split('/')
            return parts.getOrNull(1)
        }

    fun matchesQuery(query: String): Boolean {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return true
        return relativePath.lowercase().contains(q) ||
            category.lowercase().contains(q) ||
            suiteDomain?.lowercase()?.contains(q) == true ||
            suiteSubgroup?.lowercase()?.contains(q) == true
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SvgAsset) return false
        return category == other.category && assetPath == other.assetPath
    }

    override fun hashCode(): Int = 31 * category.hashCode() + assetPath.hashCode()
}

private data class SvgSubgroup(
    val key: String,
    val name: String,
    val assets: List<SvgAsset>,
)

private data class SvgDomainGroup(
    val key: String,
    val title: String,
    val subgroups: List<SvgSubgroup>,
) {
    val assets: List<SvgAsset> get() = subgroups.flatMap { it.assets }
    val assetCount: Int get() = assets.size
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val assets = remember { loadSvgAssets() }
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = Color(0xFF0F172A)) {
                    GalleryScreen(assets = assets)
                }
            }
        }
    }

    private fun loadSvgAssets(): List<SvgAsset> {
        val custom = listAssetsRecursive("svg-set", category = "Custom")
        val suite = listAssetsRecursive("resvg-suite", category = "resvg-test-suite")
        return (custom + suite).sortedWith(
            compareBy(
                { if (it.isCustom) 0 else SuiteDomainOrder.indexOf(it.suiteDomain ?: "") },
                { it.suiteSubgroup ?: "" },
                { it.relativePath },
            ),
        )
    }

    private fun listAssetsRecursive(root: String, category: String): List<SvgAsset> {
        fun walk(dir: String, prefix: String): List<SvgAsset> {
            val names = assets.list(dir) ?: return emptyList()
            val out = mutableListOf<SvgAsset>()
            for (name in names.sorted()) {
                val path = if (prefix.isEmpty()) name else "$prefix/$name"
                val full = "$dir/$name"
                val children = assets.list(full)
                if (children.isNullOrEmpty()) {
                    if (name.endsWith(".svg", ignoreCase = true)) {
                        out += SvgAsset(category = category, assetPath = full, relativePath = path)
                    }
                } else {
                    out += walk(full, path)
                }
            }
            return out
        }
        return walk(root, prefix = "")
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GalleryScreen(assets: List<SvgAsset>) {
    val context = LocalContext.current
    val fonts = remember { Resvg.loadAssetFontConfig(context) }
    var query by remember { mutableStateOf("") }
    var groupMode by remember { mutableStateOf(GroupMode.DomainAndSubgroup) }
    var selectedKeys by remember { mutableStateOf(setOf<String>()) }
    var expandedSections by remember { mutableStateOf(setOf(domainSectionKey("custom"))) }

    val filtered = remember(assets, query) {
        assets.filter { it.matchesQuery(query) }
    }
    val groups = remember(filtered, groupMode) { buildGroups(filtered, groupMode) }
    val visibleKeys = remember(groups) { groups.flatMap { it.assets }.map { it.selectionKey }.toSet() }
    val selectedVisibleCount = remember(selectedKeys, visibleKeys) {
        selectedKeys.count { it in visibleKeys }
    }
    val filterActive = query.isNotBlank()
    val allSectionKeys = remember(groups) { collectSectionKeys(groups) }

    Column(modifier = Modifier.fillMaxSize()) {
        GallerySearchHeader(
            totalCount = assets.size,
            matchCount = filtered.size,
            selectedCount = selectedVisibleCount,
            query = query,
            groupMode = groupMode,
            onQueryChange = { query = it },
            onGroupModeChange = { groupMode = it },
            onClearSelection = { selectedKeys = emptySet() },
            onSelectVisible = {
                selectedKeys = selectedKeys + visibleKeys
            },
            onExpandAll = { expandedSections = allSectionKeys },
            onCollapseAll = { expandedSections = emptySet() },
        )
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 156.dp),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            for (domain in groups) {
                val domainSection = domainSectionKey(domain.key)
                val domainExpanded = isSectionExpanded(
                    expandedSections = expandedSections,
                    sectionKey = domainSection,
                    forceExpand = filterActive,
                )
                val domainKeys = domain.assets.map { it.selectionKey }
                val domainSelected = domainKeys.count { it in selectedKeys }
                item(
                    key = "domain:${domain.key}",
                    span = { GridItemSpan(maxLineSpan) },
                ) {
                    CollapsibleGroupHeader(
                        title = domain.title,
                        count = domain.assetCount,
                        selectedCount = domainSelected,
                        expanded = domainExpanded,
                        emphasized = groupMode != GroupMode.Flat,
                        onToggleExpanded = {
                            expandedSections = toggleSectionExpansion(expandedSections, domainSection)
                        },
                        onToggleSelection = {
                            selectedKeys = toggleGroupSelection(selectedKeys, domainKeys)
                        },
                    )
                }
                if (domainExpanded) {
                    for (subgroup in domain.subgroups) {
                    val showSubgroup = groupMode == GroupMode.DomainAndSubgroup ||
                        (groupMode == GroupMode.Subgroup && domain.subgroups.size == 1 && subgroup.name != "(all)")
                    val subgroupSection = subgroupSectionKey(domain.key, subgroup.key)
                    val subgroupExpanded = if (showSubgroup && subgroup.name != "(all)") {
                        isSectionExpanded(expandedSections, subgroupSection, forceExpand = filterActive)
                    } else {
                        true
                    }

                    if (showSubgroup && subgroup.name != "(all)") {
                        val subgroupKeys = subgroup.assets.map { it.selectionKey }
                        val subgroupSelected = subgroupKeys.count { it in selectedKeys }
                        item(
                            key = "sub:${domain.key}:${subgroup.key}",
                            span = { GridItemSpan(maxLineSpan) },
                        ) {
                            CollapsibleGroupHeader(
                                title = subgroup.name,
                                count = subgroup.assets.size,
                                selectedCount = subgroupSelected,
                                expanded = subgroupExpanded,
                                emphasized = false,
                                onToggleExpanded = {
                                    expandedSections = toggleSectionExpansion(expandedSections, subgroupSection)
                                },
                                onToggleSelection = {
                                    selectedKeys = toggleGroupSelection(selectedKeys, subgroupKeys)
                                },
                            )
                        }
                    }

                    if (subgroupExpanded) {
                        items(
                            items = subgroup.assets,
                            key = { asset -> "tile:${asset.selectionKey}" },
                        ) { asset ->
                            SvgTile(
                                asset = asset,
                                selected = asset.selectionKey in selectedKeys,
                                fonts = fonts,
                                onToggleSelect = {
                                    selectedKeys = toggleItemSelection(selectedKeys, asset.selectionKey)
                                },
                            )
                        }
                    }
                }
                }
            }
        }
    }
}

private fun domainSectionKey(domainKey: String): String = "d:$domainKey"

private fun subgroupSectionKey(domainKey: String, subgroupKey: String): String = "s:$domainKey:$subgroupKey"

private fun collectSectionKeys(groups: List<SvgDomainGroup>): Set<String> {
    val keys = mutableSetOf<String>()
    for (domain in groups) {
        keys += domainSectionKey(domain.key)
        for (subgroup in domain.subgroups) {
            if (subgroup.name != "(all)") {
                keys += subgroupSectionKey(domain.key, subgroup.key)
            }
        }
    }
    return keys
}

private fun isSectionExpanded(
    expandedSections: Set<String>,
    sectionKey: String,
    forceExpand: Boolean,
): Boolean {
    if (forceExpand) return true
    return sectionKey in expandedSections
}

private fun toggleSectionExpansion(current: Set<String>, sectionKey: String): Set<String> {
    return if (sectionKey in current) current - sectionKey else current + sectionKey
}

private fun toggleItemSelection(current: Set<String>, key: String): Set<String> {
    return if (key in current) current - key else current + key
}

private fun toggleGroupSelection(current: Set<String>, keys: List<String>): Set<String> {
    if (keys.isEmpty()) return current
    val allSelected = keys.all { it in current }
    return if (allSelected) current - keys.toSet() else current + keys.toSet()
}

@Composable
private fun GallerySearchHeader(
    totalCount: Int,
    matchCount: Int,
    selectedCount: Int,
    query: String,
    groupMode: GroupMode,
    onQueryChange: (String) -> Unit,
    onGroupModeChange: (GroupMode) -> Unit,
    onClearSelection: () -> Unit,
    onSelectVisible: () -> Unit,
    onExpandAll: () -> Unit,
    onCollapseAll: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF0F172A))
            .padding(start = 20.dp, top = 20.dp, end = 20.dp, bottom = 12.dp),
    ) {
        Text(
            text = "resvg-mobile gallery",
            color = Color.White,
            style = MaterialTheme.typography.titleLarge,
        )
        Text(
            text = "$totalCount SVGs · expand groups to browse, tap tiles to select",
            color = Color(0xFF94A3B8),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = 4.dp, bottom = 8.dp),
        )
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            label = { Text("Filter") },
            placeholder = { Text("e.g. text, filters, writing-mode") },
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = when {
                    selectedCount > 0 -> "$selectedCount selected · $matchCount visible"
                    query.isNotBlank() -> "$matchCount matches"
                    else -> "Group by:"
                },
                color = Color(0xFF64748B),
                style = MaterialTheme.typography.labelMedium,
            )
            if (selectedCount > 0) {
                TextButton(onClick = onClearSelection) {
                    Text("Clear")
                }
            } else if (matchCount > 0) {
                TextButton(onClick = onSelectVisible) {
                    Text("Select visible")
                }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
        ) {
            TextButton(onClick = onExpandAll) { Text("Expand all") }
            TextButton(onClick = onCollapseAll) { Text("Collapse all") }
        }
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(top = 8.dp),
        ) {
            items(GroupMode.entries.size) { index ->
                val mode = GroupMode.entries[index]
                FilterChip(
                    selected = groupMode == mode,
                    onClick = { onGroupModeChange(mode) },
                    label = { Text(mode.label) },
                )
            }
        }
    }
}

@Composable
private fun CollapsibleGroupHeader(
    title: String,
    count: Int,
    selectedCount: Int,
    expanded: Boolean,
    emphasized: Boolean,
    onToggleExpanded: () -> Unit,
    onToggleSelection: () -> Unit,
) {
    val allSelected = count > 0 && selectedCount == count
    val partiallySelected = selectedCount in 1 until count
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF0F172A))
            .padding(
                start = if (emphasized) 0.dp else 8.dp,
                top = if (emphasized) 12.dp else 4.dp,
                bottom = if (emphasized) 6.dp else 4.dp,
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = if (expanded) "▼" else "▶",
            color = Color(0xFF94A3B8),
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier
                .clickable(onClick = onToggleExpanded)
                .padding(end = 8.dp),
        )
        Checkbox(
            checked = allSelected,
            onCheckedChange = { onToggleSelection() },
        )
        Text(
            text = buildString {
                append(title)
                append(" (")
                append(count)
                append(")")
                if (partiallySelected) append(" · $selectedCount selected")
            },
            color = if (emphasized) Color.White else Color(0xFFCBD5E1),
            style = if (emphasized) MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleSmall,
            modifier = Modifier
                .weight(1f)
                .clickable(onClick = onToggleExpanded),
        )
    }
}

private fun buildGroups(assets: List<SvgAsset>, mode: GroupMode): List<SvgDomainGroup> {
    if (assets.isEmpty()) return emptyList()
    return when (mode) {
        GroupMode.DomainAndSubgroup -> buildDomainAndSubgroupGroups(assets)
        GroupMode.Domain -> buildDomainOnlyGroups(assets)
        GroupMode.Subgroup -> buildSubgroupGroups(assets)
        GroupMode.Flat -> listOf(
            SvgDomainGroup(
                key = "all",
                title = "All",
                subgroups = listOf(
                    SvgSubgroup(
                        key = "all",
                        name = "(all)",
                        assets = assets.sortedBy { it.relativePath },
                    ),
                ),
            ),
        )
    }
}

private fun buildDomainAndSubgroupGroups(assets: List<SvgAsset>): List<SvgDomainGroup> {
    val custom = assets.filter { it.isCustom }
    val suite = assets.filterNot { it.isCustom }
    val out = mutableListOf<SvgDomainGroup>()

    if (custom.isNotEmpty()) {
        out += SvgDomainGroup(
            key = "custom",
            title = "Custom",
            subgroups = listOf(
                SvgSubgroup(
                    key = "svg-set",
                    name = "svg-set",
                    assets = custom.sortedBy { it.relativePath },
                ),
            ),
        )
    }

    val byDomain = suite.groupBy { it.suiteDomain ?: "other" }
    for (domain in SuiteDomainOrder) {
        val domainAssets = byDomain[domain].orEmpty()
        if (domainAssets.isEmpty()) continue
        out += SvgDomainGroup(
            key = domain,
            title = domain,
            subgroups = domainAssets
                .groupBy { it.suiteSubgroup ?: "(root)" }
                .entries
                .sortedBy { it.key }
                .map { (name, subgroupAssets) ->
                    SvgSubgroup(
                        key = name,
                        name = name,
                        assets = subgroupAssets.sortedBy { it.relativePath },
                    )
                },
        )
    }

    appendOtherDomains(out, byDomain)
    return out
}

private fun buildDomainOnlyGroups(assets: List<SvgAsset>): List<SvgDomainGroup> {
    val custom = assets.filter { it.isCustom }
    val suite = assets.filterNot { it.isCustom }
    val out = mutableListOf<SvgDomainGroup>()

    if (custom.isNotEmpty()) {
        out += SvgDomainGroup(
            key = "custom",
            title = "Custom",
            subgroups = listOf(
                SvgSubgroup(
                    key = "all",
                    name = "(all)",
                    assets = custom.sortedBy { it.relativePath },
                ),
            ),
        )
    }

    val byDomain = suite.groupBy { it.suiteDomain ?: "other" }
    for (domain in SuiteDomainOrder) {
        val domainAssets = byDomain[domain].orEmpty()
        if (domainAssets.isEmpty()) continue
        out += SvgDomainGroup(
            key = domain,
            title = domain,
            subgroups = listOf(
                SvgSubgroup(
                    key = "all",
                    name = "(all)",
                    assets = domainAssets.sortedBy { it.relativePath },
                ),
            ),
        )
    }

    appendOtherDomains(out, byDomain, flattenSubgroups = true)
    return out
}

private fun buildSubgroupGroups(assets: List<SvgAsset>): List<SvgDomainGroup> {
    val custom = assets.filter { it.isCustom }
    val suite = assets.filterNot { it.isCustom }
    val out = mutableListOf<SvgDomainGroup>()

    if (custom.isNotEmpty()) {
        out += SvgDomainGroup(
            key = "custom",
            title = "Custom",
            subgroups = listOf(
                SvgSubgroup(
                    key = "svg-set",
                    name = "svg-set",
                    assets = custom.sortedBy { it.relativePath },
                ),
            ),
        )
    }

    val bySubgroup = suite.groupBy { it.suiteSubgroup ?: "(root)" }
    for (name in bySubgroup.keys.sorted()) {
        val subgroupAssets = bySubgroup[name].orEmpty()
        if (subgroupAssets.isEmpty()) continue
        out += SvgDomainGroup(
            key = name,
            title = name,
            subgroups = listOf(
                SvgSubgroup(
                    key = name,
                    name = name,
                    assets = subgroupAssets.sortedBy { it.relativePath },
                ),
            ),
        )
    }

    return out
}

private fun appendOtherDomains(
    out: MutableList<SvgDomainGroup>,
    byDomain: Map<String, List<SvgAsset>>,
    flattenSubgroups: Boolean = false,
) {
    val otherDomains = byDomain.keys
        .filterNot { it in SuiteDomainOrder }
        .sorted()
    for (domain in otherDomains) {
        val domainAssets = byDomain[domain].orEmpty()
        if (domainAssets.isEmpty()) continue
        val subgroups = if (flattenSubgroups) {
            listOf(
                SvgSubgroup(
                    key = "all",
                    name = "(all)",
                    assets = domainAssets.sortedBy { it.relativePath },
                ),
            )
        } else {
            domainAssets
                .groupBy { it.suiteSubgroup ?: "(root)" }
                .entries
                .sortedBy { it.key }
                .map { (name, subgroupAssets) ->
                    SvgSubgroup(
                        key = name,
                        name = name,
                        assets = subgroupAssets.sortedBy { it.relativePath },
                    )
                }
        }
        out += SvgDomainGroup(key = domain, title = domain, subgroups = subgroups)
    }
}

@Composable
private fun SvgTile(
    asset: SvgAsset,
    selected: Boolean,
    fonts: FontConfig,
    onToggleSelect: () -> Unit,
) {
    val context = LocalContext.current
    val bytes by produceState<ByteArray?>(initialValue = null, key1 = asset.assetPath) {
        value = runCatching {
            context.assets.open(asset.assetPath).use { it.readBytes() }
        }.getOrNull()
    }

    val borderColor = if (selected) Color(0xFF38BDF8) else Color.Transparent
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(2.dp, borderColor, MaterialTheme.shapes.medium)
            .clip(MaterialTheme.shapes.medium)
            .background(Color(0xFF1E293B))
            .clickable(onClick = onToggleSelect)
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top,
        ) {
            Text(
                text = asset.relativePath,
                color = Color(0xFFCBD5E1),
                style = MaterialTheme.typography.labelSmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f)
                    .padding(end = 8.dp, bottom = 8.dp),
            )
            Box(
                modifier = Modifier
                    .size(20.dp)
                    .clip(CircleShape)
                    .background(if (selected) Color(0xFF38BDF8) else Color(0xFF334155)),
                contentAlignment = Alignment.Center,
            ) {
                if (selected) {
                    Text("✓", color = Color(0xFF0F172A), style = MaterialTheme.typography.labelSmall)
                }
            }
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp)
                .background(Color.White, shape = MaterialTheme.shapes.small)
                .padding(12.dp),
            contentAlignment = Alignment.Center,
        ) {
            val svg = bytes
            if (svg != null) {
                ResvgImage(
                    svg = svg,
                    modifier = Modifier.fillMaxSize(),
                    contentDescription = asset.relativePath,
                    fonts = fonts,
                )
            }
        }
    }
}

//
//  ContentView.swift
//  Chart_Component
//
//  Created by Mike Sedaghatnia on 12/08/2026.
//  All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @State private var usesLargeType = false

    private enum Colors {
        static let page = Color.black
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    PlaygroundSection(title: "Playground", subtitle: "Uses the same sample data as canvas previews. Turn on 200% type to check reflow.") {
                        EmptyView()
                    } controls: {
                        Toggle("200% Dynamic Type", isOn: $usesLargeType)
                    }

                    ChartPlaygroundSection()
                    AllocationPlaygroundSection()
                    HoldingsPlaygroundSection()
                    SegmentedPlaygroundSection()
                    LabelsPlaygroundSection()
                    WidgetPlaygroundSection()
                }
                .padding(16)
            }
            .background(Colors.page.ignoresSafeArea())
            .navigationTitle("Components")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.page, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .playgroundDynamicType(usesLargeType)
    }
}

// MARK: - Chart

private struct ChartPlaygroundSection: View {
    @State private var period = PerformanceChartPeriod.all
    @State private var performance = PerformanceChartPerformance.positive
    @State private var useCase = PerformanceChartUseCase.valueAndDeposit
    @State private var playgroundState = ChartPlaygroundState.data
    @State private var showsMedianLine = false
    @State private var isScrubbing = false

    var body: some View {
        PlaygroundSection(title: "Performance chart", subtitle: "Sample series. Change period, tone, and load state.") {
            PerformanceChart(
                points: PerformanceChartSampleData.points(for: period, performance: performance),
                performance: performance,
                useCase: useCase,
                showsMedianLine: showsMedianLine,
                state: playgroundState.chartState,
                onRetry: {},
                selectedPeriod: $period,
                isScrubbing: $isScrubbing
            ) { context in
                PerformanceChartHeader(context: context)
            } periodControl: { selection in
                PerformancePeriodControl(selection: selection)
            }
        } controls: {
            Picker("State", selection: $playgroundState) {
                ForEach(ChartPlaygroundState.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Performance", selection: $performance) {
                ForEach(PerformanceChartPerformance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Use case", selection: $useCase) {
                ForEach(PerformanceChartUseCase.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Median line", isOn: $showsMedianLine)
            Toggle("Scrubbing", isOn: $isScrubbing)
        }
    }
}

private enum ChartPlaygroundState: String, CaseIterable, Identifiable {
    case data
    case loading
    case error
    case notFunded

    var id: Self { self }

    var title: String {
        switch self {
        case .data: return "Data"
        case .loading: return "Loading"
        case .error: return "Error"
        case .notFunded: return "Empty"
        }
    }

    var chartState: PerformanceChartState {
        switch self {
        case .data: return .data
        case .loading: return .loading
        case .error: return .failed("We couldn't load this chart. Try again.")
        case .notFunded: return .notFunded
        }
    }
}

// MARK: - Allocation

private struct AllocationPlaygroundSection: View {
    @State private var segmentCount = 5
    @State private var legendSize = ChartLegendSize.default
    @State private var legendOrientation = ChartLegendOrientation.fill
    @State private var legendValueKind = ChartLegendValueKind.percentage
    @State private var legendListType = ChartLegendListType.standard
    @State private var showsLegendDivider = true

    private var barSegments: [StackedBarSegment] {
        StackedBarSampleData.segments(count: segmentCount)
    }

    private var legendItems: [ChartLegendItem] {
        if legendListType == .hierarchical {
            return ChartLegendSampleData.hierarchical
        }

        return StackedBarResolver
            .resolve(segments: barSegments, palette: StackedBarSampleData.palette)
            .items
            .map { $0.legendItem(valueKind: legendValueKind) }
    }

    var body: some View {
        PlaygroundSection(title: "Bar and legend", subtitle: "Segment count drives the bar. Legend can match it or switch to a hierarchical list.") {
            VStack(alignment: .leading, spacing: 16) {
                StackedBarGraph(segments: barSegments)
                ChartLegend(
                    items: legendItems,
                    size: legendSize,
                    orientation: legendOrientation,
                    valueKind: legendListType == .hierarchical ? .numeral : legendValueKind,
                    listType: legendListType,
                    showsDivider: showsLegendDivider
                )
            }
        } controls: {
            Stepper("Segments \(segmentCount)", value: $segmentCount, in: StackedBarLayout.minSegments...StackedBarLayout.maxSegments)

            Picker("Legend size", selection: $legendSize) {
                ForEach(ChartLegendSize.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Orientation", selection: $legendOrientation) {
                ForEach(ChartLegendOrientation.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("List", selection: $legendListType) {
                ForEach(ChartLegendListType.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if legendListType == .standard {
                Picker("Value", selection: $legendValueKind) {
                    ForEach(ChartLegendValueKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle("Legend divider", isOn: $showsLegendDivider)
        }
    }
}

// MARK: - Holdings

private struct HoldingsPlaygroundSection: View {
    @State private var showsIcon = true
    @State private var showsSubtext = true
    @State private var showsPerformance = true
    @State private var showsDivider = true
    @State private var usesBadge = false

    var body: some View {
        PlaygroundSection(title: "Holdings row", subtitle: "Toggle slots. Badge replaces the performance subtitle.") {
            holdingsRow
        } controls: {
            Toggle("Icon", isOn: $showsIcon)
            Toggle("Subtext", isOn: $showsSubtext)
            Toggle("Performance", isOn: $showsPerformance)
            Toggle("Divider", isOn: $showsDivider)
            Toggle("Badge instead of value", isOn: $usesBadge)
        }
    }

    @ViewBuilder
    private var holdingsRow: some View {
        if usesBadge {
            HoldingsRow(
                showsIcon: showsIcon,
                label: "CAD",
                showsSubtext: showsSubtext,
                subtext: "Cash",
                amountText: AmountLabelFormat.amount(3_304.20),
                showsPerformance: showsPerformance,
                showsDivider: showsDivider,
                icon: { HoldingsRowIcon(ticker: "CAD") },
                performance: { HoldingsRowBadge(title: "All time", performance: .positive) }
            )
        } else {
            HoldingsRow(
                showsIcon: showsIcon,
                label: "CAD",
                showsSubtext: showsSubtext,
                subtext: "Cash",
                amount: 3_304.20,
                changePercent: 0.124,
                showsPerformance: showsPerformance,
                showsDivider: showsDivider
            )
        }
    }
}

// MARK: - Segmented control

private struct SegmentedPlaygroundSection: View {
    @State private var optionCount = 4
    @State private var selectedOption = "Label 1"
    @State private var layout = "List"

    private var options: [String] {
        (1...optionCount).map { "Label \($0)" }
    }

    var body: some View {
        PlaygroundSection(title: "Segmented control", subtitle: "Generic control. Count is 2–8. Layout is a second example.") {
            VStack(alignment: .leading, spacing: 16) {
                SegmentedControl(
                    options,
                    selection: $selectedOption,
                    srLabel: "Options"
                )
                SegmentedControl(
                    ["List", "Grid"],
                    selection: $layout,
                    srLabel: "Layout"
                )
            }
        } controls: {
            Stepper("Options \(optionCount)", value: $optionCount, in: SegmentedControlLayout.minItems...SegmentedControlLayout.maxItems)
            Text("Selected \(selectedOption) · \(layout)")
                .font(.system(.footnote, design: .default).weight(.regular))
                .foregroundColor(.white.opacity(0.65))
        }
        .onChange(of: optionCount) { _ in
            if !options.contains(selectedOption), let first = options.first {
                selectedOption = first
            }
        }
    }
}

// MARK: - Labels

private struct LabelsPlaygroundSection: View {
    @State private var amountSize = AmountLabel.Size.default
    @State private var subtitleLayout = PerformanceSubtitle.Layout.numeralPercentageAndTimestamp
    @State private var timestamp = PerformanceTimestampKind.allTime
    @State private var performance = PerformanceChartPerformance.positive

    private var changeAmount: Double {
        performance == .positive ? 5_000 : -412.10
    }

    private var changePercent: Double {
        performance == .positive ? 0.505 : -0.082
    }

    var body: some View {
        PlaygroundSection(title: "Labels", subtitle: "Amount, performance line, timestamp, and scrub labels.") {
            VStack(alignment: .leading, spacing: 20) {
                AmountLabel(value: 46_648.58, currencyCode: "CAD", size: amountSize)

                PerformanceSubtitle(
                    changeAmount: changeAmount,
                    changePercent: changePercent,
                    timestamp: timestamp,
                    performance: performance,
                    layout: subtitleLayout
                )

                PerformanceTimestamp(timestamp)

                HStack(alignment: .top, spacing: 16) {
                    AccountValueLabel(
                        amount: 46_648.58,
                        date: Date(timeIntervalSince1970: 1_724_000_000),
                        period: .all,
                        performance: performance
                    )
                    DepositsLabel(amount: 40_000)
                }
            }
        } controls: {
            Picker("Amount size", selection: $amountSize) {
                ForEach(AmountLabel.Size.allCases) { option in
                    Text(option.playgroundTitle).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Subtitle", selection: $subtitleLayout) {
                ForEach(PerformanceSubtitle.Layout.allCases) { option in
                    Text(option.playgroundTitle).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Timestamp", selection: $timestamp) {
                ForEach(PerformanceTimestampKind.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            Picker("Performance", selection: $performance) {
                ForEach(PerformanceChartPerformance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Widgets

private struct WidgetPlaygroundSection: View {
    var body: some View {
        PlaygroundSection(title: "Host widgets", subtitle: "Not chart components. Kept here so you can still tap through them.") {
            VStack(alignment: .leading, spacing: 16) {
                Folder()
                    .frame(height: 108)

                CreateSpaceCard(onCreate: {}, onDismiss: {})
            }
        }
    }
}

// MARK: - Layout

private struct PlaygroundSection<Content: View, Controls: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundColor(Colors.title)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(.footnote, design: .default).weight(.regular))
                        .foregroundColor(Colors.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if Content.self != EmptyView.self {
                content
            }

            if Controls.self != EmptyView.self {
                PlaygroundControls {
                    controls
                }
            }
        }
    }
}

extension PlaygroundSection where Controls == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, content: content, controls: { EmptyView() })
    }
}

private struct PlaygroundControls<Content: View>: View {
    @ViewBuilder var content: Content


    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Colors.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundColor(Colors.content)
    }
}

private extension AmountLabel.Size {
    var playgroundTitle: String {
        switch self {
        case .default: return "Default"
        case .compact: return "Compact"
        case .automatic: return "Auto"
        }
    }
}

private extension PerformanceSubtitle.Layout {
    var playgroundTitle: String {
        switch self {
        case .numeralAndPercentage: return "Amount %"
        case .percentageAndTimestamp: return "% Time"
        case .numeralPercentageAndTimestamp: return "All"
        }
    }
}

private extension View {
    @ViewBuilder
    func playgroundDynamicType(_ isOn: Bool) -> some View {
        if isOn {
            environment(\.dynamicTypeSize, .accessibility2)
        } else {
            self
        }
    }
}

#Preview {
    ContentView()
}

private enum Colors {
    static let title = Color.white
    static let subtitle = Color.white.opacity(0.65)
    static let fill = Color(hex: 0x1A1E22)
    static let content = Color.white
}

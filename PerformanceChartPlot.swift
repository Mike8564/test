//
//  PerformanceChartPlot.swift
//  Chart_Component
//
//  Created by Mike Sedaghatnia on 12/08/2026.
//  All rights reserved.
//

import Charts
import SwiftUI

struct PerformanceChartPlot: View {
    let points: [PerformanceChartPoint]
    let performance: PerformanceChartPerformance
    let useCase: PerformanceChartUseCase
    let showsMedianLine: Bool
    let selectedPeriod: PerformanceChartPeriod
    @Binding var selectedDate: Date?

    private enum Colors {
        static let positive = Color(hex: 0x47A963)
        static let negative = Color(hex: 0xCE3D3D)
        static let depositLine = Color.white.opacity(0.35)
        static let median = Color.white.opacity(0.55)
        static let scrubber = Color.white.opacity(0.85)
        static let selectedDeposit = Color.white
        static let overlay = Color.clear
    }

    private var tone: Color {
        performance == .positive ? Colors.positive : Colors.negative
    }

    /// Recedes the unselected tail while scrubbing. Opacity reads darker on the chart surface.
    private var dimmedTone: Color {
        tone.opacity(0.38)
    }

    private var selectedPoint: PerformanceChartPoint? {
        guard let selectedDate else { return nil }
        return Self.nearestPoint(to: selectedDate, in: points)
    }

    private var filledPoints: [PerformanceChartPoint] {
        guard let selectedDate else { return points }
        let filled = points.filter { $0.date <= selectedDate }
        if filled.isEmpty, let selectedPoint {
            return [selectedPoint]
        }
        return filled
    }

    /// Includes the selected point so the dimmed tail meets the green prefix with no gap.
    private var remainingPoints: [PerformanceChartPoint] {
        guard let selectedPoint else { return [] }
        return points.filter { $0.date >= selectedPoint.date }
    }

    private var isScrubbing: Bool {
        selectedDate != nil
    }

    private var medianValue: Double? {
        guard showsMedianLine, !isScrubbing, !points.isEmpty else { return nil }
        let sorted = points.map(\.value).sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2), middle > 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.value)
        if useCase == .valueAndDeposit {
            values.append(contentsOf: points.compactMap(\.netDeposits))
        }
        if let medianValue {
            values.append(medianValue)
        }

        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, max(abs(high) * 0.02, 1))
        let bottomPadding = medianValue == nil ? span * 0.45 : span * 0.18
        return (low - bottomPadding)...(high + span * 0.42)
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [tone.opacity(0.38), tone.opacity(0.0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var plotTopInset: CGFloat { 8 }

    var body: some View {
        chart
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: yDomain)
            .chartPlotStyle { plot in
                plot.frame(maxWidth: .infinity, minHeight: PerformanceChartStyle.chartHeight, maxHeight: PerformanceChartStyle.chartHeight)
            }
            .chartOverlay { proxy in
                overlay(proxy: proxy)
            }
            .padding(.top, plotTopInset)
            .animation(nil, value: selectedDate)
    }

    private var chart: some View {
        Chart {
            if let medianValue {
                ForEach(filledPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Median", medianValue),
                        yEnd: .value("Value", point.value)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(areaGradient)
                }
            } else {
                ForEach(filledPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(areaGradient)
                }
            }

            ForEach(filledPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Series", "Past")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(tone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .miter))
            }

            if isScrubbing {
                ForEach(remainingPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Series", "Future")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(dimmedTone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .miter))
                }
            }

            if useCase == .valueAndDeposit, isScrubbing {
                ForEach(points) { point in
                    if let netDeposits = point.netDeposits {
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Net deposits", netDeposits),
                            series: .value("Series", "Deposits")
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(Colors.depositLine)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
            }

            if let medianValue {
                RuleMark(y: .value("Median", medianValue))
                    .foregroundStyle(Colors.median)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(Colors.scrubber)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                PointMark(
                    x: .value("Selected", selectedPoint.date),
                    y: .value("Value", selectedPoint.value)
                )
                .foregroundStyle(tone)
                .symbolSize(70)

                if useCase == .valueAndDeposit, let netDeposits = selectedPoint.netDeposits {
                    PointMark(
                        x: .value("Selected deposits", selectedPoint.date),
                        y: .value("Net deposits", netDeposits)
                    )
                    .foregroundStyle(Colors.selectedDeposit)
                    .symbolSize(60)
                }
            }
        }
    }

    @ViewBuilder
    private func overlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Colors.overlay
                .contentShape(Rectangle())
                .gesture(scrubGesture(proxy: proxy, geometry: geometry))
        }
    }

    private func scrubGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                select(at: value.location, proxy: proxy, geometry: geometry)
            }
            .onEnded { _ in
                selectedDate = nil
            }
    }

    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let x = plotX(for: location, proxy: proxy, geometry: geometry)
        guard let date: Date = proxy.value(atX: x, as: Date.self) else { return }
        selectedDate = Self.nearestPoint(to: date, in: points)?.date
    }

    private func plotX(for location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> CGFloat {
        if #available(iOS 17.0, *), let plotFrame = proxy.plotFrame {
            return location.x - geometry[plotFrame].origin.x
        }
        return location.x
    }

    static func nearestPoint(to date: Date, in points: [PerformanceChartPoint]) -> PerformanceChartPoint? {
        points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}

#Preview("Plot preview") {
    struct PlotPreviewHost: View {
        @State private var selectedDate: Date? = nil
        private let period: PerformanceChartPeriod = .all
        private let performance: PerformanceChartPerformance = .positive
        private let useCase: PerformanceChartUseCase = .valueAndDeposit
        private let showsMedianLine = false
        private let points = PerformanceChartSampleData.points(for: .all, performance: .positive)

        var body: some View {
            PerformanceChartPlot(
                points: points,
                performance: performance,
                useCase: useCase,
                showsMedianLine: showsMedianLine,
                selectedPeriod: period,
                selectedDate: $selectedDate
            )
            .padding()
            .background(Color.black)
        }
    }
    return PlotPreviewHost()
}

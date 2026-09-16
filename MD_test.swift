////  MD_test.swift
//  POC

import SwiftUI
import UIKit
import MaterialComponents

enum MDTheme {
    static let containerScheme: MDCContainerScheme = {
        let scheme = MDCContainerScheme()
        let shape = MDCShapeScheme(defaults: .material201809)
        // 201809 large surfaces are square (0). Use 16pt so the sheet shape is visible.
        shape.largeComponentShape = MDCShapeCategory(cornersWith: .rounded, andSize: 16)
        scheme.shapeScheme = shape
        return scheme
    }()
}

struct MD_test: View {
    @State private var isLoading = true
    @State private var selectedTab = 0
    @State private var isBannerVisible = true
    @State private var isAllChipSelected = true
    @State private var isUnreadChipSelected = false
    @State private var name = ""
    private let tabs = ["Home", "Recents", "Account"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
            MDTabBar(titles: tabs, selectedIndex: $selectedTab)
                .frame(height: 48)
                .frame(maxWidth: .infinity)

            if isBannerVisible {
                MDBanner(
                    text: "There was a problem processing a transaction on your credit card.",
                    leadingTitle: "Dismiss",
                    trailingTitle: "Fix it",
                    onLeading: {
                        isBannerVisible = false
                    },
                    onTrailing: {
                        showSnackbar(text: "Fix it")
                    }
                )
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                MDButton(title: "Show banner", style: .text) {
                    isBannerVisible = true
                }
            }

            Text("Selected: \(tabs[selectedTab])")
                .font(.subheadline)

            HStack(spacing: 8) {
                MDChip(title: "All", isSelected: $isAllChipSelected)
                MDChip(title: "Unread", isSelected: $isUnreadChipSelected)
                MDChip(title: "Action", style: .filled) {
                    showSnackbar(text: "Chip action")
                }
            }

            MDTextField(
                text: $name,
                placeholder: "Name",
                helperText: "Helper text"
            )
            .padding(.horizontal)

            MDButton(title: "Show sheet") {
                presentBottomSheet()
            }

            MDButton(title: "Saved") {
                showSnackbar(text: "Saved")
            }

            MDButton(
                title: isLoading ? "Stop" : "Start",
                style: .outlined
            ) {
                isLoading.toggle()
            }

            MDFlatButton(title: "Flat") {
                showSnackbar(text: "Flat")
            }

            MDActivityIndicator(isAnimating: isLoading)
                .frame(width: 40, height: 40)

            MDCard(isInteractable: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.headline)
                    Text("Supporting text")
                        .font(.subheadline)
                    MDButton(title: "Action", style: .text) {
                        showSnackbar(text: "Card action")
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
        }
        .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func showSnackbar(text: String) {
        if let window = Self.keyWindow {
            MDCSnackbarManager.default.setPresentationHostView(window)
        }

        let message = MDCSnackbarMessage(text: text)
        MDCSnackbarManager.default.show(message)
    }

    private func presentBottomSheet() {
        guard let presenter = Self.topViewController() else { return }

        let content = MDBottomSheetContentController()
        content.preferredContentSize = CGSize(width: presenter.view.bounds.width, height: 220)

        let sheet = MDCBottomSheetController(contentViewController: content)
        if let shapeScheme = MDTheme.containerScheme.shapeScheme {
            let generator = MDCRectangleShapeGenerator()
            generator.topLeftCorner = shapeScheme.largeComponentShape.topLeftCorner
            generator.topRightCorner = shapeScheme.largeComponentShape.topRightCorner
            sheet.setShapeGenerator(generator, for: .preferred)
        }

        presenter.present(sheet, animated: true)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func topViewController() -> UIViewController? {
        guard var top = keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

final class MDBottomSheetContentController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Bottom sheet"
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        let detailLabel = UILabel()
        detailLabel.text = "Top corners come from MDCShapeScheme largeComponentShape."
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        let closeButton = MDCButton()
        closeButton.enableRippleBehavior = true
        closeButton.applyContainedTheme(withScheme: MDTheme.containerScheme)
        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, closeButton])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

#Preview {
    MD_test()
}

struct MDBanner: UIViewRepresentable {
    var text: String
    var leadingTitle: String
    var trailingTitle: String?
    var onLeading: () -> Void
    var onTrailing: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onLeading: onLeading, onTrailing: onTrailing)
    }

    func makeUIView(context: Context) -> MDCBannerView {
        let banner = MDCBannerView()
        banner.applyTheme(withScheme: MDTheme.containerScheme)
        banner.bannerViewLayoutStyle = .automatic
        banner.showsDivider = true
        banner.imageView.isHidden = true
        banner.textView.text = text
        banner.textView.isEditable = false
        banner.textView.isScrollEnabled = false
        banner.leadingButton.setTitle(leadingTitle, for: .normal)
        banner.leadingButton.addTarget(
            context.coordinator,
            action: #selector(Coordinator.leadingTap),
            for: .touchUpInside
        )
        if let trailingTitle {
            banner.trailingButton.isHidden = false
            banner.trailingButton.setTitle(trailingTitle, for: .normal)
            banner.trailingButton.addTarget(
                context.coordinator,
                action: #selector(Coordinator.trailingTap),
                for: .touchUpInside
            )
        } else {
            banner.trailingButton.isHidden = true
        }
        banner.setContentHuggingPriority(.required, for: .vertical)
        banner.setContentCompressionResistancePriority(.required, for: .vertical)
        return banner
    }

    func updateUIView(_ banner: MDCBannerView, context: Context) {
        context.coordinator.onLeading = onLeading
        context.coordinator.onTrailing = onTrailing
        banner.textView.text = text
        banner.leadingButton.setTitle(leadingTitle, for: .normal)
        if let trailingTitle {
            banner.trailingButton.isHidden = false
            banner.trailingButton.setTitle(trailingTitle, for: .normal)
        } else {
            banner.trailingButton.isHidden = true
        }
        banner.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MDCBannerView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
        return CGSize(width: width, height: size.height)
    }

    final class Coordinator: NSObject {
        var onLeading: () -> Void
        var onTrailing: (() -> Void)?

        init(onLeading: @escaping () -> Void, onTrailing: (() -> Void)?) {
            self.onLeading = onLeading
            self.onTrailing = onTrailing
        }

        @objc func leadingTap() {
            onLeading()
        }

        @objc func trailingTap() {
            onTrailing?()
        }
    }
}

struct MDChip: UIViewRepresentable {
    enum Style {
        case filled
        case outlined
    }

    var title: String
    var style: Style = .outlined
    var isSelected: Binding<Bool>?
    var action: (() -> Void)?

    init(
        title: String,
        style: Style = .outlined,
        isSelected: Binding<Bool>? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.style = style
        self.isSelected = isSelected
        self.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isSelected: isSelected, action: action)
    }

    func makeUIView(context: Context) -> MDCChipView {
        let chip = MDCChipView()
        chip.enableRippleBehavior = true
        apply(style, to: chip)
        chip.titleLabel.text = title
        chip.isSelected = isSelected?.wrappedValue ?? false
        chip.selectedImageView.image = UIImage(systemName: "checkmark")
        chip.imageViewSize = CGSize(width: 18, height: 18)
        chip.addTarget(
            context.coordinator,
            action: #selector(Coordinator.tap),
            for: .touchUpInside
        )
        chip.setContentHuggingPriority(.required, for: .vertical)
        chip.setContentHuggingPriority(.required, for: .horizontal)
        chip.setContentCompressionResistancePriority(.required, for: .horizontal)
        return chip
    }

    func updateUIView(_ chip: MDCChipView, context: Context) {
        context.coordinator.isSelected = isSelected
        context.coordinator.action = action
        apply(style, to: chip)
        chip.titleLabel.text = title
        chip.isSelected = isSelected?.wrappedValue ?? false
        chip.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MDCChipView, context: Context) -> CGSize? {
        uiView.sizeThatFits(
            CGSize(
                width: proposal.width ?? UIView.layoutFittingCompressedSize.width,
                height: proposal.height ?? UIView.layoutFittingCompressedSize.height
            )
        )
    }

    private func apply(_ style: Style, to chip: MDCChipView) {
        let scheme = MDTheme.containerScheme
        switch style {
        case .filled:
            chip.applyTheme(withScheme: scheme)
        case .outlined:
            chip.applyOutlinedTheme(withScheme: scheme)
        }
    }

    final class Coordinator: NSObject {
        var isSelected: Binding<Bool>?
        var action: (() -> Void)?

        init(isSelected: Binding<Bool>?, action: (() -> Void)?) {
            self.isSelected = isSelected
            self.action = action
        }

        @objc func tap() {
            if let isSelected {
                isSelected.wrappedValue.toggle()
            }
            action?()
        }
    }
}

struct MDTextField: UIViewRepresentable {
    enum Style {
        case outlined
        case filled
        case underline
    }

    @Binding var text: String
    var placeholder: String
    var helperText: String?
    var style: Style = .outlined

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> MDCTextField {
        let textField = MDCTextField()
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )

        let controller: MDCTextInputControllerBase
        switch style {
        case .outlined:
            controller = MDCTextInputControllerOutlined(textInput: textField)
        case .filled:
            controller = MDCTextInputControllerFilled(textInput: textField)
        case .underline:
            controller = MDCTextInputControllerUnderline(textInput: textField)
        }
        context.coordinator.controller = controller
        apply(controller)

        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateUIView(_ textField: MDCTextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        apply(context.coordinator.controller)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MDCTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
        return CGSize(width: width, height: max(size.height, 56))
    }

    private func apply(_ controller: MDCTextInputControllerBase?) {
        guard let controller else { return }
        controller.placeholderText = placeholder
        controller.helperText = helperText
        let primary = MDTheme.containerScheme.colorScheme.primaryColor
        controller.activeColor = primary
        controller.floatingPlaceholderActiveColor = primary
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var controller: MDCTextInputControllerBase?

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textChanged(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

struct MDFlatButton: UIViewRepresentable {
    var title: String
    var uppercaseTitle: Bool = true
    var hasOpaqueBackground: Bool = false
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> MDCFlatButton {
        let button = MDCFlatButton()
        button.enableRippleBehavior = true
        button.isUppercaseTitle = uppercaseTitle
        button.hasOpaqueBackground = hasOpaqueBackground
        button.applyTextTheme(withScheme: MDTheme.containerScheme)
        button.setTitle(title, for: .normal)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateUIView(_ button: MDCFlatButton, context: Context) {
        context.coordinator.action = action
        button.isUppercaseTitle = uppercaseTitle
        button.hasOpaqueBackground = hasOpaqueBackground
        button.applyTextTheme(withScheme: MDTheme.containerScheme)
        button.setTitle(title, for: .normal)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tap() {
            action()
        }
    }
}

struct MDButton: UIViewRepresentable {
    enum Style {
        case contained
        case outlined
        case text
    }

    var title: String
    var style: Style = .contained
    var uppercaseTitle: Bool = true
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> MDCButton {
        let button = MDCButton()
        button.enableRippleBehavior = true
        button.isUppercaseTitle = uppercaseTitle
        apply(style, to: button)
        button.setTitle(title, for: .normal)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateUIView(_ button: MDCButton, context: Context) {
        context.coordinator.action = action
        button.isUppercaseTitle = uppercaseTitle
        apply(style, to: button)
        button.setTitle(title, for: .normal)
    }

    private func apply(_ style: Style, to button: MDCButton) {
        let scheme = MDTheme.containerScheme
        switch style {
        case .contained:
            button.applyContainedTheme(withScheme: scheme)
        case .outlined:
            button.applyOutlinedTheme(withScheme: scheme)
        case .text:
            button.applyTextTheme(withScheme: scheme)
        }
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tap() {
            action()
        }
    }
}

struct MDTabBar: UIViewRepresentable {
    var titles: [String]
    @Binding var selectedIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIndex: $selectedIndex)
    }

    func makeUIView(context: Context) -> MDCTabBar {
        let tabBar = MDCTabBar()
        tabBar.itemAppearance = .titles
        tabBar.alignment = .justified
        tabBar.enableRippleBehavior = true
        tabBar.displaysUppercaseTitles = true
        tabBar.barTintColor = .systemBackground
        tabBar.selectedItemTintColor = .systemBlue
        tabBar.unselectedItemTintColor = .secondaryLabel
        tabBar.bottomDividerColor = .separator
        tabBar.delegate = context.coordinator
        tabBar.items = makeItems()
        selectItem(on: tabBar)
        tabBar.setContentHuggingPriority(.required, for: .vertical)
        return tabBar
    }

    func updateUIView(_ tabBar: MDCTabBar, context: Context) {
        context.coordinator.selectedIndex = $selectedIndex
        let items = makeItems()
        if tabBar.items.map(\.title) != items.map(\.title) {
            tabBar.items = items
        }
        selectItem(on: tabBar)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MDCTabBar, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let height = MDCTabBar.defaultHeight(for: .titles)
        return CGSize(width: width, height: height)
    }

    private func makeItems() -> [UITabBarItem] {
        titles.enumerated().map { index, title in
            UITabBarItem(title: title, image: nil, tag: index)
        }
    }

    private func selectItem(on tabBar: MDCTabBar) {
        guard !tabBar.items.isEmpty else { return }
        let index = min(max(selectedIndex, 0), tabBar.items.count - 1)
        if tabBar.selectedItem !== tabBar.items[index] {
            tabBar.setSelectedItem(tabBar.items[index], animated: false)
        }
    }

    final class Coordinator: NSObject, MDCTabBarDelegate {
        var selectedIndex: Binding<Int>

        init(selectedIndex: Binding<Int>) {
            self.selectedIndex = selectedIndex
        }

        func tabBar(_ tabBar: MDCTabBar, didSelect item: UITabBarItem) {
            selectedIndex.wrappedValue = item.tag
        }
    }
}

struct MDActivityIndicator: UIViewRepresentable {
    var isAnimating: Bool
    var radius: CGFloat = 16
    var strokeWidth: CGFloat = 2.5
    var cycleColors: [UIColor] = [.systemBlue]

    func makeUIView(context: Context) -> MDCActivityIndicator {
        let indicator = MDCActivityIndicator()
        indicator.indicatorMode = .indeterminate
        indicator.radius = radius
        indicator.strokeWidth = strokeWidth
        indicator.cycleColors = cycleColors
        indicator.sizeToFit()
        return indicator
    }

    func updateUIView(_ indicator: MDCActivityIndicator, context: Context) {
        indicator.radius = radius
        indicator.strokeWidth = strokeWidth
        indicator.cycleColors = cycleColors
        if isAnimating {
            indicator.startAnimating()
        } else {
            indicator.stopAnimating()
        }
    }
}

struct MDCard<Content: View>: UIViewRepresentable {
    var cornerRadius: CGFloat = 4
    var isInteractable: Bool = false
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MDCCard {
        let card = MDCCard()
        card.cornerRadius = cornerRadius
        card.isInteractable = isInteractable
        card.enableRippleBehavior = isInteractable
        card.setShadowElevation(.cardResting, for: .normal)
        card.setShadowElevation(.cardPickedUp, for: .highlighted)
        card.setContentHuggingPriority(.required, for: .vertical)
        card.setContentCompressionResistancePriority(.required, for: .vertical)

        let host = UIHostingController(rootView: content())
        host.sizingOptions = [.intrinsicContentSize]
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.setContentHuggingPriority(.required, for: .vertical)
        host.view.setContentCompressionResistancePriority(.required, for: .vertical)
        card.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: card.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        context.coordinator.host = host
        return card
    }

    func updateUIView(_ card: MDCCard, context: Context) {
        card.cornerRadius = cornerRadius
        card.isInteractable = isInteractable
        card.enableRippleBehavior = isInteractable
        context.coordinator.host?.rootView = content()
        context.coordinator.host?.view.invalidateIntrinsicContentSize()
        card.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MDCCard, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let size = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: size.height)
    }

    final class Coordinator {
        var host: UIHostingController<Content>?
    }
}

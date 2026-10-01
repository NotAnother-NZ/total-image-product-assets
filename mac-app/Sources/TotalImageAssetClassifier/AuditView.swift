import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AuditView: View {
    @ObservedObject var model: AuditModel
    let onBack: () -> Void

    @State private var sourceTargeted = false
    @State private var destinationTargeted = false
    @State private var excelTargeted = false
    @State private var showChangePlan = false
    @State private var showRollbackConfirmation = false

    var body: some View {
        Group {
            if model.scanResult == nil {
                setupView
            } else {
                reviewView
            }
        }
        .frame(minWidth: 1120, minHeight: 760)
        .alert(
            "Asset Audit",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: {
                    if !$0 {
                        model.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $showChangePlan) {
            AuditChangePlanView(
                model: model,
                onClose: {
                    showChangePlan = false
                }
            )
        }
        .confirmationDialog(
            "Rollback the last applied audit changes?",
            isPresented: $showRollbackConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Rollback Last Apply",
                role: .destructive
            ) {
                model.rollbackLastApply()
            }
        } message: {
            Text(
                "Rollback is hash-guarded and will stop if any affected file changed after the audit apply."
            )
        }
    }

    private var setupView: some View {
        VStack(spacing: 24) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Label(
                        "Back",
                        systemImage: "chevron.left"
                    )
                }

                Spacer()
            }

            Spacer()

            Image(systemName: "checklist.checked")
                .font(
                    .system(
                        size: 50,
                        weight: .light
                    )
                )
                .foregroundStyle(.secondary)

            Text("Audit Final Assets")
                .font(.largeTitle.bold())

            Text(
                "Compare the current source against the finalized GitHub assets, review destination-only files and pixel duplicates visually, validate names, and queue safe changes before anything is modified."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 760)

            HStack(spacing: 16) {
                auditDropZone(
                    title: "Current Source",
                    subtitle: "ALL_PRODUCT_ASSETS",
                    systemImage:
                        "tray.and.arrow.down",
                    selectedURL:
                        model.sourceSelection,
                    isTargeted:
                        sourceTargeted,
                    chooseAction:
                        model.chooseSourceFolder
                )
                .onDrop(
                    of: [
                        UTType.fileURL.identifier
                    ],
                    isTargeted:
                        $sourceTargeted
                ) { providers in
                    handleDirectoryDrop(
                        providers
                    ) {
                        model.setSourceFolder($0)
                    }
                }

                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                auditDropZone(
                    title: "Final Destination",
                    subtitle: "GitHub assets",
                    systemImage:
                        "shippingbox",
                    selectedURL:
                        model.destinationSelection,
                    isTargeted:
                        destinationTargeted,
                    chooseAction:
                        model.chooseDestinationFolder
                )
                .onDrop(
                    of: [
                        UTType.fileURL.identifier
                    ],
                    isTargeted:
                        $destinationTargeted
                ) { providers in
                    handleDirectoryDrop(
                        providers
                    ) {
                        model.setDestinationFolder($0)
                    }
                }
            }
            .frame(maxWidth: 900)

            VStack(spacing: 10) {
                auditDropZone(
                    title: "Client Excel",
                    subtitle:
                        "Optional, recommended for rename validation",
                    systemImage:
                        "tablecells",
                    selectedURL:
                        model.excelSelection,
                    isTargeted:
                        excelTargeted,
                    chooseAction:
                        model.chooseExcelFile,
                    compact: true
                )
                .frame(maxWidth: 600)
                .onDrop(
                    of: [
                        UTType.fileURL.identifier
                    ],
                    isTargeted:
                        $excelTargeted
                ) { providers in
                    handleFileDrop(
                        providers,
                        extensionRequired:
                            "xlsx"
                    ) {
                        model.setExcelFile($0)
                    }
                }

                if model.excelSelection != nil {
                    Button("Remove Excel") {
                        model.setExcelFile(nil)
                    }
                    .buttonStyle(.link)
                    .disabled(
                        model.isScanning
                            || model.isApplying
                    )
                }
            }

            if model.isScanning {
                scanProgressPanel()
                    .frame(maxWidth: 700)
            } else {
                if model.lastScanError != nil {
                    scanFailurePanel
                        .frame(maxWidth: 700)
                }

                Button(
                    model.lastScanError == nil
                        ? "Build Audit Queue"
                        : "Retry Audit"
                ) {
                    model.startAudit()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canStartAudit)
            }

            if model.magickPath == nil {
                Label(
                    "ImageMagick is required for pixel comparison.",
                    systemImage:
                        "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(34)
    }

    private func scanProgressPanel(
        compact: Bool = false
    ) -> some View {
        TimelineView(
            .periodic(
                from: Date(),
                by: 1
            )
        ) { context in
            let startedAt =
                model.scanStartedAt
                ?? context.date
            let updatedAt =
                model.scanLastUpdateAt
                ?? startedAt
            let elapsed = max(
                0,
                context.date.timeIntervalSince(
                    startedAt
                )
            )
            let sinceUpdate = max(
                0,
                context.date.timeIntervalSince(
                    updatedAt
                )
            )

            VStack(
                alignment: .leading,
                spacing: compact ? 6 : 10
            ) {
                HStack(spacing: 10) {
                    if !compact {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(model.scanStage)
                        .font(
                            compact
                            ? .caption.bold()
                            : .headline
                        )
                        .foregroundStyle(.primary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                    Spacer()

                    Text(
                        "\(Int((model.scanProgress * 100).rounded()))%"
                    )
                    .font(
                        .caption.monospacedDigit()
                    )
                    .foregroundStyle(.secondary)
                }

                ProgressView(
                    value: model.scanProgress
                )

                HStack(spacing: 14) {
                    Label(
                        "Elapsed \(durationText(elapsed))",
                        systemImage: "clock"
                    )

                    Label(
                        "Last update \(durationText(sinceUpdate)) ago",
                        systemImage:
                            "arrow.triangle.2.circlepath"
                    )

                    Spacer()

                    if model.scanStage
                        .localizedCaseInsensitiveContains(
                            "Excel"
                        )
                    {
                        Text(
                            "Excel reads time out after 30s"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if sinceUpdate >= 15 {
                    Label(
                        "This step is taking longer than usual. The audit is still responsive; bounded file/image operations will surface an error instead of waiting indefinitely.",
                        systemImage: "hourglass"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }
            }
            .padding(
                compact ? 8 : 14
            )
            .background(
                RoundedRectangle(
                    cornerRadius: 12
                )
                .fill(
                    Color.secondary.opacity(
                        compact ? 0.04 : 0.06
                    )
                )
            )
        }
    }

    private var scanFailurePanel: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Label(
                "Audit stopped safely",
                systemImage:
                    "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(.red)

            if let stage =
                model.lastScanFailureStage
            {
                Text("Failed stage: \(stage)")
                    .font(.caption.bold())
                    .textSelection(.enabled)
            }

            if let detail =
                model.lastScanError
            {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Text(
                "No destination assets are modified while the audit queue is being built."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if model.excelSelection != nil {
                Button(
                    "Retry Without Excel"
                ) {
                    model.retryWithoutExcel()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(
                cornerRadius: 12
            )
            .fill(
                Color.red.opacity(0.06)
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 12
            )
            .strokeBorder(
                Color.red.opacity(0.25)
            )
        )
    }

    private func durationText(
        _ interval: TimeInterval
    ) -> String {
        let seconds = max(
            0,
            Int(interval.rounded(.down))
        )

        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        let remaining = seconds % 60
        return "\(minutes)m \(remaining)s"
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            auditHeader

            Divider()

            HStack(spacing: 0) {
                queueSidebar
                    .frame(width: 285)

                Divider()

                issueWorkspace

                Divider()

                actionPanel
                    .frame(width: 350)
            }
        }
    }

    private var auditHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    model.resetSelections()
                    onBack()
                } label: {
                    Label(
                        "Home",
                        systemImage: "house"
                    )
                }

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text("Asset Audit")
                        .font(.headline)

                    Text(
                        "\(model.sourceSelection?.lastPathComponent ?? "Source") → \(model.destinationSelection?.lastPathComponent ?? "Destination")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Re-scan") {
                    model.startAudit()
                }
                .disabled(
                    model.isScanning
                        || model.isApplying
                )

                Button("Reveal Destination") {
                    model.revealDestination()
                }

                Button(
                    "Review Changes (\(model.queuedChangeCount))"
                ) {
                    showChangePlan = true
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    Button(
                        "Rollback Last Apply…",
                        role: .destructive
                    ) {
                        showRollbackConfirmation = true
                    }
                    .disabled(!model.canRollback)
                } label: {
                    Image(
                        systemName:
                            "ellipsis.circle"
                    )
                }
            }

            if let summary = model.summary {
                HStack(spacing: 12) {
                    summaryChip(
                        "\(summary.totalDestinationAssets) finalized",
                        icon: "photo.stack"
                    )
                    summaryChip(
                        "\(summary.destinationOnlyCount) destination-only",
                        icon:
                            "questionmark.folder"
                    )
                    summaryChip(
                        "\(summary.duplicateIssueCount) duplicate groups",
                        icon:
                            "square.on.square"
                    )
                    summaryChip(
                        "\(summary.namingWarningCount) naming",
                        icon:
                            "character.cursor.ibeam"
                    )
                    if summary.missingOutputCount > 0 {
                        summaryChip(
                            "\(summary.missingOutputCount) missing",
                            icon:
                                "exclamationmark.triangle"
                        )
                    }

                    Spacer()

                    Text(
                        "\(model.reviewedCount) / \(model.issues.count) reviewed"
                    )
                    .font(
                        .caption.monospacedDigit()
                    )
                    .foregroundStyle(.secondary)
                }
            }

            if model.isScanning {
                scanProgressPanel(compact: true)
            } else if model.isApplying {
                HStack(spacing: 10) {
                    ProgressView()
                        .frame(width: 180)

                    Text(
                        model.message
                            ?? "Applying changes…"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
            } else if let message = model.message {
                HStack {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(14)
    }

    private var queueSidebar: some View {
        VStack(spacing: 0) {
            Picker(
                "Queue",
                selection: $model.filter
            ) {
                ForEach(
                    AuditQueueFilter.allCases
                ) { filter in
                    Text(filter.label)
                        .tag(filter)
                }
            }
            .pickerStyle(.menu)
            .padding(12)

            Divider()

            if model.filteredIssues.isEmpty {
                VStack(spacing: 12) {
                    Spacer()

                    Image(
                        systemName:
                            "checkmark.circle"
                    )
                    .font(.system(size: 34))
                    .foregroundStyle(.green)

                    Text("No items in this queue")
                        .font(.headline)

                    if model.filter == .unresolved {
                        Text(
                            "Everything currently detected has a review decision."
                        )
                        .font(.caption)
                        .multilineTextAlignment(
                            .center
                        )
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
            } else {
                ScrollViewReader { proxy in
                    List(
                        model.filteredIssues
                    ) { issue in
                        Button {
                            model.jumpToIssue(
                                issue
                            )
                        } label: {
                            issueRow(issue)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            model.currentIssue?.id
                                == issue.id
                                ? Color.accentColor
                                    .opacity(0.10)
                                : Color.clear
                        )
                        .id(issue.id)
                    }
                    .listStyle(.sidebar)
                    .onChange(
                        of:
                            model.currentIssue?.id
                    ) { _, value in
                        if let value {
                            proxy.scrollTo(
                                value,
                                anchor: .center
                            )
                        }
                    }
                }
            }
        }
    }

    private func issueRow(
        _ issue: AuditIssue
    ) -> some View {
        let decision =
            model.decision(for: issue)

        return VStack(
            alignment: .leading,
            spacing: 5
        ) {
            HStack(spacing: 6) {
                Image(
                    systemName:
                        issueIcon(issue.kind)
                )
                .foregroundStyle(
                    issueTint(issue.kind)
                )

                Text(issue.kind.label)
                    .font(.caption.bold())

                Spacer()

                if decision.action
                    != .unreviewed
                {
                    Image(
                        systemName:
                            decisionIcon(
                                decision.action
                            )
                    )
                    .foregroundStyle(
                        decision.action
                            == .delete
                            ? .red
                            : .green
                    )
                }
            }

            Text(issue.title)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }

    private var issueWorkspace: some View {
        Group {
            if let issue = model.currentIssue {
                VStack(spacing: 12) {
                    HStack {
                        Label(
                            issue.kind.label,
                            systemImage:
                                issueIcon(
                                    issue.kind
                                )
                        )
                        .font(.caption.bold())
                        .foregroundStyle(
                            issueTint(
                                issue.kind
                            )
                        )

                        Spacer()

                        if !issue.relatedRelativePaths
                            .isEmpty
                        {
                            Picker(
                                "Preview",
                                selection:
                                    $model.previewMode
                            ) {
                                ForEach(
                                    AuditPreviewMode
                                        .allCases
                                ) { mode in
                                    Text(mode.label)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 430)
                            .onChange(
                                of:
                                    model.previewMode
                            ) { _, _ in
                                model
                                    .generateDifferenceIfNeeded()
                            }
                        }
                    }

                    if issue.relatedRelativePaths.count > 1 {
                        HStack {
                            Text("Compare against")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Picker(
                                "Related image",
                                selection: Binding(
                                    get: { model.relatedIndex },
                                    set: { model.selectRelated($0) }
                                )
                            ) {
                                ForEach(
                                    Array(
                                        issue.relatedRelativePaths.enumerated()
                                    ),
                                    id: \.offset
                                ) { index, path in
                                    Text(
                                        URL(fileURLWithPath: path)
                                            .lastPathComponent
                                    )
                                    .tag(index)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 520)

                            Spacer()
                        }
                    }

                    auditPreview(issue)

                    VStack(spacing: 4) {
                        Text(issue.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(
                                .middle
                            )

                        Text(
                            issue.primaryRelativePath
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(
                            .middle
                        )

                        if let source =
                            issue.sourceRelativePath
                        {
                            Text(
                                "Source: \(source)"
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                .tertiary
                            )
                            .textSelection(.enabled)
                            .lineLimit(1)
                        }
                    }
                }
                .padding(18)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else {
                VStack(spacing: 12) {
                    Spacer()

                    Image(
                        systemName:
                            "checkmark.seal.fill"
                    )
                    .font(.system(size: 50))
                    .foregroundStyle(.green)

                    Text("Queue complete")
                        .font(.largeTitle.bold())

                    Text(
                        "Choose another queue from the sidebar or review the queued changes."
                    )
                    .foregroundStyle(.secondary)

                    Button(
                        "Review Changes (\(model.queuedChangeCount))"
                    ) {
                        showChangePlan = true
                    }
                    .buttonStyle(
                        .borderedProminent
                    )

                    Spacer()
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
        }
    }

    @ViewBuilder
    private func auditPreview(
        _ issue: AuditIssue
    ) -> some View {
        let primary =
            model.primaryURL(for: issue)
        let related =
            model.relatedURL(for: issue)

        switch model.previewMode {
        case .sideBySide:
            HStack(spacing: 12) {
                imageCard(
                    title: "Primary",
                    url: primary
                )

                if related != nil {
                    imageCard(
                        title: "Compared with",
                        url: related
                    )
                }
            }

        case .primary:
            imageCard(
                title: "Primary",
                url: primary
            )

        case .related:
            imageCard(
                title: "Compared with",
                url: related
            )

        case .difference:
            if model.isGeneratingDifference {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text(
                        "Generating pixel difference…"
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else {
                imageCard(
                    title: "Pixel difference",
                    url: model.differenceURL
                )
            }
        }

        if let source =
            model.sourceURL(for: issue),
           source.path != primary?.path
        {
            sourceReferenceCard(source)
        }
    }

    private func sourceReferenceCard(
        _ source: URL
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        Color.secondary.opacity(0.06)
                    )

                if let image = NSImage(contentsOf: source) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 74)

            VStack(alignment: .leading, spacing: 3) {
                Label(
                    "Current source",
                    systemImage: "arrow.turn.down.right"
                )
                .font(.caption.bold())

                Text(source.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.04))
        )
    }

    private func imageCard(
        title: String,
        url: URL?
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ZStack {
                RoundedRectangle(
                    cornerRadius: 12
                )
                .fill(
                    Color(
                        nsColor:
                            .windowBackgroundColor
                    )
                )

                if let url,
                   let image = NSImage(
                    contentsOf: url
                   )
                {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                } else {
                    VStack(spacing: 8) {
                        Image(
                            systemName:
                                "photo.badge.exclamationmark"
                        )
                        .font(
                            .system(size: 34)
                        )
                        .foregroundStyle(.secondary)

                        Text("Preview unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private var actionPanel: some View {
        Group {
            if let issue = model.currentIssue {
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: 16
                    ) {
                        Text("Review")
                            .font(.title2.bold())

                        Text(issue.detail)
                            .foregroundStyle(.secondary)

                        sourceBackedNotice(
                            issue
                        )

                        Divider()

                        decisionControls(issue)

                        if issue.kind
                            == .destinationOnly
                            || issue.kind
                            == .namingWarning
                        {
                            Divider()
                            renameControls(issue)
                        }

                        Divider()

                        HStack {
                            Button {
                                model.previousIssue()
                            } label: {
                                Label(
                                    "Previous",
                                    systemImage:
                                        "chevron.left"
                                )
                            }
                            .disabled(
                                model.currentIndex == 0
                            )

                            Spacer()

                            Button {
                                model.nextIssue()
                            } label: {
                                Label(
                                    "Next",
                                    systemImage:
                                        "chevron.right"
                                )
                            }
                            .disabled(
                                model.currentIndex
                                    >= model
                                    .filteredIssues
                                    .count - 1
                            )
                        }

                        if model.decision(
                            for: issue
                        ).action != .unreviewed {
                            Button(
                                "Clear Review Decision"
                            ) {
                                model.clearDecision()
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(22)
                }
            } else {
                EmptyView()
            }
        }
    }

    private func sourceBackedNotice(
        _ issue: AuditIssue
    ) -> some View {
        Group {
            if issue.primarySourceBacked {
                Label(
                    "Current source-backed output",
                    systemImage:
                        "lock.shield.fill"
                )
                .font(.caption.bold())
                .foregroundStyle(.green)

                Text(
                    "Audit mode will not allow this file to be deleted. If it is wrong, fix the name or flag the source issue."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Destination-only output",
                    systemImage:
                        "questionmark.folder"
                )
                .font(.caption.bold())
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func decisionControls(
        _ issue: AuditIssue
    ) -> some View {
        switch issue.kind {
        case .destinationOnly:
            actionButton(
                "Keep",
                icon: "checkmark",
                prominent: true
            ) {
                model.setDecision(.keep)
            }

            actionButton(
                "Delete",
                icon: "trash",
                destructive: true
            ) {
                model.setDecision(.delete)
            }

            actionButton(
                "Needs Client Review",
                icon:
                    "person.crop.circle.badge.questionmark"
            ) {
                model.setDecision(
                    .clientReview
                )
            }

        case .pixelDuplicate:
            actionButton(
                "Keep Both",
                icon:
                    "square.on.square",
                prominent: true
            ) {
                model.setDecision(.keep)
            }

            actionButton(
                "Intentional Duplicate",
                icon: "checkmark.seal"
            ) {
                model.setDecision(
                    .intentionalDuplicate
                )
            }

            actionButton(
                "Flag Source Issue",
                icon:
                    "exclamationmark.triangle"
            ) {
                model.setDecision(
                    .sourceIssue
                )
            }

            actionButton(
                "Needs Client Review",
                icon:
                    "person.crop.circle.badge.questionmark"
            ) {
                model.setDecision(
                    .clientReview
                )
            }

        case .namingWarning:
            actionButton(
                "Keep Name",
                icon: "checkmark",
                prominent: true
            ) {
                model.setDecision(.keep)
            }

            if issue.primarySourceBacked {
                actionButton(
                    "Flag Source Issue",
                    icon:
                        "exclamationmark.triangle"
                ) {
                    model.setDecision(
                        .sourceIssue
                    )
                }
            } else {
                actionButton(
                    "Delete",
                    icon: "trash",
                    destructive: true
                ) {
                    model.setDecision(.delete)
                }
            }

            actionButton(
                "Needs Client Review",
                icon:
                    "person.crop.circle.badge.questionmark"
            ) {
                model.setDecision(
                    .clientReview
                )
            }

        case .missingOutput:
            actionButton(
                "Flag Source Issue",
                icon:
                    "exclamationmark.triangle",
                prominent: true
            ) {
                model.setDecision(
                    .sourceIssue
                )
            }

            actionButton(
                "Needs Client Review",
                icon:
                    "person.crop.circle.badge.questionmark"
            ) {
                model.setDecision(
                    .clientReview
                )
            }
        }
    }

    private func renameControls(
        _ issue: AuditIssue
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Rename")
                .font(.headline)

            TextField(
                "Correct filename.webp",
                text: $model.renameDraft
            )
            .textFieldStyle(.roundedBorder)
            .onChange(
                of: model.renameDraft
            ) { _, _ in
                model.validateRenameDraft()
            }

            if let validation =
                model.renameValidation
            {
                Label(
                    validation.message,
                    systemImage:
                        validation.isValid
                        ? "checkmark.circle"
                        : "xmark.circle"
                )
                .font(.caption)
                .foregroundStyle(
                    validation.isValid
                        ? .green
                        : .red
                )
            }

            if let suggestion =
                model.renameValidation?
                    .suggestedFileName
                ?? issue.suggestedFileName,
               suggestion
                .caseInsensitiveCompare(
                    model.renameDraft
                ) != .orderedSame
            {
                Button(
                    "Use suggestion: \(suggestion)"
                ) {
                    model.useSuggestedRename()
                }
                .font(.caption)
                .buttonStyle(.link)
            }

            Button("Queue Rename") {
                model.setDecision(.rename)
            }
            .buttonStyle(.bordered)
            .disabled(
                model.renameValidation?
                    .isValid != true
            )
        }
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        icon: String,
        prominent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                actionButtonContent(
                    title: title,
                    icon: icon
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(destructive ? .red : nil)
        } else {
            Button(action: action) {
                actionButtonContent(
                    title: title,
                    icon: icon
                )
            }
            .buttonStyle(.bordered)
            .tint(destructive ? .red : nil)
        }
    }

    private func actionButtonContent(
        title: String,
        icon: String
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            Text(title)
            Spacer()
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 34
        )
    }

    private func auditDropZone(
        title: String,
        subtitle: String,
        systemImage: String,
        selectedURL: URL?,
        isTargeted: Bool,
        chooseAction: @escaping () -> Void,
        compact: Bool = false
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size:
                            compact ? 22 : 30
                    )
                )
                .foregroundStyle(
                    isTargeted
                    ? Color.accentColor
                    : Color.secondary
                )

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selectedURL {
                Text(selectedURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(
                        .center
                    )
            } else {
                Text(
                    compact
                    ? "Drop .xlsx here"
                    : "Drop folder here"
                )
                .foregroundStyle(.secondary)
            }

            Button("Choose…") {
                chooseAction()
            }
        }
        .padding(compact ? 12 : 18)
        .frame(
            maxWidth: .infinity,
            minHeight:
                compact ? 120 : 180
        )
        .background(
            RoundedRectangle(
                cornerRadius: 14
            )
            .fill(
                Color.secondary.opacity(0.04)
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 14
            )
            .strokeBorder(
                isTargeted
                    ? Color.accentColor
                    : Color.secondary
                        .opacity(0.35),
                style: StrokeStyle(
                    lineWidth: 2,
                    dash: [9, 7]
                )
            )
        )
    }

    private func summaryChip(
        _ text: String,
        icon: String
    ) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .padding(
                .horizontal,
                8
            )
            .padding(.vertical, 4)
            .background(
                Color.secondary.opacity(0.08)
            )
            .clipShape(Capsule())
    }

    private func issueIcon(
        _ kind: AuditIssueKind
    ) -> String {
        switch kind {
        case .destinationOnly:
            return "questionmark.folder"
        case .pixelDuplicate:
            return "square.on.square"
        case .namingWarning:
            return "character.cursor.ibeam"
        case .missingOutput:
            return "exclamationmark.triangle"
        }
    }

    private func issueTint(
        _ kind: AuditIssueKind
    ) -> Color {
        switch kind {
        case .destinationOnly:
            return .orange
        case .pixelDuplicate:
            return .purple
        case .namingWarning:
            return .blue
        case .missingOutput:
            return .red
        }
    }

    private func decisionIcon(
        _ action: AuditDecisionKind
    ) -> String {
        switch action {
        case .unreviewed:
            return "circle"
        case .keep:
            return "checkmark.circle.fill"
        case .delete:
            return "trash.circle.fill"
        case .rename:
            return "pencil.circle.fill"
        case .clientReview:
            return "person.crop.circle.badge.questionmark"
        case .intentionalDuplicate:
            return "checkmark.seal.fill"
        case .sourceIssue:
            return "exclamationmark.triangle.fill"
        }
    }

    private func handleDirectoryDrop(
        _ providers: [NSItemProvider],
        completion: @escaping (URL) -> Void
    ) -> Bool {
        handleURLDrop(
            providers
        ) { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default
                .fileExists(
                    atPath: url.path,
                    isDirectory:
                        &isDirectory
                ),
                isDirectory.boolValue
            else {
                model.errorMessage =
                    "Please drop a folder."
                return
            }

            completion(url)
        }
    }

    private func handleFileDrop(
        _ providers: [NSItemProvider],
        extensionRequired: String,
        completion: @escaping (URL) -> Void
    ) -> Bool {
        handleURLDrop(
            providers
        ) { url in
            guard url.pathExtension
                .caseInsensitiveCompare(
                    extensionRequired
                ) == .orderedSame
            else {
                model.errorMessage =
                    "Please drop a .\(extensionRequired) file."
                return
            }

            completion(url)
        }
    }

    private func handleURLDrop(
        _ providers: [NSItemProvider],
        completion:
            @escaping (URL) -> Void
    ) -> Bool {
        guard let provider =
            providers.first
        else {
            return false
        }

        provider.loadItem(
            forTypeIdentifier:
                UTType.fileURL.identifier,
            options: nil
        ) { item, _ in
            let url: URL?

            if let direct = item as? URL {
                url = direct
            } else if let data =
                item as? Data
            {
                url = URL(
                    dataRepresentation: data,
                    relativeTo: nil
                )
            } else {
                url = nil
            }

            guard let url else { return }

            DispatchQueue.main.async {
                completion(url)
            }
        }

        return true
    }
}

private struct AuditChangePlanView: View {
    @ObservedObject var model: AuditModel
    let onClose: () -> Void

    @State private var confirmApply = false

    private var plan: AuditChangePlan? {
        model.changePlan
    }

    private var queued: [AuditPlannedChange] {
        plan?.changes ?? []
    }

    private var conflicts: [AuditPlanConflict] {
        plan?.conflicts ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("Review Changes")
                        .font(.title2.bold())

                    Text(
                        "\(queued.count) effective filesystem change(s)"
                    )
                    .foregroundStyle(.secondary)

                    if let superseded =
                        plan?.supersededDecisionCount,
                       superseded > 0
                    {
                        Text(
                            "\(superseded) older duplicate-path decision(s) were superseded by the latest review choice."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Close") {
                    onClose()
                }
            }
            .padding(18)

            Divider()

            if queued.isEmpty {
                VStack(spacing: 12) {
                    Spacer()

                    Image(
                        systemName:
                            "checkmark.circle"
                    )
                    .font(.system(size: 44))
                    .foregroundStyle(.green)

                    Text(
                        "No destructive changes queued"
                    )
                    .font(.headline)

                    Text(
                        "Keep, Client Review, Intentional Duplicate, and Source Issue decisions are saved but do not modify files."
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(
                        .center
                    )
                    .frame(maxWidth: 520)

                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    if !conflicts.isEmpty {
                        VStack(
                            alignment: .leading,
                            spacing: 8
                        ) {
                            Label(
                                "Resolve before applying",
                                systemImage:
                                    "exclamationmark.triangle.fill"
                            )
                            .font(.headline)
                            .foregroundStyle(.red)

                            ForEach(conflicts) { conflict in
                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(conflict.message)
                                        .font(.caption.bold())

                                    ForEach(
                                        conflict.paths,
                                        id: \.self
                                    ) { path in
                                        Text(path)
                                            .font(.caption2)
                                            .foregroundStyle(
                                                .secondary
                                            )
                                            .textSelection(
                                                .enabled
                                            )
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            Color.red.opacity(0.06)
                        )

                        Divider()
                    }

                    List {
                        ForEach(queued) { change in
                            HStack(
                                alignment: .top,
                                spacing: 12
                            ) {
                                Image(
                                    systemName:
                                        change.action
                                            == .delete
                                        ? "trash"
                                        : "pencil"
                                )
                                .foregroundStyle(
                                    change.state
                                        == .alreadySatisfied
                                    ? .green
                                    : (
                                        change.action
                                            == .delete
                                        ? .red
                                        : .blue
                                    )
                                )
                                .frame(width: 24)

                                VStack(
                                    alignment: .leading,
                                    spacing: 4
                                ) {
                                    HStack {
                                        Text(
                                            change.action.label
                                        )
                                        .font(.headline)

                                        if change.state
                                            == .alreadySatisfied
                                        {
                                            Text(
                                                "Already satisfied"
                                            )
                                            .font(.caption.bold())
                                            .foregroundStyle(.green)
                                        }
                                    }

                                    Text(
                                        change.originalRelativePath
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                    .textSelection(.enabled)

                                    if let target =
                                        change.targetRelativePath
                                    {
                                        Text(
                                            "→ \(target)"
                                        )
                                        .font(.caption.bold())
                                    }

                                    if let note = change.note {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(
                                                .secondary
                                            )
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            }

            Divider()

            HStack {
                if model.canRollback {
                    Button(
                        "Rollback Last Apply"
                    ) {
                        model.rollbackLastApply()
                    }
                    .disabled(
                        model.isApplying
                    )
                }

                Spacer()

                Text(
                    conflicts.isEmpty
                    ? "Apply creates a hash-verified backup in Downloads first."
                    : "Apply is disabled until the effective plan has no conflicts."
                )
                .font(.caption)
                .foregroundStyle(
                    conflicts.isEmpty
                    ? .secondary
                    : .red
                )

                Button("Apply Changes…") {
                    confirmApply = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !model.canApplyChanges
                        || !conflicts.isEmpty
                )
            }
            .padding(18)
        }
        .frame(
            minWidth: 760,
            minHeight: 560
        )
        .confirmationDialog(
            "Apply the reviewed file changes?",
            isPresented: $confirmApply,
            titleVisibility: .visible
        ) {
            Button(
                "Apply \(queued.count) Change(s)",
                role: .destructive
            ) {
                onClose()
                model.applyQueuedChanges()
            }
        } message: {
            Text(
                "Every affected file is backed up and hash-checked before the change. Source-backed outputs cannot be deleted."
            )
        }
    }
}
